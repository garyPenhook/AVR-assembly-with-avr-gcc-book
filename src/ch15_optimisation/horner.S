/* horner.S — polynomial evaluation by Horner's method
 *             Companion source for Chapter 15: Optimisation Techniques
 *             (see "Horner's Method for Polynomials" section)
 *
 * Horner rewrites
 *   p(x) = c2*x^2 + c1*x + c0
 * as
 *   p(x) = (c2*x + c1)*x + c0
 * which needs one multiply and one add per coefficient and never forms x^2
 * explicitly. For a degree-n polynomial that is n multiply-adds instead of
 * computing and summing n separate powers.
 *
 * This file evaluates the fixed polynomial 2*x^2 + 3*x + 5 with unsigned
 * 8-bit x and a 16-bit unsigned accumulator. The coefficients live in flash,
 * most-significant first, so the routine streams them with LPM Z+.
 */

#include <avr/io.h>

.section .progmem.data,"a",@progbits
.global poly_coeffs
poly_coeffs:
    .byte 2, 3, 5               /* c2, c1, c0  ->  2*x^2 + 3*x + 5           */
.size poly_coeffs, .-poly_coeffs

/* horner8 -- evaluate p(x) = 2*x^2 + 3*x + 5
 *
 * Arguments:
 *   R24  x   (uint8_t)
 *
 * Returns:
 *   R25:R24  p(x), unsigned 16-bit (low 16 bits if it overflows)
 *
 * Accumulator is R19:R18. Each step is acc = acc*x + c, where acc*x is a
 * 16x8 multiply kept to its low 16 bits. The first coefficient seeds the
 * accumulator, then two more flow through the loop.
 */
.section .text
.global horner8
.type   horner8, @function
horner8:
    ldi   ZL, lo8(poly_coeffs)  /* Z = base of coefficient table in flash    */
    ldi   ZH, hi8(poly_coeffs)
    mov   r22, r24              /* r22 = x (kept as the multiplier)          */
    lpm   r18, Z+               /* acc low  = c2                             */
    clr   r19                   /* acc high = 0   ->  acc = c2               */
    ldi   r20, 2                /* two coefficients remain (c1, c0)          */
.Lhorner_loop:
    mul   r18, r22              /* r1:r0 = accL * x                          */
    movw  r24, r0               /* R25:R24 = accL*x  (16-bit partial)        */
    mul   r19, r22              /* r1:r0 = accH * x  (only low byte matters) */
    add   r25, r0               /* fold (accH*x) << 8 into the high byte     */
    clr   r1                    /* product consumed; restore zero register   */
    lpm   r0, Z+                /* r0 = next coefficient                     */
    add   r24, r0               /* acc low  += coefficient                   */
    adc   r25, r1               /* acc high += carry  (r1 = 0)               */
    movw  r18, r24              /* acc = acc*x + c                           */
    dec   r20
    brne  .Lhorner_loop
    movw  r24, r18              /* return acc in R25:R24                     */
    ret
.size horner8, .-horner8
