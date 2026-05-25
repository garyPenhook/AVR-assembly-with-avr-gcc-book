/* cordic_helpers.S — small CORDIC support routines for ATtiny3217
 *
 * These helpers are intentionally small: they support the chapter examples
 * without pretending to be a complete sine/cosine implementation.
 */

#include <avr/io.h>

#define K_Q15 0x4DBA

.section .text

/* BAM16 atan(2^-i) table for i = 0..11.
 * Stored in flash. Use LPM through Z to read bytes from this table.
 */
.global cordic_atan_bam16
.type cordic_atan_bam16, @object
.balign 2
cordic_atan_bam16:
    .word 0x2000, 0x12E4, 0x09FB, 0x0511
    .word 0x028B, 0x0146, 0x00A3, 0x0051
    .word 0x0029, 0x0014, 0x000A, 0x0005
.size cordic_atan_bam16, .-cordic_atan_bam16

/* cordic_load_k_q15
 *
 * Exit: R25:R24 = K_Q15 = round(0.607252959 * 32768) = 0x4DBA
 */
.global cordic_load_k_q15
.type cordic_load_k_q15, @function
cordic_load_k_q15:
    ldi   r24, lo8(K_Q15)
    ldi   r25, hi8(K_Q15)
    ret
.size cordic_load_k_q15, .-cordic_load_k_q15

/* cordic_asr16
 *
 * Entry: R25:R24 = signed 16-bit value
 *        R17     = shift count, 0..15
 * Exit:  R25:R24 = value >> count, arithmetic shift
 * Clobbers: R17
 */
.global cordic_asr16
.type cordic_asr16, @function
cordic_asr16:
    tst   r17
    breq  .Lasr16_done
.Lasr16_loop:
    asr   r25
    ror   r24
    dec   r17
    brne  .Lasr16_loop
.Lasr16_done:
    ret
.size cordic_asr16, .-cordic_asr16
