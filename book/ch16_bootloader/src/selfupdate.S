/*
 * selfupdate.S — UART-driven self-update firmware for ATtiny3217 Curiosity Nano
 *
 * Target:  ATtiny3217 (AVRXMEGA3 architecture)
 * Board:   Curiosity Nano
 * Clock:   3.333 MHz (20 MHz internal oscillator / 6, CLKCTRL default)
 *
 * Hardware connections (Curiosity Nano defaults):
 *   PB2 = USART0 TXD (connected to on-board debugger USB virtual COM port)
 *   PB3 = USART0 RXD
 *   PA3 = LED0 (active-low: 0 = on, 1 = off)
 *   PA0 = UPDI (do not touch)
 *
 * Protocol (Intel HEX subset):
 *   Host sends:  :LLAAAATT[DD...]CC\r\n
 *   Device replies: '.' (ACK, checksum OK) or '!' (NACK, checksum error)
 *   On EOF record (type 0x01): device sends "OK\r\n", then jumps to 0x0000
 *   Partial/noise bytes before ':' are silently ignored
 *
 * Flash write:
 *   NVMCTRL PAGEERASEWRITE command, CCP-protected.
 *   64-byte page size. Writes are deferred until a 64-byte boundary is
 *   crossed — pages are written when full.
 *
 * Build (no BOOTEND protection):
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -nodefaultlibs \
 *           -o selfupdate.elf selfupdate.S
 *   avr-objcopy -O ihex selfupdate.elf selfupdate.hex
 *   avrdude -c serialupdi -p t3217 -P /dev/ttyUSB0 \
 *           -U flash:w:selfupdate.hex:i
 *
 * Build (with BOOTEND=0x04, 1 KB boot section):
 *   Same build command — selfupdate always links at 0x0000.
 *   The application must link at 0x0400:
 *     avr-gcc -mmcu=attiny3217 -nostartfiles -nodefaultlibs \
 *             -Wl,--section-start=.text=0x0400 -o app.elf app.S
 *   Set BOOTEND fuse:
 *     avrdude -c serialupdi -p t3217 -P /dev/ttyUSB0 -U fuse8:w:0x04:m
 *
 * Registers (global, live throughout the main loop):
 *   Z  (R31:R30)  flash write address — current page base, advances by page
 *   X  (R27:R26)  SRAM page buffer pointer — resets to PAGE_BUF each record
 *   R16           scratch: UART byte, NVMCTRL command, loop data
 *   R17           checksum accumulator (zeroed at each record start)
 *   R18           byte count from record header
 *   R19           record type (0x00 = data, 0x01 = EOF)
 *   R24           address low byte from record header
 *   R25           address high byte from record header
 *   R20, R21      scratch in helpers
 *   R15           saved high nibble in recv_hex_byte
 */

#include <avr/io.h>

/* ── NVMCTRL ────────────────────────────────────────────────────────────── */
.equ NVMCTRL_CTRLA,               0x1000
.equ NVMCTRL_STATUS,              0x1002
.equ NVMCTRL_FBUSY_bp,            0
.equ NVMCTRL_CMD_NOCMD_gc,        0x00
.equ NVMCTRL_CMD_PAGEERASEWRITE_gc, 0x03

/* ── CCP ─────────────────────────────────────────────────────────────────── */
.equ CPU_CCP,   0x0034
.equ CCP_SPM_gc, 0x9D

/* ── USART0 registers (all outside I/O space: use LDS/STS) ─────────────── */
.equ USART0_RXDATAL, 0x0800
.equ USART0_TXDATAL, 0x0802
.equ USART0_STATUS,  0x0804       /* RXCIF=bit7, DREIF=bit5                   */
.equ USART0_CTRLB,   0x0806       /* TXEN=bit6, RXEN=bit7                     */
.equ USART0_BAUDL,   0x0808
.equ USART0_BAUDH,   0x0809

.equ USART_RXCIF_bp,  7           /* RX Complete Interrupt Flag bit position  */
.equ USART_DREIF_bp,  5           /* Data Register Empty Flag bit position    */
.equ USART_TXEN_bm,   0x40        /* CTRLB: TX enable                         */
.equ USART_RXEN_bm,   0x80        /* CTRLB: RX enable                         */

/* ── Baud rate for 9600 baud @ 3.333 MHz ───────────────────────────────── */
/* BAUD_REG = (f_cpu × 64) / (16 × baud) = (3333333 × 64) / 153600 = 1389  */
.equ BAUD_REG, 1389               /* 0x056D — error < 0.01%                  */

/* ── Virtual PORT aliases for sbi/cbi/sbis ─────────────────────────────── */
.equ VPORTA_DIR,  0x00            /* direction: 1 = output, 0 = input        */
.equ VPORTA_OUT,  0x01            /* output data register                     */
.equ VPORTB_DIR,  0x04            /* direction: 1 = output, 0 = input        */
.equ VPORTB_OUT,  0x05            /* output data register                     */
.equ VPORTB_IN,   0x06            /* input data register                      */

/* ── Pin assignments ────────────────────────────────────────────────────── */
.equ TXD_PIN,   2                 /* PB2 = TXD                                */
.equ RXD_PIN,   3                 /* PB3 = RXD (input, no config needed)      */
.equ LED0_PIN,  3                 /* PA3 = LED0, active-low                   */

/* ── Flash geometry ─────────────────────────────────────────────────────── */
.equ PAGE_SIZE, 64                /* ATtiny3217: 64 bytes per page            */

/* ── SRAM page buffer ───────────────────────────────────────────────────── */
/* 64-byte buffer used to accumulate data before a page write.               */
/* Placed in .bss (zero-initialised by convention, but we overwrite anyway). */
.section .bss
page_buf:
    .space PAGE_SIZE              /* 64 bytes of uninitialised SRAM           */

/* ═══════════════════════════════════════════════════════════════════════════
 * Interrupt vector table
 * ATtiny3217 reset vector is at address 0x0000.
 * A single RJMP to selfupdate_main handles the reset vector.
 * All other vectors are unused — point them to a safe infinite loop.
 * ═══════════════════════════════════════════════════════════════════════════ */
.section .text
.global __vectors
__vectors:
    rjmp  selfupdate_main         /* 0x0000: RESET → selfupdate entry         */
    /* remaining vectors omitted — add as needed                              */


/* ═══════════════════════════════════════════════════════════════════════════
 * usart_init — configure USART0 for 9600 8N1 at 3.333 MHz
 * Clobbers: R16
 * ═══════════════════════════════════════════════════════════════════════════ */
usart_init:
    sbi   VPORTB_DIR, TXD_PIN         /* PB2 = TXD output                    */
    /* PB3 (RXD) = input by default — no configuration needed                */
    ldi   r16, lo8(BAUD_REG)
    sts   USART0_BAUDL, r16
    ldi   r16, hi8(BAUD_REG)
    sts   USART0_BAUDH, r16
    ldi   r16, USART_TXEN_bm | USART_RXEN_bm
    sts   USART0_CTRLB, r16           /* enable TX and RX                    */
    /* USART0_CTRLC defaults to 8N1 after reset — no write needed            */
    ret


/* ═══════════════════════════════════════════════════════════════════════════
 * usart_tx — transmit byte in R16 (polling)
 * Waits for DREIF = 1 (data register empty), then writes TXDATAL.
 * Clobbers: R20
 * ═══════════════════════════════════════════════════════════════════════════ */
usart_tx:
.Lwait_dreif:
    lds   r20, USART0_STATUS          /* 2 cy: read status                   */
    sbrs  r20, USART_DREIF_bp         /* 1 cy: skip if DREIF = 1             */
    rjmp  .Lwait_dreif                /* 2 cy: not ready, loop               */
    sts   USART0_TXDATAL, r16         /* 2 cy: send byte                     */
    ret


/* ═══════════════════════════════════════════════════════════════════════════
 * usart_rx — receive one byte → R16 (polling)
 * Spins until RXCIF = 1, then reads RXDATAL.
 * Clobbers: R20
 * ═══════════════════════════════════════════════════════════════════════════ */
usart_rx:
.Lwait_rxcif:
    lds   r20, USART0_STATUS          /* 2 cy: read status                   */
    sbrs  r20, USART_RXCIF_bp         /* 1 cy: skip if RXCIF = 1             */
    rjmp  .Lwait_rxcif                /* 2 cy: no byte yet, loop             */
    lds   r16, USART0_RXDATAL         /* 2 cy: read received byte            */
    ret


/* ═══════════════════════════════════════════════════════════════════════════
 * hex_nibble — convert ASCII hex character in R16 to 0..15
 *
 * Input:  R16 = ASCII '0'..'9' or 'A'..'F' (uppercase only)
 * Output: R16 = 0..15
 * Clobbers: R16
 * ═══════════════════════════════════════════════════════════════════════════ */
hex_nibble:
    cpi   r16, 'A'
    brsh  .Lhex_alpha
    subi  r16, '0'                    /* '0'..'9' → 0..9                     */
    ret
.Lhex_alpha:
    subi  r16, 'A' - 10               /* 'A'..'F' → 10..15                   */
    ret


/* ═══════════════════════════════════════════════════════════════════════════
 * recv_hex_byte — receive two ASCII hex chars, combine to one byte → R16
 *
 * Calls uart_rx twice, converts each char via hex_nibble, combines:
 *   r16 = (high_nibble << 4) | low_nibble
 *
 * Example: receives '4', 'B' → r16 = 0x4B
 *
 * Uses R15 to save the high nibble (R15 is not a standard call-clobbered
 * register in GCC ABI — safe to use here in a non-C mixed environment).
 * Clobbers: R15, R20 (via usart_rx)
 * ═══════════════════════════════════════════════════════════════════════════ */
recv_hex_byte:
    push  r15
    rcall usart_rx                    /* receive high nibble ASCII char       */
    rcall hex_nibble                  /* convert → 0..15 in r16              */
    swap  r16                         /* move nibble to high position: 0xN0  */
    mov   r15, r16                    /* save: r15 = 0xN0                    */
    rcall usart_rx                    /* receive low nibble ASCII char        */
    rcall hex_nibble                  /* convert → 0..15 in r16              */
    or    r16, r15                    /* combine: r16 = (hi<<4) | lo = 0xNN  */
    pop   r15
    ret


/* ═══════════════════════════════════════════════════════════════════════════
 * nvm_wait — spin until NVMCTRL_STATUS.FBUSY = 0
 * Clobbers: R16
 * ═══════════════════════════════════════════════════════════════════════════ */
nvm_wait:
    lds   r16, NVMCTRL_STATUS
    sbrc  r16, NVMCTRL_FBUSY_bp       /* skip next if FBUSY = 0              */
    rjmp  nvm_wait
    ret


/* ═══════════════════════════════════════════════════════════════════════════
 * nvm_write_page — write the 64-byte SRAM page buffer to flash
 *
 * Entry:  Z = flash byte address of target page (64-byte aligned)
 *         X = SRAM address of 64-byte source (page_buf or equivalent)
 * Exit:   Z += 64 (advanced to next page)
 *         X += 64 (advanced past source data)
 * Clobbers: R16, R17, R18
 * ═══════════════════════════════════════════════════════════════════════════ */
nvm_write_page:
    /* Step 1: wait for NVM ready */
    rcall nvm_wait

    /* Step 2: clear stale errors */
    ldi   r16, NVMCTRL_CMD_NOCMD_gc
    sts   NVMCTRL_CTRLA, r16

    /* Step 3: fill page buffer from SRAM (64 plain ST writes) */
    ldi   r17, PAGE_SIZE
.Lnvm_fill:
    ld    r18, X+                     /* load byte from SRAM buffer           */
    st    Z+,  r18                    /* write to flash page buffer           */
    dec   r17
    brne  .Lnvm_fill

    /* Step 4: rewind Z to page base */
    sbiw  ZL, PAGE_SIZE               /* Z -= 64                              */

    /* Step 5: CCP-protected PAGEERASEWRITE */
    cli
    ldi   r16, CCP_SPM_gc
    sts   CPU_CCP, r16                /* open 4-cycle CCP window              */
    ldi   r16, NVMCTRL_CMD_PAGEERASEWRITE_gc
    sts   NVMCTRL_CTRLA, r16         /* issue command (within window)        */
    sei

    /* Step 6: wait for completion */
    rcall nvm_wait

    /* Advance Z to next page */
    adiw  ZL, PAGE_SIZE               /* Z += 64                              */
    ret


/* ═══════════════════════════════════════════════════════════════════════════
 * selfupdate_main — entry point
 * ═══════════════════════════════════════════════════════════════════════════ */
.global selfupdate_main
selfupdate_main:

    /* ── Initialise stack pointer ─────────────────────────────────────── */
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    /* ── Configure LED0 (PA3) as output, turn on (active-low = 0) ─────── */
    sbi   VPORTA_DIR, LED0_PIN        /* PA3 = output                        */
    cbi   VPORTA_OUT, LED0_PIN        /* PA3 = 0 → LED0 on (update active)   */

    /* ── Initialise USART0 ────────────────────────────────────────────── */
    rcall usart_init

    /* ── Send banner "SU\r\n" so host knows device is ready ──────────── */
    ldi   r16, 'S'
    rcall usart_tx
    ldi   r16, 'U'
    rcall usart_tx
    ldi   r16, '\r'
    rcall usart_tx
    ldi   r16, '\n'
    rcall usart_tx

    /* ── Z = 0: flash write pointer starts at address 0x0000 ──────────── */
    clr   ZL
    clr   ZH

/* ═══════════════════════════════════════════════════════════════════════════
 * Main record loop
 *
 * Receives Intel HEX records one at a time.
 * Each data record (type 0x00): accumulate data into page_buf, write page
 * when full.
 * EOF record (type 0x01): flush any partial page, jump to application.
 * ═══════════════════════════════════════════════════════════════════════════ */
.Lrecord_loop:

    /* ── Wait for start-of-record ':' — discard anything else ─────────── */
.Lwait_start:
    rcall usart_rx
    cpi   r16, ':'
    brne  .Lwait_start

    /* ── Reset checksum accumulator ────────────────────────────────────── */
    clr   r17                         /* checksum accumulator = 0             */

    /* ── Receive record header (4 hex bytes = byte_count, addrH, addrL, type) */

    /* byte count */
    rcall recv_hex_byte
    mov   r18, r16                    /* r18 = byte count (LL)               */
    add   r17, r16                    /* checksum += byte_count              */

    /* address high byte */
    rcall recv_hex_byte
    mov   r25, r16                    /* r25 = addr_hi                       */
    add   r17, r16                    /* checksum += addr_hi                 */

    /* address low byte */
    rcall recv_hex_byte
    mov   r24, r16                    /* r24 = addr_lo                       */
    add   r17, r16                    /* checksum += addr_lo                 */

    /* record type */
    rcall recv_hex_byte
    mov   r19, r16                    /* r19 = type                          */
    add   r17, r16                    /* checksum += type                    */

    /* ── Dispatch on record type ───────────────────────────────────────── */
    cpi   r19, 0x01
    breq  .Leof                       /* type 01 = EOF: finish up            */
    /* else fall through to type 00 (data) handler                           */

    /* ── Data record: set flash write address from header ──────────────── */
    /*
     * The record header contains the target byte address in flash.
     * Z = R25:R24 = addr_hi:addr_lo from the record.
     * We also initialise X to point at the start of the SRAM page buffer.
     *
     * Assumption: the host sends records in order, with addresses that
     * advance exactly PAGE_SIZE bytes per page. The address in each record
     * is authoritative — we set Z from it rather than relying on it to
     * equal our running pointer.
     */
    mov   ZL, r24
    mov   ZH, r25

    /* Point X to the SRAM page buffer */
    ldi   XL, lo8(page_buf)
    ldi   XH, hi8(page_buf)

    /* ── Receive data bytes and accumulate in page buffer ──────────────── */
    tst   r18
    breq  .Ldata_done                 /* empty record: skip data loop        */

.Ldata_loop:
    rcall recv_hex_byte               /* r16 = next data byte                */
    st    X+, r16                     /* store in SRAM page buffer           */
    add   r17, r16                    /* checksum += data byte               */
    dec   r18                         /* byte count--                        */

    /*
     * Check if page buffer is full (X has advanced to a 64-byte boundary).
     * X started at page_buf (aligned to 64 bytes). After 64 stores,
     * XL[5:0] = 0 again.
     */
    mov   r20, XL
    andi  r20, (PAGE_SIZE - 1)        /* r20 = XL mod 64                     */
    brne  .Lcheck_done                /* not at boundary: continue           */

    /*
     * Page buffer full: write it to flash.
     * Save X (nvm_write_page modifies both Z and X).
     * Z is already at the page base (set from record address header).
     */
    movw  r20, XL                     /* r21:r20 = save X                    */
    ldi   XL, lo8(page_buf)           /* reset X to start of page buffer     */
    ldi   XH, hi8(page_buf)
    rcall nvm_write_page              /* write page, Z advances by 64        */
    movw  XL, r20                     /* restore X (now past end of buffer)  */
    /* Reset X to page_buf for next record's accumulation */
    ldi   XL, lo8(page_buf)
    ldi   XH, hi8(page_buf)

.Lcheck_done:
    tst   r18
    brne  .Ldata_loop                 /* more bytes in this record            */

.Ldata_done:

    /* ── Verify checksum ────────────────────────────────────────────────── */
    /*
     * Receive the checksum byte and add to accumulator.
     * If the record is valid, the sum of all bytes (including checksum) = 0
     * (mod 256). The checksum byte is the two's complement of the sum of
     * the other bytes.
     */
    rcall recv_hex_byte               /* r16 = checksum byte from record     */
    add   r17, r16                    /* r17 should now be 0x00 if valid     */
    tst   r17
    brne  .Lcksum_err

    /* Checksum OK: acknowledge with '.' */
    ldi   r16, '.'
    rcall usart_tx
    rjmp  .Lrecord_loop

.Lcksum_err:
    /* Checksum failed: send '!' and loop — host will resend */
    ldi   r16, '!'
    rcall usart_tx
    rjmp  .Lrecord_loop


/* ═══════════════════════════════════════════════════════════════════════════
 * EOF record handler
 *
 * A type-0x01 record signals end of file. Format: :00 0000 01 FF
 * (0 data bytes, address 0x0000, type 0x01, checksum 0xFF)
 *
 * We consume the checksum byte, wait for any in-progress NVM write,
 * turn off LED0, send "OK\r\n", and jump to the application.
 * ═══════════════════════════════════════════════════════════════════════════ */
.Leof:
    /* Consume checksum byte of EOF record (not verified in this implementation) */
    rcall recv_hex_byte

    /* Flush any partial page that didn't fill the 64-byte buffer.
     * Check if X has advanced past page_buf (i.e. we received some bytes
     * for the current page but didn't cross the 64-byte boundary).
     * If XL != lo8(page_buf), there are bytes pending in the buffer.
     */
    ldi   r20, lo8(page_buf)
    cp    XL, r20
    breq  .Lno_flush                  /* X = page_buf base: nothing pending  */
    ldi   XL, lo8(page_buf)
    ldi   XH, hi8(page_buf)
    rcall nvm_write_page              /* write final partial page            */
.Lno_flush:

    /* Wait for NVM to be fully idle */
    rcall nvm_wait

    /* Turn off LED0 (PA3 = 1, active-low) */
    sbi   VPORTA_OUT, LED0_PIN        /* LED0 off — update complete          */

    /* Send "OK\r\n" */
    ldi   r16, 'O'
    rcall usart_tx
    ldi   r16, 'K'
    rcall usart_tx
    ldi   r16, '\r'
    rcall usart_tx
    ldi   r16, '\n'
    rcall usart_tx

    /*
     * Jump to the new application at address 0x0000.
     * If BOOTEND is set (e.g. BOOTEND=0x04), change this to 0x0400.
     * The application's reset vector lives at this address.
     */
    clr   ZL
    clr   ZH
    ijmp                              /* PC ← Z = 0x0000                     */
