/*
 * bootloader.S — minimal UART bootloader for ATmega328P
 *                Companion source for Chapter 16: Self-Programming Flash: NVMCTRL
 *
 * Covers (ATmega328P SPM-based approach, for conceptual comparison with ATtiny3217):
 *   Boot section: linked at 0x7C00 with --section-start=.text=0x7C00
 *   BOOTRST fuse: redirects reset vector to boot section
 *   SPM instruction: store to page buffer, page-erase, page-write sequence
 *   Intel HEX protocol: parse :LL AAAA TT [DD...] CC records over UART
 *   Checksum verification: 0x00 - sum of all record bytes (two's complement)
 *   Jump-to-application: IJMP via Z after receiving EOF record (type 0x01)
 *   Self-programming pattern contrasted with ATtiny3217 NVMCTRL in nvmctrl_write.S
 *
 * Target: ATmega328P (16 MHz, BOOTSZ=10 → 1KB boot section at 0x7C00)
 *
 * NOTE: This bootloader targets ATmega328P rather than ATtiny3217 because
 * the tinyAVR 1-series ATtiny3217 uses UPDI for programming and does not
 * expose SPM in the same way. ATmega328P (Arduino Uno) is the canonical
 * bootloader platform and matches the hardware most readers have on hand.
 *
 * Protocol (simplified Intel HEX subset, one record at a time):
 *   Host sends:  :LLAAAATT[DD...]CC\r\n
 *   Bootloader:  replies '.' on success, '!' on checksum error
 *   Record type 00 = data, 01 = EOF
 *
 * Build:
 *   avr-gcc -mmcu=atmega328p -nostartfiles -nodefaultlibs \
 *           -Wl,--section-start=.text=0x7C00 \
 *           -o bootloader.elf bootloader.S
 *   avr-objcopy -O ihex bootloader.elf bootloader.hex
 *
 * Fuses: BOOTSZ=10 (1KB boot), BOOTRST=0 (reset vector → boot section)
 *
 * Registers (global, live throughout main loop):
 *   Z (R31:R30)  = flash page write pointer
 *   R16          = scratch / UART RX byte
 *   R17          = checksum accumulator
 *   R18          = byte count from record header
 *   R25:R24      = address from record header
 *   R19          = record type
 */

#include <avr/io.h>

/* ATmega328P UART at 9600 baud, 16 MHz crystal
 * UBRR = F_CPU / (16 * BAUD) - 1 = 16000000 / 153600 - 1 = 103 */
.equ F_CPU,  16000000
.equ BAUD,   9600
.equ UBRR_V, (F_CPU / (16 * BAUD) - 1)    /* = 103 */

/* SPM opcodes embedded in SPMCSR */
.equ SPM_PGERS,  (1<<PGERS)|(1<<SELFPRGEN)   /* page erase                */
.equ SPM_PGWRT,  (1<<PGWRT)|(1<<SELFPRGEN)   /* page write                */
.equ SPM_RWWSRE, (1<<RWWSRE)|(1<<SELFPRGEN)  /* re-enable RWW section     */
.equ SPM_BLBSET, (1<<BLBSET)|(1<<SELFPRGEN)  /* boot lock bits (unused)   */
.equ SPM_ENABLE, (1<<SELFPRGEN)              /* fill temp buffer           */

/* page size in bytes (ATmega328P: 64 words = 128 bytes) */
.equ PAGE_SIZE, 128

/* ─── vectors ─────────────────────────────────────────────────────────── */
.section .text
.global __vectors
__vectors:
    rjmp  boot_main          /* reset → bootloader entry                    */

/* ─── UART init ────────────────────────────────────────────────────────── */
uart_init:
    ldi   r16, hi8(UBRR_V)
    sts   UBRR0H, r16
    ldi   r16, lo8(UBRR_V)
    sts   UBRR0L, r16
    ldi   r16, (1<<TXEN0)|(1<<RXEN0)
    sts   UCSR0B, r16            /* enable TX and RX                        */
    ldi   r16, (1<<UCSZ01)|(1<<UCSZ00)
    sts   UCSR0C, r16            /* 8N1 frame format                        */
    ret

/* ─── UART transmit one byte in R16 ───────────────────────────────────── */
uart_tx:
    lds   r17, UCSR0A
    sbrs  r17, UDRE0             /* wait until data register empty          */
    rjmp  uart_tx
    sts   UDR0, r16
    ret

/* ─── UART receive one byte → R16 ─────────────────────────────────────── */
uart_rx:
    lds   r17, UCSR0A
    sbrs  r17, RXC0              /* wait until byte received                */
    rjmp  uart_rx
    lds   r16, UDR0
    ret

/* ─── hex_digit_to_nibble: R16 (ASCII hex char) → R16 (0..15) ─────────── */
hex_nibble:
    cpi   r16, 'A'
    brsh  .Lhex_alpha
    subi  r16, '0'               /* '0'..'9' → 0..9                        */
    ret
.Lhex_alpha:
    subi  r16, 'A' - 10          /* 'A'..'F' → 10..15                      */
    ret

/* ─── recv_hex_byte: receive two ASCII hex chars, combine → R16 ────────── */
recv_hex_byte:
    push  r15
    rcall uart_rx                /* receive high nibble char                */
    rcall hex_nibble             /* convert to 0..15                        */
    swap  r16                    /* shift to high nibble position            */
    mov   r15, r16               /* save high nibble                        */
    rcall uart_rx                /* receive low nibble char                 */
    rcall hex_nibble             /* convert to 0..15                        */
    or    r16, r15               /* combine: r16 = (hi << 4) | lo          */
    pop   r15
    ret

/* ─── SPM helpers ──────────────────────────────────────────────────────── */

/* spm_wait: spin until SPM not busy */
spm_wait:
    lds   r16, SPMCSR
    sbrc  r16, SELFPRGEN         /* SELFPRGEN clear = SPM done              */
    rjmp  spm_wait
    ret

/* spm_page_erase: erase page whose byte address is in Z */
spm_page_erase:
    rcall spm_wait
    ldi   r16, SPM_PGERS
    sts   SPMCSR, r16
    spm                          /* execute: erase page                     */
    rcall spm_wait
    ret

/* spm_page_write: write temp buffer to page whose byte address is in Z */
spm_page_write:
    rcall spm_wait
    ldi   r16, SPM_PGWRT
    sts   SPMCSR, r16
    spm                          /* execute: write page                     */
    rcall spm_wait
    ldi   r16, SPM_RWWSRE
    sts   SPMCSR, r16
    spm                          /* re-enable RWW so app can execute        */
    ret

/* spm_fill_word: load R1:R0 into SPM temp buffer at Z, Z += 2 */
spm_fill_word:
    ldi   r16, SPM_ENABLE
    sts   SPMCSR, r16
    spm                          /* load R1:R0 into temp buffer word at Z   */
    adiw  ZL, 2                  /* advance Z by one word                   */
    ret

/* ─── main bootloader loop ─────────────────────────────────────────────── */
boot_main:
    /* initialise stack */
    ldi   r16, hi8(RAMEND)
    out   _SFR_IO_ADDR(SPH), r16
    ldi   r16, lo8(RAMEND)
    out   _SFR_IO_ADDR(SPL), r16

    rcall uart_init

    /* send banner so host knows bootloader is ready */
    ldi   r16, 'B'
    rcall uart_tx
    ldi   r16, 'L'
    rcall uart_tx
    ldi   r16, '\r'
    rcall uart_tx
    ldi   r16, '\n'
    rcall uart_tx

    /* Z will track current write address in flash */
    clr   ZL
    clr   ZH

.Lrecord_loop:
    /* wait for ':' start-of-record marker */
    rcall uart_rx
    cpi   r16, ':'
    brne  .Lrecord_loop

    clr   r17                   /* checksum accumulator = 0                 */

    /* byte count */
    rcall recv_hex_byte
    mov   r18, r16              /* r18 = byte count                         */
    add   r17, r16              /* checksum += byte count                   */

    /* address high byte */
    rcall recv_hex_byte
    mov   r25, r16              /* r25 = addr_hi                            */
    add   r17, r16

    /* address low byte */
    rcall recv_hex_byte
    mov   r24, r16              /* r24 = addr_lo                            */
    add   r17, r16

    /* record type */
    rcall recv_hex_byte
    mov   r19, r16              /* r19 = type (00=data, 01=EOF)             */
    add   r17, r16

    /* type 01 = EOF: send '.' and jump to application */
    cpi   r19, 0x01
    breq  .Leof

    /* type 00 = data: set Z to record address for SPM */
    mov   ZL, r24
    mov   ZH, r25

    /* erase page if at a page boundary */
    mov   r20, ZL
    andi  r20, (PAGE_SIZE - 1)
    brne  .Lno_erase
    rcall spm_page_erase

.Lno_erase:
    /* receive data bytes, fill SPM temp buffer two bytes at a time */
    tst   r18
    breq  .Ldata_done

.Ldata_loop:
    rcall recv_hex_byte         /* receive low byte of word                 */
    mov   r0, r16
    add   r17, r16              /* checksum                                 */
    dec   r18

    tst   r18
    breq  .Lodd_byte            /* odd number of bytes: pad high with 0xFF  */

    rcall recv_hex_byte         /* receive high byte of word                */
    mov   r1, r16
    add   r17, r16
    dec   r18
    rjmp  .Lfill

.Lodd_byte:
    ldi   r16, 0xFF
    mov   r1, r16

.Lfill:
    rcall spm_fill_word         /* load R1:R0 into temp buffer, Z += 2      */

    /* if Z crossed a page boundary, write the page */
    mov   r20, ZL
    andi  r20, (PAGE_SIZE - 1)
    brne  .Ldata_loop
    /* Z is at next page boundary: write the just-completed page */
    movw  r22, ZL               /* save Z (spm_page_write uses it)          */
    subi  ZL, PAGE_SIZE         /* point Z back to the page we just filled  */
    sbci  ZH, 0
    rcall spm_page_write
    movw  ZL, r22               /* restore Z                                */
    tst   r18
    brne  .Ldata_loop

.Ldata_done:
    /* if Z is not at a page boundary, flush the partial page */
    mov   r20, ZL
    andi  r20, (PAGE_SIZE - 1)
    breq  .Lcksum
    movw  r22, ZL
    subi  ZL, lo8(r20)          /* round Z down to page start               */
    sbci  ZH, 0
    rcall spm_page_write
    movw  ZL, r22

.Lcksum:
    /* verify checksum: receive checksum byte, add to accumulator → must be 0 */
    rcall recv_hex_byte
    add   r17, r16
    tst   r17
    brne  .Lcksum_err

    ldi   r16, '.'
    rcall uart_tx
    rjmp  .Lrecord_loop

.Lcksum_err:
    ldi   r16, '!'
    rcall uart_tx
    rjmp  .Lrecord_loop

.Leof:
    /* consume checksum byte (not verified for EOF record) */
    rcall recv_hex_byte

    ldi   r16, 'O'
    rcall uart_tx
    ldi   r16, 'K'
    rcall uart_tx
    ldi   r16, '\r'
    rcall uart_tx
    ldi   r16, '\n'
    rcall uart_tx

    /* jump to application at address 0x0000 */
    clr   ZL
    clr   ZH
    ijmp                        /* indirect jump through Z                  */
