/* bin16_to_bcd.S — double-dabble: 16-bit binary → 5-digit packed BCD
 *
 * Entry:  R25:R24 = 16-bit unsigned value (0–65535)
 * Exit:   R21:R20:R19 = packed BCD (5 digits)
 *           R21[3:0]  = ten-thousands
 *           R20[7:4]  = thousands
 *           R20[3:0]  = hundreds
 *           R19[7:4]  = tens
 *           R19[3:0]  = ones
 * Clobbers: R16, R17, R22
 *
 * Algorithm: double-dabble (shift-and-add-3)
 * Cycles: 16 × (bcd_adjust [~25] + 5 shifts + 3 loop overhead) ≈ 528
 */

#include <avr/io.h>

.global bin16_to_bcd
bin16_to_bcd:
    clr   r19
    clr   r20
    clr   r21
    ldi   r16, 16

.Lbcd_loop:
    rcall bcd_adjust

    /* shift binary value and BCD digits left by 1 bit together */
    lsl   r24
    rol   r25
    rol   r19
    rol   r20
    rol   r21

    dec   r16
    brne  .Lbcd_loop
    ret

/*
 * bcd_adjust — add 3 to any BCD nibble > 4 in R21:R20:R19
 * Clobbers: R17, R22
 */
bcd_adjust:
    /* R19 low nibble (ones) */
    mov   r22, r19
    andi  r22, 0x0F
    cpi   r22, 5
    brlo  .Lbcda_r19h
    subi  r19, -3
.Lbcda_r19h:
    /* R19 high nibble (tens) */
    mov   r22, r19
    andi  r22, 0xF0
    cpi   r22, 0x50
    brlo  .Lbcda_r20l
    subi  r19, -0x30
.Lbcda_r20l:
    /* R20 low nibble (hundreds) */
    mov   r22, r20
    andi  r22, 0x0F
    cpi   r22, 5
    brlo  .Lbcda_r20h
    subi  r20, -3
.Lbcda_r20h:
    /* R20 high nibble (thousands) */
    mov   r22, r20
    andi  r22, 0xF0
    cpi   r22, 0x50
    brlo  .Lbcda_r21
    subi  r20, -0x30
.Lbcda_r21:
    /* R21 low nibble (ten-thousands; max 6) */
    mov   r22, r21
    andi  r22, 0x0F
    cpi   r22, 5
    brlo  .Lbcda_done
    subi  r21, -3
.Lbcda_done:
    ret
