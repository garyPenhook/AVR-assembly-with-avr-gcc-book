/*
 * servo_pwm.S — Drive the Explorer's servomotor headers with 50 Hz PWM.
 *
 * Curiosity Nano Explorer (EV58G97A). Three servo headers with MOSFET-driven
 * open-drain control outputs, shared with the RGB LED and mikroBUS PWM.
 *   Outputs : TCA0 WO0/WO1/WO2 -> ATtiny3217 PB0/PB1/PB2 (default PORTMUX)
 *             Wire PWM-A/B/C to PB0/PB1/PB2. Use an external 5-24V supply
 *             (J310/J308) for the servos.
 *
 * Standard hobby servo: 50 Hz frame (20 ms), 1.0-2.0 ms pulse (1.5 ms = centre).
 * At CLK_PER = 3.333 MHz with prescaler /64: 1 tick = 19.2 us.
 *   PER  = 1042  (~20.0 ms frame)
 *   CMP  =  78 (1.5 ms centre),  52 (1.0 ms),  104 (2.0 ms)
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o servo_pwm.o servo_pwm.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o servo_pwm.elf servo_pwm.o
 */

#include <avr/io.h>

.equ SERVO_PER,     1042        /* ~20 ms at /64, 3.333 MHz                   */
.equ SERVO_CENTRE,  78          /* ~1.5 ms                                    */

.section .text
.global main

main:
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    rcall servo_init

    /* Centre channel A (WO0) */
    ldi   r24, lo8(SERVO_CENTRE)
    ldi   r25, hi8(SERVO_CENTRE)
    rcall servo_set_a

.Lhalt:
    rjmp  .Lhalt

/* ------------------------------------------------------------------------- */
servo_init:
    ldi   r16, (1 << 0) | (1 << 1) | (1 << 2)
    out   VPORTB_DIR, r16

    ldi   r16, lo8(SERVO_PER)
    sts   TCA0_SINGLE_PERL, r16
    ldi   r16, hi8(SERVO_PER)
    sts   TCA0_SINGLE_PERH, r16

    /* CTRLB: single-slope PWM + CMP0/1/2 enable */
    ldi   r16, (1 << 6) | (1 << 5) | (1 << 4) | 0x03
    sts   TCA0_SINGLE_CTRLB, r16
    /* CTRLA: CLKSEL = DIV64 (0x05 << 1), ENABLE */
    ldi   r16, (0x05 << 1) | 0x01
    sts   TCA0_SINGLE_CTRLA, r16
    ret

/* servo_set_a — r25:r24 = pulse width in timer ticks (channel A / WO0) */
servo_set_a:
    sts   TCA0_SINGLE_CMP0L, r24
    sts   TCA0_SINGLE_CMP0H, r25
    ret

/* servo_set_b / servo_set_c — channels B (WO1) and C (WO2) */
servo_set_b:
    sts   TCA0_SINGLE_CMP1L, r24
    sts   TCA0_SINGLE_CMP1H, r25
    ret
servo_set_c:
    sts   TCA0_SINGLE_CMP2L, r24
    sts   TCA0_SINGLE_CMP2H, r25
    ret
