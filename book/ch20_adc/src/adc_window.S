/*
 * adc_window.S - ADC0 window comparator below half scale.
 * Target: ATtiny3217 Curiosity Nano.
 */

#include <avr/io.h>

.equ LED_BIT,          3
.equ ADC_PINCTRL,      0x04
.equ ADC_REF_1V1,      0x10
.equ ADC_PRESC_DIV16,  0x03
.equ ADC_INITDLY32,    0x40
.equ ADC_AIN4,         0x04
.equ ADC_SAMPLEN8,     8
.equ ADC_WIN_BELOW,    0x01

.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    rjmp  main

.section .text
.global main
main:
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    sbi   VPORTA_DIR, LED_BIT
    sbi   VPORTA_OUT, LED_BIT

    ldi   r16, ADC_PINCTRL
    sts   PORTA_PIN4CTRL, r16
    ldi   r16, ADC_REF_1V1
    sts   VREF_CTRLA, r16
    ldi   r16, ADC_PRESC_DIV16
    sts   ADC0_CTRLC, r16
    ldi   r16, ADC_INITDLY32
    sts   ADC0_CTRLD, r16
    ldi   r16, ADC_SAMPLEN8
    sts   ADC0_SAMPCTRL, r16
    ldi   r16, ADC_AIN4
    sts   ADC0_MUXPOS, r16

    ldi   r16, 0x00
    sts   ADC0_WINLTL, r16
    ldi   r16, 0x02
    sts   ADC0_WINLTH, r16
    ldi   r16, ADC_WIN_BELOW
    sts   ADC0_CTRLE, r16

    ldi   r16, ADC_ENABLE_bm
    sts   ADC0_CTRLA, r16

.Lmain_loop:
    rcall adc0_convert_window
    sbrc  r16, ADC_WCMP_bp
    rjmp  .Lbelow_threshold
    sbi   VPORTA_OUT, LED_BIT
    rjmp  .Lmain_loop
.Lbelow_threshold:
    cbi   VPORTA_OUT, LED_BIT
    rjmp  .Lmain_loop

adc0_convert_window:
    ldi   r16, ADC_STCONV_bm
    sts   ADC0_COMMAND, r16
.Lwait_adc:
    lds   r16, ADC0_INTFLAGS
    sbrs  r16, ADC_RESRDY_bp
    rjmp  .Lwait_adc
    mov   r17, r16
    lds   r24, ADC0_RESL
    lds   r25, ADC0_RESH
    ldi   r16, (ADC_RESRDY_bm | ADC_WCMP_bm)
    sts   ADC0_INTFLAGS, r16
    mov   r16, r17
    ret
