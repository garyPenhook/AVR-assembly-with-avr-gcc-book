/* ============================================================
 * fuse_read.S — read configuration fuses at run time
 * Target: ATtiny3217 @ 3.333 MHz (default OSC20M /6)
 * Build:  avr-gcc -mmcu=attiny3217 -nostartfiles fuse_read.S -o fuse_read.elf
 * ============================================================
 *
 * Demonstrates:
 *   - Fuses are nonvolatile configuration latched into peripheral registers at
 *     reset. They are READ-ONLY at run time and memory-mapped at 0x1280, so a
 *     plain LDS reads the live value. (Writing fuses needs a UPDI programmer;
 *     the NVM FUSEWRITE command is PDI-only and not reachable from firmware.)
 *   - Here we read SYSCFG0 and check the Reset Pin Configuration (RSTPINCFG)
 *     field. The on-board LED (PA3) lights if the UPDI pin is in UPDI mode
 *     (RSTPINCFG = 0x1, the default) — i.e. the device is still reprogrammable.
 *
 * RSTPINCFG (SYSCFG0 bits[3:2]): 0=GPIO, 1=UPDI (default), 2=RESET.
 *
 * Constants: FUSE_SYSCFG0 is a #define (assembles in .S). The field shift/mask
 * are .equ from the datasheet so the file builds without the _gc enums.
 *
 * Registers: r16 scratch.
 * ============================================================ */
#include <avr/io.h>

.equ RSTPINCFG_gp,   2          /* SYSCFG0 RSTPINCFG field position  */
.equ RSTPINCFG_gm,   0x0C       /* field mask (bits 3:2)             */
.equ RSTPINCFG_UPDI, (0x1 << 2) /* UPDI mode value in place          */
.equ LED_BIT,        3          /* on-board LED on PA3               */

.section .text
.global main

main:
    sbi   VPORTA_DIR, LED_BIT          /* LED pin as output            */

    /* read SYSCFG0 fuse (memory-mapped, read-only) and isolate RSTPINCFG */
    lds   r16, FUSE_SYSCFG0
    andi  r16, RSTPINCFG_gm
    cpi   r16, RSTPINCFG_UPDI          /* == UPDI mode?                */
    brne  done                         /* not UPDI -> leave LED off    */
    sbi   VPORTA_OUT, LED_BIT          /* UPDI mode -> LED on          */
done:
loop:
    rjmp  loop
