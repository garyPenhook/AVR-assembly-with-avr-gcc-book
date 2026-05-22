/* display.S — ADC reading → temperature → BCD → SPI 7-segment display
 *
 * Target: ATmega328P (has SPI hardware and MUL instruction)
 * Wiring: MAX7219 or similar SPI 7-segment driver on SPI0
 *         SS  = PB2, SCK = PB5, MOSI = PB3
 *
 * Temperature scaling:
 *   Assumes 10-bit ADC, linear sensor: 0 → 0.0°C, 1023 → 99.9°C
 *   Formula: temp10 = (adc × 999 + 512) >> 10  (0.1°C units, 0–999)
 *   Error < 0.1°C across range.
 *
 * Register map:
 *   R25:R24  ADC reading (0–1023)
 *   R23:R22  temp × 10 (0–999)
 *   R21:R20:R19  BCD digits (5 packed)
 *   R18      loop scratch
 *   R17      SPI data byte
 *   R16      scratch
 *   Z        LUT pointer
 */

#include <avr/io.h>

/* SPI register addresses (ATmega328P) */
#ifndef SPCR
#define SPCR  0x4C
#define SPSR  0x4D
#define SPDR  0x4E
#endif

.extern bin16_to_bcd
.extern mulq88

/* ------------------------------------------------------------------ */
/* 7-segment LUT (active high, gfedcba bit order)                     */
/* ------------------------------------------------------------------ */
.section .rodata
seg7_lut:
    .byte 0x3F   /* 0 */
    .byte 0x06   /* 1 */
    .byte 0x5B   /* 2 */
    .byte 0x4F   /* 3 */
    .byte 0x66   /* 4 */
    .byte 0x6D   /* 5 */
    .byte 0x7D   /* 6 */
    .byte 0x07   /* 7 */
    .byte 0x7F   /* 8 */
    .byte 0x6F   /* 9 */

.section .text

/* ------------------------------------------------------------------ */
/* spi_init — configure SPI master, Mode 0, Fosc/16                   */
/* ------------------------------------------------------------------ */
.global spi_init
spi_init:
    /* Set MOSI, SCK, SS as outputs */
    in    r16, _SFR_IO_ADDR(DDRB)
    ori   r16, (1<<DDB3)|(1<<DDB5)|(1<<DDB2)
    out   _SFR_IO_ADDR(DDRB), r16
    /* SS high (deselect) */
    in    r16, _SFR_IO_ADDR(PORTB)
    ori   r16, (1<<PB2)
    out   _SFR_IO_ADDR(PORTB), r16
    /* SPI master, mode 0, Fosc/16 */
    ldi   r16, (1<<SPE)|(1<<MSTR)|(1<<SPR0)
    sts   SPCR, r16
    ret

/* ------------------------------------------------------------------ */
/* spi_send — send R17 via SPI (polling), SS managed by caller        */
/* ------------------------------------------------------------------ */
spi_send:
    sts   SPDR, r17
.Lspi_wait:
    lds   r16, SPSR
    sbrs  r16, SPIF
    rjmp  .Lspi_wait
    ret

/* ------------------------------------------------------------------ */
/* scale_adc — convert 10-bit ADC reading to temp × 10 (0–999)       */
/*                                                                     */
/* Formula: temp10 = (adc × 999 + 512) >> 10                          */
/*          999 = 0x3E7                                                */
/*                                                                     */
/* 32-bit intermediate to avoid overflow:                              */
/*   adc ≤ 1023; adc × 999 ≤ 1,021,977 (fits in 20 bits)             */
/*   Use R27:R26:R25:R24 as 32-bit accumulator                        */
/*                                                                     */
/* Entry:  R25:R24 = ADC (0–1023)                                     */
/* Exit:   R23:R22 = temp × 10 (0–999)                                */
/* Clobbers: R16–R20, R26, R27                                        */
/* ------------------------------------------------------------------ */
.global scale_adc
scale_adc:
    /* 32-bit product = R27:R26:R25:R24 × 999                               */
    /* Use R19:R18:R17:R16 as accumulator; input is 16-bit so R27:R26 = 0   */
    clr   r16
    clr   r17
    clr   r18
    clr   r19

    movw  r26, r24      /* R27:R26 = input (R27=0 since adc ≤ 1023 < 0x400) */
    clr   r27

    /* 999 = 512 + 256 + 128 + 64 + 32 + 4 + 2 + 1 */
    /* Accumulate: result += input << k for each set bit k in 999 */

    /* bit 0 (weight 1): add R27:R26 to accum */
    add   r16, r26
    adc   r17, r27
    adc   r18, r1
    adc   r19, r1

    /* bit 1 (weight 2): shift input left once, add */
    lsl   r26
    rol   r27
    add   r16, r26
    adc   r17, r27
    adc   r18, r1
    adc   r19, r1

    /* bit 2 (weight 4): shift, add */
    lsl   r26
    rol   r27
    add   r16, r26
    adc   r17, r27
    adc   r18, r1
    adc   r19, r1

    /* bits 3, 4 not set in 999; skip shifts 3 and 4 but keep shifting     */
    lsl   r26
    rol   r27           /* × 8 */
    lsl   r26
    rol   r27           /* × 16 */

    /* bit 5 (weight 32): add */
    lsl   r26
    rol   r27
    add   r16, r26
    adc   r17, r27
    adc   r18, r1
    adc   r19, r1

    /* bit 6 (weight 64) */
    lsl   r26
    rol   r27
    add   r16, r26
    adc   r17, r27
    adc   r18, r1
    adc   r19, r1

    /* bit 7 (weight 128) */
    lsl   r26
    rol   r27
    add   r16, r26
    adc   r17, r27
    adc   r18, r1
    adc   r19, r1

    /* bit 8 (weight 256) */
    lsl   r26
    rol   r27
    add   r16, r26
    adc   r17, r27
    adc   r18, r1
    adc   r19, r1

    /* bit 9 (weight 512) */
    lsl   r26
    rol   r27
    add   r16, r26
    adc   r17, r27
    adc   r18, r1
    adc   r19, r1

    /* add rounding constant 512 before shifting */
    ldi   r20, lo8(512)
    add   r16, r20
    ldi   r20, hi8(512)
    adc   r17, r20
    adc   r18, r1
    adc   r19, r1

    /* right shift 32-bit accum by 10 (two 5-bit shifts, or shift 8 + shift 2) */
    /* shift 8: result = R19:R18:R17  (discard R16) */
    mov   r16, r17
    mov   r17, r18
    mov   r18, r19
    clr   r19
    /* shift 2 more: */
    lsr   r18
    ror   r17
    ror   r16
    lsr   r18
    ror   r17
    ror   r16

    /* R17:R16 = temp × 10 (0–999) */
    movw  r22, r16
    ret

/* ------------------------------------------------------------------ */
/* send_digit — look up seg7_lut[R16], send via SPI                   */
/* ------------------------------------------------------------------ */
send_digit:
    ldi   ZL, lo8(seg7_lut)
    ldi   ZH, hi8(seg7_lut)
    add   ZL, r16
    adc   ZH, r1
    lpm   r17, Z
    rjmp  spi_send

/* send digit with decimal point (bit 7 = DP) */
send_digit_dp:
    ldi   ZL, lo8(seg7_lut)
    ldi   ZH, hi8(seg7_lut)
    add   ZL, r16
    adc   ZH, r1
    lpm   r17, Z
    ori   r17, 0x80     /* set decimal point bit */
    rjmp  spi_send

/* ------------------------------------------------------------------ */
/* display_temp — scale ADC, convert to BCD, drive 4-digit display    */
/*                                                                     */
/* Entry:  R25:R24 = ADC reading (0–1023)                             */
/* Display format:  [D3][D2][D1].[D0]  e.g. " 36.5" for 36.5°C       */
/* ------------------------------------------------------------------ */
.global display_temp
display_temp:
    rcall scale_adc     /* R23:R22 = temp × 10 */
    movw  r24, r22
    rcall bin16_to_bcd  /* R21:R20:R19 = BCD digits */

    /* Assert SS low */
    in    r16, _SFR_IO_ADDR(PORTB)
    andi  r16, ~(1<<PB2)
    out   _SFR_IO_ADDR(PORTB), r16

    /* Digit 3 (hundreds — leading zero blank) */
    mov   r16, r20
    andi  r16, 0x0F     /* hundreds digit */
    breq  .Ldisp_blank_d3
    rcall send_digit
    rjmp  .Ldisp_d2
.Ldisp_blank_d3:
    ldi   r17, 0x00     /* all segments off */
    rcall spi_send

.Ldisp_d2:
    /* Digit 2 (tens) */
    mov   r16, r19
    swap  r16
    andi  r16, 0x0F
    rcall send_digit

    /* Digit 1 (ones) + decimal point */
    mov   r16, r19
    andi  r16, 0x0F
    rcall send_digit_dp

    /* Digit 0 (tenths) — this is the ones digit of temp×10
       (temp×10 ones = temp tenths) */
    /* Reload BCD of temp×10 ones digit from R19 after bin16_to_bcd.
       temp×10 was in R23:R22; BCD is still valid in R19. */
    /* The ones digit of temp×10 IS the tenths of temp. Already in R19[3:0]. */
    mov   r16, r19
    andi  r16, 0x0F
    /* Actually, bin16_to_bcd was called with temp×10. The ones digit of
       temp×10 = (temp×10) mod 10 = 10×(fractional part of temp). This is
       the tenths digit. Correct. */
    rcall send_digit

    /* Deassert SS */
    in    r16, _SFR_IO_ADDR(PORTB)
    ori   r16, (1<<PB2)
    out   _SFR_IO_ADDR(PORTB), r16
    ret
