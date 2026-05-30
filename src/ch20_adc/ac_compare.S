/* ============================================================
 * ac_compare.S — Analog Comparator AC0: AINP0 (PA7) vs internal 1.1 V
 * Target: ATtiny3217 @ 3.333 MHz (default OSC20M /6)
 * Build:  avr-gcc -mmcu=attiny3217 -nostartfiles ac_compare.S -o ac_compare.elf
 * ============================================================
 *
 * Demonstrates:
 *   - AC0 compares the positive input (AINP0 = PA7) against the negative input
 *     (the shared VREF, set to 1.1 V). The result is a single bit, available
 *     "live" in AC0.STATUS.STATE with no conversion time.
 *   - The comparator output is also driven on the OUT pin (PA5) via OUTEN, so
 *     it can be probed or wired to another peripheral.
 *   - The main loop mirrors STATE onto the on-board LED (PA3): LED on while the
 *     PA7 voltage is above 1.1 V.
 *
 * Pins (datasheet Table 5-1 / sec.29 AC):
 *   AINP0 = PA7 (positive input), OUT = PA5, VREF negative input is internal.
 *
 * Constants: _bm masks are #define and assemble in .S. The MUXPOS/MUXNEG and
 * VREF group configs are C enums in the header (not usable in .S), so their
 * values are .equ from the datasheet.
 *
 * Registers used: r16 (scratch)
 * ============================================================ */
#include <avr/io.h>

.equ AC_MUXPOS_PIN0,        (0x00 << 3)   /* MUXCTRLA MUXPOS = AINP0 (PA7)   */
.equ AC_MUXNEG_VREF,        (0x02 << 0)   /* MUXCTRLA MUXNEG = internal VREF */
.equ VREF_DAC0REFSEL_1V1,   0x01          /* VREF.CTRLA DAC0REFSEL = 1.1 V   */
.equ PORT_ISC_INPUT_DISABLE, 0x04         /* PINnCTRL ISC = buffer disabled  */
.equ LED_BIT,               3             /* on-board LED on PA3             */

.section .text
.global main

main:
    /* 1. Reference: set the shared DAC0/AC0 reference to 1.1 V (VREF.CTRLA) */
    ldi   r16, VREF_DAC0REFSEL_1V1
    sts   VREF_CTRLA, r16

    /* 2. Disable the digital input buffer on the analog input pin PA7 */
    ldi   r16, PORT_ISC_INPUT_DISABLE
    sts   PORTA_PIN7CTRL, r16

    /* 3. OUT pin PA5 and LED pin PA3 as outputs */
    sbi   VPORTA_DIR, 5
    sbi   VPORTA_DIR, LED_BIT

    /* 4. Route the mux: positive = AINP0 (PA7), negative = VREF (1.1 V) */
    ldi   r16, AC_MUXPOS_PIN0 | AC_MUXNEG_VREF
    sts   AC0_MUXCTRLA, r16

    /* 5. Enable AC0 and drive the result on the OUT pin (PA5) */
    ldi   r16, AC_ENABLE_bm | AC_OUTEN_bm
    sts   AC0_CTRLA, r16

    /* main loop: mirror the live comparator state onto the LED */
loop:
    lds   r16, AC0_STATUS          /* STATE (bit4) = live comparator output    */
    sbrc  r16, AC_STATE_bp         /* skip clear if STATE == 1                 */
    rjmp  led_on
    cbi   VPORTA_OUT, LED_BIT      /* PA7 below 1.1 V -> LED off               */
    rjmp  loop
led_on:
    sbi   VPORTA_OUT, LED_BIT      /* PA7 above 1.1 V -> LED on                */
    rjmp  loop
