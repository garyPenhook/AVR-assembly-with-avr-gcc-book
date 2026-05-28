/*
 * control.S — branches, skip instructions, loops, jump tables on ATtiny3217.
 *              Companion source for Chapter 7: Branches and Control Flow
 *
 * Covers:
 *   Conditional Branches: CPI + BRLO / BRSH for unsigned range clamp
 *   Structured Control Flow Patterns:
 *     two-way if/else (top-branch, fall-through)
 *     top-tested while loop (test before body, may execute 0 times)
 *     bottom-tested do-while (body always executes once)
 *     fixed-count for loop with DEC + BRNE
 *   Worked Example: Sum an Array — LPM loop accumulating into 16-bit r25:r24
 *   Skip Instructions: SBRC / SBRS (register bit), SBIC / SBIS (I/O bit)
 *   Jump Tables: bounds-check + IJMP via Z to RJMP dispatch table
 *   Polling Loops: SBIS-based spin-wait on GPIO pin
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c control.S -o control.o
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o control.elf control.o
 *   avr-objdump -d control.elf
 */

#include <avr/io.h>

/* ── Test data in flash ───────────────────────────────────────────────── */
.section .progmem.data, "a", @progbits

test_array:
    .byte 10, 20, 30, 40, 50, 60, 70, 80
.equ ARRAY_LEN, 8

/* ── SRAM ─────────────────────────────────────────────────────────────── */
.section .bss
result16: .skip 2          ; 16-bit sum result

/* ── Vectors ──────────────────────────────────────────────────────────── */
.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    jmp main

/* ── Code ─────────────────────────────────────────────────────────────── */
.section .text
.global main

main:
    ldi r16, lo8(RAMEND)
    out SPL, r16
    ldi r16, hi8(RAMEND)
    out SPH, r16

    /* ── Structured Control Flow: two-way if/else (Chapter 7) ───────────
     * Branch-to-else, fall-through-to-then pattern.
     * CPI + BRLO: "if r16 >= 101 (i.e. > 100) fall through to then-branch."
     * Inverted condition on the branch is normal in assembly — you branch
     * PAST the then-body when the condition is false (else case).
     */
    ldi r16, 120
    cpi r16, 101            ; compare r16 with 101 (> 100 means >= 101)
    brlo else_branch        ; if r16 < 101: go to else
    ldi r16, 100            ; then-branch: clamp
    rjmp end_if
else_branch:
    subi r16, -5            ; else-branch: r16 += 5
end_if:

    /* ── Structured Control Flow: top-tested while loop (Chapter 7) ─────
     * Test condition BEFORE the body; the loop may execute 0 times.
     * Equivalent C: while (r16 != 0) { r16--; }
     * BREQ at top exits immediately if r16 is already 0.
     */
    ldi r16, 10
top_test:
    tst r16
    breq top_done
    dec r16
    rjmp top_test
top_done:

    /* ── Structured Control Flow: bottom-tested do-while (Chapter 7) ────
     * Body executes, THEN test: always runs at least once.
     * Equivalent C: do { r16++; } while (r16 != 50);
     * The single branch at the bottom both tests and loops back — saves
     * one unconditional RJMP compared to the top-tested form.
     */
    clr r16
do_body:
    inc r16
    cpi r16, 50
    brne do_body            ; loop back if not 50 yet

    /* ── Structured Control Flow: fixed-count for loop (Chapter 7) ──────
     * Count DOWN to 0: DEC + BRNE is the tightest idiom.
     * DEC sets Z=1 when the counter hits 0; no CPI needed.
     * Equivalent C: for (r18 = 8; r18 != 0; r18--) { r17 += 3; }
     */
    clr r17
    ldi r18, 8
count_loop:
    subi r17, -3            ; r17 += 3
    dec  r18
    brne count_loop

    /* ── Worked Example: Sum an Array (Chapter 7) ────────────────────────
     * Sum 8 bytes from flash into a 16-bit accumulator r25:r24.
     * Z holds the flash byte address; LPM reads each byte and Z++ advances.
     * ADC r25, r1 propagates any carry from the 8-bit ADD into the high byte.
     * r1 is the GCC zero register — always 0 unless MUL/MULS just ran.
     */
    ldi ZL, lo8(test_array)
    ldi ZH, hi8(test_array)
    clr r24                 ; sum low byte
    clr r25                 ; sum high byte
    ldi r18, ARRAY_LEN

sum_loop:
    lpm  r16, Z+            ; load byte from flash, advance pointer
    add  r24, r16           ; add to sum low byte
    adc  r25, r1            ; propagate carry (r1 = 0)
    dec  r18
    brne sum_loop

    sts result16,   r24     ; store result
    sts result16+1, r25

    /* ── Skip Instructions: SBRC / SBRS (Chapter 7) ─────────────────────
     * SBRC Rr, b — Skip next instruction if bit b of Rr is Clear
     * SBRS Rr, b — Skip next instruction if bit b of Rr is Set
     * Skips exactly one instruction (1-word or 2-word — skip is adjusted).
     * Avoids a branch label for simple "do one thing if bit set" patterns.
     */
    ldi r16, 0b00000101     ; flags byte
    sbrc r16, 0             ; skip next if bit 0 clear — bit 0 IS set, no skip
    rcall action_a          ; executed
    sbrc r16, 1             ; skip next if bit 1 clear — bit 1 IS clear, SKIP
    rcall action_b          ; skipped
    sbrs r16, 2             ; skip next if bit 2 set — bit 2 IS set, SKIP
    rcall action_c          ; skipped
    sbrs r16, 3             ; skip next if bit 3 set — bit 3 clear, no skip
    rcall action_d          ; executed

    /* ── Skip Instructions: SBIC / SBIS — I/O bit test (Chapter 7) ──────
     * SBIC A, b — Skip if bit b of I/O reg A (addr 0x00–0x1F) is Clear
     * SBIS A, b — Skip if bit b of I/O reg A (addr 0x00–0x1F) is Set
     * I/O address range is 0x00–0x1F (lower half of classical I/O space).
     * On ATtiny3217, VPORTA/B/C and GPIOR0-3 live here.
     * GPIOR0 is a general-purpose flag byte accessible in a single cycle.
     */
    ldi r16, (1 << 2)
    out GPIOR0, r16         ; GPIOR0 bit 2 = 1
    sbis GPIOR0, 2          ; skip if bit 2 set — IS set → skip
    rcall action_a          ; skipped
    sbic GPIOR0, 3          ; skip if bit 3 clear — IS clear → skip
    rcall action_b          ; skipped

    /* ── Jump Tables: IJMP dispatch (Chapter 7) ──────────────────────────
     * Dispatch r16 values 0, 1, or 2 to separate handlers.
     * Strategy: load Z with the address of jtable[selector] and IJMP.
     * Each table entry is one RJMP instruction = one word (2 bytes).
     * Z is a word pointer: Z = pm(jtable) + selector (add the index directly).
     * Always bounds-check BEFORE computing Z to prevent wild jumps.
     */
    ldi r16, 1              ; selector = 1

    cpi r16, 3              ; bounds check: selector >= 3?
    brsh jtable_default     ; out of range → default

    ; Compute jump table entry address:
    ; Each entry is 1 instruction word (2 bytes).
    ; Z is a program word address, so:
    ; Z = pm(jtable) + r16
    ldi ZL, lo8(pm(jtable))
    ldi ZH, hi8(pm(jtable))
    add ZL, r16             ; Z += selector index (each entry is 1 word)
    adc ZH, r1              ; carry
    ijmp                    ; jump to selected RJMP entry in the table

jtable_default:
    rcall default_handler
    rjmp jtable_done

jtable:
    rjmp entry0_handler     ; selector 0
    rjmp entry1_handler     ; selector 1
    rjmp entry2_handler     ; selector 2

entry0_handler: rcall action_a
               rjmp jtable_done
entry1_handler: rcall action_b
               rjmp jtable_done
entry2_handler: rcall action_c
               rjmp jtable_done

jtable_done:

halt:
    rjmp halt

/* ── Stubs ────────────────────────────────────────────────────────────── */
action_a:       ret
action_b:       ret
action_c:       ret
action_d:       ret
default_handler:ret
