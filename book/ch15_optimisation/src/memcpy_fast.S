#include <avr/io.h>

/* memcpy_fast -- unrolled 4x copy with tail handler
 *
 * Register interface used by the assembly benchmark:
 *   dst   R25:R24  (pointer)
 *   src   R23:R22  (pointer)
 *   len   R20      (uint8_t)
 *
 * Strategy: process 4 bytes per loop iteration (unrolled x4),
 * handle remaining 0-3 bytes with a compact tail loop.
 *
 * Registers used (all call-clobbered, no push/pop needed):
 *   Z (R31:R30) = src
 *   X (R27:R26) = dst
 *   R20  = len
 *   R21  = len & 3 (tail count)
 *   R18-R21 = four data bytes per unrolled iteration
 */

.section .text
.global memcpy_fast
.type   memcpy_fast, @function
memcpy_fast:
    movw  ZL, r22           /* Z = src                                      */
    movw  XL, r24           /* X = dst                                      */
    tst   r20
    breq  .Lfast_done

    /* compute tail = len % 4 and blocks = len / 4 */
    mov   r21, r20
    andi  r21, 0x03         /* r21 = len & 3 (tail count: 0..3)             */
    lsr   r20
    lsr   r20               /* r20 = len >> 2 = number of 4-byte blocks     */
    breq  .Lfast_tail       /* no full blocks: go straight to tail          */

.Lfast_block:
    ld    r18, Z+
    ld    r19, Z+
    ld    r22, Z+
    ld    r23, Z+
    st    X+, r18
    st    X+, r19
    st    X+, r22
    st    X+, r23
    dec   r20
    brne  .Lfast_block

    /* tail: 0, 1, 2, or 3 remaining bytes */
.Lfast_tail:
    tst   r21
    breq  .Lfast_done
    ld    r18, Z+
    st    X+, r18
    dec   r21
    brne  .Lfast_tail

.Lfast_done:
    ret

.size   memcpy_fast, .-memcpy_fast
