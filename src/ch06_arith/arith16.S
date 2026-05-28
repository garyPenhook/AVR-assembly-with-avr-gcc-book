/*
 * arith16.S — 16-bit arithmetic, shifts, MUL family, division on ATtiny3217.
 *              Companion source for Chapter 6: Arithmetic and Logic: 16-bit and Beyond
 *
 * Covers:
 *   LSL / LSR — logical shift left/right (unsigned multiply/divide by 2)
 *   ASR — arithmetic shift right (signed divide by 2, sign bit preserved)
 *   ROL / ROR — rotate through carry for multi-byte shifts
 *   SWAP — swap nibbles, 1 cycle, no flags (BCD / hex display use)
 *   MUL — unsigned 8×8 → 16 result in r1:r0; must CLR r1 afterward (ABI)
 *   MULS — signed 8×8 → 16 (operands r16–r31 only)
 *   MULSU — signed × unsigned → 16 (used in fixed-point coefficient math)
 *   div8u_clean — restoring shift-subtract division (no DIV instruction on AVR)
 *   div16u8 — 16-bit / 8-bit restoring division with 9-bit remainder path
 *
 * Build:
 *   avr-gcc -x assembler-with-cpp -mmcu=attiny3217 -c arith16.S -o arith16.o
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o arith16.elf arith16.o
 *   avr-objdump -d arith16.elf
 */

#include <avr/io.h>

.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    jmp main

.section .text
.global main

main:
    ldi r16, lo8(RAMEND)
    out SPL, r16
    ldi r16, hi8(RAMEND)
    out SPH, r16

    /* ── 16-bit add ──────────────────────────────────────────────────────
     * r25:r24 = 0x01F4 (500) + 0x0190 (400) = 0x0384 (900)             */
    ldi r24, lo8(500)
    ldi r25, hi8(500)
    ldi r22, lo8(400)
    ldi r23, hi8(400)
    add r24, r22
    adc r25, r23            ; r25:r24 = 900 = 0x0384

    /* ── 16-bit subtract ─────────────────────────────────────────────────
     * r25:r24 = 0x0384 (900) - 0x00C8 (200) = 0x02BC (700)             */
    ldi r22, lo8(200)
    ldi r23, hi8(200)
    sub r24, r22
    sbc r25, r23            ; r25:r24 = 700

    /* ── Logical Shift Left / Right: LSL / LSR (Chapter 6) ─────────────
     * LSL Rd: Rd <<= 1 (unsigned ×2), old bit 7 → C, 0 → bit 0
     * LSR Rd: Rd >>= 1 (unsigned ÷2), old bit 0 → C, 0 → bit 7
     * C flag carries the shifted-out bit — used to chain multi-byte shifts. */
    ldi r16, 0b00001010     ; = 10
    lsl r16                 ; r16 = 0b00010100 = 20, C=0
    lsl r16                 ; r16 = 0b00101000 = 40, C=0

    ldi r16, 0b10000000     ; = 128
    lsr r16                 ; r16 = 0b01000000 = 64,  C=0
    lsr r16                 ; r16 = 0b00100000 = 32,  C=0

    /* ── Arithmetic Shift Right: ASR (Chapter 6) ────────────────────────
     * Bit 7 is replicated (sign-extended) rather than filled with 0.
     * Divides a signed value by 2, rounding toward negative infinity.
     * Use LSR for unsigned divide-by-2, ASR for signed divide-by-2.    */
    ldi r16, 0b10000100     ; = -124 signed
    asr r16                 ; r16 = 0b11000010 = -62, C=0
    asr r16                 ; r16 = 0b11100001 = -31, C=0

    /* ── Rotate Through Carry: ROL / ROR — multi-byte shifts (Chapter 6) ─
     * ROL: old bit 7 → C, old C → new bit 0  (like LSL but uses carry)
     * ROR: old bit 0 → C, old C → new bit 7  (like LSR but uses carry)
     * Chain: LSL low-byte (C = bit7 of low) then ROL high-byte (C→bit0). */
    ldi r17, 0b00000001     ; r17:r16 = 16-bit value 0x0140 = 320
    ldi r16, 0b01000000
    ; Shift r17:r16 left 1 (multiply 320 by 2 = 640)
    lsl r16                 ; low byte: bit7 → C
    rol r17                 ; high byte: C → bit0, bit7 → C
    ; r17:r16 = 0b00000010_10000000 = 0x0280 = 640

    /* ── 16-bit shift right (logical) ───────────────────────────────────
     * Shift r25:r24 right 1 (divide 900 by 2 = 450)                    */
    ldi r24, lo8(900)
    ldi r25, hi8(900)
    lsr r25                 ; high byte: bit0 → C, 0 → bit7
    ror r24                 ; low byte: C → bit7, bit0 → C
    ; r25:r24 = 450

    /* ── SWAP — swap nibbles ──────────────────────────────────────────────
     * Upper nibble ↔ lower nibble. 1 cycle, no flags.                  */
    ldi r16, 0xAB
    swap r16                ; r16 = 0xBA

    /* ── MUL: unsigned 8×8 → 16 (Chapter 6) ────────────────────────────
     * Result always lands in r1:r0 (2 cycles).  r1 = high, r0 = low.
     * GCC ABI assumes r1 = 0 (the "zero register").  After any MUL, MULS,
     * or MULSU, clear r1 with CLR before calling a C function or using
     * r1 as zero.  Forgetting this causes subtle, hard-to-trace bugs.  */
    ldi r16, 12
    ldi r17, 25
    mul r16, r17            ; r1:r0 = 12 * 25 = 300 = 0x012C
    movw r24, r0            ; copy result to r25:r24 (safe to use)
    clr r1                  ; restore r1 = 0 (ABI requirement)

    /* ── MULS — signed 8×8 → 16-bit signed result ───────────────────────
     * Operands treated as signed (-128..127). r16–r31 only.
     * Result in r1:r0 (signed 16-bit).                                  */
    ldi r16, 0xF6           ; = -10 signed
    ldi r17, 5
    muls r16, r17           ; r1:r0 = -10 * 5 = -50 = 0xFFCE
    movw r24, r0
    clr r1

    /* ── MULSU — signed × unsigned → signed 16-bit ──────────────────────
     * Rd (r16–r23) is signed, Rr (r16–r23) is unsigned.
     * Used in fixed-point when one operand is a coefficient.            */
    ldi r16, 0xF6           ; = -10 signed
    ldi r17, 200            ; = 200 unsigned
    mulsu r16, r17          ; r1:r0 = -10 * 200 = -2000 = 0xF830
    movw r24, r0
    clr r1

    /* ── Division by shift-subtract (Chapter 6) ─────────────────────────
     * AVR has no DIV instruction.  Restoring division: shift dividend MSB
     * into remainder, test remainder >= divisor, subtract and set quotient
     * bit if so.  Loop once per bit (8 iterations for 8-bit dividend).
     * Routine below: r16 / r17 → quotient r18, remainder r19           */
    ldi r16, 100
    ldi r17, 7
    rcall div8u_clean       ; r18 = 14 (quotient), r19 = 2 (remainder)

    /* -- 16-bit / 8-bit divide (unsigned) -------------------------------
     * r25:r24 / r16 -> quotient r25:r24, remainder r18.
     * 256 / 129 = 1 remainder 127 exercises the 9th remainder bit.      */
    ldi r24, lo8(256)
    ldi r25, hi8(256)
    ldi r16, 129
    rcall div16u8           ; r25:r24 = 1, r18 = 127

    /* ── Absolute value of signed 8-bit ─────────────────────────────────
     * If r16 < 0: negate it. Else leave it.                            */
    ldi r16, 0xD2           ; = -46 signed
    sbrc r16, 7             ; skip if bit 7 clear (positive)
    neg r16                 ; r16 = 46
    ; r16 now holds |input|

halt:
    rjmp halt

/* ════════════════════════════════════════════════════════════════════════
 * div8u_clean — restoring unsigned 8-bit division
 *   Input:  r16 = dividend, r17 = divisor
 *   Output: r18 = quotient, r19 = remainder
 *   Clobbers: r20 (loop counter)
 * ════════════════════════════════════════════════════════════════════════ */
div8u_clean:
    clr  r18                ; quotient = 0
    clr  r19                ; remainder = 0
    ldi  r20, 8
1:
    lsl  r16                ; shift MSB of dividend into C
    rol  r19                ; remainder = (remainder << 1) | dividend_MSB
    lsl  r18                ; quotient <<= 1
    cp   r19, r17
    brlo 2f                 ; remainder < divisor: quotient bit stays 0
    sub  r19, r17
    ori  r18, 1             ; quotient bit = 1
2:
    dec  r20
    brne 1b
    ret

/* ------------------------------------------------------------------------
 * div16u8 -- restoring unsigned 16-bit / 8-bit division
 *   Input:  r25:r24 = dividend, r16 = divisor
 *   Output: r25:r24 = quotient, r18 = remainder
 *   Clobbers: r19, r20, r21, r22, r23
 * ------------------------------------------------------------------------ */
div16u8:
    clr  r18                ; remainder low = 0
    clr  r22                ; remainder high = 0
    clr  r23                ; zero register for 16-bit subtract
    ldi  r19, 16            ; 16 bits
    clr  r20                ; quotient low
    clr  r21                ; quotient high
1:
    lsl  r24                ; shift MSB of dividend into C
    rol  r25
    rol  r18                ; remainder <<= 1, | C
    rol  r22                ; keep the 9th remainder bit
    lsl  r20                ; quotient <<= 1
    rol  r21
    tst  r22                ; high byte nonzero means remainder >= divisor
    brne 3f
    cp   r18, r16
    brlo 2f
3:
    sub  r18, r16
    sbc  r22, r23
    ori  r20, 1             ; quotient bit = 1
2:
    dec  r19
    brne 1b
    movw r24, r20           ; quotient -> r25:r24
    ret
