/* isqrt16.S — 16-bit integer square root, digit-by-digit (no MUL, no divide)
 *             Companion source for Chapter 17: Bit Manipulation & Fixed-Point Math
 *             (see "Integer Square Root" section)
 *
 * Works on any AVR: only shifts, adds, subtracts, and compares.
 *
 * Algorithm (binary "digit-by-digit", two bits per step). Maintain a result
 * "res" and a probe "bit" that walks down the powers of four. At each step the
 * trial value is res + bit:
 *   if N >= res + bit:  subtract it, and set res = (res >> 1) + bit
 *   else:                              res = (res >> 1)
 *   bit >>= 2
 * Starting bit at 0x4000 (= 4^7, the largest power of four in 16 bits) and
 * running a fixed 8 steps covers every input 0..65535. Starting too high for a
 * small N is harmless: those early steps just take the else branch and leave
 * res at 0, so no alignment pre-loop is needed.
 *
 * Entry:  R25:R24 = N, unsigned 16-bit (0..65535)
 * Exit:   R24     = floor(sqrt(N)), 0..255   (R25 is left as the remaining
 *                   high bits of N and should be ignored)
 * Clobbers: R18, R20, R21, R22, R23, R26, R27, and R25
 * Cycles: 137 (N=0) to 177 (N=65535) including RET on AVRxt. The fixed 8
 *         iterations make timing nearly constant; the only variation is the
 *         taken/not-taken trial branch each step.
 */

#include <avr/io.h>

.global isqrt16
.type   isqrt16, @function
isqrt16:
    clr   r22                  /* res = 0 (R23:R22)                          */
    clr   r23
    ldi   r20, 0x00            /* bit = 0x4000 (R21:R20) = 4^7               */
    ldi   r21, 0x40
    ldi   r18, 8               /* fixed iteration count                      */
.Lsq_loop:
    movw  r26, r22             /* sum = res            (R27:R26)             */
    add   r26, r20             /* sum += bit                                 */
    adc   r27, r21
    cp    r24, r26             /* compare N : sum                            */
    cpc   r25, r27
    brlo  .Lsq_else            /* N < sum -> no subtract                     */
    sub   r24, r26             /* N -= sum                                   */
    sbc   r25, r27
    lsr   r23                  /* res >>= 1                                  */
    ror   r22
    add   r22, r20             /* res += bit                                 */
    adc   r23, r21
    rjmp  .Lsq_next
.Lsq_else:
    lsr   r23                  /* res >>= 1                                  */
    ror   r22
.Lsq_next:
    lsr   r21                  /* bit >>= 2                                  */
    ror   r20
    lsr   r21
    ror   r20
    dec   r18
    brne  .Lsq_loop
    mov   r24, r22             /* return low byte of res (0..255)            */
    ret
.size isqrt16, .-isqrt16
