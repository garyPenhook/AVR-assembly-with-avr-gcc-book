/*
 * mcp9808_temp.S — Read temperature from the Explorer's MCP9808 sensor.
 *
 * Curiosity Nano Explorer (EV58G97A). MCP9808 is on the shared I2C bus.
 *   I2C address : 0x1C (7-bit)
 *   Bus         : COM-section I2C -> TWI0 (SDA = PB1, SCL = PB0 on ATtiny3217)
 *   ALERT pin   : Explorer IO-24 (optional; not used here)
 *
 * Ambient-temperature register (pointer 0x05) is 16 bits:
 *   bit15..13 = flags, bit12 = sign, bits 11..0 = temperature in 1/16 degC.
 * This reads the two bytes and computes a signed integer degrees Celsius.
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o mcp9808_temp.o mcp9808_temp.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o mcp9808_temp.elf mcp9808_temp.o
 */

#include <avr/io.h>

.equ MCP9808_ADDR,  0x1C
.equ REG_TA,        0x05        /* ambient temperature register               */
.equ TWI_BAUD_100K, 12

.equ TWI_BUSSTATE_IDLE_gc,  0x01
.equ TWI_MCMD_RECVTRANS_gc, 0x02
.equ TWI_MCMD_STOP_gc,      0x03
/* TWI_ACKACT_bm (0x04) comes from <avr/io.h> */

.section .text
.global main

main:
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    rcall twi_init
    rcall mcp9808_read_temp     /* r25 = TA high byte, r24 = TA low byte      */

    /* Integer degrees C in r23 (sign-extended), ignoring fractional bits */
    mov   r23, r25
    andi  r23, 0x0F             /* keep bits 11..8                            */
    swap  r23                   /* (bits 11..8) << 4                          */
    swap  r24
    andi  r24, 0x0F
    or    r23, r24              /* r23 = whole degrees (bits 11..4)           */
    sbrc  r25, 4                /* sign bit (bit12 of TA = bit4 of high byte) */
    neg   r23                   /* negative temperature                       */

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

/* ------------------------------------------------------------------------- */
/* mcp9808_read_temp — read 2-byte TA register; r25 = MSB, r24 = LSB         */
mcp9808_read_temp:
    /* set register pointer */
    ldi   r24, MCP9808_ADDR
    lsl   r24
    sts   TWI0_MADDR, r24
    rcall wait_wif
    ldi   r16, REG_TA
    sts   TWI0_MDATA, r16
    rcall wait_wif

    /* repeated START for read */
    ldi   r24, MCP9808_ADDR
    lsl   r24
    ori   r24, 0x01
    sts   TWI0_MADDR, r24

    rcall wait_rif
    lds   r25, TWI0_MDATA        /* MSB                                       */
    ldi   r16, TWI_MCMD_RECVTRANS_gc
    sts   TWI0_MCTRLB, r16
    rcall wait_rif
    lds   r24, TWI0_MDATA        /* LSB                                       */
    ldi   r16, TWI_ACKACT_bm | TWI_MCMD_STOP_gc
    sts   TWI0_MCTRLB, r16
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
