/* ============================================================
 * dac_output.S — DAC0: drive ~1.25 V on the OUT pin (PA6)
 * Target: ATtiny3217 @ 3.333 MHz (default OSC20M /6)
 * Build:  avr-gcc -mmcu=attiny3217 -nostartfiles dac_output.S -o dac_output.elf
 * ============================================================
 *
 * Demonstrates:
 *   - DAC0 is an 8-bit resistor-string DAC. It converts the value in DAC0.DATA
 *     to an analog voltage between GND and the selected VREF:
 *         Vout = (DATA / 256) * VREF
 *   - With VREF = 2.5 V and DATA = 128: Vout = 128/256 * 2.5 = 1.25 V.
 *   - The output is enabled on the OUT pin (PA6) via OUTEN. PA6 is also the
 *     AC0 negative input AINN0, so the DAC can feed the comparator internally.
 *
 * Init order (datasheet sec.31): VREF select -> OUTEN/pin -> DATA -> ENABLE.
 *
 * Constants: _bm masks are #define and assemble in .S. The VREF group config
 * is a C enum in the header, so its value is .equ from the datasheet.
 *
 * Registers used: r16 (scratch)
 * ============================================================ */
#include <avr/io.h>

.equ VREF_DAC0REFSEL_2V5,    0x02          /* VREF.CTRLA DAC0REFSEL = 2.5 V   */
.equ PORT_ISC_INPUT_DISABLE, 0x04          /* PINnCTRL ISC = buffer disabled  */

.section .text
.global main

main:
    /* 1. Reference: set the shared DAC0/AC0 reference to 2.5 V (VREF.CTRLA) */
    ldi   r16, VREF_DAC0REFSEL_2V5
    sts   VREF_CTRLA, r16

    /* 2. Disable the digital input buffer on the analog output pin PA6 */
    ldi   r16, PORT_ISC_INPUT_DISABLE
    sts   PORTA_PIN6CTRL, r16

    /* 3. Initial value: 128 -> mid-scale = 1.25 V at VREF = 2.5 V */
    ldi   r16, 128
    sts   DAC0_DATA, r16

    /* 4. Enable DAC0 and route the output to the OUT pin (PA6) */
    ldi   r16, DAC_ENABLE_bm | DAC_OUTEN_bm
    sts   DAC0_CTRLA, r16

    /* DAC now holds PA6 at ~1.25 V. Writing DAC0_DATA changes it live. */
loop:
    rjmp  loop
