/*
 * mcp23008_buttons.S — Read buttons / joystick via the Explorer's I/O Expander 2.
 *
 * Curiosity Nano Explorer (EV58G97A). I/O Expander 2 is an MCP23008 whose
 * eight GP pins read the joystick directions and the SW1/SW2/SW3 buttons
 * (each button is shared between a tactile and a capacitive-touch input).
 *   I2C address : 0x24 (7-bit)
 *   Bus         : COM-section I2C -> TWI0 (SDA = PB1, SCL = PB0)
 *   INT pin     : Explorer "IO EXP 2 INT" (optional; not used here)
 *
 * GP bit assignment (per Figure 5-4, J401 order):
 *   GP0 J-UP  GP1 J-LEFT  GP2 J-DOWN  GP3 J-RIGHT  GP4 J-PUSH
 *   GP5 SW3   GP6 SW2     GP7 SW1
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o mcp23008_buttons.o mcp23008_buttons.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o mcp23008_buttons.elf mcp23008_buttons.o
 */

#include <avr/io.h>

.equ EXP2_ADDR,     0x24
.equ MCP_IODIR,     0x00
.equ MCP_GPPU,      0x06
.equ MCP_GPIO,      0x09
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
    rcall buttons_init
    rcall buttons_read         /* r24 = raw GP state                         */

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

/* buttons_init — all GP pins inputs with pull-ups */
buttons_init:
    ldi   r18, MCP_IODIR
    ldi   r19, 0xFF            /* all inputs                                */
    rcall mcp_write_reg
    ldi   r18, MCP_GPPU
    ldi   r19, 0xFF            /* enable pull-ups                           */
    rjmp  mcp_write_reg

/* buttons_read — returns r24 = GPIO register (raw pin levels) */
buttons_read:
    ldi   r24, EXP2_ADDR
    lsl   r24
    sts   TWI0_MADDR, r24
    rcall wait_wif
    ldi   r16, MCP_GPIO
    sts   TWI0_MDATA, r16
    rcall wait_wif

    ldi   r24, EXP2_ADDR
    lsl   r24
    ori   r24, 0x01
    sts   TWI0_MADDR, r24
    rcall wait_rif
    lds   r24, TWI0_MDATA
    ldi   r16, TWI_ACKACT_bm | TWI_MCMD_STOP_gc
    sts   TWI0_MCTRLB, r16
    ret

/* mcp_write_reg — r18 = register, r19 = value */
mcp_write_reg:
    ldi   r24, EXP2_ADDR
    lsl   r24
    sts   TWI0_MADDR, r24
    rcall wait_wif
    sts   TWI0_MDATA, r18
    rcall wait_wif
    sts   TWI0_MDATA, r19
    rcall wait_wif
    ldi   r16, TWI_MCMD_STOP_gc
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
