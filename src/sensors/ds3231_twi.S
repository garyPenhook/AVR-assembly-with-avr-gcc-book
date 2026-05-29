/*
 * ds3231_twi.S — Read the time/date from a DS3231 I2C real-time clock.
 *
 * The DS3231 (Maxim/Analog Devices) is a cheap, very accurate I2C RTC with a
 * freely downloadable datasheet. Fixed 7-bit address 0x68. All time/date
 * registers are stored as packed BCD (two decimal digits per byte).
 *
 * Timekeeping register map (auto-incrementing from pointer 0x00):
 *
 *     0x00  seconds   BCD 00-59
 *     0x01  minutes   BCD 00-59
 *     0x02  hours     BCD; bit6 = 12/24h mode, bit5 = AM/PM or 20s-of-hours
 *     0x03  day       1-7 (user-defined weekday)
 *     0x04  date      BCD 01-31
 *     0x05  month     BCD 01-12 (bit7 = century)
 *     0x06  year      BCD 00-99
 *
 * This example reads all seven bytes into SRAM with a single multi-byte read
 * (one repeated-START transaction, ACK each byte, NACK+STOP on the last) and
 * converts the seconds field from BCD to binary as a worked helper.
 *
 * A complete read transaction:
 *   START + addr+W, write pointer 0x00          (select seconds register)
 *   repeated START + addr+R
 *   read byte, ACK + continue   (x6)
 *   read byte, NACK + STOP       (last)
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o ds3231_twi.o ds3231_twi.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o ds3231_twi.elf ds3231_twi.o
 *   avr-objcopy -O ihex ds3231_twi.elf ds3231_twi.hex
 */

#include <avr/io.h>

.equ DS3231_ADDR,   0x68
.equ TIME_BYTES,    7           /* sec, min, hour, day, date, month, year     */
.equ TWI_BAUD_100K, 12          /* ~98 kHz SCL at 3.333 MHz                    */

/* _gc group codes are C enums, invisible to the assembler — define them here */
.equ TWI_BUSSTATE_IDLE_gc,   0x01
.equ TWI_MCMD_RECVTRANS_gc,  0x02   /* ACK action, then receive next byte      */
.equ TWI_MCMD_STOP_gc,       0x03   /* ACK action, then STOP                   */
/* TWI_ACKACT_bm (0x04: 0 = ACK, 1 = NACK) comes from <avr/io.h>              */

/* ------------------------------------------------------------------------- */
.section .bss
time_buf:   .skip TIME_BYTES        /* [0]=sec [1]=min [2]=hour ... [6]=year   */

/* ------------------------------------------------------------------------- */
.section .text
.global main

main:
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    rcall twi_init
    rcall ds3231_read_time      /* fills time_buf with 7 BCD bytes            */

    /* Convert the seconds field (time_buf[0]) to a binary count in r24 */
    lds   r24, time_buf
    rcall bcd_to_bin            /* r24 = 0..59                                */

.Lhalt:
    rjmp  .Lhalt

/* ------------------------------------------------------------------------- */
/* twi_init — TWI0 master, ~100 kHz                                          */
twi_init:
    ldi   r16, TWI_BAUD_100K
    sts   TWI0_MBAUD, r16
    ldi   r16, TWI_ENABLE_bm
    sts   TWI0_MCTRLA, r16
    ldi   r16, TWI_BUSSTATE_IDLE_gc     /* force idle AFTER enable           */
    sts   TWI0_MSTATUS, r16
    ret

/* ------------------------------------------------------------------------- */
/*
 * ds3231_read_time — read 7 timekeeping bytes into time_buf
 * Clobbers: r16, r17, r18, r24, Y (r29:r28)
 */
ds3231_read_time:
    /* --- phase 1: write the register pointer (0x00) --- */
    ldi   r24, DS3231_ADDR
    lsl   r24                    /* addr<<1, R/W = 0 (write)                  */
    sts   TWI0_MADDR, r24        /* START + address                           */
    rcall wait_wif

    ldi   r16, 0x00              /* seconds register pointer                  */
    sts   TWI0_MDATA, r16
    rcall wait_wif

    /* --- phase 2: repeated START, then read TIME_BYTES bytes --- */
    ldi   r24, DS3231_ADDR
    lsl   r24
    ori   r24, 0x01              /* R/W = 1 (read)                            */
    sts   TWI0_MADDR, r24        /* repeated START + address                  */

    ldi   YL, lo8(time_buf)
    ldi   YH, hi8(time_buf)
    ldi   r18, TIME_BYTES        /* byte counter                              */

.Lrd_loop:
    rcall wait_rif               /* next data byte ready in MDATA             */
    lds   r17, TWI0_MDATA
    st    Y+, r17                /* store into buffer                         */
    dec   r18
    breq  .Lrd_last              /* that was the final byte                   */
    ldi   r16, TWI_MCMD_RECVTRANS_gc    /* ACK + clock the next byte          */
    sts   TWI0_MCTRLB, r16
    rjmp  .Lrd_loop

.Lrd_last:
    ldi   r16, TWI_ACKACT_bm | TWI_MCMD_STOP_gc     /* NACK + STOP            */
    sts   TWI0_MCTRLB, r16
    ret

/* ------------------------------------------------------------------------- */
/*
 * bcd_to_bin — convert a packed-BCD byte to binary
 * In:  r24 = BCD (high nibble = tens, low nibble = units)
 * Out: r24 = binary value (0..99 for valid BCD)
 * Clobbers: r0, r1, r18, r25
 */
bcd_to_bin:
    mov   r25, r24
    swap  r25
    andi  r25, 0x0F             /* tens digit                                */
    andi  r24, 0x0F             /* units digit                               */
    ldi   r18, 10
    mul   r25, r18              /* r0 = tens * 10                            */
    add   r24, r0
    clr   r1                    /* restore the r1 == 0 convention after MUL  */
    ret

/* ------------------------------------------------------------------------- */
/* wait_wif — spin until master write-interrupt flag (WIF) sets               */
wait_wif:
    lds   r17, TWI0_MSTATUS
    sbrs  r17, TWI_WIF_bp        /* WIF = bit 6                               */
    rjmp  wait_wif
    ret

/* wait_rif — spin until master read-interrupt flag (RIF) sets                */
wait_rif:
    lds   r17, TWI0_MSTATUS
    sbrs  r17, TWI_RIF_bp        /* RIF = bit 7                               */
    rjmp  wait_rif
    ret
