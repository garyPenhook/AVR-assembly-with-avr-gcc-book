/* ============================================================
 * mat2_vmul.S — 2x2 fixed-point matrix x vector  (Q15 matrix)
 * Target: ATtiny3217 (portable AVRxt; uses the hardware multiplier)
 * Build:  avr-gcc -mmcu=attiny3217 -nostartfiles mat2_vmul.S -o mat2_vmul.elf
 * ============================================================
 *
 * void mat2_vmul(const int16_t *M, const int16_t *vin, int16_t *vout)
 *   M    = r25:r24  -> 4 Q15 entries, row-major: M0 M1 / M2 M3
 *   vin  = r23:r22  -> 2 integer (Q0) coords: v0, v1
 *   vout = r21:r20  -> 2 results
 *
 *   vout[0] = (M0*v0 + M1*v1) >> 15
 *   vout[1] = (M2*v0 + M3*v1) >> 15
 *
 * The key fixed-point rule: accumulate the FULL 32-bit products and shift the
 * sum ONCE. Rounding each product before adding loses up to one LSB per term,
 * an error that compounds with the length of the dot product.
 *
 * Reuses the AVR201 signed 16x16->32 multiply (smul32) and a 32-bit arithmetic
 * shift (asr32) from the approximation chapter.
 *
 * Registers: v0=r15:r14, v1=r13:r12, partial P0=r7:r6:r5:r4, vout=Y, M=X.
 * ============================================================ */

.section .text
.global mat2_vmul

mat2_vmul:
    push  r2
    push  r4
    push  r5
    push  r6
    push  r7
    push  r12
    push  r13
    push  r14
    push  r15
    push  r28
    push  r29

    movw  r28, r20            /* Y = vout */
    movw  r30, r22            /* Z = vin  */
    ld    r14, Z+             /* v0 (r15:r14) */
    ld    r15, Z+
    ld    r12, Z+             /* v1 (r13:r12) */
    ld    r13, Z+
    movw  r26, r24            /* X = M */

    ldi   r24, 2             /* two rows */
.Lrow:
    /* P0 = M[k] * v0 */
    ld    r22, X+
    ld    r23, X+            /* A = M[k] */
    movw  r20, r14           /* B = v0   */
    rcall smul32             /* -> r19:r18:r17:r16 */
    movw  r4, r16            /* P0 low  = r5:r4  */
    movw  r6, r18            /* P0 high = r7:r6  */

    /* P1 = M[k+1] * v1 ; then acc = P0 + P1 */
    ld    r22, X+
    ld    r23, X+            /* A = M[k+1] */
    movw  r20, r12           /* B = v1     */
    rcall smul32             /* -> r19:r18:r17:r16 */
    add   r16, r4
    adc   r17, r5
    adc   r18, r6
    adc   r19, r7

    /* >>15 and store the low word */
    ldi   r20, 15
    rcall asr32
    st    Y+, r16
    st    Y+, r17

    dec   r24
    brne  .Lrow

    pop   r29
    pop   r28
    pop   r15
    pop   r14
    pop   r13
    pop   r12
    pop   r7
    pop   r6
    pop   r5
    pop   r4
    pop   r2
    ret

/* ---- smul32: signed 16x16 -> 32  (AVR201) ; A=r23:r22 B=r21:r20 -> r19:r18:r17:r16 */
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
1:  asr   r19
    ror   r18
    ror   r17
    ror   r16
    dec   r20
    brne  1b
    ret
