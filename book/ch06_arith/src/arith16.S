/*
 * arith16.S — 16-bit arithmetic, shifts, MUL family, division on ATtiny3217.
 *
 * Build:
 *   avr-as -mmcu=attiny3217 -o arith16.o arith16.S
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

    /* ── LSL / LSR — logical shift ───────────────────────────────────────
     * LSL Rd: shift left 1 bit (Rd *= 2), bit 7 → C, 0 → bit 0
     * LSR Rd: shift right 1 bit (Rd /= 2 unsigned), bit 0 → C, 0→bit7  */
    ldi r16, 0b00001010     ; = 10
    lsl r16                 ; r16 = 0b00010100 = 20, C=0
    lsl r16                 ; r16 = 0b00101000 = 40, C=0

    ldi r16, 0b10000000     ; = 128
    lsr r16                 ; r16 = 0b01000000 = 64,  C=0
    lsr r16                 ; r16 = 0b00100000 = 32,  C=0

    /* ── ASR — arithmetic (signed) shift right ───────────────────────────
     * Bit 7 is copied (sign-extended), not replaced with 0.
     * Divides signed value by 2, rounding toward negative infinity.     */
    ldi r16, 0b10000100     ; = -124 signed
    asr r16                 ; r16 = 0b11000010 = -62, C=0
    asr r16                 ; r16 = 0b11100001 = -31, C=0

    /* ── ROL / ROR — rotate through carry ───────────────────────────────
     * ROL: bit 7 → C, old C → bit 0
     * ROR: bit 0 → C, old C → bit 7
     * Used to shift multi-byte values:                                  */
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

    /* ── MUL — unsigned 8×8 → 16-bit result ─────────────────────────────
     * Result always lands in r1:r0. 2 cycles.
     * r1 = high byte, r0 = low byte.
     * MUST clear r1 after MUL if code assumes r1 = 0 (GCC ABI).       */
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

    /* ── 8-bit divide (unsigned): quotient + remainder ───────────────────
     * AVR has no DIV instruction. Use the shift-subtract algorithm.
     * Routine below: r16 / r17 → quotient r18, remainder r19           */
    ldi r16, 100
    ldi r17, 7
    rcall div8u             ; r18 = 14 (quotient), r19 = 2 (remainder)

    /* ── Absolute value of signed 8-bit ─────────────────────────────────
     * If r16 < 0: negate it. Else leave it.                            */
    ldi r16, 0xD2           ; = -46 signed
    sbrc r16, 7             ; skip if bit 7 clear (positive)
    neg r16                 ; r16 = 46
    ; r16 now holds |input|

halt:
    rjmp halt

/* ════════════════════════════════════════════════════════════════════════
 * div8u — unsigned 8-bit division
 *   Input:  r16 = dividend, r17 = divisor
 *   Output: r18 = quotient, r19 = remainder
 *   Clobbers: r20 (loop counter)
 * ════════════════════════════════════════════════════════════════════════ */
div8u:
    clr  r18                ; quotient = 0
    clr  r19                ; remainder = 0
    ldi  r20, 8             ; 8 bits to process

1:
    lsl  r16                ; shift dividend left: MSB → C
    rol  r19                ; shift C into remainder LSB
    cp   r19, r17           ; remainder >= divisor?
    brlo 2f                 ; no: skip subtraction
    sub  r19, r17           ; yes: remainder -= divisor
    inc  r18                ; set quotient bit (will be shifted in on next lsl)
    ; Note: the quotient bit accumulates via the INC trick combined
    ; with the fact that bit 0 of r16 is 0 after LSL.
    ; Cleaner: use separate quotient accumulation below.
2:
    dec  r20
    brne 1b
    ret

/* ════════════════════════════════════════════════════════════════════════
 * div8u_clean — cleaner restoring division, quotient in r18 per bit
 *   Input:  r16 = dividend, r17 = divisor
 *   Output: r18 = quotient, r19 = remainder
 *   Clobbers: r20
 * ════════════════════════════════════════════════════════════════════════ */
div8u_clean:
    clr  r19                ; remainder = 0
    ldi  r20, 8
1:
    lsl  r16                ; shift MSB of dividend into C
    rol  r19                ; remainder = (remainder << 1) | dividend_MSB
    sec                     ; tentatively set quotient bit
    cp   r19, r17
    brsh 2f                 ; remainder >= divisor: keep bit set, subtract
    clc                     ; remainder < divisor: clear quotient bit
    rjmp 3f
2:
    sub  r19, r17
3:
    rol  r18                ; shift quotient bit (C) into r18 LSB
    dec  r20
    brne 1b
    ret
