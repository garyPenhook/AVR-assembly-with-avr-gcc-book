/*
 * adc_freerun.S - ADC0 AIN4 in free-running mode.
 * Target: ATtiny3217 Curiosity Nano.
 */

#include <avr/io.h>

.equ LED_BIT,          3
.equ ADC_PINCTRL,      0x04
.equ ADC_REF_1V1,      0x10
.equ ADC_REFEN,        0x02
.equ ADC_PRESC_DIV16,  0x03
.equ ADC_INITDLY32,    0x40
.equ ADC_AIN4,         0x04
.equ ADC_SAMPLEN8,     8

.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    jmp   main
    .rept 30
    jmp   default_isr
    .endr

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
    ldi   r16, ADC_REFEN
    sts   VREF_CTRLB, r16
    ldi   r16, ADC_PRESC_DIV16
    sts   ADC0_CTRLC, r16
    ldi   r16, ADC_INITDLY32
    sts   ADC0_CTRLD, r16
    ldi   r16, ADC_SAMPLEN8
    sts   ADC0_SAMPCTRL, r16
    ldi   r16, ADC_AIN4
    sts   ADC0_MUXPOS, r16

    ldi   r16, (ADC_ENABLE_bm | ADC_FREERUN_bm)
    sts   ADC0_CTRLA, r16

    ldi   r16, ADC_STCONV_bm
    sts   ADC0_COMMAND, r16

.Lmain_loop:
    rcall adc0_read_latest
    sbrs  r25, 1
    rjmp  .Lbelow_half
    sbi   VPORTA_OUT, LED_BIT
    rjmp  .Lmain_loop
.Lbelow_half:
    cbi   VPORTA_OUT, LED_BIT
    rjmp  .Lmain_loop

adc0_read_latest:
.Lwait_adc:
    lds   r16, ADC0_INTFLAGS
    sbrs  r16, ADC_RESRDY_bp
    rjmp  .Lwait_adc
    lds   r24, ADC0_RESL
    lds   r25, ADC0_RESH
    ldi   r16, ADC_RESRDY_bm
    sts   ADC0_INTFLAGS, r16
    ret

default_isr:
    reti
