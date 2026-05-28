/*
 * clock_prescale.S — Change ATtiny3217 main clock prescaler through CCP.
 *                    Companion source for Chapter 10A: Power and Clock Options
 *
 * Covers:
 *   CCP (Configuration Change Protection) — write 0xD8 to CCP, then write
 *   the protected register within 4 CPU cycles with no interrupt between
 *   CLKCTRL_MCLKCTRLB — prescaler enable and division factor
 *   Factory default: OSC20M / 6 = 3.333 MHz; this demo changes the divisor
 *   Observable effect: different prescaler visibly changes LED blink rate
 *
 * Hardware:
 *   LED0 on PA3, active-low on the Curiosity Nano.
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o clock_prescale.o clock_prescale.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o clock_prescale.elf clock_prescale.o
 */

#include <avr/io.h>

/* ── Constants ───────────────────────────────────────────────────────────── */
.equ LED_BIT, 3                 /* PA3, Curiosity Nano LED0 (active-low)       */

/* Outer loop count for blink_delay.
 * The inner loop is 256 × 256 = 65536 iterations at 4 cy each = 262144 cy.
 * At 3.333 MHz (full speed) 262144 cy × 24 = 6291456 cy ≈ 1.89 s per half
 * period → LED toggle every ~1.9 s.
 * At 416.7 kHz (÷48) the same loop runs 8× slower → toggle every ~15 s.   */
.equ DELAY_FAST_OUTER, 24
.equ DELAY_SLOW_OUTER, 4

/* CCP key for protected I/O register writes (CLKCTRL, SLPCTRL, etc.).
 * Write 0xD8 to CPU_CCP; the next instruction must write the protected reg. */
.equ CCP_IOREG_KEY, 0xD8

/* MCLKCTRLB value to prescale 20 MHz OSC20M by 48 → 416.7 kHz.
 * PDIV field bits [5:2] = 0x0C selects DIV48.
 * PEN bit [0] enables the prescaler.                                         */
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

    /* Run at full speed: clear MCLKCTRLB.PEN to disable prescaler.
     * PEN = 0 means the prescaler is bypassed; CPU sees the full 20 MHz.    */
    clr   r17
    rcall clock_write_mclkctrlb

    ldi   r18, 8                    /* blink 8 times fast so the speed change  */
.Lfast:                             /* is visible before we slow down          */
    ldi   r19, DELAY_FAST_OUTER
    rcall blink_delay
    ldi   r16, (1 << LED_BIT)
    sts   PORTA_OUTTGL, r16
    dec   r18
    brne  .Lfast

    /* Slow down: 20 MHz / 48 = about 416.7 kHz.
     * After this write the CPU runs ~8× slower; the same delay loop becomes
     * visibly much longer, demonstrating the effect of the prescaler change. */
    ldi   r17, MCLKCTRLB_DIV48
    rcall clock_write_mclkctrlb

.Lslow:
    ldi   r19, DELAY_SLOW_OUTER
    rcall blink_delay
    ldi   r16, (1 << LED_BIT)
    sts   PORTA_OUTTGL, r16
    rjmp  .Lslow

/* ── clock_write_mclkctrlb ────────────────────────────────────────────────
 *
 * Input:  r17 = new value for CLKCTRL_MCLKCTRLB
 *
 * CLKCTRL_MCLKCTRLB is a CCP-protected register. The ATtiny3217 datasheet
 * requires: write CCP_IOREG_KEY (0xD8) to CPU_CCP, then write the target
 * register within the very next instruction. Any instruction in between
 * (including RCALL) will consume the protection window and the write to
 * MCLKCTRLB will be silently ignored.
 *
 * Here we load the key into r16 before the unlock so the STS CPU_CCP and
 * STS CLKCTRL_MCLKCTRLB are truly back-to-back.
 */
clock_write_mclkctrlb:
    ldi   r16, CCP_IOREG_KEY           /* key value: must be 0xD8             */
    sts   CPU_CCP, r16                 /* open 4-instruction CCP window        */
    sts   CLKCTRL_MCLKCTRLB, r17      /* protected write: must be next instr  */
    ret

/* ── blink_delay ──────────────────────────────────────────────────────────
 *
 * Input:  r19 = outer loop count
 *
 * Nested busy-wait loop: outer × 256 × 256 × 4 CPU cycles.
 * Deliberately uses the CPU clock without calibration — the wall-clock delay
 * changes when the prescaler is altered, making the speed difference visible.
 * Clobbers r24:r25 and flags.
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
