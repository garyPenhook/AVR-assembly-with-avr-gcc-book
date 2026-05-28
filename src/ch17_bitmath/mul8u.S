/* mul8u.S — unsigned 8×8 → 16 shift-and-add multiply
 *
 * Works on any AVR (no MUL instruction needed).
 *
 * Entry:  R16 = multiplicand A
 *         R17 = multiplier   B
 * Exit:   R25:R24 = A × B (unsigned 16-bit)
 * Clobbers: R16, R17, R18, R20
 * Cycles: 71 + popcount(multiplier), including setup and RET (AVRxt)
 */

#include <avr/io.h>

.global mul8u
.type mul8u, @function
mul8u:
    clr   r24
    clr   r25
    clr   r20           /* multiplicand high byte */
    ldi   r18, 8
.Lmul8u_loop:
    lsr   r17           /* LSB of multiplier → C */
    brcc  .Lmul8u_skip
    add   r24, r16
    adc   r25, r20
.Lmul8u_skip:
    lsl   r16           /* multiplicand <<= 1 */
    rol   r20
    dec   r18
    brne  .Lmul8u_loop
    ret
.size mul8u, .-mul8u

/* mul8s — signed 8×8 → 16 multiply
 *
 * Entry:  R16 = multiplicand (signed int8)
 *         R17 = multiplier   (signed int8)
 * Exit:   R25:R24 = R16 × R17 (signed int16)
 * Clobbers: R16, R17, R18, R20
 */

.global mul8s
.type mul8s, @function
mul8s:
    clr   r24
    clr   r25
    /* sign-extend R16 into R20 */
    mov   r20, r16
    lsl   r20           /* old bit 7 of R16 → C */
    sbc   r20, r20      /* r20 = 0xFF if negative, 0x00 if positive */
    ldi   r18, 7        /* 7 unsigned bits */
.Lmul8s_loop:
    lsr   r17
    brcc  .Lmul8s_skip
    add   r24, r16
    adc   r25, r20
.Lmul8s_skip:
    lsl   r16
    rol   r20
    dec   r18
    brne  .Lmul8s_loop
    /* bit 7 of multiplier: negative weight → subtract */
    lsr   r17
    brcc  .Lmul8s_done
    sub   r24, r16
    sbc   r25, r20
.Lmul8s_done:
    ret
.size mul8s, .-mul8s
