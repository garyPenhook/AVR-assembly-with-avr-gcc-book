/*
 * number_systems.S — Number system conversions and BCD arithmetic.
 *                    Companion source for Chapter 1a.
 *
 * Covers:
 *   Literal notation: decimal, binary (0b), hex (0x)
 *   ASCII ↔ BCD digit conversion
 *   Packed BCD addition with manual correction
 *   Packed BCD subtraction with manual correction
 *   8-bit binary to 3-digit packed BCD (double-dabble)
 *   2-digit packed BCD to binary
 *
 * Build:
 *   avr-gcc -x assembler-with-cpp -mmcu=attiny3217 -c number_systems.S -o number_systems.o
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o number_systems.elf number_systems.o
 *   avr-objdump -d number_systems.elf
 */

#include <avr/io.h>

/* ── Vector table ─────────────────────────────────────────────────────────── */
.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    jmp main

/* ── Data section ─────────────────────────────────────────────────────────── */
.section .data

bcd_result_lo:  .byte 0     ; packed BCD result (low 2 digits)
bcd_result_hi:  .byte 0     ; BCD hundreds digit

/* ── Text section ─────────────────────────────────────────────────────────── */
.section .text
.global main

main:
    /* ── Stack pointer ─────────────────────────────────────────────────────── */
    ldi  r16, lo8(RAMEND)
    out  SPL, r16
    ldi  r16, hi8(RAMEND)
    out  SPH, r16


/* ════════════════════════════════════════════════════════════════════════════
 * LITERAL NOTATION: same value in decimal, binary, and hex
 * All three load the same bit pattern (182 = 0xB6 = 0b10110110) into r16.
 * ════════════════════════════════════════════════════════════════════════════ */
section_literals:
    ldi  r16, 182           ; decimal literal
    ldi  r16, 0b10110110    ; binary literal  (same value)
    ldi  r16, 0xB6          ; hex literal     (same value)

    /* Common single-byte constants expressed in their most natural base */
    ldi  r17, 0b00001111    ; 0x0F = 15  — lower nibble mask
    ldi  r18, 0b11110000    ; 0xF0 = 240 — upper nibble mask
    ldi  r19, 0xFF          ; 255 — all bits set (SER alias)
    ldi  r20, 0x80          ; 128 — MSB set (sign bit in signed interpretation)
    ldi  r21, 0x01          ; 1   — LSB set


/* ════════════════════════════════════════════════════════════════════════════
 * ASCII DIGIT ↔ BCD DIGIT CONVERSION
 * ASCII '0'–'9' = 0x30–0x39.  BCD digit = ASCII - 0x30.
 * ════════════════════════════════════════════════════════════════════════════ */
section_ascii_bcd:
    /* BCD digit → ASCII character */
    ldi  r16, 7             ; BCD digit 7 (units)
    ldi  r17, '0'           ; 0x30
    add  r16, r17           ; r16 = '7' = 0x37 ✓

    /* ASCII character → BCD digit */
    ldi  r16, '4'           ; ASCII '4' = 0x34
    subi r16, '0'           ; r16 = 4 (BCD digit) ✓

    /* Extract tens and units from packed BCD byte 0x47 */
    ldi  r16, 0x47          ; BCD 47 (packed)

    mov  r17, r16
    swap r17                ; high nibble → low nibble: r17 = 0x74
    andi r17, 0x0F          ; mask: r17 = 0x04 = tens digit 4 ✓

    mov  r18, r16
    andi r18, 0x0F          ; r18 = 0x07 = units digit 7 ✓

    /* Convert both digits to ASCII */
    ldi  r19, '0'
    add  r17, r19           ; r17 = '4' = 0x34
    add  r18, r19           ; r18 = '7' = 0x37


/* ════════════════════════════════════════════════════════════════════════════
 * BCD ADDITION: 0x29 + 0x38 = BCD 67
 * ════════════════════════════════════════════════════════════════════════════ */
section_bcd_add_test1:
    ldi  r16, 0x29          ; BCD 29
    ldi  r17, 0x38          ; BCD 38
    rcall bcd_add
    ; r16 should be 0x67 (BCD 67), C=0  ✓


/* ════════════════════════════════════════════════════════════════════════════
 * BCD ADDITION WITH CARRY: 0x75 + 0x48 = BCD 123 (r16=0x23, C=1)
 * ════════════════════════════════════════════════════════════════════════════ */
section_bcd_add_test2:
    ldi  r16, 0x75          ; BCD 75
    ldi  r17, 0x48          ; BCD 48
    rcall bcd_add
    ; r16 should be 0x23 (BCD 23), C=1 (hundreds carry)  ✓


/* ════════════════════════════════════════════════════════════════════════════
 * BCD SUBTRACTION: 0x73 - 0x28 = BCD 45
 * ════════════════════════════════════════════════════════════════════════════ */
section_bcd_sub_test:
    ldi  r16, 0x73          ; BCD 73
    ldi  r17, 0x28          ; BCD 28
    rcall bcd_sub
    ; r16 should be 0x45 (BCD 45), C=0  ✓


/* ════════════════════════════════════════════════════════════════════════════
 * BINARY → PACKED BCD: 137 = 0x89 → r18=0x01, r17=0x37 (BCD 137)
 * ════════════════════════════════════════════════════════════════════════════ */
section_bin_to_bcd_test:
    ldi  r16, 137           ; binary 137
    rcall bin8_to_bcd
    ; r18 = 0x01 (hundreds=1), r17 = 0x37 (tens=3, units=7) ✓
    sts  bcd_result_lo, r17
    sts  bcd_result_hi, r18

    /* Also test edge cases */
    ldi  r16, 0             ; binary 0 → BCD 000
    rcall bin8_to_bcd
    ; r18=0x00, r17=0x00 ✓

    ldi  r16, 255           ; binary 255 → BCD 255
    rcall bin8_to_bcd
    ; r18=0x02, r17=0x55 ✓


/* ════════════════════════════════════════════════════════════════════════════
 * PACKED BCD → BINARY: 0x47 (BCD 47) → binary 47
 * ════════════════════════════════════════════════════════════════════════════ */
section_bcd_to_bin_test:
    ldi  r16, 0x47          ; BCD 47
    rcall bcd2_to_bin
    ; r16 should be 47 (0x2F)  ✓

    ldi  r16, 0x99          ; BCD 99
    rcall bcd2_to_bin
    ; r16 should be 99 (0x63)  ✓

    ldi  r16, 0x10          ; BCD 10
    rcall bcd2_to_bin
    ; r16 should be 10 (0x0A)  ✓


/* ── End of demo — halt ───────────────────────────────────────────────────── */
halt:
    rjmp halt


/* ════════════════════════════════════════════════════════════════════════════
 * SUBROUTINES
 * ════════════════════════════════════════════════════════════════════════════ */

/*
 * bcd_add — add two packed BCD bytes
 *   Input:  r16 = BCD addend A (0x00–0x99)
 *           r17 = BCD addend B (0x00–0x99)
 *   Output: r16 = BCD sum (0x00–0x99, with C=1 if decimal overflow ≥ 100)
 *   Clobbers: r18
 */
bcd_add:
    add  r16, r17

    /* Low nibble correction: H=1 or low nibble > 9 */
    brhs bcd_add_low_fix
    mov  r18, r16
    andi r18, 0x0F
    cpi  r18, 10
    brlo bcd_add_low_ok
bcd_add_low_fix:
    subi r16, -6            /* r16 += 6 */
bcd_add_low_ok:

    /* High nibble correction: C=1 or high nibble > 9 */
    brcs bcd_add_high_fix
    mov  r18, r16
    andi r18, 0xF0
    cpi  r18, 0xA0
    brlo bcd_add_high_ok
bcd_add_high_fix:
    subi r16, -0x60         /* r16 += 0x60 */
bcd_add_high_ok:
    ret


/*
 * bcd_sub — subtract packed BCD (r16 - r17)
 *   Input:  r16 = minuend (0x00–0x99), r17 = subtrahend (0x00–0x99)
 *   Output: r16 = BCD difference; C=1 if borrow occurred
 *   Clobbers: (none beyond r16)
 */
bcd_sub:
    sub  r16, r17

    /* Low nibble correction: H=1 (half-borrow occurred) */
    brhs bcd_sub_low_fix
    rjmp bcd_sub_low_ok
bcd_sub_low_fix:
    subi r16, 6             /* r16 -= 6 */
bcd_sub_low_ok:

    /* High nibble correction: C=1 (borrow occurred) */
    brcc bcd_sub_high_ok
    subi r16, 0x60          /* r16 -= 0x60 */
bcd_sub_high_ok:
    ret


/*
 * bin8_to_bcd — convert 8-bit binary to 3-digit packed BCD (double-dabble)
 *   Input:  r16 = binary value (0–255)
 *   Output: r18 = hundreds digit (low nibble, 0–2)
 *           r17 = packed BCD tens:units
 *   Clobbers: r19, r20
 */
bin8_to_bcd:
    clr  r17
    clr  r18
    ldi  r20, 8

bin_bcd_loop:
    /* Add 3 to any nibble that is >= 5 (before the shift) */
    mov  r19, r17
    andi r19, 0x0F              /* units nibble */
    cpi  r19, 5
    brlo bin_bcd_skip_units
    subi r17, -3
bin_bcd_skip_units:

    mov  r19, r17
    andi r19, 0xF0              /* tens nibble position */
    cpi  r19, 0x50
    brlo bin_bcd_skip_tens
    subi r17, -0x30
bin_bcd_skip_tens:

    mov  r19, r18
    andi r19, 0x0F              /* hundreds nibble */
    cpi  r19, 5
    brlo bin_bcd_skip_hunds
    subi r18, -3
bin_bcd_skip_hunds:

    /* Shift MSB of input into LSB of BCD accumulator */
    lsl  r16
    rol  r17
    rol  r18

    dec  r20
    brne bin_bcd_loop
    ret


/*
 * bcd2_to_bin — convert 2-digit packed BCD to 8-bit binary (0–99)
 *   Input:  r16 = packed BCD (0x00–0x99)
 *   Output: r16 = binary value (0–99)
 *   Clobbers: r17, r18
 */
bcd2_to_bin:
    mov  r17, r16
    andi r17, 0xF0          /* high nibble = tens */
    swap r17                /* move to low nibble position */
    mov  r18, r17           /* save tens */
    lsl  r17                /* × 2 */
    lsl  r17                /* × 4 */
    add  r17, r18           /* × 5 */
    lsl  r17                /* × 10 */
    andi r16, 0x0F          /* low nibble = units */
    add  r16, r17           /* binary = (tens × 10) + units */
    ret
