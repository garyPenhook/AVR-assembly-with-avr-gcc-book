/*
 * rgb_led_pwm.S — Drive the Explorer's RGB LED with TCA0 PWM.
 *
 * Curiosity Nano Explorer (EV58G97A). One common RGB LED driven from three PWM
 * outputs (PWM-A / PWM-B / PWM-C), shared with the servo headers and mikroBUS
 * PWM (separate them with jumpers J309 / J203).
 *   Outputs : TCA0 WO0/WO1/WO2 -> ATtiny3217 PB0/PB1/PB2 (default PORTMUX)
 *             Wire PWM-A/B/C to PB0/PB1/PB2.
 *
 * Single-slope 8-bit PWM: PER = 0xFF, duty 0..255 per channel sets brightness.
 * CAUTION: the LED is very bright at full power.
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o rgb_led_pwm.o rgb_led_pwm.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o rgb_led_pwm.elf rgb_led_pwm.o
 */

#include <avr/io.h>

.section .text
.global main

main:
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    rcall pwm_init

    /* A warm colour: R=200, G=80, B=10 */
    ldi   r24, 200
    ldi   r22, 80
    ldi   r20, 10
    rcall rgb_set

.Lhalt:
    rjmp  .Lhalt

/* ------------------------------------------------------------------------- */
pwm_init:
    /* WO0..WO2 outputs */
    ldi   r16, (1 << 0) | (1 << 1) | (1 << 2)
    out   VPORTB_DIR, r16

    /* PER = 0x00FF */
    ldi   r16, 0xFF
    sts   TCA0_SINGLE_PERL, r16
    ldi   r16, 0x00
    sts   TCA0_SINGLE_PERH, r16

    /* start all channels off */
    clr   r24
    clr   r22
    clr   r20
    rcall rgb_set

    /* CTRLB: single-slope PWM + CMP0/1/2 enable */
    ldi   r16, (1 << 6) | (1 << 5) | (1 << 4) | 0x03
    sts   TCA0_SINGLE_CTRLB, r16
    /* CTRLA: CLKSEL = DIV1, ENABLE */
    ldi   r16, 0x01
    sts   TCA0_SINGLE_CTRLA, r16
    ret

/* rgb_set — r24 = R duty, r22 = G duty, r20 = B duty (0..255) */
rgb_set:
    sts   TCA0_SINGLE_CMP0L, r24
    ldi   r16, 0
    sts   TCA0_SINGLE_CMP0H, r16
    sts   TCA0_SINGLE_CMP1L, r22
    sts   TCA0_SINGLE_CMP1H, r16
    sts   TCA0_SINGLE_CMP2L, r20
    sts   TCA0_SINGLE_CMP2H, r16
    ret
