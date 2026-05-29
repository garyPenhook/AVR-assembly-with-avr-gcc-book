/*
 * vcnl4200_prox_als.S — Read the Explorer's VCNL4200 proximity / light sensor.
 *
 * Curiosity Nano Explorer (EV58G97A). VCNL4200 is on the shared I2C bus.
 *   I2C address : 0x51 (7-bit)
 *   Bus         : COM-section I2C -> TWI0 (SDA = PB1, SCL = PB0)
 *   INT pin     : Explorer IO-16 (optional; not used here)
 *
 * VCNL4200 registers are 16-bit and accessed by a "command code" (the register
 * pointer). Data is little-endian on the wire: low byte first, then high byte.
 *
 *   0x00  ALS_CONF   (write 0x0000 = ALS enabled, default integration)
 *   0x03  PS_CONF1/2 (write 0x0001 low = PS enabled)
 *   0x08  PS_DATA    (read 16-bit proximity)
 *   0x09  ALS_DATA   (read 16-bit ambient light)
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o vcnl4200_prox_als.o vcnl4200_prox_als.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o vcnl4200_prox_als.elf vcnl4200_prox_als.o
 */

#include <avr/io.h>

.equ VCNL_ADDR,     0x51
.equ ALS_CONF,      0x00
.equ PS_CONF12,     0x03
.equ PS_DATA,       0x08
.equ ALS_DATA,      0x09
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
    rcall vcnl_init
    rcall vcnl_read_als         /* r25:r24 = 16-bit ALS value                 */
    rcall vcnl_read_ps          /* r25:r24 = 16-bit PS value                  */

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
/* vcnl_init — enable ALS and PS */
vcnl_init:
    ldi   r24, ALS_CONF
    ldi   r22, 0x00             /* low byte:  ALS_SD = 0 (enabled)            */
    ldi   r23, 0x00             /* high byte                                  */
    rcall vcnl_write16
    ldi   r24, PS_CONF12
    ldi   r22, 0x01             /* low byte:  PS_SD = 0, PS_ON                */
    ldi   r23, 0x08             /* high byte: 16-bit PS output                */
    rcall vcnl_write16
    ret

/* vcnl_write16 — write a 16-bit register
 *   r24 = command code, r22 = data low, r23 = data high                     */
vcnl_write16:
    mov   r18, r24              /* keep command code                         */
    ldi   r24, VCNL_ADDR
    lsl   r24
    sts   TWI0_MADDR, r24
    rcall wait_wif
    sts   TWI0_MDATA, r18       /* command code                              */
    rcall wait_wif
    sts   TWI0_MDATA, r22       /* data low                                  */
    rcall wait_wif
    sts   TWI0_MDATA, r23       /* data high                                 */
    rcall wait_wif
    ldi   r16, TWI_MCMD_STOP_gc
    sts   TWI0_MCTRLB, r16
    ret

vcnl_read_als:
    ldi   r18, ALS_DATA
    rjmp  vcnl_read16
vcnl_read_ps:
    ldi   r18, PS_DATA
    /* fall through */

/* vcnl_read16 — read 16-bit register r18; returns r25:r24 (high:low)        */
vcnl_read16:
    ldi   r24, VCNL_ADDR
    lsl   r24
    sts   TWI0_MADDR, r24
    rcall wait_wif
    sts   TWI0_MDATA, r18        /* command code                              */
    rcall wait_wif

    ldi   r24, VCNL_ADDR
    lsl   r24
    ori   r24, 0x01
    sts   TWI0_MADDR, r24        /* repeated START + read                     */

    rcall wait_rif
    lds   r24, TWI0_MDATA        /* data low (little-endian)                  */
    ldi   r16, TWI_MCMD_RECVTRANS_gc
    sts   TWI0_MCTRLB, r16
    rcall wait_rif
    lds   r25, TWI0_MDATA        /* data high                                 */
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
