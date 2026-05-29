/* lut_interp.S — linear interpolation between flash look-up table entries
 *                 Companion source for Chapter 15: Optimisation Techniques
 *                 (see "Interpolating Between Table Entries" section)
 *
 * Trade-off: a coarse 17-entry table plus interpolation replaces the dense
 * 256-entry table in lut_sin.S. It spends ~17 flash bytes of data instead of
 * 256, at the cost of more cycles per lookup and a small approximation error.
 *
 * The table holds the same unsigned sine curve sampled every 16th step:
 *   interp_table[i] = sin_table[i*16],  i = 0..16
 * The extra final entry (i = 16, the wrap back to sin_table[0] = 128) lets the
 * routine always read both T[i] and T[i+1] without a bounds check.
 *
 * The curve is smooth enough that every consecutive difference
 *   delta = T[i+1] - T[i]
 * lands in the signed-byte range -49..+49, which is what makes the single
 * MULSU below correct.
 */

#include <avr/io.h>

.section .progmem.data,"a",@progbits
.global interp_table
interp_table:
    /* sin_table[0], [16], [32], ... [240], then wrap [256]=[0]=128          */
    .byte 128,176,218,246,255,246,218,176,128,79,37,9,0,9,37,79,128
.size interp_table, .-interp_table

/* interp8 -- interpolated table lookup
 *
 * Arguments:
 *   R24  index i      (0..15, selects the segment between T[i] and T[i+1])
 *   R22  fraction f   (uint8_t, Q0.8 position in that segment: 0 = T[i],
 *                      255 ~= T[i+1])
 *
 * Returns:
 *   R24  interpolated value, unsigned 0..255:
 *        y = T[i] + ((T[i+1] - T[i]) * f) >> 8
 *
 * MULSU treats r21 (delta) as signed and r22 (f) as unsigned, so the
 * correction carries the right sign when the curve is falling. Both MULSU
 * operands must live in r16..r23; r21 and r22 satisfy that.
 */
.section .text
.global interp8
.type   interp8, @function
interp8:
    ldi   ZL, lo8(interp_table) /* Z = base of interp_table in flash         */
    ldi   ZH, hi8(interp_table)
    add   ZL, r24               /* Z += i                                    */
    adc   ZH, r1                /* propagate carry (r1 = 0)                  */
    lpm   r20, Z+               /* r20 = T[i],   Z now -> T[i+1]             */
    lpm   r21, Z                /* r21 = T[i+1]                              */
    sub   r21, r20              /* r21 = delta = T[i+1] - T[i]  (signed)     */
    mulsu r21, r22              /* r1:r0 = delta(signed) * f(unsigned)       */
    add   r20, r1               /* y = T[i] + ((delta*f) >> 8)               */
    clr   r1                    /* MUL dirtied r1; restore the zero register */
    mov   r24, r20              /* return value in R24                       */
    ret
.size interp8, .-interp8
