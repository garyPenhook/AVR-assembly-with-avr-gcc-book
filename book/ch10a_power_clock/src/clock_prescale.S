/*
 * clock_prescale.S - Change ATtiny3217 main clock prescaler through CCP.
 *
 * Hardware:
 *   LED0 on PA3, active-low on the Curiosity Nano.
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o clock_prescale.o clock_prescale.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o clock_prescale.elf clock_prescale.o
 */

#include <avr/io.h>

.equ LED_BIT, 3
.equ DELAY_FAST_OUTER, 24
.equ DELAY_SLOW_OUTER, 4
.equ CCP_IOREG_KEY, 0xD8
.equ MCLKCTRLB_DIV48, ((0x0C << CLKCTRL_PDIV_gp) | CLKCTRL_PEN_bm)

.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    jmp   main

.section .text
.global main
main:
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    sbi   VPORTA_DIR, LED_BIT
    sbi   VPORTA_OUT, LED_BIT       /* LED off */

    /* Run at full OSC20M speed: MCLKCTRLB.PEN = 0. */
    clr   r17
    rcall clock_write_mclkctrlb

    ldi   r18, 8                    /* show a few fast toggles, then slow down */
.Lfast:
    ldi   r19, DELAY_FAST_OUTER
    rcall blink_delay
    ldi   r16, (1 << LED_BIT)
    sts   PORTA_OUTTGL, r16
    dec   r18
    brne  .Lfast

    /* Slow down: 20 MHz / 48 = about 416.7 kHz. */
    ldi   r17, MCLKCTRLB_DIV48
    rcall clock_write_mclkctrlb

.Lslow:
    ldi   r19, DELAY_SLOW_OUTER
    rcall blink_delay
    ldi   r16, (1 << LED_BIT)
    sts   PORTA_OUTTGL, r16
    rjmp  .Lslow

/*
 * clock_write_mclkctrlb
 *
 * Input:
 *   r17 = new CLKCTRL_MCLKCTRLB value
 *
 * The protected write must immediately follow the CPU_CCP unlock.
 */
clock_write_mclkctrlb:
    ldi   r16, CCP_IOREG_KEY
    sts   CPU_CCP, r16
    sts   CLKCTRL_MCLKCTRLB, r17
    ret

/*
 * blink_delay
 *
 * Input:
 *   r19 = outer loop count
 *
 * Clobbers r24:r25 and flags. This is only a visible timing demo; exact
 * wall-clock delay changes intentionally when the clock prescaler changes.
 */
blink_delay:
.Louter:
    ldi   r25, 0
    ldi   r24, 0
.Linner:
    sbiw  r24, 1
    brne  .Linner
    dec   r19
    brne  .Louter
    ret
