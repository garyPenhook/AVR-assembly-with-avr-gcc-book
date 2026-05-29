/*
 * timer_ctc.S — LED toggle using TCA0 in frequency (CTC) mode.
 *               Companion source for Chapter 11: Timer/Counter
 *
 * Covers:
 *   TCA0 CTC (Clear Timer on Compare) — CNT counts up; resets to 0 when CNT == CMP0
 *   Prescaler selection: DIV1024 reduces 3.333 MHz to a ~3255 Hz timer clock
 *   TOP calculation: TOP = (f_cpu / (prescaler × f_tick)) - 1 = 3254 for 1 Hz
 *   TCA0_INTCTRL: enable CMP0 interrupt (LCMP0EN bit)
 *   ISR: save/restore SREG, toggle LED, clear interrupt flag (write-1-to-clear)
 *   SEI before entering idle loop — timer interrupt drives all activity
 *
 * Target: factory-default ATtiny3217 clock, 20 MHz / 6 = 3.333 MHz.
 * TCA0 counts up. When CNT == CMP0, it fires an interrupt and resets to 0.
 * Prescaler 1024, TOP = 3254:
 *   f_tick = 3333333 / (1024 * (3254 + 1)) = 1.0000639 Hz
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
    jmp  main            /* 0x0000: RESET                                   */
    jmp  isr_default     /* 0x0004: CRCSCAN_NMI                             */
    jmp  isr_default     /* 0x0008: BOD_VLM                                 */
    jmp  isr_default     /* 0x000C: PORTA_PORT                              */
    jmp  isr_default     /* 0x0010: PORTB_PORT                              */
    jmp  isr_default     /* 0x0014: PORTC_PORT                              */
    jmp  isr_default     /* 0x0018: RTC_CNT                                 */
    jmp  isr_default     /* 0x001C: RTC_PIT                                 */
    jmp  isr_default     /* 0x0020: TCA0_LUNF/TCA0_OVF (not enabled here)   */
    jmp  isr_default     /* 0x0024: TCA0_HUNF                               */
    jmp  tca0_cmp0_isr   /* 0x0028: TCA0_LCMP0/TCA0_CMP0 handler           */
    jmp  isr_default     /* 0x002C: TCA0_LCMP1/TCA0_CMP1                   */
    jmp  isr_default     /* 0x0030: TCA0_CMP2/TCA0_LCMP2                   */
    jmp  isr_default     /* 0x0034: TCB0_INT                                */
    jmp  isr_default     /* 0x0038: TCB1_INT                                */
    jmp  isr_default     /* 0x003C: TCD0_OVF                                */
    jmp  isr_default     /* 0x0040: TCD0_TRIG                               */
    jmp  isr_default     /* 0x0044: AC0_AC                                  */
    jmp  isr_default     /* 0x0048: AC1_AC                                  */
    jmp  isr_default     /* 0x004C: AC2_AC                                  */
    jmp  isr_default     /* 0x0050: ADC0_RESRDY                             */
    jmp  isr_default     /* 0x0054: ADC0_WCOMP                              */
    jmp  isr_default     /* 0x0058: ADC1_RESRDY                             */
    jmp  isr_default     /* 0x005C: ADC1_WCOMP                              */
    jmp  isr_default     /* 0x0060: TWI0_TWIS                               */
    jmp  isr_default     /* 0x0064: TWI0_TWIM                               */
    jmp  isr_default     /* 0x0068: SPI0_INT                                */
    jmp  isr_default     /* 0x006C: USART0_RXC                              */
    jmp  isr_default     /* 0x0070: USART0_DRE                              */
    jmp  isr_default     /* 0x0074: USART0_TXC                              */
    jmp  isr_default     /* 0x0078: NVMCTRL_EE                              */

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
