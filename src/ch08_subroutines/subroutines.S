/*
 * subroutines.S — call/ret, stack frames, register discipline, recursion.
 *                 Companion source for Chapter 8: Subroutines and the Stack
 *
 * Covers:
 *   CALL and RCALL — push 2-byte return address, branch to target (see ch08)
 *   RET / RETI — pop return address, resume caller
 *   PUSH and POP — manual register save/restore; stack grows downward
 *   Register Ownership — callee-saved r14–r15, call-clobbered r18–r27
 *   Prologue and Epilogue Patterns — save Y, allocate locals, restore Y
 *   Stack Depth Analysis — 4 bytes locals + 2 return address = 6 bytes peak
 *   Worked Example: Recursive Factorial — save n across RCALL, restore with POP
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c subroutines.S -o subroutines.o
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o subroutines.elf subroutines.o
 *   avr-objdump -d subroutines.elf
 */

#include <avr/io.h>

.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    jmp main

/* ════════════════════════════════════════════════════════════════════════
 * simple_add — add two 8-bit unsigned numbers, return 16-bit result.
 *   Input:  r24 = first addend, r22 = second addend
 *   Output: r25:r24 = 16-bit sum
 *   Clobbers: r24, r25
 *
 * Chapter 8: Register Ownership — r24/r25 are the AVR-LibC ABI return
 * registers for 16-bit values.  r22/r23 hold the second argument.
 * ════════════════════════════════════════════════════════════════════════ */
.section .text

.global simple_add
simple_add:
    add  r24, r22       ; r24 = a + b (may carry)
    clr  r25
    adc  r25, r1        ; r25 = 0 + carry
    ret                 ; return r25:r24

/* ════════════════════════════════════════════════════════════════════════
 * save_restore — demonstrates callee-saved register discipline.
 * Uses r14, r15: this routine saves and restores them.
 *
 * Chapter 8: Register Ownership — r14/r15 are callee-saved.  Any routine
 * that uses them must PUSH on entry and POP in reverse order before RET.
 * The caller can assume r14/r15 are unchanged across a subroutine call.
 * ════════════════════════════════════════════════════════════════════════ */
.global save_restore
save_restore:
    push r14                    ; save call-preserved regs we will use
    push r15
    ldi  r16, 0xAA
    mov  r14, r16               ; r14 = 0xAA (free to clobber — it's saved)
    ldi  r16, 0x55
    mov  r15, r16               ; r15 = 0x55
    add  r14, r15               ; r14 = 0xFF — do real work in saved regs
    mov  r24, r14               ; return value in r24
    pop  r15                    ; restore in reverse push order
    pop  r14
    ret

/* ════════════════════════════════════════════════════════════════════════
 * with_frame — routine that uses local variables via Y frame pointer.
 *   Allocates 4 bytes of locals on the stack.
 *   Local layout (Y = SP after allocation):
 *     Y+1 = local_a  (1 byte)
 *     Y+2 = local_b  (1 byte)
 *     Y+3 = local_c  (2 bytes, Y+3=lo, Y+4=hi)
 *
 * Chapter 8: Prologue and Epilogue Patterns
 *   Prologue: PUSH Y; IN Y, SP; SBIW Y, n; OUT SP, Y
 *   Epilogue (inverse): ADIW Y, n; OUT SP, Y (restore SP); POP Y
 *   Write SPH before SPL when increasing SP to avoid a transient low SP.
 *   Write SPH before SPL when decreasing SP is critical for interrupt safety.
 * ════════════════════════════════════════════════════════════════════════ */
.global with_frame
with_frame:
    /* Prologue */
    push r28            ; save Y
    push r29
    in   r28, SPL       ; Y = current SP (below saved r29)
    in   r29, SPH
    sbiw r28, 4         ; allocate 4 bytes of locals
    out  SPH, r29       ; write SP high first
    out  SPL, r28       ; write SPL last; hardware masks interrupts briefly

    /* Body: access locals via LDD/STD Y+offset */
    ldi  r16, 10
    std  Y+1, r16       ; local_a = 10
    ldi  r16, 20
    std  Y+2, r16       ; local_b = 20
    ldd  r16, Y+1
    ldd  r17, Y+2
    add  r16, r17       ; r16 = 30
    std  Y+3, r16       ; local_c_lo = 30
    ldi  r16, 0
    std  Y+4, r16       ; local_c_hi = 0

    ldd  r24, Y+3       ; return local_c (16-bit)
    ldd  r25, Y+4

    /* Epilogue */
    adiw r28, 4         ; deallocate locals — SP is below saved r29
    out  SPH, r29       ; restore SP (SPH before SPL when increasing)
    out  SPL, r28
    pop  r29            ; restore Y
    pop  r28
    ret

/* ════════════════════════════════════════════════════════════════════════
 * mul8x16 — multiply 8-bit × 16-bit → 16-bit (truncated).
 *   Input:  r16 = 8-bit multiplier, r25:r24 = 16-bit multiplicand
 *   Output: r25:r24 = (r16 × r25:r24) low 16 bits
 *   Clobbers: r0, r1 (cleared before return)
 * ════════════════════════════════════════════════════════════════════════ */
.global mul8x16
mul8x16:
    mul   r16, r24          ; r1:r0 = r16 × multiplicand_lo
    movw  r22, r0           ; r23:r22 = partial low result
    mul   r16, r25          ; r1:r0 = r16 × multiplicand_hi
    add   r23, r0           ; r23 += (r16 × hi) — contributes to result byte 1
    clr   r1
    movw  r24, r22          ; result → r25:r24
    ret

/* ════════════════════════════════════════════════════════════════════════
 * factorial — recursive unsigned factorial.
 *   Input:  r24 = n (0 <= n <= 8 for 16-bit result)
 *   Output: r25:r24 = n!
 *   Clobbers: r0, r1, r16, r22, r23
 *
 *   Peak stack for n=8: 8 return addresses + 7 saved n bytes = 23 bytes.
 *
 * Chapter 8: Worked Example: Recursive Factorial
 *   PUSH r24 saves the current n before the recursive RCALL overwrites it.
 *   POP r16 recovers n after RCALL returns, then calls mul8x16 to multiply.
 *   Each recursion level consumes 2 bytes (return addr) + 1 byte (saved n).
 * ════════════════════════════════════════════════════════════════════════ */
.global factorial

factorial:
    /* Base case: n <= 1 → return 1 */
    cpi   r24, 2
    brlo  .Lfact_base

    /* Recursive case */
    push  r24               ; save n across the recursive call
    dec   r24               ; n - 1
    rcall factorial         ; r25:r24 = factorial(n-1)

    /* Restore n, compute n * factorial(n-1) */
    pop   r16               ; r16 = original n (8-bit)
    rcall mul8x16           ; r25:r24 = r16 × r25:r24
    ret

.Lfact_base:
    clr   r25
    ldi   r24, 1            ; return 1
    ret

/* ════════════════════════════════════════════════════════════════════════
 * main
 * ════════════════════════════════════════════════════════════════════════ */
.global main

main:
    ldi r16, lo8(RAMEND)
    ldi r17, hi8(RAMEND)
    out SPH, r17
    out SPL, r16

    /* Test simple_add: 200 + 100 = 300 = 0x012C */
    ldi  r24, 200
    ldi  r22, 100
    rcall simple_add        ; r25:r24 = 300

    /* Test with_frame */
    rcall with_frame        ; r25:r24 = 30

    /* Test factorial(7) = 5040 = 0x13B0 */
    ldi  r24, 7
    rcall factorial         ; r25:r24 = 5040

    /* Test factorial(0) = 1 */
    ldi  r24, 0
    rcall factorial         ; r25:r24 = 1

halt:
    rjmp halt
