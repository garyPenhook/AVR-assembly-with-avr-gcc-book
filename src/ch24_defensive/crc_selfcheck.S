/* ============================================================
 * crc_selfcheck.S — verify Flash integrity at run time with CRCSCAN
 * Target: ATtiny3217 @ 3.333 MHz (default OSC20M /6)
 * Build:  avr-gcc -mmcu=attiny3217 -nostartfiles crc_selfcheck.S -o crc_selfcheck.elf
 * ============================================================
 *
 * Demonstrates the CRCSCAN peripheral, which computes a CRC-16 over a Flash
 * section in hardware and reports pass/fail:
 *   1. select the section in CRCSCAN.CTRLB (SRC = FLASH = entire Flash),
 *   2. start the scan by writing ENABLE in CRCSCAN.CTRLA,
 *   3. in Priority mode (the only mode here) the CRC has priority access to
 *      Flash and stalls the CPU until the scan finishes, so BUSY reads 0 by the
 *      time we look,
 *   4. check the OK flag in CRCSCAN.STATUS: 1 = Flash matches its stored CRC.
 *
 * The LED (PA3) lights when OK = 1.
 *
 * IMPORTANT — this builds and the control flow is correct, but OK will only be
 * 1 on real hardware if a valid CRC-16 has been APPENDED to the end of Flash by
 * a post-build tool (the pre-calculated checksum lives at FLASHEND-1:FLASHEND
 * for a full-Flash scan). Without that step the scan runs but reports OK = 0.
 * See the chapter for the fuse-driven pre-boot scan (CRCSRC in SYSCFG0), which
 * needs no run-time code at all.
 *
 * Constants: _bm/_bp masks are #define. SRC is a C enum in the header, so its
 * value is .equ from the datasheet (CRCSCAN.CTRLB SRC = FLASH = 0x0).
 *
 * Registers: r16 scratch.
 * ============================================================ */
#include <avr/io.h>

.equ CRCSCAN_SRC_FLASH, 0x00      /* CTRLB SRC = CRC over entire Flash       */
.equ LED_BIT,           3         /* on-board LED on PA3                     */

.section .text
.global main

main:
    sbi   VPORTA_DIR, LED_BIT

    /* 1. select the section to check: entire Flash (Priority mode = 0) */
    ldi   r16, CRCSCAN_SRC_FLASH
    sts   CRCSCAN_CTRLB, r16

    /* 2. start the scan */
    ldi   r16, CRCSCAN_ENABLE_bm
    sts   CRCSCAN_CTRLA, r16

    /* 3. wait until the scan is done (BUSY clears; CPU was stalled in Priority
     *    mode, so this typically falls through immediately) */
1:  lds   r16, CRCSCAN_STATUS
    sbrc  r16, CRCSCAN_BUSY_bp
    rjmp  1b

    /* 4. OK = 1 -> Flash integrity verified */
    sbrc  r16, CRCSCAN_OK_bp
    sbi   VPORTA_OUT, LED_BIT

loop:
    rjmp  loop
