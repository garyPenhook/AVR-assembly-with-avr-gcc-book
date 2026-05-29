/*
 * adc_event_pit.S - RTC PIT event triggers ADC0 conversions.
 *
 * Target: ATtiny3217 Curiosity Nano, factory clock 3.333 MHz.
 *
 * The ATtiny3217 Event System routes hardware events between peripherals
 * without CPU involvement. Here the RTC PIT generates an event every ~31 ms
 * (1024 cycles of the default 32.768 kHz internal RTC oscillator). That event
 * is routed through asynchronous event channel 3 to ADC0's event user, which
 * starts a conversion automatically when the event fires. (To get a ~1 s
 * period instead, select the 1.024 kHz source in RTC_CLKSEL before enabling
 * the PIT.)
 *
 * Event routing used:
 *   Generator: RTC PIT DIV1024  → EVSYS_ASYNCCH3 generator = 0x0D
 *   User:      ADC0 STARTEI     → EVSYS_ASYNCUSER1 (ADC0) = 0x06
 * (See ATtiny3217 datasheet section "Event System" for full channel/user map.)
 */

#include <avr/io.h>

/* (ADC constants match adc_poll.S — see that file for detailed explanations.) */
.equ LED_BIT,          3       /* PA3, Curiosity Nano LED0 (active-low)        */
.equ ADC_PINCTRL,      0x04    /* PORTA_PIN4CTRL: disable digital input buffer */
.equ ADC_REF_1V1,      0x10    /* VREF_CTRLA: ADC0REFSEL = 1.1 V              */
.equ ADC_REFEN,        0x02    /* VREF_CTRLB: force ADC0 reference on          */
.equ ADC_PRESC_DIV16,  0x03    /* ADC0_CTRLC: CLK_ADC = CLK_PER / 16          */
.equ ADC_INITDLY32,    0x40    /* ADC0_CTRLD: 32 CLK_ADC startup delay         */
.equ ADC_AIN4,         0x04    /* ADC0_MUXPOS: select PA4 / AIN4               */
.equ ADC_SAMPLEN8,     8       /* ADC0_SAMPCTRL: 8 extra sample cycles         */

/* EVSYS_ASYNCCH3 generator value 0x0D = RTC_PIT_DIV1024_gc:
 * The RTC PIT with period 1024 RTC cycles is the event source.              */
.equ EVGEN_PIT_DIV1024, 0x0D

/* EVSYS_ASYNCUSER1 (the ADC0 event user) = 0x06 = ASYNCCH3:
 * Routes asynchronous channel 3 events to the ADC0 start-event input.      */
.equ EVUSER_ASYNCCH3,  0x06

/* RTC_PITCTRLA value: PERIOD field = 9 (CYC1024) and PITEN = 1.
 * PIT period = 1024 RTC cycles at the default 32.768 kHz ≈ 31 ms.
 * Field PERIOD occupies bits [6:3], so 9 << 3 = 0x48.                      */
.equ PIT_DIV1024_EN,   ((9 << 3) | RTC_PITEN_bm)

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

    /* ── ADC setup ──────────────────────────────────────────────────────── */
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

    /* STARTEI bit: when set, an incoming event on the ADC event user
     * triggers ADC0_COMMAND.STCONV automatically. The CPU does not need
     * to write STCONV — the event system does it for us.                   */
    ldi   r16, ADC_STARTEI_bm
    sts   ADC0_EVCTRL, r16              /* enable event-triggered start         */

    ldi   r16, ADC_ENABLE_bm
    sts   ADC0_CTRLA, r16               /* enable ADC0                          */

    /* ── Event system routing ────────────────────────────────────────────
     * Step 1: point asynchronous channel 3 generator at the RTC PIT.     */
    ldi   r16, EVGEN_PIT_DIV1024
    sts   EVSYS_ASYNCCH3, r16           /* CH3 generator = RTC PIT DIV1024     */

    /* Step 2: connect CH3 to ADC0's start-event user (ASYNCUSER1).       */
    ldi   r16, EVUSER_ASYNCCH3
    sts   EVSYS_ASYNCUSER1, r16         /* ADC0 event user = ASYNCCH3           */

    /* ── Start the RTC PIT ───────────────────────────────────────────────
     * Must wait for any pending CTRLBUSY sync before writing PITCTRLA.   */
.Lwait_pit_sync:
    lds   r16, RTC_PITSTATUS            /* CTRLBUSY = 1 while sync is pending  */
    sbrc  r16, RTC_CTRLBUSY_bp
    rjmp  .Lwait_pit_sync

    ldi   r16, PIT_DIV1024_EN
    sts   RTC_PITCTRLA, r16             /* enable PIT with 1024-cycle period    */

/* ── Main loop ─────────────────────────────────────────────────────────────
 * The ADC fires automatically every ~1 s via the event system.
 * CPU just polls RESRDY to catch each result.                              */
.Lmain_loop:
    rcall adc0_wait_event_result        /* r25:r24 = result of event-triggered conversion */
    sbrs  r25, 1                        /* bit 9 set → result >= 512            */
    rjmp  .Lbelow_half
    sbi   VPORTA_OUT, LED_BIT           /* >= 512: LED off                      */
    rjmp  .Lmain_loop
.Lbelow_half:
    cbi   VPORTA_OUT, LED_BIT           /* < 512: LED on                        */
    rjmp  .Lmain_loop

/* ── adc0_wait_event_result ─────────────────────────────────────────────────
 * Spin until RESRDY is set (triggered by the PIT event), read result,
 * and clear the flag.
 * Exit: R25:R24 = 10-bit result. Clobbers: R16.                              */
adc0_wait_event_result:
.Lwait_adc:
    lds   r16, ADC0_INTFLAGS            /* poll for event-triggered result      */
    sbrs  r16, ADC_RESRDY_bp
    rjmp  .Lwait_adc
    lds   r24, ADC0_RESL
    lds   r25, ADC0_RESH
    ldi   r16, ADC_RESRDY_bm
    sts   ADC0_INTFLAGS, r16            /* W1C: clear RESRDY                    */
    ret

default_isr:
    reti
