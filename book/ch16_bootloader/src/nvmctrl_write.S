/*
 * nvmctrl_write.S — NVMCTRL flash page-write routines for ATtiny3217
 *
 * Target:  ATtiny3217 (AVRXMEGA3 architecture)
 * Board:   Curiosity Nano
 *
 * This file provides two routines:
 *
 *   nvm_wait         — poll NVMCTRL_STATUS.FBUSY until the NVM is idle
 *   nvm_write_page   — write one 64-byte page from SRAM to flash
 *
 * Flash write sequence (AVRXMEGA3 / NVMCTRL):
 *   1. Wait until FBUSY = 0 (no operation in progress)
 *   2. Write NOCMD (0x00) to NVMCTRL_CTRLA (clear any stale error)
 *   3. Fill page buffer: 64 × ST Z+, Rn  (plain stores to flash address)
 *   4. Rewind Z to page-start base address
 *   5. CLI — disable interrupts to protect the CCP window
 *   6. STS CPU_CCP, 0x9D     (CCP_SPM_gc key, opens 4-cycle window)
 *   7. STS NVMCTRL_CTRLA, 0x03  (PAGEERASEWRITE — must be within 4 cycles)
 *   8. SEI — re-enable interrupts
 *   9. Wait until FBUSY = 0 again
 *
 * CCP (Configuration Change Protection):
 *   The PAGEERASEWRITE command requires the CCP unlock key 0x9D to be written
 *   to CPU_CCP (0x0034), then the NVMCTRL_CTRLA write must execute within
 *   the next four CPU instructions. This source makes it the next instruction.
 *
 * Entry conditions for nvm_write_page:
 *   Z  (R31:R30) = mapped flash data address of target page
 *                  (0x8000 + flash byte address, 64-byte aligned)
 *   X  (R27:R26) = SRAM address of 64-byte source data buffer
 *
 * Exit conditions:
 *   Z advanced by 64 (points to start of next page)
 *   X advanced by 64 (points past the last source byte)
 *   Flash page at entry-Z contains the new data
 *   Clobbers: R16, R17, R18
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -nodefaultlibs \
 *           -o nvmctrl_write.elf nvmctrl_write.S
 *   avr-objcopy -O ihex nvmctrl_write.elf nvmctrl_write.hex
 *
 * Standalone test:
 *   avr-objdump -d nvmctrl_write.elf
 *   Check that STS 0x0034 and STS 0x1000 are back-to-back (no instruction
 *   between them) in the CCP sequence.
 */

/* ── NVMCTRL register addresses (all outside I/O space: use LDS/STS) ───── */
.equ NVMCTRL_CTRLA,   0x1000       /* command register                      */
.equ NVMCTRL_CTRLB,   0x1001       /* BOOTLOCK / APCWP configuration        */
.equ NVMCTRL_STATUS,  0x1002       /* FBUSY (bit 0), EEBUSY (bit 1)         */
                                    /* WRERROR (bit 2) — write 1 to clear    */

/* ── NVMCTRL_STATUS bit positions ──────────────────────────────────────── */
.equ NVMCTRL_FBUSY_bp,  0          /* Flash Busy bit position                */
.equ NVMCTRL_EEBUSY_bp, 1          /* EEPROM Busy bit position               */
.equ NVMCTRL_WRERROR_bp, 2         /* Write Error bit position               */

/* ── NVMCTRL commands (written to NVMCTRL_CTRLA) ───────────────────────── */
.equ NVMCTRL_CMD_NOCMD_gc,          0x00  /* no operation / clear error      */
.equ NVMCTRL_CMD_PAGEWRITE_gc,      0x01  /* write page buffer (no erase)    */
.equ NVMCTRL_CMD_PAGEERASE_gc,      0x02  /* erase one page                  */
.equ NVMCTRL_CMD_PAGEERASEWRITE_gc, 0x03  /* erase + write (recommended)     */
.equ NVMCTRL_CMD_PAGEBUFERASE_gc,   0x04  /* clear page buffer               */
.equ NVMCTRL_CMD_CHIPERASE_gc,      0x05  /* erase flash array; avoid here   */
.equ NVMCTRL_CMD_EEERASE_gc,        0x06  /* erase EEPROM                    */
.equ NVMCTRL_CMD_FUSEWRITE_gc,      0x07  /* write fuses (restricted)        */

/* ── CCP (Configuration Change Protection) ─────────────────────────────── */
.equ CPU_CCP,       0x0034          /* CCP register address (I/O space)      */
.equ CCP_SPM_gc,    0x9D            /* key for NVM self-programming commands  */
.equ CCP_IOREG_gc,  0xD8            /* key for protected I/O register writes  */

/* ── Flash page size ────────────────────────────────────────────────────── */
.equ PAGE_SIZE,     64              /* ATtiny3217: 64 bytes per flash page    */

/* ═══════════════════════════════════════════════════════════════════════════
 * nvm_wait — spin until NVMCTRL_STATUS.FBUSY = 0
 *
 * Inputs:  none
 * Outputs: none
 * Clobbers: R16
 *
 * Timing per poll iteration:
 *   LDS  NVMCTRL_STATUS  — 2 cycles (extended I/O read)
 *   SBRC R16, 0          — 1 cycle (not skipping, bit is set)
 *   RJMP nvm_wait        — 2 cycles (taken branch)
 *   ─────────────────────  5 cycles per iteration
 *
 * A PAGEERASEWRITE takes ~2.5 ms at any clock frequency.
 * At 3.333 MHz, that is ~8333 cycles → ~1667 poll iterations.
 * ═══════════════════════════════════════════════════════════════════════════ */
.global nvm_wait
nvm_wait:
    lds   r16, NVMCTRL_STATUS          /* 2 cy: read NVMCTRL status register */
    sbrc  r16, NVMCTRL_FBUSY_bp        /* 1 cy: skip next if FBUSY = 0       */
    rjmp  nvm_wait                     /* 2 cy: still busy — loop            */
    ret                                /* 4 cy                                */


/* ═══════════════════════════════════════════════════════════════════════════
 * nvm_write_page — write one 64-byte page from SRAM to flash
 *
 * Entry:
 *   Z (R31:R30) = mapped flash data address of target page
 *                 0x8000 + flash byte address
 *                 MUST be 64-byte aligned (bits 5:0 = 0)
 *   X (R27:R26) = SRAM address of 64-byte source buffer
 *
 * Exit:
 *   Z = entry_Z + 64  (points to start of next page)
 *   X = entry_X + 64  (points past last byte copied)
 *   Clobbers: R16, R17, R18
 *
 * Notes:
 *   - If Z is not 64-byte aligned, partial page corruption will occur.
 *   - Do not call from an ISR (uses CLI/SEI around the CCP sequence).
 *   - The caller may wish to CLI around the entire write for maximum safety.
 * ═══════════════════════════════════════════════════════════════════════════ */
.global nvm_write_page
nvm_write_page:

    /* ── Step 1: Wait for any previous NVM operation to finish ─────────── */
    rcall nvm_wait                     /* spin until FBUSY = 0               */

    /* ── Step 2: Clear any stale error (NOCMD) ─────────────────────────── */
    ldi   r16, NVMCTRL_CMD_NOCMD_gc   /* r16 = 0x00                          */
    sts   NVMCTRL_CTRLA, r16          /* 2 cy: write NOCMD to command reg    */

    /* ── Step 3: Fill the page buffer (64 bytes) ───────────────────────── */
    /*
     * Each iteration: LD r18, X+ (2 cy) + ST Z+, r18 (2 cy)
     *                + DEC r17 (1 cy) + BRNE (2 cy taken / 1 cy last)
     * Total fill: 64 × 7 − 1 (last brne not taken) = 447 cycles
     */
    ldi   r17, PAGE_SIZE              /* loop counter = 64                   */
.Lfill_loop:
    ld    r18, X+                     /* 2 cy: load byte from SRAM buffer    */
    st    Z+,  r18                    /* 2 cy: write to flash page buffer    */
    dec   r17                         /* 1 cy: decrement loop counter        */
    brne  .Lfill_loop                 /* 2/1 cy: loop until counter = 0      */

    /* ── Step 4: Rewind Z to page start ────────────────────────────────── */
    /*
     * After the fill loop, Z = entry_Z + 64.
     * SBIW ZL, 64 subtracts 64 from the 16-bit Z register pair in 2 cycles.
     * Z now points to the base address of the page we just filled.
     */
    subi  ZL, lo8(PAGE_SIZE)          /* Z -= 64                             */
    sbci  ZH, hi8(PAGE_SIZE)

    /* ── Step 5–7: CCP-protected PAGEERASEWRITE command ────────────────── */
    /*
     * The PAGEERASEWRITE command requires the CCP unlock sequence:
     *   1. Write CCP_SPM_gc (0x9D) to CPU_CCP (0x0034) — opens 4-cycle window
     *   2. Write PAGEERASEWRITE (0x03) to NVMCTRL_CTRLA — within 4 cycles
     *
     * Two STS instructions = 2 + 2 = exactly 4 cycles.
     * CLI/SEI prevent an ISR from consuming cycles inside the window.
     *
     * IMPORTANT: Do NOT place any instruction between the two STS calls.
     */
    cli                               /* 1 cy: disable interrupts             */
    ldi   r16, NVMCTRL_CMD_PAGEERASEWRITE_gc  /* command ready before unlock */
    ldi   r17, CCP_SPM_gc             /* key ready before unlock              */
    sts   CPU_CCP, r17                /* open CCP window                      */
    sts   NVMCTRL_CTRLA, r16          /* next instruction: issue command      */
    sei                               /* 1 cy: re-enable interrupts           */

    /* ── Step 8: Wait for the erase+write to complete ──────────────────── */
    rcall nvm_wait                    /* spin until FBUSY = 0                */

    /* ── Advance Z to start of next page for caller convenience ────────── */
    subi  ZL, lo8(-PAGE_SIZE)         /* Z += 64                             */
    sbci  ZH, hi8(-PAGE_SIZE)

    ret                               /* 4 cy: return to caller               */


/* ═══════════════════════════════════════════════════════════════════════════
 * nvm_erase_page — erase one flash page (set all bytes to 0xFF)
 *
 * Entry:
 *   Z (R31:R30) = mapped flash data address of any byte within the target page
 *                 (0x8000 + flash byte address)
 *                 (the hardware ignores the low 6 bits — page-aligned auto.)
 * Exit:
 *   Z unchanged
 *   Clobbers: R16
 *
 * Use case: erase a page without writing new content (e.g. clearing a log).
 * ═══════════════════════════════════════════════════════════════════════════ */
.global nvm_erase_page
nvm_erase_page:
    rcall nvm_wait

    ldi   r16, NVMCTRL_CMD_NOCMD_gc
    sts   NVMCTRL_CTRLA, r16          /* clear any previous error             */

    cli
    ldi   r16, NVMCTRL_CMD_PAGEERASE_gc
    ldi   r17, CCP_SPM_gc
    sts   CPU_CCP, r17                /* open CCP window                      */
    sts   NVMCTRL_CTRLA, r16          /* next instruction: issue PAGEERASE    */
    sei

    rcall nvm_wait
    ret


/* ═══════════════════════════════════════════════════════════════════════════
 * nvm_chip_erase — issue the NVMCTRL CHIPERASE command
 *
 * Entry:  none
 * Exit:   none
 * Clobbers: R16
 *
 * WARNING: Microchip AN2634 warns against using CHIPERASE during
 * self-programming because it erases the Flash array. Do not use this in a
 * recoverable bootloader design.
 * ═══════════════════════════════════════════════════════════════════════════ */
.global nvm_chip_erase
nvm_chip_erase:
    rcall nvm_wait

    cli
    ldi   r16, NVMCTRL_CMD_CHIPERASE_gc
    ldi   r17, CCP_SPM_gc
    sts   CPU_CCP, r17
    sts   NVMCTRL_CTRLA, r16
    sei

    rcall nvm_wait
    ret
