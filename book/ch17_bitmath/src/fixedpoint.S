/* fixedpoint.S — Q8.8 fixed-point arithmetic (ATtiny3217, portable multiply)
 *
 * mulq88 — unsigned Q8.8 × Q8.8 → Q8.8 using mul8u.
 */

#include <avr/io.h>

/*
 * mulq88 — unsigned Q8.8 × Q8.8 → Q8.8
 *
 * Entry:  R25:R24 = A (Q8.8)
 *         R23:R22 = B (Q8.8)
 * Exit:   R25:R24 = A × B (Q8.8, lower bits truncated)
 * Clobbers: R16, R17, R18, R20–R25
 * Saves/restores: R12–R15
 *
 * Uses mul8u (must be linked from mul8u.S).
 * Four partial products; extract bits [23:8] of 32-bit result.
 *
 * A = AH:AL = R25:R24    B = BH:BL = R23:R22
 *
 * Full product bits [31..0]:
 *   [31:16] = AH×BH
 *   [23:8]  = AH×BL + AL×BH  (cross-terms)
 *   [15:0]  = AL×BL
 *
 * Q8.8 result = bits [23:8] = shift-right-8 of 32-bit product.
 */

.extern mul8u

.global mulq88
.type mulq88, @function
mulq88:
    push  r12
    push  r13
    push  r14
    push  r15

    /* Save A and B; mul8u clobbers the argument and result registers. */
    mov   r12, r24      /* AL */
    mov   r13, r25      /* AH */
    mov   r14, r22      /* BL */
    mov   r15, r23      /* BH */

    /* AL × BL */
    mov   r16, r12      /* multiplicand = AL */
    mov   r17, r14      /* multiplier   = BL */
    rcall mul8u         /* R25:R24 = AL×BL */
    mov   r21, r25      /* result low byte starts with high(AL×BL) */
    clr   r22           /* result high byte */

    /* AL × BH */
    mov   r16, r12
    mov   r17, r15
    rcall mul8u
    add   r21, r24
    adc   r22, r25

    /* AH × BL */
    mov   r16, r13
    mov   r17, r14
    rcall mul8u
    add   r21, r24
    adc   r22, r25

    /* AH × BH */
    mov   r16, r13
    mov   r17, r15
    rcall mul8u
    add   r22, r24      /* low byte of AH×BH contributes to result high byte */
    /* R25 = high byte of AH×BH = overflow beyond Q8.8 result, discarded. */

    mov   r24, r21
    mov   r25, r22

    pop   r15
    pop   r14
    pop   r13
    pop   r12
    ret
.size mulq88, .-mulq88
