/* ============================================================
 * timer_pwm.S — single-slope PWM on TCA0 WO0 (PB0)
 * Target: ATtiny3217 @ 3.333 MHz (default OSC20M /6)
 * Build:  avr-gcc -mmcu=attiny3217 -nostartfiles timer_pwm.S -o timer_pwm.elf
 * ============================================================
 *
 * Demonstrates:
 *   - TCA0 single-slope PWM (WGMODE = SINGLESLOPE)
 *   - PER sets the period (TOP); CMP0 sets the duty cycle
 *   - the WO0 waveform-output pin (PB0) toggles in hardware, no CPU
 *
 * Output: PB0 = WO0 (verified: datasheet Table 5-1, TCA0 WO0 default = PB0).
 *   Connect an LED + series resistor from PB0 to GND, or probe PB0.
 *
 * Timing (CLK_PER = 3.333 MHz, prescaler DIV1):
 *   period  = (PER + 1) ticks = 1000 ticks = 300 us  -> ~3.33 kHz (no flicker)
 *   duty    = CMP0 / (PER + 1) = 250 / 1000 = 25%
 *
 * Constants: _bm bit masks are #define macros (assemble in .S). WGMODE is a
 * group config (a C enum in the header, not usable in .S), so its value is
 * .equ from the datasheet (TCA0.CTRLB WGMODE: SINGLESLOPE = 0x3).
 *
 * Registers used: r16 (scratch), r17 (16-bit high byte)
 * ============================================================ */
#include <avr/io.h>

.equ TCA_WGMODE_SINGLESLOPE, 0x03   /* CTRLB WGMODE[2:0] = single-slope     */

.section .text
.global main

main:
    /* WO0 pin (PB0) as output so the timer can drive it */
    sbi   VPORTB_DIR, 0

    /* period: PER = 999 (16-bit, write LOW byte first, then HIGH) */
    ldi   r16, lo8(999)
    ldi   r17, hi8(999)
    sts   TCA0_SINGLE_PERL, r16
    sts   TCA0_SINGLE_PERH, r17

    /* duty: CMP0 = 250 (25%) */
    ldi   r16, lo8(250)
    ldi   r17, hi8(250)
    sts   TCA0_SINGLE_CMP0L, r16
    sts   TCA0_SINGLE_CMP0H, r17

    /* waveform mode: single-slope PWM, enable compare-channel 0 output */
    ldi   r16, TCA_WGMODE_SINGLESLOPE | TCA_SINGLE_CMP0EN_bm
    sts   TCA0_SINGLE_CTRLB, r16

    /* start the timer: prescaler DIV1 (CLKSEL = 0), ENABLE */
    ldi   r16, TCA_SINGLE_ENABLE_bm
    sts   TCA0_SINGLE_CTRLA, r16

    /* PWM now runs entirely in hardware. */
loop:
    rjmp  loop
