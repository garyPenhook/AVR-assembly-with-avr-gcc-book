/* display.S — ADC reading → temperature → BCD → SPI 7-segment display
 *
 * Target: ATmega328P (has SPI hardware and MUL instruction)
 * Wiring: raw segment-byte SPI/shift-register display interface on SPI0
 *         SS  = PB2, SCK = PB5, MOSI = PB3
 *
 * Temperature scaling:
 *   Assumes 10-bit ADC, linear sensor: 0 → 0.0°C, 1023 → 99.9°C
 *   Formula: temp10 = (adc × 63998 + 32768) >> 16
 *            63998 = round(999 / 1023 × 65536)
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
/* Formula: temp10 = (adc × 63998 + 32768) >> 16                       */
/*          63998 = 0xF9FE = round(999 / 1023 × 65536)                 */
/*                                                                     */
/* 32-bit intermediate to avoid overflow:                              */
/*   adc ≤ 1023; adc × 63998 ≤ 65,469,954 (fits in 26 bits)           */
/*   Use R19:R18:R17:R16 as 32-bit accumulator                        */
/*                                                                     */
/* Entry:  R25:R24 = ADC (0–1023)                                     */
/* Exit:   R23:R22 = temp × 10 (0–999)                                */
/* Clobbers: R0, R1, R16–R21                                          */
/* ------------------------------------------------------------------ */
.global scale_adc
scale_adc:
    /* 32-bit product = ADC * 0xF9FE in R19:R18:R17:R16. */
    clr   r16
    clr   r17
    clr   r18
    clr   r19
    clr   r21           /* zero for carry propagation */

    /* AL * low(scale) -> bits [15:0] */
    ldi   r20, lo8(63998)
    mul   r24, r20
    movw  r16, r0

    /* AH * low(scale) -> bits [23:8] */
    mul   r25, r20
    add   r17, r0
    adc   r18, r1
    adc   r19, r21

    /* AL * high(scale) -> bits [23:8] */
    ldi   r20, hi8(63998)
    mul   r24, r20
    add   r17, r0
    adc   r18, r1
    adc   r19, r21

    /* AH * high(scale) -> bits [31:16] */
    mul   r25, r20
    add   r18, r0
    adc   r19, r1

    /* Round before >> 16 by adding 0x00008000. */
    ldi   r20, 0x80
    add   r17, r20
    adc   r18, r21
    adc   r19, r21

    clr   r1            /* restore zero-register convention after MUL */

    /* R19:R18 = temp × 10 (0–999) */
    movw  r22, r18
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
/* Display format:  [blank][tens][ones].[tenths], e.g. " 36.5"       */
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

    /* Digit 3: blank, because scaled range is 0.0 through 99.9. */
    ldi   r17, 0x00     /* all segments off */
    rcall spi_send

    /* Digit 2: tens of degrees (hundreds digit of temp×10) */
    mov   r16, r20
    andi  r16, 0x0F
    rcall send_digit

    /* Digit 1: ones of degrees (tens digit of temp×10), with decimal point */
    mov   r16, r19
    swap  r16
    andi  r16, 0x0F
    rcall send_digit_dp

    /* Digit 0: tenths of degrees (ones digit of temp×10) */
    mov   r16, r19
    andi  r16, 0x0F
    rcall send_digit

    /* Deassert SS */
    in    r16, _SFR_IO_ADDR(PORTB)
    ori   r16, (1<<PB2)
    out   _SFR_IO_ADDR(PORTB), r16
    ret
