/*
 * mcp23008_led_row.S — Drive the Explorer's 8 yellow LEDs via I/O Expander 1.
 *
 * Curiosity Nano Explorer (EV58G97A). I/O Expander 1 is an MCP23008 whose
 * eight GP pins each drive one yellow LED of the "LED ROW".
 *   I2C address : 0x25 (7-bit)
 *   Bus         : COM-section I2C -> TWI0 (SDA = PB1, SCL = PB0)
 *   LEDs        : ACTIVE-LOW (drive a GP pin low to light its LED)
 *
 * MCP23008 registers (sequential mode, IOCON.BANK = 0):
 *   0x00 IODIR (1=input, 0=output)   0x06 GPPU (pull-ups)
 *   0x09 GPIO  (read pins / write OLAT)
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o mcp23008_led_row.o mcp23008_led_row.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o mcp23008_led_row.elf mcp23008_led_row.o
 */

#include <avr/io.h>

.equ EXP1_ADDR,     0x25
.equ MCP_IODIR,     0x00
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
    rcall ledrow_init

    /* Light LEDs 0,2,4,6 (mask: 1 = on) */
    ldi   r24, 0b01010101
    rcall ledrow_set

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

/* ledrow_init — all GP pins outputs, LEDs off */
ledrow_init:
    ldi   r18, MCP_IODIR
    ldi   r19, 0x00            /* all outputs                               */
    rcall mcp_write_reg
    ldi   r18, MCP_GPIO
    ldi   r19, 0xFF            /* all high = all LEDs off (active-low)       */
    rcall mcp_write_reg
    ret

/* ledrow_set — r24 = LED mask (bit n set -> LED n on); active-low to chip   */
ledrow_set:
    com   r24                  /* invert: on-bit -> drive low               */
    mov   r19, r24
    ldi   r18, MCP_GPIO
    rjmp  mcp_write_reg

/* mcp_write_reg — r18 = register, r19 = value */
mcp_write_reg:
    ldi   r24, EXP1_ADDR
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
