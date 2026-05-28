/*
 * arithmetic.S — add, subtract, compare, logic demos on ATtiny3217.
 *                Companion source for Chapter 4: Instruction Set Basics
 *
 * Covers:
 *   Arithmetic Instructions: ADD, ADC (carry chain), SUB, SUBI, INC, DEC, NEG, COM
 *   Logic Instructions: ANDI, ORI, EOR, CLR, TST
 *   Comparison Instructions: CP, CPI — sets flags without storing result
 *   Unsigned vs Signed Comparisons: BRLO (unsigned C-based) vs BRLT (signed S-flag)
 *   Flag Effects Summary: which flags each instruction updates (see ch04 table)
 *   Worked Example: Compare, Clamp, Negate
 *
 * Build:
 *   avr-gcc -x assembler-with-cpp -mmcu=attiny3217 -c arithmetic.S -o arithmetic.o
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o arithmetic.elf arithmetic.o
 *   avr-objdump -d arithmetic.elf
 */

#include <avr/io.h>

.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    jmp     main

.section .text
.global main

main:
    ldi r16, lo8(RAMEND)
    out SPL, r16
    ldi r16, hi8(RAMEND)
    out SPH, r16

    /* ── Arithmetic Instructions: 8-bit unsigned addition (Chapter 4) ──────
     * r16 = 100 + 50 = 150.  No unsigned carry (150 < 256), so C=0, Z=0.
     * 150 = 0x96, bit 7 = 1, so N=1.  Signed view: 100 + 50 overflows
     * 8-bit signed range (+127 max) and the bits look like -106, so V=1.
     * S = N XOR V = 0.                                                  */
    ldi     r16, 100
    ldi     r17, 50
    add     r16, r17            ; r16 = 150 (0x96), C=0, N=1, V=1, S=0

    /* ── 8-bit addition with overflow ───────────────────────────────────
     * 200 + 100 = 300 → wraps to 44.  Carry out → C=1.                  */
    ldi     r16, 200
    ldi     r17, 100
    add     r16, r17            ; r16 = 44, C=1

    /* ── Arithmetic Instructions: 16-bit ADD + ADC carry chain (Chapter 4) ─
     * r17:r16 = 0x0190 (400) + 0x0190 (400) = 0x0320 (800)
     * Add low bytes FIRST to generate carry, then high bytes with ADC.   */
    ldi     r16, lo8(400)       ; r16 = 0x90
    ldi     r17, hi8(400)       ; r17 = 0x01
    ldi     r18, lo8(400)       ; r18 = 0x90
    ldi     r19, hi8(400)       ; r19 = 0x01
    add     r16, r18            ; low  bytes: r16 = 0x20, C=1 (carry!)
    adc     r17, r19            ; high bytes: r17 = 0x03 (includes carry)
    ; r17:r16 = 0x0320 = 800 OK

    /* ── 8-bit subtraction ───────────────────────────────────────────────
     * r16 = 100 - 30 = 70.  No borrow.  C=0.                            */
    ldi     r16, 100
    ldi     r17, 30
    sub     r16, r17            ; r16 = 70, C=0

    /* ── Subtraction with borrow (unsigned underflow) ────────────────────
     * r16 = 10 - 20 = -10 → wraps to 246 unsigned.  C=1 (borrow).      */
    ldi     r16, 10
    ldi     r17, 20
    sub     r16, r17            ; r16 = 246, C=1

    /* ── Subtract immediate: SUBI ────────────────────────────────────────
     * SUBI works on r16–r31 only (like LDI).
     * r16 = 50 - 7 = 43.                                                */
    ldi     r16, 50
    subi    r16, 7              ; r16 = 43 — no second register needed

    /* ── Comparison Instructions: CP (Chapter 4) ────────────────────────
     * CP sets flags exactly like SUB but discards the result.
     * Use it before a conditional branch.  BREQ checks Z; BRLO checks C. */
    ldi     r16, 42
    ldi     r17, 42
    cp      r16, r17            ; 42 - 42 = 0, Z=1
    breq    equal               ; taken: Z=1 → values are equal

not_equal:
    ldi     r18, 0              ; r18 = 0 — values differ
    rjmp    after_compare

equal:
    ldi     r18, 1              ; r18 = 1 — values match

after_compare:

    /* ── Compare with immediate: CPI ─────────────────────────────────────
     * CPI Rd, K — Rd must be r16–r31.                                   */
    ldi     r16, 100
    cpi     r16, 200
    brlo    r16_lower           ; BRLO = branch if lower (unsigned, C=1)
    rjmp    after_brlo
r16_lower:
    nop
after_brlo:

    /* ── Unsigned vs Signed Comparisons: BRLT vs BRLO (Chapter 4) ─────────
     * -10 (0xF6) < 5 in signed interpretation, but 0xF6 > 5 unsigned.
     * BRLT uses the S flag (N XOR V) — correct for signed comparisons.
     * BRLO uses the C flag — correct for unsigned comparisons.
     * Choosing the wrong branch here produces silent wrong results.      */
    ldi     r16, 0xF6           ; = -10 signed
    ldi     r17, 5
    cp      r16, r17
    brlt    r16_less            ; taken: -10 < 5
    rjmp    after_signed
r16_less:
    nop
after_signed:

    /* ── Logic Instructions: AND / OR / EOR (Chapter 4) ────────────────
     * Mask off upper nibble: keep bits 3..0 only.                       */
    ldi     r16, 0xAB
    andi    r16, 0x0F           ; r16 = 0x0B — ANDI works on r16–r31

    /* ── Logic: OR ───────────────────────────────────────────────────────
     * Set bit 7 of r16.                                                  */
    ldi     r16, 0x2A
    ori     r16, 0x80           ; r16 = 0xAA

    /* ── Logic: EOR (XOR) ────────────────────────────────────────────────
     * Toggle bit 3.                                                      */
    ldi     r16, 0b00001111
    ldi     r17, 0b00001000
    eor     r16, r17            ; r16 = 0b00000111

    /* ── CLR: clear register (EOR with self) ─────────────────────────────
     * clr Rd is a pseudo-instruction for eor Rd, Rd.  Z=1; C is unchanged. */
    clr     r16                 ; r16 = 0, Z=1

    /* ── TST: test register (AND with self) ──────────────────────────────
     * Sets N and Z flags without modifying the register.                */
    ldi     r16, 0x80
    tst     r16                 ; N=1 (bit 7 set), Z=0

    /* ── NEG: two's complement negate ───────────────────────────────────
     * NEG Rd = 0x00 - Rd.  NEG 0 leaves 0 with C=0; all others C=1.   */
    ldi     r16, 10
    neg     r16                 ; r16 = 246 (0xF6 = -10 signed), C=1

    /* ── COM: one's complement (bitwise invert) ──────────────────────────
     * COM Rd = 0xFF - Rd (flip every bit).                             */
    ldi     r16, 0b10101010
    com     r16                 ; r16 = 0b01010101

    /* ── Arithmetic Instructions: INC / DEC — carry-flag pitfall (Chapter 4)
     * INC and DEC do NOT affect the carry flag.  If you need carry for a
     * multi-byte counter, use ADD Rd, r1 (r1=0) instead of INC.        */
    ldi     r16, 255
    inc     r16                 ; r16 = 0, Z=1, C unchanged (still 1!)

    ldi     r16, 0
    dec     r16                 ; r16 = 255, Z=0, N=1

halt:
    rjmp    halt
