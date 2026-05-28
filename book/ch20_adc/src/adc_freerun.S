/*
 * adc_freerun.S - ADC0 AIN4 in free-running mode.
 *
 * Target: ATtiny3217 Curiosity Nano, factory clock 3.333 MHz.
 *
 * In free-running mode the ADC automatically starts a new conversion as soon
 * as each result is ready. The CPU does not need to retrigger STCONV — it
 * simply waits for RESRDY to be set, reads the result, and clears the flag.
 * This avoids the overhead of writing ADC0_COMMAND on every sample.
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
    ldi   r16, ADC_AIN4
    sts   ADC0_MUXPOS, r16              /* select PA4 / AIN4                   */

    /* Enable ADC with free-running mode.
     * FREERUN_bm: after each conversion completes, the ADC automatically
     * starts the next one — no need to write STCONV between samples.        */
    ldi   r16, (ADC_ENABLE_bm | ADC_FREERUN_bm)
    sts   ADC0_CTRLA, r16

    /* Trigger the very first conversion. In free-running mode, subsequent
     * conversions start automatically when RESRDY is cleared.               */
    ldi   r16, ADC_STCONV_bm
    sts   ADC0_COMMAND, r16

.Lmain_loop:
    rcall adc0_read_latest              /* r25:r24 = latest 10-bit result       */
    sbrs  r25, 1                        /* bit 9 set → result >= 512            */
    rjmp  .Lbelow_half
    sbi   VPORTA_OUT, LED_BIT           /* >= 512: LED off                      */
    rjmp  .Lmain_loop
.Lbelow_half:
    cbi   VPORTA_OUT, LED_BIT           /* < 512:  LED on                       */
    rjmp  .Lmain_loop

/* ── adc0_read_latest ───────────────────────────────────────────────────────
 * Wait for the ADC to signal a completed conversion (RESRDY = 1), read
 * the result, then clear the flag so the next conversion can proceed.
 * In free-running mode the ADC restarts immediately after RESRDY is cleared.
 * Exit: R25:R24 = 10-bit result. Clobbers: R16.                              */
adc0_read_latest:
.Lwait_adc:
    lds   r16, ADC0_INTFLAGS            /* poll conversion-complete flag        */
    sbrs  r16, ADC_RESRDY_bp            /* skip if RESRDY = 1                  */
    rjmp  .Lwait_adc
    lds   r24, ADC0_RESL                /* read result low byte                */
    lds   r25, ADC0_RESH                /* read result high byte               */
    ldi   r16, ADC_RESRDY_bm
    sts   ADC0_INTFLAGS, r16            /* W1C: clear RESRDY, ADC restarts     */
    ret

default_isr:
    reti
