/* fixedpoint.S — Q8.8 fixed-point arithmetic (ATtiny3217, shift-and-add only)
 *
 * mulq88 — unsigned Q8.8 × Q8.8 → Q8.8 using mul8u (no MUL instruction)
 */

#include <avr/io.h>

/*
 * mulq88 — unsigned Q8.8 × Q8.8 → Q8.8
 *
 * Entry:  R25:R24 = A (Q8.8)
 *         R23:R22 = B (Q8.8)
 * Exit:   R25:R24 = A × B (Q8.8, lower bits truncated)
 * Clobbers: R0, R1, R14–R21 (saves/restores R14, R15 via stack)
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
mulq88:
    push  r14           /* save R14, R15 (call-saved in GCC ABI)             */
    push  r15

    /* Save A and B — mul8u clobbers R24/R25 */
    mov   r14, r24      /* R14 = AL */
    mov   r15, r25      /* R15 = AH */
    /* R22 = BL, R23 = BH — not clobbered by mul8u (uses R16/R17/R18/R20)  */

    clr   r16           /* weight-8 accumulator low */
    clr   r17           /* weight-16 accumulator */

    /* AL × BL */
    mov   r16, r14      /* multiplicand = AL */
    mov   r17, r22      /* multiplier   = BL */
    rcall mul8u         /* R25:R24 = AL×BL */
    mov   r16, r25      /* save high byte of AL×BL */
    clr   r17

    /* AL × BH */
    mov   r16, r14
    mov   r17, r23      /* BH */
    rcall mul8u
    add   r16, r24
    adc   r17, r25

    /* AH × BL */
    mov   r16, r15      /* AH */
    mov   r17, r22      /* BL */
    rcall mul8u
    add   r16, r24
    adc   r17, r25

    /* AH × BH */
    mov   r16, r15      /* AH */
    mov   r17, r23      /* BH */
    rcall mul8u
    add   r17, r24      /* low byte of AH×BH contributes to weight-16 */
    /* R25 = high byte of AH×BH = overflow, discard */

    movw  r24, r16      /* R25:R24 = result */

    pop   r15
    pop   r14
    ret
