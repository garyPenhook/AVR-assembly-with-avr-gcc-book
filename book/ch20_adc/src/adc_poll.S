/*
 * adc_poll.S - Poll ADC0 AIN4 and drive LED0.
 * Target: ATtiny3217 Curiosity Nano, factory clock about 3.333 MHz.
 *
 * PA4/AIN4 is sampled with ADC0 using the internal 1.1 V reference.
 * If the result is below half scale, LED0 on PA3 is turned on.
 * If the result is half scale or above, LED0 is turned off.
 */

#include <avr/io.h>

/* ── Constants ───────────────────────────────────────────────────────────── */
.equ LED_BIT,          3       /* PA3, Curiosity Nano LED0 (active-low)        */

/* PORTA_PIN4CTRL ISC field: INPUT_DISABLE (0x04) turns off the digital input
 * buffer on PA4/AIN4. Required by the datasheet when using a pin as ADC input
 * to avoid leakage current through the Schmitt trigger and reduce noise.     */
.equ ADC_PINCTRL,      0x04

/* VREF_CTRLA: ADC0REFSEL field (bits [6:4] = 0x01) selects 1.1 V internal
 * reference. Shifted into the correct field: 0x01 << 4 = 0x10.              */
.equ ADC_REF_1V1,      0x10

/* VREF_CTRLB bit 1 = ADC0REFEN: force-enable the 1.1 V reference so it is
 * on continuously (not just when a conversion is running). Required to allow
 * the reference to settle before the first conversion.                       */
.equ ADC_REFEN,        0x02

/* ADC0_CTRLC: REFSEL bits [1:0] = 0 (use the internal VREF configured above)
 * PRESC bits [5:4] = 0x03 (CLK_ADC = CLK_PER / 16 = 3333333/16 ≈ 208 kHz).
 * ADC datasheet requirement: CLK_ADC must be between 100 kHz and 1.5 MHz.   */
.equ ADC_PRESC_DIV16,  0x03

/* ADC0_CTRLD: INITDLY bits [6:4] = 0x04 (32 CLK_ADC cycles startup delay).
 * The ADC needs time after the reference is enabled before the first result
 * is accurate. 32 CLK_ADC at 208 kHz ≈ 154 µs startup delay.               */
.equ ADC_INITDLY32,    0x40

.equ ADC_AIN4,         0x04    /* ADC0_MUXPOS: select PA4 / AIN4               */

/* ADC0_SAMPCTRL: SAMPLEN field extends the sampling time by N CLK_ADC cycles.
 * SAMPLEN = 8 adds 8 extra cycles → total sample time = 2 + 8 = 10 CLK_ADC. */
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

    sbi   VPORTA_DIR, LED_BIT           /* PA3 = output                        */
    sbi   VPORTA_OUT, LED_BIT           /* LED off (active-low: 1 = off)       */

    ldi   r16, ADC_PINCTRL
    sts   PORTA_PIN4CTRL, r16           /* disable digital input buffer on PA4 */

    ldi   r16, ADC_REF_1V1
    sts   VREF_CTRLA, r16               /* 1.1 V internal reference for ADC0   */
    ldi   r16, ADC_REFEN
    sts   VREF_CTRLB, r16               /* hold reference on continuously       */

    ldi   r16, ADC_PRESC_DIV16
    sts   ADC0_CTRLC, r16               /* CLK_ADC = CLK_PER / 16 ≈ 208 kHz    */

    ldi   r16, ADC_INITDLY32
    sts   ADC0_CTRLD, r16               /* 32 CLK_ADC startup delay             */

    ldi   r16, ADC_SAMPLEN8
    sts   ADC0_SAMPCTRL, r16            /* extend sample by 8 CLK_ADC cycles   */

    ldi   r16, ADC_AIN4
    sts   ADC0_MUXPOS, r16              /* select PA4 / AIN4 as input channel  */

    ldi   r16, ADC_ENABLE_bm
    sts   ADC0_CTRLA, r16               /* enable ADC0                          */

/* ── Main polling loop ─────────────────────────────────────────────────────
 * Trigger a conversion, wait for it, then drive the LED based on result.    */
.Lmain_loop:
    rcall adc0_read_ain4                /* r25:r24 = 10-bit ADC result          */

    sbrs  r25, 1                        /* bit 9 of result set means >= 512     */
    rjmp  .Lbelow_half                  /* result < 512: below half-scale       */

    sbi   VPORTA_OUT, LED_BIT           /* result >= 512: LED off               */
    rjmp  .Lmain_loop

.Lbelow_half:
    cbi   VPORTA_OUT, LED_BIT           /* result < 512:  LED on                */
    rjmp  .Lmain_loop

/* ── adc0_read_ain4 ─────────────────────────────────────────────────────────
 * Trigger one conversion on AIN4 and return the 10-bit result.
 * Exit: R25:R24 = result (0..1023), RESRDY flag cleared.
 * Clobbers: R16.                                                              */
adc0_read_ain4:
    ldi   r16, ADC_STCONV_bm
    sts   ADC0_COMMAND, r16             /* write STCONV bit to start conversion */

.Lwait_adc:
    lds   r16, ADC0_INTFLAGS            /* read interrupt flags register        */
    sbrs  r16, ADC_RESRDY_bp            /* skip if RESRDY = 1 (result ready)    */
    rjmp  .Lwait_adc                    /* not done yet: keep polling           */

    lds   r24, ADC0_RESL                /* read low byte of result first        */
    lds   r25, ADC0_RESH                /* then high byte (10-bit, bits[9:0])   */

    ldi   r16, ADC_RESRDY_bm
    sts   ADC0_INTFLAGS, r16            /* write 1 to clear RESRDY flag (W1C)  */
    ret

default_isr:
    reti
