/*
 * lm75_twi.S — Read temperature from an LM75 I2C sensor (ATtiny3217).
 *
 * The LM75 (NXP LM75A/B, TI LM75) is a cheap I2C temperature sensor with a
 * freely downloadable datasheet. Default 7-bit address 0x48 (A2:A0 = 000).
 *
 * Temperature register layout (pointer 0x00), read as two bytes MSB:LSB:
 *
 *     MSB = bits 10..3 of the signed reading (1 degC per LSB at this byte)
 *     LSB = bits 2..0 in the top 3 bits; lower 5 bits are zero
 *
 * The 11-bit two's-complement value is (MSB:LSB) >> 5, with a resolution of
 * 0.125 degC. This example returns the raw two bytes; converting to a scaled
 * integer is left as an exercise (see the book's fixed-point chapter).
 *
 * A complete read transaction:
 *   START + addr+W, write pointer 0x00          (select temp register)
 *   repeated START + addr+R
 *   read byte 1 (MSB), send ACK + continue
 *   read byte 2 (LSB), send NACK + STOP
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o lm75_twi.o lm75_twi.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o lm75_twi.elf lm75_twi.o
 *   avr-objcopy -O ihex lm75_twi.elf lm75_twi.hex
 */

#include <avr/io.h>

.equ LM75_ADDR,     0x48
.equ TWI_BAUD_100K, 12          /* ~98 kHz SCL at 3.333 MHz                    */

/* _gc group codes are C enums, invisible to the assembler — define them here */
.equ TWI_BUSSTATE_IDLE_gc,   0x01
.equ TWI_MCMD_RECVTRANS_gc,  0x02   /* ACK action, then receive next byte      */
.equ TWI_MCMD_STOP_gc,       0x03   /* ACK action, then STOP                   */
/* TWI_ACKACT_bm (0x04: 0 = ACK, 1 = NACK) comes from <avr/io.h>              */

.section .text
.global main

main:
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    rcall twi_init
    rcall lm75_read_temp        /* r25 = MSB, r24 = LSB                        */

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
 * lm75_read_temp — read the 2-byte temperature register
 * Returns: r25 = MSB, r24 = LSB
 * Clobbers: r16, r17, r24
 */
lm75_read_temp:
    /* --- phase 1: write the register pointer (0x00) --- */
    ldi   r24, LM75_ADDR
    lsl   r24                    /* addr<<1, R/W = 0 (write)                  */
    sts   TWI0_MADDR, r24        /* START + address                           */
    rcall wait_wif

    ldi   r16, 0x00              /* temperature register pointer              */
    sts   TWI0_MDATA, r16
    rcall wait_wif

    /* --- phase 2: repeated START for reading --- */
    ldi   r24, LM75_ADDR
    lsl   r24
    ori   r24, 0x01              /* R/W = 1 (read)                            */
    sts   TWI0_MADDR, r24        /* repeated START + address                  */
    rcall wait_rif               /* first data byte arrives                   */

    lds   r25, TWI0_MDATA        /* MSB                                        */
    ldi   r16, TWI_MCMD_RECVTRANS_gc    /* ACK + fetch next byte             */
    sts   TWI0_MCTRLB, r16
    rcall wait_rif

    lds   r24, TWI0_MDATA        /* LSB                                        */
    ldi   r16, TWI_ACKACT_bm | TWI_MCMD_STOP_gc  /* NACK + STOP              */
    sts   TWI0_MCTRLB, r16
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
