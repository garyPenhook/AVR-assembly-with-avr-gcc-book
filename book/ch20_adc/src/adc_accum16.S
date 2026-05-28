/*
 * adc_accum16.S - ADC0 AIN4 with 16-sample hardware accumulation.
 *
 * Target: ATtiny3217 Curiosity Nano, factory clock 3.333 MHz.
 *
 * The ATtiny3217 ADC can accumulate up to 64 conversions in hardware.
 * With ACCUMULATE=16 samples, RESL:RESH holds the sum (0..16×1023 = 16368).
 * Divide by 16 (right-shift 4) to get the averaged result in 0..1023.
 * This improves effective resolution by reducing noise (oversampling).
 */

#include <avr/io.h>

/* (Constants match adc_poll.S — see that file for detailed explanations.)   */
.equ LED_BIT,          3       /* PA3, Curiosity Nano LED0 (active-low)        */
.equ ADC_PINCTRL,      0x04    /* PORTA_PIN4CTRL: disable digital input buffer */
.equ ADC_REF_1V1,      0x10    /* VREF_CTRLA: ADC0REFSEL = 1.1 V              */
.equ ADC_REFEN,        0x02    /* VREF_CTRLB: force ADC0 reference on          */
.equ ADC_PRESC_DIV16,  0x03    /* ADC0_CTRLC: CLK_ADC = CLK_PER / 16          */
.equ ADC_INITDLY32,    0x40    /* ADC0_CTRLD: 32 CLK_ADC startup delay         */
.equ ADC_AIN4,         0x04    /* ADC0_MUXPOS: select PA4 / AIN4               */
.equ ADC_SAMPLEN8,     8       /* ADC0_SAMPCTRL: 8 extra sample cycles         */

/* ADC0_CTRLB: SAMPNUM field = 0x04 = ADC_SAMPNUM_ACC16_gc.
 * Tells the ADC to accumulate 16 consecutive conversions before setting
 * RESRDY. The result register then holds the 16-sample sum (up to 16368).   */
.equ ADC_ACC16,        0x04

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

    sbi   VPORTA_DIR, LED_BIT           /* PA3 = output                        */
    sbi   VPORTA_OUT, LED_BIT           /* LED off (active-low: 1 = off)       */

    ldi   r16, ADC_PINCTRL
    sts   PORTA_PIN4CTRL, r16           /* disable digital input buffer on PA4 */
    ldi   r16, ADC_REF_1V1
    sts   VREF_CTRLA, r16               /* 1.1 V internal reference             */
    ldi   r16, ADC_REFEN
    sts   VREF_CTRLB, r16               /* hold reference on continuously       */
    ldi   r16, ADC_PRESC_DIV16
    sts   ADC0_CTRLC, r16               /* CLK_ADC = CLK_PER / 16 ≈ 208 kHz    */
    ldi   r16, ADC_INITDLY32
    sts   ADC0_CTRLD, r16               /* 32 CLK_ADC startup delay             */
    ldi   r16, ADC_SAMPLEN8
    sts   ADC0_SAMPCTRL, r16            /* extend sample by 8 CLK_ADC cycles   */
    ldi   r16, ADC_ACC16
    sts   ADC0_CTRLB, r16               /* accumulate 16 conversions per result */
    ldi   r16, ADC_AIN4
    sts   ADC0_MUXPOS, r16              /* select PA4 / AIN4                   */
    ldi   r16, ADC_ENABLE_bm
    sts   ADC0_CTRLA, r16               /* enable ADC0                          */

.Lmain_loop:
    rcall adc0_read_acc16_avg           /* r25:r24 = 16-sample average (0..1023) */
    sbrs  r25, 1                        /* bit 9 set → average >= 512           */
    rjmp  .Lbelow_half
    sbi   VPORTA_OUT, LED_BIT           /* >= 512: LED off                      */
    rjmp  .Lmain_loop
.Lbelow_half:
    cbi   VPORTA_OUT, LED_BIT           /* < 512: LED on                        */
    rjmp  .Lmain_loop

/* ── adc0_read_acc16_avg ────────────────────────────────────────────────────
 * Trigger a 16-sample accumulation, wait for completion, then divide the
 * sum by 16 to produce an averaged result in 0..1023.
 * Dividing by 16 = four logical right-shifts (LSR high, ROR low each time).
 * Exit: R25:R24 = average. Clobbers: R16.                                    */
adc0_read_acc16_avg:
    ldi   r16, ADC_STCONV_bm
    sts   ADC0_COMMAND, r16             /* start 16-sample accumulation run     */
.Lwait_adc:
    lds   r16, ADC0_INTFLAGS
    sbrs  r16, ADC_RESRDY_bp            /* RESRDY set after all 16 conversions  */
    rjmp  .Lwait_adc
    lds   r24, ADC0_RESL                /* result = sum of 16 samples (0..16368) */
    lds   r25, ADC0_RESH
    ldi   r16, ADC_RESRDY_bm
    sts   ADC0_INTFLAGS, r16            /* clear RESRDY flag (W1C)              */

    /* Divide 16-bit sum by 16 (4 right-shifts).
     * LSR shifts high byte right (0 → bit 7), old bit 0 → Carry.
     * ROR shifts low byte right, Carry from LSR → bit 7.                   */
    lsr   r25
    ror   r24                           /* ÷ 2 (shift 1)                        */
    lsr   r25
    ror   r24                           /* ÷ 4 (shift 2)                        */
    lsr   r25
    ror   r24                           /* ÷ 8 (shift 3)                        */
    lsr   r25
    ror   r24                           /* ÷ 16 (shift 4) → 0..1023 average     */
    ret

default_isr:
    reti
