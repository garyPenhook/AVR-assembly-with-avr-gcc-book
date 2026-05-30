/* vec.S - a small library: each function in its own section for --gc-sections */
.section .text.vec_add,"ax",@progbits
.global vec_add                 /* int16_t vec_add(int16_t a, int16_t b) */
vec_add:                        /* a=r25:r24, b=r23:r22 -> r25:r24 */
    add   r24, r22
    adc   r25, r23
    ret

.section .text.vec_scale,"ax",@progbits
.global vec_scale               /* int16_t vec_scale(int16_t a, int16_t k) */
vec_scale:                      /* UNUSED by main -> should be GC'd */
    muls  r25, r23
    movw  r24, r0
    clr   r1
    ret
