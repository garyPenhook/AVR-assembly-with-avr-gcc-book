/*
 * adc_poll.S - Poll ADC0 AIN4 and drive LED0.
 * Target: ATtiny3217 Curiosity Nano, factory clock about 3.333 MHz.
 *
 * PA4/AIN4 is sampled with ADC0 using the internal 1.1 V reference.
 * If the result is below half scale, LED0 on PA3 is turned on.
 * If the result is half scale or above, LED0 is turned off.
 */

#include <avr/io.h>

.equ LED_BIT,          3       /* PA3, active-low LED0 */
.equ ADC_PINCTRL,      0x04    /* PORT ISC input buffer disabled */
.equ ADC_REF_1V1,      0x10    /* VREF ADC0REFSEL = 1.1 V, bits 6:4 */
.equ ADC_PRESC_DIV16,  0x03    /* ADC0_CTRLC: internal ref, prescaler /16 */
.equ ADC_INITDLY32,    0x40    /* ADC0_CTRLD: 32 CLK_ADC startup delay */
.equ ADC_AIN4,         0x04    /* PA4 / AIN4 */
.equ ADC_SAMPLEN8,     8

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
    sbi   VPORTA_OUT, LED_BIT       /* LED off */

    ldi   r16, ADC_PINCTRL
    sts   PORTA_PIN4CTRL, r16       /* disable digital input on PA4 */

    ldi   r16, ADC_REF_1V1
    sts   VREF_CTRLA, r16           /* internal 1.1 V reference for ADC0 */

    ldi   r16, ADC_PRESC_DIV16
    sts   ADC0_CTRLC, r16

    ldi   r16, ADC_INITDLY32
    sts   ADC0_CTRLD, r16

    ldi   r16, ADC_SAMPLEN8
    sts   ADC0_SAMPCTRL, r16

    ldi   r16, ADC_AIN4
    sts   ADC0_MUXPOS, r16

    ldi   r16, ADC_ENABLE_bm
    sts   ADC0_CTRLA, r16

.Lmain_loop:
    rcall adc0_read_ain4

    sbrs  r25, 1                    /* result bit 9 set means >= 512 */
    rjmp  .Lbelow_half

    sbi   VPORTA_OUT, LED_BIT       /* LED off */
    rjmp  .Lmain_loop

.Lbelow_half:
    cbi   VPORTA_OUT, LED_BIT       /* LED on */
    rjmp  .Lmain_loop

adc0_read_ain4:
    ldi   r16, ADC_STCONV_bm
    sts   ADC0_COMMAND, r16

.Lwait_adc:
    lds   r16, ADC0_INTFLAGS
    sbrs  r16, ADC_RESRDY_bp
    rjmp  .Lwait_adc

    lds   r24, ADC0_RESL
    lds   r25, ADC0_RESH

    ldi   r16, ADC_RESRDY_bm
    sts   ADC0_INTFLAGS, r16
    ret
