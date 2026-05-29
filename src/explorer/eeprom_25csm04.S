/*
 * eeprom_25csm04.S — Byte read/write on the Explorer's 25CSM04 SPI EEPROM.
 *
 * Curiosity Nano Explorer (EV58G97A). 25CSM04 is a 4 Mbit (512 KB) SPI EEPROM.
 *   SPI bus : COM-section SPI0 (MOSI = PA1, MISO = PA2, SCK = PA3)
 *   CS      : Explorer "SPI EEPROM CS" (this file uses PA4, the SPI0 SS pin)
 *   HOLD    : Explorer IO-13 (hold high to allow access; tie externally)
 *
 * 25CSM04 uses 24-bit (3-byte) addresses. Commands used here:
 *   WREN 0x06   WRITE 0x02   READ 0x03   RDSR 0x05 (status: WIP = bit0)
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o eeprom_25csm04.o eeprom_25csm04.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o eeprom_25csm04.elf eeprom_25csm04.o
 */

#include <avr/io.h>

.equ CS_PIN,    4               /* PA4 = SPI0 SS / SPI EEPROM CS              */
.equ CMD_WREN,  0x06
.equ CMD_WRITE, 0x02
.equ CMD_READ,  0x03
.equ CMD_RDSR,  0x05

.section .text
.global main

main:
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    rcall spi_init

    /* Write 0x5A to address 0x000100 */
    ldi   r20, 0x00            /* addr[23:16]                                */
    ldi   r21, 0x01            /* addr[15:8]                                 */
    ldi   r22, 0x00            /* addr[7:0]                                  */
    ldi   r19, 0x5A            /* data                                       */
    rcall ee_write_byte
    rcall ee_wait_wip

    /* Read it back into r24 */
    ldi   r20, 0x00
    ldi   r21, 0x01
    ldi   r22, 0x00
    rcall ee_read_byte         /* r24 = data                                 */

.Lhalt:
    rjmp  .Lhalt

/* ------------------------------------------------------------------------- */
spi_init:
    ldi   r16, (1 << 1) | (1 << 3) | (1 << CS_PIN)
    out   VPORTA_DIR, r16       /* MOSI, SCK, CS outputs                     */
    sbi   VPORTA_OUT, CS_PIN    /* CS high (idle)                           */
    ldi   r16, SPI_SSD_bm
    sts   SPI0_CTRLB, r16
    ldi   r16, SPI_MASTER_bm | SPI_ENABLE_bm
    sts   SPI0_CTRLA, r16
    ret

/* ee_write_byte — r20:r21:r22 = 24-bit addr, r19 = data */
ee_write_byte:
    /* WREN */
    cbi   VPORTA_OUT, CS_PIN
    ldi   r16, CMD_WREN
    rcall spi_xfer
    sbi   VPORTA_OUT, CS_PIN

    /* WRITE opcode + 3 address bytes + data */
    cbi   VPORTA_OUT, CS_PIN
    ldi   r16, CMD_WRITE
    rcall spi_xfer
    mov   r16, r20
    rcall spi_xfer
    mov   r16, r21
    rcall spi_xfer
    mov   r16, r22
    rcall spi_xfer
    mov   r16, r19
    rcall spi_xfer
    sbi   VPORTA_OUT, CS_PIN    /* CS high latches the write                 */
    ret

/* ee_read_byte — r20:r21:r22 = 24-bit addr; returns r24 = data */
ee_read_byte:
    cbi   VPORTA_OUT, CS_PIN
    ldi   r16, CMD_READ
    rcall spi_xfer
    mov   r16, r20
    rcall spi_xfer
    mov   r16, r21
    rcall spi_xfer
    mov   r16, r22
    rcall spi_xfer
    ldi   r16, 0xFF            /* dummy to clock data out                   */
    rcall spi_xfer
    mov   r24, r16
    sbi   VPORTA_OUT, CS_PIN
    ret

/* ee_wait_wip — poll RDSR until WIP (bit0) clears */
ee_wait_wip:
.Lwip:
    cbi   VPORTA_OUT, CS_PIN
    ldi   r16, CMD_RDSR
    rcall spi_xfer
    ldi   r16, 0xFF
    rcall spi_xfer            /* r16 = status                              */
    sbi   VPORTA_OUT, CS_PIN
    sbrc  r16, 0
    rjmp  .Lwip
    ret

/* spi_xfer — r16 out, returns r16 in */
spi_xfer:
    sts   SPI0_DATA, r16
.Lsx:
    lds   r17, SPI0_INTFLAGS
    sbrs  r17, SPI_IF_bp
    rjmp  .Lsx
    lds   r16, SPI0_DATA
    ret
