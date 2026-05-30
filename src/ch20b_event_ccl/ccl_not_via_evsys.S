/* ============================================================
 * ccl_not_via_evsys.S — CCL logic gate wired with the Event System
 * Target: ATtiny3217 @ 3.333 MHz (default OSC20M /6)
 * Build:  avr-gcc -mmcu=attiny3217 -nostartfiles ccl_not_via_evsys.S \
 *                 -o ccl_not_via_evsys.elf
 * ============================================================
 *
 * Demonstrates:
 *   - a CCL LUT computing OUT = NOT(IN0) from an event input
 *   - feeding the LUT from EVSYS (EVENTA), not a raw pin, so the
 *     example does not depend on the CCL's fixed I/O pin assignments
 *   - routing the LUT result back out through EVSYS to EVOUTA (PA2)
 *
 * Signal path (all in hardware, CPU idle):
 *   PA6 --ASYNCCH0--> CCL_LUT0_EV0 (ASYNCUSER2) = LUT0 EVENTA
 *   LUT0 TRUTH=0x55 (inverter) --ASYNCCH1(CCL_LUT0)--> EVOUTA(ASYNCUSER8)=PA2
 *   => PA2 = NOT(PA6)
 *
 * Note on constants: in iotn3217.h the _gc group-config constants are C
 * enum members, not #define macros, so the assembler cannot see them
 * (a bare _gc => "undefined reference"). The _bm/_bp bit constants are
 * #defines and work in .S. So _gc selection values are .equ here.
 *
 * Verified values (ATtiny3217 datasheet DS40002205A):
 *   p.119  ASYNCCH0 gen PORTA_PIN6 = 0x10 ; ASYNCCH1 gen CCL_LUT0 = 0x01
 *   p.121  ASYNCUSER2 = CCL_LUT0_EV0 ; ASYNCUSER8 = EVOUTA(PA2)
 *          channel select ASYNCCH0 = 0x03, ASYNCCH1 = 0x04
 *   p.409  CCL regs: LUTnCTRLA(ENABLE=bit0, OUTEN=bit3),
 *          LUTnCTRLB(INSEL0[3:0], INSEL1[7:4]), LUTnCTRLC(INSEL2[3:0])
 *          CCL INSEL: MASK=0x0, EVENTA=0x3
 *
 * Wiring (ATtiny3217 Curiosity Nano):
 *   PA6 = input  (drive high/low)
 *   PA2 = output (shows the inverted level)
 *
 * Ordering note: CCL LUT config registers are enable-protected — set
 * LUT0CTRLB/C and TRUTH0 BEFORE enabling the LUT and the module.
 *
 * Registers used:
 *   r16 = scratch for register writes
 * ============================================================ */
#include <avr/io.h>

/* EVSYS selection values (datasheet sec.15) */
.equ ASYNCCH0_PORTA_PIN6, 0x10
.equ ASYNCCH1_CCL_LUT0,   0x01
.equ ASYNCUSER_SEL_CH0,   0x03   /* user listens to ASYNCCH0 */
.equ ASYNCUSER_SEL_CH1,   0x04   /* user listens to ASYNCCH1 */

/* CCL field values (datasheet sec.28) */
.equ CCL_INSEL0_EVENTA, 0x03     /* LUTnCTRLB[3:0] = EVENTA            */
.equ CCL_INSEL1_MASK,   0x00     /* LUTnCTRLB[7:4] = MASK             */
.equ CCL_INSEL2_MASK,   0x00     /* LUTnCTRLC[3:0] = MASK             */
.equ CCL_LUT_ENABLE,    0x01     /* LUTnCTRLA bit0                    */
.equ CCL_MOD_ENABLE,    0x01     /* CTRLA   bit0                      */
.equ TRUTH_NOT_IN0,     0x55     /* OUT = NOT(IN0)                    */

.section .text
.global main

main:
    /* --- PA6 input, PA2 output --- */
    cbi   VPORTA_DIR, 6
    sbi   VPORTA_DIR, 2

    /* --- EVSYS: PA6 onto async channel 0 --- */
    ldi   r16, ASYNCCH0_PORTA_PIN6
    sts   EVSYS_ASYNCCH0, r16

    /* --- EVSYS: channel 0 feeds LUT0's EVENTA (CCL_LUT0_EV0 = user 2) --- */
    ldi   r16, ASYNCUSER_SEL_CH0
    sts   EVSYS_ASYNCUSER2, r16

    /* --- CCL LUT0 inputs: IN0 = EVENTA, IN1/IN2 masked off --- */
    ldi   r16, CCL_INSEL0_EVENTA | (CCL_INSEL1_MASK << 4)
    sts   CCL_LUT0CTRLB, r16
    ldi   r16, CCL_INSEL2_MASK
    sts   CCL_LUT0CTRLC, r16

    /* --- truth table: OUT = NOT(IN0) --- */
    ldi   r16, TRUTH_NOT_IN0
    sts   CCL_TRUTH0, r16

    /* --- enable LUT0 (no OUTEN: we take the output via EVSYS) --- */
    ldi   r16, CCL_LUT_ENABLE
    sts   CCL_LUT0CTRLA, r16

    /* --- enable the CCL module --- */
    ldi   r16, CCL_MOD_ENABLE
    sts   CCL_CTRLA, r16

    /* --- EVSYS: LUT0 output onto async channel 1 --- */
    ldi   r16, ASYNCCH1_CCL_LUT0
    sts   EVSYS_ASYNCCH1, r16

    /* --- EVSYS: channel 1 drives EVOUTA (PA2) --- */
    ldi   r16, ASYNCUSER_SEL_CH1
    sts   EVSYS_ASYNCUSER8, r16

loop:
    rjmp  loop
