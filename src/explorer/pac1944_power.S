/*
 * pac1944_power.S — Read a bus voltage from the Explorer's PAC1944 monitor.
 *
 * Curiosity Nano Explorer (EV58G97A). PAC1944 is a 4-channel power/energy
 * monitor on the I2C bus (it can be isolated on its own bus with switch S500).
 *   I2C address : 0x1F (7-bit)
 *   Bus         : COM-section I2C -> TWI0 (SDA = PB1, SCL = PB0)
 *
 * To take a measurement you first issue a REFRESH command (write register
 * pointer 0x00 then STOP). This latches the V_BUS / V_SENSE result registers.
 * After ~1 ms the latched values can be read. V_BUS is a 16-bit big-endian
 * unsigned value, full-scale = 9V (FSR), so volts = raw / 65536 * 9.
 *
 *   0x00 REFRESH    0x07 VBUS1   0x08 VBUS2   0x09 VBUS3   0x0A VBUS4
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o pac1944_power.o pac1944_power.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o pac1944_power.elf pac1944_power.o
 */

#include <avr/io.h>

.equ PAC_ADDR,      0x1F
.equ PAC_REFRESH,   0x00
.equ PAC_VBUS1,     0x07
.equ TWI_BAUD_100K, 12

.equ TWI_BUSSTATE_IDLE_gc,  0x01
.equ TWI_MCMD_RECVTRANS_gc, 0x02
.equ TWI_MCMD_STOP_gc,      0x03

.section .text
.global main

main:
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    rcall twi_init
    rcall pac_refresh
    rcall delay_1ms             /* let the result registers settle           */
    rcall pac_read_vbus1        /* r25:r24 = VBUS1 (big-endian 16-bit)        */

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

/* pac_refresh — write the REFRESH register pointer with no data, then STOP  */
pac_refresh:
    ldi   r24, PAC_ADDR
    lsl   r24
    sts   TWI0_MADDR, r24
    rcall wait_wif
    ldi   r16, PAC_REFRESH
    sts   TWI0_MDATA, r16
    rcall wait_wif
    ldi   r16, TWI_MCMD_STOP_gc
    sts   TWI0_MCTRLB, r16
    ret

/* pac_read_vbus1 — read 16-bit VBUS1 (MSB first); returns r25:r24           */
pac_read_vbus1:
    ldi   r24, PAC_ADDR
    lsl   r24
    sts   TWI0_MADDR, r24
    rcall wait_wif
    ldi   r16, PAC_VBUS1
    sts   TWI0_MDATA, r16
    rcall wait_wif

    ldi   r24, PAC_ADDR
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
/* delay_1ms — ~1 ms at 3.333 MHz */
delay_1ms:
    ldi   r26, lo8(1111)
    ldi   r27, hi8(1111)
.Ld:
    sbiw  r26, 1
    brne  .Ld
    ret

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
