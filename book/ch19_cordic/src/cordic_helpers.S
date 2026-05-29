/* cordic_helpers.S — CORDIC support routines for ATtiny3217
 *
 * These helpers support the Chapter 19 CORDIC examples without being a
 * full sine/cosine library.
 *
 * Numeric format:
 *   All angles use BAM16 (Binary Angular Measurement, 16-bit).
 *   The full circle maps to 0x0000..0xFFFF (0 to 65535).
 *   0x2000 = 45°, 0x4000 = 90°, 0x8000 = 180°.
 *
 *   Magnitudes use Q1.15 signed fixed-point (1 sign bit, 15 fractional bits).
 *   1.0 is represented as 0x7FFF; -1.0 as 0x8000.
 */

#include <avr/io.h>

/* CORDIC gain constant K (Q1.15 format).
 * The CORDIC rotation algorithm accumulates a gain of approximately 1.6468.
 * To keep the output magnitude in the range [-1, 1], the result must be
 * multiplied by K = 1 / 1.6468 = 0.6073.
 * K_Q15 = round(0.607252959 × 32768) = 19898 = 0x4DBA                      */
#define K_Q15 0x4DBA

.section .text

/* ── cordic_atan_bam16 ────────────────────────────────────────────────────
 *
 * Flash table of atan(2^-i) values in BAM16 format for i = 0..11.
 *
 * These are the rotation angles used in each CORDIC iteration.
 * At iteration i, the algorithm rotates by ±atan(2^-i) and scales by
 * sqrt(1 + 2^(-2i)). The 12 entries correspond to 12 CORDIC iterations.
 *
 * Derivation: atan(2^-i) × (65536 / (2π))
 *   i=0:  atan(1)       = 45.0°   → 0x2000
 *   i=1:  atan(0.5)     = 26.57°  → 0x12E4
 *   i=2:  atan(0.25)    = 14.04°  → 0x09FB
 *   i=3:  atan(0.125)   =  7.12°  → 0x0511
 *   ...
 *   i=11: atan(2^-11)   ≈  0.028° → 0x0005
 *
 * To read: LPM with Z pointing at the word for iteration i
 * (Z = cordic_atan_bam16 + 2*i, since each entry is a 16-bit word).        */
.global cordic_atan_bam16
.type cordic_atan_bam16, @object
.balign 2
cordic_atan_bam16:
    .word 0x2000, 0x12E4, 0x09FB, 0x0511  /* iterations 0..3                */
    .word 0x028B, 0x0146, 0x00A3, 0x0051  /* iterations 4..7                */
    .word 0x0029, 0x0014, 0x000A, 0x0005  /* iterations 8..11               */
.size cordic_atan_bam16, .-cordic_atan_bam16

/* ── cordic_load_k_q15 ───────────────────────────────────────────────────
 *
 * Returns the CORDIC gain compensation constant K in Q1.15 format.
 * Multiply the CORDIC output (x, y) by K to normalise the amplitude.
 *
 * Exit: R25:R24 = 0x4DBA = round(0.607252959 × 32768)
 */
.global cordic_load_k_q15
.type cordic_load_k_q15, @function
cordic_load_k_q15:
    ldi   r24, lo8(K_Q15)           /* 0xBA                                   */
    ldi   r25, hi8(K_Q15)           /* 0x4D                                   */
    ret
.size cordic_load_k_q15, .-cordic_load_k_q15

/* ── cordic_asr16 ────────────────────────────────────────────────────────
 *
 * Arithmetic right shift of a signed 16-bit value by a variable count.
 * Used in CORDIC to implement the ÷2^i scaling step:
 *   x_new = x ± (y >> i)  (rotate by ±atan(2^-i), scaled by 1/sqrt(1+2^-2i))
 *
 * Entry: R25:R24 = signed 16-bit input value
 *        R17     = shift count (0..15)
 * Exit:  R25:R24 = input >> count  (sign bit is replicated, not zeroed)
 * Clobbers: R17 (count decremented to zero)
 */
.global cordic_asr16
.type cordic_asr16, @function
cordic_asr16:
    tst   r17
    breq  .Lasr16_done              /* shift by 0: return input unchanged      */
.Lasr16_loop:
    asr   r25                       /* high byte: sign bit (bit7) preserved   */
    ror   r24                       /* rotate low byte: carry in from high    */
    dec   r17
    brne  .Lasr16_loop
.Lasr16_done:
    ret
.size cordic_asr16, .-cordic_asr16
