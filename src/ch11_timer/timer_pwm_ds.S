/* ============================================================
 * timer_pwm_ds.S — dual-slope (center-aligned) PWM on TCA0 WO0 (PB0)
 * Target: ATtiny3217 @ 3.333 MHz (default OSC20M /6)
 * Build:  avr-gcc -mmcu=attiny3217 -nostartfiles timer_pwm_ds.S -o timer_pwm_ds.elf
 * ============================================================
 *
 * Demonstrates:
 *   - TCA0 dual-slope PWM (WGMODE = DSBOTTOM): the counter ramps UP to PER
 *     then back DOWN to 0, so one period spans 2 x PER ticks. The pulse is
 *     symmetric about the midpoint (center-aligned), which is the standard
 *     choice for motor / H-bridge drive because it cuts switching noise.
 *   - PER sets TOP (half the period); CMP0 sets the duty cycle.
 *   - WO0 (PB0) is driven in hardware, no CPU involvement.
 *
 * Output: PB0 = WO0 (datasheet Table 5-1, TCA0 WO0 default = PB0).
 *
 * Timing (CLK_PER = 3.333 MHz, prescaler DIV1):
 *   period = 2 x PER ticks = 2 x 500 = 1000 ticks = 300 us -> ~3.33 kHz
 *   duty   = CMP0 / PER = 125 / 500 = 25%
 *
 *   Compare with single-slope, where period = (PER + 1) and duty = CMP0/(PER+1).
 *   Dual-slope trades half the resolution (period is 2 x PER) for a centered,
 *   glitch-symmetric pulse.
 *
 * Constants: _bm bit masks are #define macros (assemble in .S). WGMODE is a
 * group config (a C enum in the header, not usable in .S), so its value is
 * .equ from the datasheet (TCA0.CTRLB WGMODE: DSBOTTOM = 0x7).
 *
 * Registers used: r16 (scratch), r17 (16-bit high byte)
 * ============================================================ */
#include <avr/io.h>

.equ TCA_WGMODE_DSBOTTOM, 0x07   /* CTRLB WGMODE[2:0] = dual-slope, OVF at BOTTOM */

.section .text
.global main

main:
    /* WO0 pin (PB0) as output so the timer can drive it */
    sbi   VPORTB_DIR, 0

    /* period: PER = 500 -> 2 x 500 = 1000 ticks = 300 us (16-bit, LOW first) */
    ldi   r16, lo8(500)
    ldi   r17, hi8(500)
    sts   TCA0_SINGLE_PERL, r16
    sts   TCA0_SINGLE_PERH, r17

    /* duty: CMP0 = 125 -> 125/500 = 25% */
    ldi   r16, lo8(125)
    ldi   r17, hi8(125)
    sts   TCA0_SINGLE_CMP0L, r16
    sts   TCA0_SINGLE_CMP0H, r17

    /* waveform mode: dual-slope PWM, enable compare-channel 0 output */
    ldi   r16, TCA_WGMODE_DSBOTTOM | TCA_SINGLE_CMP0EN_bm
    sts   TCA0_SINGLE_CTRLB, r16

    /* start the timer: prescaler DIV1 (CLKSEL = 0), ENABLE */
    ldi   r16, TCA_SINGLE_ENABLE_bm
    sts   TCA0_SINGLE_CTRLA, r16

    /* center-aligned PWM now runs entirely in hardware. */
loop:
    rjmp  loop
