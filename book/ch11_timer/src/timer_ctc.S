/*
 * timer_ctc.S — LED toggle using TCA0 in frequency mode.
 * Target: factory-default ATtiny3217 clock, 20 MHz / 6 = 3.333 MHz.
 *
 * TCA0 counts up. When CNT == CMP0, it fires an interrupt and resets to 0.
 * Prescaler 1024, TOP = 3254:
 *   f_tick = 3333333 / (1024 * (3254 + 1)) = 1.000371 Hz
 *
 * LED0 on PA3. Toggled each CMP0 interrupt, about once per second.
 */

#include <avr/io.h>

.equ LED_BIT,    3          /* PA3, Curiosity Nano LED0 */
.equ TCA_TOP_LO, 0xB6       /* lo8(3254) */
.equ TCA_TOP_HI, 0x0C       /* hi8(3254) */
.equ TCA_FRQ_MODE, 0x01     /* TCA_SINGLE_WGMODE_FRQ_gc */
.equ TCA_DIV1024_ENABLE, 0x0F /* TCA_SINGLE_CLKSEL_DIV1024_gc | ENABLE */

/* ── Vector table ─────────────────────────────────────────────────────── */
.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    rjmp  main           /* 0x0000: RESET                                   */
    rjmp  isr_default    /* 0x0002: CRCSCAN_NMI                             */
    rjmp  isr_default    /* 0x0004: BOD_VLM                                 */
    rjmp  isr_default    /* 0x0006: PORTA_PORT                              */
    rjmp  isr_default    /* 0x0008: PORTB_PORT                              */
    rjmp  isr_default    /* 0x000A: PORTC_PORT                              */
    rjmp  isr_default    /* 0x000C: RTC_CNT                                 */
    rjmp  isr_default    /* 0x000E: RTC_PIT                                 */
    rjmp  isr_default    /* 0x0010: TCA0_OVF  (not enabled here)           */
    rjmp  isr_default    /* 0x0012: TCA0_HUNF                               */
    rjmp  tca0_cmp0_isr  /* 0x0014: TCA0_CMP0 ← our compare-match handler  */
    rjmp  isr_default    /* 0x0016: TCA0_CMP1                               */
    rjmp  isr_default    /* 0x0018: TCA0_CMP2                               */
    rjmp  isr_default    /* 0x001A: TCB0_INT                                */
    rjmp  isr_default    /* 0x001C: TCB1_INT                                */
    rjmp  isr_default    /* 0x001E: TCD0_OVF                                */
    rjmp  isr_default    /* 0x0020: TCD0_TRIG                               */
    rjmp  isr_default    /* 0x0022: AC0_AC                                  */
    rjmp  isr_default    /* 0x0024: AC1_AC                                  */
    rjmp  isr_default    /* 0x0026: AC2_AC                                  */
    rjmp  isr_default    /* 0x0028: ADC0_RESRDY                             */
    rjmp  isr_default    /* 0x002A: ADC0_WCOMP                              */
    rjmp  isr_default    /* 0x002C: ADC1_RESRDY                             */
    rjmp  isr_default    /* 0x002E: ADC1_WCOMP                              */
    rjmp  isr_default    /* 0x0030: TWI0_TWIS                               */
    rjmp  isr_default    /* 0x0032: TWI0_TWIM                               */
    rjmp  isr_default    /* 0x0034: SPI0_INT                                */
    rjmp  isr_default    /* 0x0036: USART0_RXC                              */
    rjmp  isr_default    /* 0x0038: USART0_DRE                              */
    rjmp  isr_default    /* 0x003A: USART0_TXC                              */
    rjmp  isr_default    /* 0x003C: NVMCTRL_EE                              */

/* ── Text ─────────────────────────────────────────────────────────────── */
.section .text

isr_default:
    reti

/* ── TCA0 CMP0 ISR ────────────────────────────────────────────────────── */
tca0_cmp0_isr:
    push  r16
    in    r16, SREG
    push  r16

    ldi   r16, (1 << LED_BIT)
    sts   PORTA_OUTTGL, r16         /* toggle LED                           */

    ldi   r16, TCA_SINGLE_CMP0_bm   /* = 0x10: clear CMP0 interrupt flag    */
    sts   TCA0_SINGLE_INTFLAGS, r16 /* W1C                                  */

    pop   r16
    out   SREG, r16
    pop   r16
    reti

/* ── main ─────────────────────────────────────────────────────────────── */
.global main
main:
    /* Stack pointer */
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    /* PA3 = output, LED off (active-low) */
    sbi   VPORTA_DIR, LED_BIT
    sbi   VPORTA_OUT, LED_BIT

    /* TCA0 setup:
     *   CTRLA:  prescaler DIV1024, timer disabled for now
     *   CTRLB:  WGMODE = FRQ (0x01), CMP0 controls period
     *   CMP0:   TOP value = 3254
     *   INTCTRL: enable CMP0 interrupt
     *   CTRLA:  enable timer
     */
    ldi   r16, TCA_FRQ_MODE                /* CTRLB: WGM = FRQ mode        */
    sts   TCA0_SINGLE_CTRLB, r16

    ldi   r16, TCA_TOP_LO
    sts   TCA0_SINGLE_CMP0L, r16           /* CMP0 low byte                 */
    ldi   r16, TCA_TOP_HI
    sts   TCA0_SINGLE_CMP0H, r16           /* CMP0 high byte                */

    ldi   r16, TCA_SINGLE_CMP0_bm          /* enable CMP0 interrupt         */
    sts   TCA0_SINGLE_INTCTRL, r16

    /* start timer: prescaler 1024, enable */
    ldi   r16, TCA_DIV1024_ENABLE
    sts   TCA0_SINGLE_CTRLA, r16

    sei                                    /* global interrupt enable        */

.Lidle:
    rjmp  .Lidle
