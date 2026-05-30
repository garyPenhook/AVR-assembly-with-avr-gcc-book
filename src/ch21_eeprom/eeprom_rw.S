/* ============================================================
 * eeprom_rw.S — write and read back a byte in EEPROM via NVMCTRL
 * Target: ATtiny3217 @ 3.333 MHz (default OSC20M /6)
 * Build:  avr-gcc -mmcu=attiny3217 -nostartfiles eeprom_rw.S -o eeprom_rw.elf
 * ============================================================
 *
 * Demonstrates:
 *   - EEPROM is memory-mapped at 0x1400 (256 bytes, 64-byte page). Reading is
 *     a plain LDS; no command or wait is needed.
 *   - Writing goes through the Nonvolatile Memory Controller (NVMCTRL):
 *       1. wait for EEBUSY to clear,
 *       2. store the byte to the mapped EEPROM address (fills the page buffer),
 *       3. unlock CPU.CCP with the SPM key (0x9D),
 *       4. within 4 instructions, write the Erase+Write Page command (ERWP) to
 *          NVMCTRL.CTRLA.
 *     For EEPROM, only the bytes touched in the page buffer are erased/written,
 *     so this updates a single byte without disturbing the rest of the page.
 *
 * This program writes 0x2A to EEPROM offset 0, reads it back into r20, and
 * mirrors bit 1 of the value onto the on-board LED (PA3) as a visible check
 * (0x2A has bit 1 set, so the LED turns on if the round-trip worked).
 *
 * Constants: _bm/_bp masks are #define and assemble in .S. CMD and CCP group
 * configs are C enums in the header, so their values are .equ from the
 * datasheet (NVMCTRL p.61-63).
 *
 * Registers: r16 scratch, r18 offset arg, r19 data arg, r20 read-back,
 *            Z (r30:r31) EEPROM pointer.
 * ============================================================ */
#include <avr/io.h>

.equ EEPROM_BASE,  0x1400          /* mapped EEPROM start (datasheet)        */
.equ NVM_CMD_ERWP, 0x03            /* NVMCTRL.CTRLA CMD = erase+write page    */
.equ CCP_SPM_KEY,  0x9D            /* CPU.CCP unlock key for NVMCTRL.CTRLA    */
.equ LED_BIT,      3               /* on-board LED on PA3                     */

.section .text
.global main

main:
    sbi   VPORTA_DIR, LED_BIT      /* LED pin as output                      */

    /* write 0x2A to EEPROM offset 0 */
    ldi   r18, 0                   /* offset                                 */
    ldi   r19, 0x2A                /* data                                   */
    rcall eeprom_write_byte

    /* read it back from offset 0 */
    ldi   ZL, lo8(EEPROM_BASE)
    ldi   ZH, hi8(EEPROM_BASE)
    ld    r20, Z                   /* r20 = stored byte                      */

    /* visible check: light the LED if bit 1 of the read-back is set */
    sbrc  r20, 1
    sbi   VPORTA_OUT, LED_BIT

loop:
    rjmp  loop

/* ------------------------------------------------------------
 * eeprom_write_byte: write r19 to EEPROM[r18]
 *   in:  r18 = offset (0..255), r19 = data byte
 *   uses: r16, Z
 * ------------------------------------------------------------ */
eeprom_write_byte:
    /* 1. wait until any previous EEPROM write has finished */
1:  lds   r16, NVMCTRL_STATUS
    sbrc  r16, NVMCTRL_EEBUSY_bp
    rjmp  1b

    /* 2. point Z at EEPROM_BASE + offset and store the byte (fills buffer).
     *    EEPROM_BASE low byte is 0x00 and offset <= 0xFF, so no carry to ZH. */
    ldi   ZL, lo8(EEPROM_BASE)
    ldi   ZH, hi8(EEPROM_BASE)
    add   ZL, r18
    st    Z, r19

    /* 3+4. unlock CCP, then issue ERWP within the 4-instruction window */
    ldi   r16, CCP_SPM_KEY
    sts   CPU_CCP, r16             /* arm CCP for the next 4 instructions     */
    ldi   r16, NVM_CMD_ERWP
    sts   NVMCTRL_CTRLA, r16       /* protected write: erase+write the page   */
    ret
