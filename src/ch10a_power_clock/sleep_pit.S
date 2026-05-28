/*
 * sleep_pit.S — Power-down sleep, wake from RTC PIT, toggle LED0.
 *               Companion source for Chapter 10A: Power and Clock Options
 *
 * Covers:
 *   SLPCTRL — select power-down sleep mode (lowest power, most peripherals off)
 *   RTC PIT (Periodic Interrupt Timer) — stays active in power-down sleep
 *   ULP 1 kHz oscillator (INT1K): selected with CLKSEL = 0x01, always on
 *   PIT period: RTC_PERIOD_CYC1024_gc = 1024 / 1000 Hz = ~1.024 s per wake
 *   SLEEP instruction — CPU halts; PIT ISR wakes it, RETI resumes after SLEEP
 *   Power savings: main loop spends nearly all time in power-down
 *
 * Hardware:
 *   LED0 on PA3, active-low on the ATtiny3217 Curiosity Nano.
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o sleep_pit.o sleep_pit.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o sleep_pit.elf sleep_pit.o
 */

#include <avr/io.h>

/* ── Constants ───────────────────────────────────────────────────────────── */
.equ LED_BIT, 3                     /* PA3, Curiosity Nano LED0 (active-low)   */

/* RTC_CLKSEL: select the internal 1 kHz (ULP) oscillator as RTC/PIT source.
 * This low-power oscillator is always available in power-down sleep.
 * CLKSEL = 0x01 = RTC_CLKSEL_INT1K_gc in the header macros.                */
.equ RTC_CLKSEL_INT1K,   0x01

/* PIT period = 1024 RTC cycles at 1 kHz = 1024 ms ≈ 1 second per wake-up.
 * PERIOD field lives at bits [6:3] of RTC_PITCTRLA.
 * RTC_PERIOD_CYC1024_gc = 0x09 → shifted into the field gives 0x48.        */
.equ RTC_PIT_CYC1024,    (0x09 << RTC_PERIOD_gp)

/* SLPCTRL_CTRLA: power-down sleep mode.
 * SMODE bits [3:2] = 0x02 selects PDOWN (deepest sleep: all clocks stopped
 * except RTC and async peripherals; CPU and most peripherals off).
 * SEN bit [0] must also be set to allow the SLEEP instruction to work.      */
.equ SLPCTRL_MODE_PDOWN, (0x02 << SLPCTRL_SMODE_gp)

.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    jmp   main            /* 0x0000: RESET */
    .rept 6
    jmp   default_isr     /* vectors 1..6 */
    .endr
    jmp   rtc_pit_isr     /* vector 7: RTC_PIT */
    .rept 23
    jmp   default_isr     /* vectors 8..30 */
    .endr

.section .text
.global main
main:
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    sbi   VPORTA_DIR, LED_BIT
    sbi   VPORTA_OUT, LED_BIT       /* LED off */

    /* ── Configure RTC / PIT ─────────────────────────────────────────────
     * Datasheet rule: do not change RTC_CLKSEL while the RTC or PIT is
     * running. Force-disable both and wait for each SYNCBUSY to clear.
     * The SYNCBUSY flag indicates that a register write has not yet
     * propagated to the slow RTC clock domain (up to 2 RTC clock cycles).  */
    clr   r16
    sts   RTC_PITCTRLA, r16         /* disable PIT (PITEN = 0)                */
.Lwait_pit_sync0:
    lds   r16, RTC_PITSTATUS        /* CTRLBUSY = 1 while write is pending    */
    sbrc  r16, RTC_CTRLBUSY_bp
    rjmp  .Lwait_pit_sync0          /* loop until CTRLBUSY clears             */

    clr   r16
    sts   RTC_CTRLA, r16            /* disable RTC counter (RTCEN = 0)        */
.Lwait_rtc_sync0:
    lds   r16, RTC_STATUS           /* CTRLABUSY = 1 while write is pending   */
    sbrc  r16, RTC_CTRLABUSY_bp
    rjmp  .Lwait_rtc_sync0          /* loop until CTRLABUSY clears            */

    /* Select the 1 kHz internal oscillator as the RTC/PIT clock source.
     * This oscillator keeps running in power-down sleep.                    */
    ldi   r16, RTC_CLKSEL_INT1K
    sts   RTC_CLKSEL, r16

    /* Clear any stale PIT interrupt flag (W1C) before enabling the ISR.
     * If this is skipped, an already-pending flag fires immediately on SEI. */
    ldi   r16, RTC_PI_bm
    sts   RTC_PITINTFLAGS, r16      /* write 1 to clear PIT Interrupt Flag     */
    sts   RTC_PITINTCTRL, r16       /* enable PIT interrupt (PI bit = 1)       */

    /* Enable PIT with 1024-cycle period (≈ 1 s at 1 kHz).
     * PITEN = 1 starts the PIT; the period is already selected by PERIOD.  */
    ldi   r16, (RTC_PIT_CYC1024 | RTC_PITEN_bm)
    sts   RTC_PITCTRLA, r16

    /* ── Configure sleep mode: power-down ────────────────────────────────
     * SEN = 1 enables the SLEEP instruction; without it SLEEP is a NOP.
     * PDOWN stops everything except the RTC/PIT and async event system.    */
    ldi   r16, (SLPCTRL_MODE_PDOWN | SLPCTRL_SEN_bm)
    sts   SLPCTRL_CTRLA, r16

    sei                             /* enable global interrupts before sleeping */

.Lsleep_forever:
    sleep                           /* enter power-down; wake on PIT interrupt */
    rjmp  .Lsleep_forever           /* rjmp here handles spurious wake-ups     */

/* ── rtc_pit_isr ─────────────────────────────────────────────────────────
 * Fires every ~1 s (1024 RTC cycles at 1 kHz).
 * Saves SREG and r16, toggles LED, clears the PIT flag, restores context.
 * Clearing the flag (W1C) is mandatory — if omitted the interrupt fires
 * again immediately upon RETI.                                              */
rtc_pit_isr:
    push  r16
    in    r16, SREG                 /* save status register                   */
    push  r16

    ldi   r16, (1 << LED_BIT)
    sts   PORTA_OUTTGL, r16         /* atomic toggle PA3 via the PORT register */

    ldi   r16, RTC_PI_bm
    sts   RTC_PITINTFLAGS, r16      /* write 1 to clear PIT interrupt flag (W1C) */

    pop   r16
    out   SREG, r16                 /* restore status register exactly         */
    pop   r16
    reti                            /* return, re-enable global interrupts      */

default_isr:
    reti
