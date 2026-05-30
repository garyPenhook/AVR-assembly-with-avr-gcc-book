/* ============================================================
 * evsys_pin_mirror.S — mirror one pin to another with the Event System
 * Target: ATtiny3217 @ 3.333 MHz (default OSC20M /6)
 * Build:  avr-gcc -mmcu=attiny3217 -nostartfiles evsys_pin_mirror.S \
 *                 -o evsys_pin_mirror.elf
 * ============================================================
 *
 * Demonstrates:
 *   - EVSYS generator -> async channel  (PA6 onto ASYNCCH0)
 *   - EVSYS async channel -> user       (EVOUTA = ASYNCUSER8)
 *   - zero-CPU signal routing: PA2 follows PA6 in hardware
 *
 * Note on constants: in iotn3217.h the EVSYS/CCL _gc group-config
 * constants exist, but as C *enum* members — not #define macros. The
 * assembler only runs the C preprocessor, so it never sees enum names
 * (that is why a bare _gc gives "undefined reference" when assembling).
 * The _bm/_bp bit constants ARE #defines and do work in .S. So here we
 * define the _gc selection values as .equ from the datasheet (sec.15).
 *
 * Verified values (ATtiny3217 datasheet DS40002205A):
 *   p.119  ASYNCCH0 generator: PORTA_PIN6 = 0x10
 *   p.121  ASYNCUSER8 = EVOUTA (drives PA2); channel select ASYNCCH0 = 0x03
 *
 * Wiring (ATtiny3217 Curiosity Nano):
 *   PA6 = input  (drive it high/low, e.g. a button or jumper)
 *   PA2 = output (EVOUTA) — scope/LED here mirrors PA6, no code in the loop
 *
 * Registers used:
 *   r16 = scratch for register writes
 * ============================================================ */
#include <avr/io.h>

/* EVSYS selection values (datasheet sec.15; no _gc macros in the header) */
.equ ASYNCCH0_PORTA_PIN6, 0x10   /* ASYNCCHn generator: PORTA pin 6        */
.equ ASYNCUSER_SEL_CH0,   0x03   /* ASYNCUSERn listens to ASYNCCH0         */

.section .text
.global main

main:
    /* --- PA6 as input (its pin state is the event source) --- */
    cbi   VPORTA_DIR, 6              /* PA6 = input                           */

    /* --- PA2 as output so EVOUTA can drive it --- */
    sbi   VPORTA_DIR, 2              /* PA2 = output                          */

    /* --- generator: PA6 drives async channel 0 --- */
    ldi   r16, ASYNCCH0_PORTA_PIN6
    sts   EVSYS_ASYNCCH0, r16

    /* --- user: EVOUTA (async user 8) listens to async channel 0 --- */
    ldi   r16, ASYNCUSER_SEL_CH0
    sts   EVSYS_ASYNCUSER8, r16

    /* The routing now runs in hardware. The CPU has nothing to do. */
loop:
    rjmp  loop
