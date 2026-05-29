/*
 * at24cm02_eeprom.S — Byte read/write on the Explorer's AT24CM02 I2C EEPROM.
 *
 * Curiosity Nano Explorer (EV58G97A). AT24CM02 is a 2 Mbit (256 KB) EEPROM.
 *   I2C address : 0x54..0x57 (7-bit). The two LSBs of the device byte carry
 *                 the top two bits (A17:A16) of the 18-bit memory address.
 *   Bus         : COM-section I2C -> TWI0 (SDA = PB1, SCL = PB0)
 *   WP pin      : pin header J209 (hold low to allow writes)
 *
 * An 18-bit address splits as:
 *   device byte = 0x54 | (A17:A16)
 *   word addr   = A15:A8 (high), A7:A0 (low)
 *
 * Write cycle is up to 5 ms; poll with ACK-polling before the next access.
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o at24cm02_eeprom.o at24cm02_eeprom.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o at24cm02_eeprom.elf at24cm02_eeprom.o
 */

#include <avr/io.h>

.equ AT24_BASE,     0x54
.equ TWI_BAUD_100K, 12

.equ TWI_BUSSTATE_IDLE_gc,  0x01
.equ TWI_MCMD_STOP_gc,      0x03

.section .text
.global main

main:
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    rcall twi_init

    /* Write 0xA5 to address 0x00100 */
    ldi   r20, 0x00            /* A17:A16                                    */
    ldi   r21, 0x01            /* A15:A8                                     */
    ldi   r22, 0x00            /* A7:A0                                      */
    ldi   r19, 0xA5            /* data                                       */
    rcall eeprom_write_byte
    rcall eeprom_wait_ready

    /* Read it back into r24 */
    ldi   r20, 0x00
    ldi   r21, 0x01
    ldi   r22, 0x00
    rcall eeprom_read_byte     /* r24 = data                                 */

.Lhalt:
    rjmp  .Lhalt

/* ------------------------------------------------------------------------- */
twi_init:
    ldi   r16, TWI_BAUD_100K
    sts   TWI0_MBAUD, r16
    ldi   r16, TWI_ENABLE_bm
    sts   TWI0_MCTRLA, r16
    ldi   r16, TWI_BUSSTATE_IDLE_gc
    sts   TWI0_MSTATUS, r16
    ret

/* dev_byte_w — build device write byte in r25 from A17:A16 (r20)            */
dev_byte_w:
    mov   r25, r20
    andi  r25, 0x03
    ori   r25, AT24_BASE
    lsl   r25                  /* <<1, R/W = 0                               */
    ret

/* ------------------------------------------------------------------------- */
/* eeprom_write_byte — r20=A17:16, r21=A15:8, r22=A7:0, r19=data             */
eeprom_write_byte:
    rcall dev_byte_w
    sts   TWI0_MADDR, r25
    rcall wait_wif
    sts   TWI0_MDATA, r21       /* addr high                                 */
    rcall wait_wif
    sts   TWI0_MDATA, r22       /* addr low                                  */
    rcall wait_wif
    sts   TWI0_MDATA, r19       /* data                                      */
    rcall wait_wif
    ldi   r16, TWI_MCMD_STOP_gc
    sts   TWI0_MCTRLB, r16
    ret

/* eeprom_read_byte — r20=A17:16, r21=A15:8, r22=A7:0; returns r24=data      */
eeprom_read_byte:
    rcall dev_byte_w
    sts   TWI0_MADDR, r25       /* dummy write to set address pointer        */
    rcall wait_wif
    sts   TWI0_MDATA, r21
    rcall wait_wif
    sts   TWI0_MDATA, r22
    rcall wait_wif

    rcall dev_byte_w
    ori   r25, 0x01            /* device read byte                          */
    sts   TWI0_MADDR, r25       /* repeated START + read                     */
    rcall wait_rif
    lds   r24, TWI0_MDATA
    ldi   r16, TWI_ACKACT_bm | TWI_MCMD_STOP_gc    /* NACK + STOP            */
    sts   TWI0_MCTRLB, r16
    ret

/* eeprom_wait_ready — ACK-poll until the write cycle completes              */
eeprom_wait_ready:
    rcall dev_byte_w
.Lwr_poll:
    sts   TWI0_MADDR, r25       /* address-only write                        */
    rcall wait_wif
    lds   r17, TWI0_MSTATUS
    ldi   r16, TWI_MCMD_STOP_gc
    sts   TWI0_MCTRLB, r16
    sbrc  r17, TWI_RXACK_bp     /* RXACK = 1 -> still busy (NACK)            */
    rjmp  .Lwr_poll
    ret

/* ------------------------------------------------------------------------- */
wait_wif:
    lds   r17, TWI0_MSTATUS
    sbrs  r17, TWI_WIF_bp
    rjmp  wait_wif
    ret
wait_rif:
    lds   r17, TWI0_MSTATUS
    sbrs  r17, TWI_RIF_bp
    rjmp  wait_rif
    ret
