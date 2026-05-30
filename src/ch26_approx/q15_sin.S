/* ============================================================
 * q15_sin.S — fixed-point sine via a minimax odd polynomial
 * Target: ATtiny3217 (portable AVRxt; uses the hardware multiplier)
 * Build:  avr-gcc -mmcu=attiny3217 -nostartfiles q15_sin.S -o q15_sin.elf
 * ============================================================
 *
 * uint... int16_t q15_sin(int16_t x)
 *   in : x  = angle in Q14, valid range [0, pi/2] = [0, 25736]
 *   out: sin(x) in Q15
 *
 * Method: a degree-5 ODD minimax-style polynomial (only x, x^3, x^5 terms),
 * evaluated with Horner. Coefficients were fit by least squares on [0, pi/2]
 * and rounded to Q15; the resulting max error is ~7.6 LSB of Q15 (2.3e-4),
 * versus ~148 LSB for the same-degree Taylor series. See the host reference
 * model sinref.c, which is swept over all 25737 inputs to confirm the bound.
 *
 *   sin(x) ~= ((c5*x^2 + c3)*x^2 + c1) * x     (all in fixed point)
 *   c1 = +0.999786  -> 32761   (Q15)
 *   c3 = -0.165833  ->  -5434  (Q15)
 *   c5 = +0.007568  ->    248  (Q15)
 *
 * Fixed-point bookkeeping (arithmetic shifts, toward -inf, matching ASR):
 *   x2 = (x  * x ) >> 15   ; Q14*Q14 = Q28 -> Q13
 *   p  = c5                ; Q15
 *   p  = c3 + (p*x2) >> 13 ; Q15*Q13 = Q28 -> Q15
 *   p  = c1 + (p*x2) >> 13 ; Q15
 *   r  =      (p*x ) >> 14 ; Q15*Q14 = Q29 -> Q15, then clamp the +4 LSB overshoot
 *
 * Register use: x in r15:r14, x2 in r13:r12 (call-saved, restored).
 * Helpers smul32 / asr32 use r0,r1,r2 and r16-r23 (scratch).
 * ============================================================ */

.section .text
.global q15_sin

q15_sin:                        /* x = r25:r24 (Q14) -> r25:r24 (Q15) */
    push  r2
    push  r12
    push  r13
    push  r14
    push  r15
    movw  r14, r24              /* save x in r15:r14 */

    /* x2 = (x*x) >> 15  (Q13) */
    movw  r22, r14
    movw  r20, r14
    rcall smul32
    ldi   r20, 15
    rcall asr32
    movw  r12, r16             /* x2 = r13:r12 */

    /* p = c5 */
    ldi   r24, lo8(248)
    ldi   r25, hi8(248)

    /* p = c3 + (p*x2) >> 13 */
    movw  r22, r24
    movw  r20, r12
    rcall smul32
    ldi   r20, 13
    rcall asr32
    ldi   r24, lo8(-5434)
    ldi   r25, hi8(-5434)
    add   r24, r16
    adc   r25, r17

    /* p = c1 + (p*x2) >> 13 */
    movw  r22, r24
    movw  r20, r12
    rcall smul32
    ldi   r20, 13
    rcall asr32
    ldi   r24, lo8(32761)
    ldi   r25, hi8(32761)
    add   r24, r16
    adc   r25, r17

    /* r = (p*x) >> 14 */
    movw  r22, r24
    movw  r20, r14
    rcall smul32
    ldi   r20, 14
    rcall asr32
    movw  r24, r16             /* result -> r25:r24 */

    /* saturate the small positive overshoot: result in [0,1], so bit15 set
     * means it crept above Q15 max -> clamp to 0x7FFF. */
    tst   r25
    brpl  1f
    ldi   r24, 0xFF
    ldi   r25, 0x7F
1:
    pop   r15
    pop   r14
    pop   r13
    pop   r12
    pop   r2
    ret

/* ---- smul32: signed 16x16 -> 32  (AVR201) -----------------
 * A = r23:r22, B = r21:r20  ->  r19:r18:r17:r16 ; clobbers r0,r1,r2 */
smul32:
    clr   r2
    muls  r23, r21
    movw  r18, r0
    mul   r22, r20
    movw  r16, r0
    mulsu r23, r20
    sbc   r19, r2
    add   r17, r0
    adc   r18, r1
    adc   r19, r2
    mulsu r21, r22
    sbc   r19, r2
    add   r17, r0
    adc   r18, r1
    adc   r19, r2
    clr   r1
    ret

/* ---- asr32: arithmetic shift r19:r18:r17:r16 right by r20 ---- */
asr32:
2:  asr   r19
    ror   r18
    ror   r17
    ror   r16
    dec   r20
    brne  2b
    ret
