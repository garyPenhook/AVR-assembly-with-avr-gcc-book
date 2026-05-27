/*
 * sleep_pit.S - Power-down sleep, wake from RTC PIT, toggle LED0.
 *
 * Hardware:
 *   LED0 on PA3, active-low on the ATtiny3217 Curiosity Nano.
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o sleep_pit.o sleep_pit.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o sleep_pit.elf sleep_pit.o
 */

#include <avr/io.h>

.equ LED_BIT, 3
.equ RTC_CLKSEL_INT1K,   0x01
.equ RTC_PIT_CYC1024,    (0x09 << RTC_PERIOD_gp)
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

    /* Use the internal 1 kHz RTC clock; PIT period 1024 cycles is about 1 s. */
    /*
     * Datasheet rule: change CLK_RTC only when RTC/PIT are disabled.
     * On reset they are typically off, but the datasheet notes RTC is used
     * during device start-up, so we force-disable and wait for sync anyway.
     */
    clr   r16
    sts   RTC_PITCTRLA, r16         /* PITEN = 0 */
.Lwait_pit_sync0:
    lds   r16, RTC_PITSTATUS
    sbrc  r16, RTC_CTRLBUSY_bp
    rjmp  .Lwait_pit_sync0

    clr   r16
    sts   RTC_CTRLA, r16            /* RTCEN = 0 */
.Lwait_rtc_sync0:
    lds   r16, RTC_STATUS
    sbrc  r16, RTC_CTRLABUSY_bp
    rjmp  .Lwait_rtc_sync0

    ldi   r16, RTC_CLKSEL_INT1K
    sts   RTC_CLKSEL, r16

    ldi   r16, RTC_PI_bm
    sts   RTC_PITINTFLAGS, r16      /* clear any stale PIT flag */
    sts   RTC_PITINTCTRL, r16       /* enable PIT interrupt */

    ldi   r16, (RTC_PIT_CYC1024 | RTC_PITEN_bm)
    sts   RTC_PITCTRLA, r16

    ldi   r16, (SLPCTRL_MODE_PDOWN | SLPCTRL_SEN_bm)
    sts   SLPCTRL_CTRLA, r16

    sei

.Lsleep_forever:
    sleep
    rjmp  .Lsleep_forever

rtc_pit_isr:
    push  r16
    in    r16, SREG
    push  r16

    ldi   r16, (1 << LED_BIT)
    sts   PORTA_OUTTGL, r16

    ldi   r16, RTC_PI_bm
    sts   RTC_PITINTFLAGS, r16      /* W1C: clear PIT interrupt flag */

    pop   r16
    out   SREG, r16
    pop   r16
    reti

default_isr:
    reti
