/* ============================================================
 * wdt_demo.S — watchdog setup, petting, reset-cause decode, software reset
 * Target: ATtiny3217 @ 3.333 MHz (default OSC20M /6)
 * Build:  avr-gcc -mmcu=attiny3217 -nostartfiles wdt_demo.S -o wdt_demo.elf
 * ============================================================
 *
 * Demonstrates:
 *   - Reading and clearing the reset cause in RSTCTRL.RSTFR on startup. The LED
 *     (PA3) is lit when this boot was caused by a Watchdog reset (WDRF), so you
 *     can SEE the watchdog recover the system.
 *   - Enabling the WDT for a 1 s normal-mode timeout. WDT.CTRLA is under CCP
 *     using the IOREG key (0xD8) — note this differs from NVMCTRL's SPM key
 *     (0x9D) used for EEPROM. The CTRLA write is also clock-domain synchronized,
 *     so we wait for SYNCBUSY to clear first.
 *   - Petting the dog with the WDR instruction in the main loop.
 *   - A software reset path via RSTCTRL.SWRR (also CCP / IOREG protected).
 *
 * To watch the watchdog bite: comment out the `wdr` in the loop. After ~1 s with
 * no WDR the device resets; on the next boot WDRF is set and the LED comes on.
 *
 * Constants: _bm/_bp masks are #define. PERIOD value and the CCP key are .equ
 * from the datasheet (the _gc names are C enums, unusable in .S).
 *
 * Registers: r16 scratch.
 * ============================================================ */
#include <avr/io.h>

.equ CCP_IOREG_KEY,   0xD8       /* CPU.CCP key for WDT.CTRLA / RSTCTRL.SWRR  */
.equ WDT_PERIOD_1KCLK, 0x08      /* WDT.CTRLA PERIOD = 1K cycles ~= 1.0 s     */
.equ LED_BIT,         3          /* on-board LED on PA3                       */

.section .text
.global main

main:
    sbi   VPORTA_DIR, LED_BIT

    /* --- decode and clear the reset cause --------------------------------- */
    lds   r16, RSTCTRL_RSTFR         /* read all reset flags                  */
    sts   RSTCTRL_RSTFR, r16         /* clear them (write 1 to clear)         */
    sbrc  r16, RSTCTRL_WDRF_bp       /* was this a watchdog reset?            */
    sbi   VPORTA_OUT, LED_BIT        /* yes -> light the LED                  */

    /* --- enable the watchdog: 1 s normal mode ----------------------------- */
1:  lds   r16, WDT_STATUS            /* CTRLA write needs SYNCBUSY == 0       */
    sbrc  r16, WDT_SYNCBUSY_bp
    rjmp  1b
    ldi   r16, CCP_IOREG_KEY
    sts   CPU_CCP, r16               /* arm CCP for the next 4 instructions   */
    ldi   r16, WDT_PERIOD_1KCLK
    sts   WDT_CTRLA, r16             /* protected write: enable WDT, ~1 s      */

    /* --- main loop: keep the system alive by petting the dog -------------- */
loop:
    wdr                              /* reset the watchdog timer              */
    /* ... real work would go here ... */
    rjmp  loop

/* ------------------------------------------------------------
 * software_reset: request an immediate system reset.
 *   RSTCTRL.SWRR is CCP-protected with the IOREG key.
 * ------------------------------------------------------------ */
.global software_reset
software_reset:
    ldi   r16, CCP_IOREG_KEY
    sts   CPU_CCP, r16
    ldi   r16, RSTCTRL_SWRE_bm       /* = 0x01: request software reset        */
    sts   RSTCTRL_SWRR, r16          /* resets immediately; never returns     */
    ret
