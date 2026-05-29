/*
 * mcp4821_dac.S — Drive the Explorer's MCP4821 12-bit DAC over SPI.
 *
 * Curiosity Nano Explorer (EV58G97A). MCP4821 single-channel 12-bit DAC on
 * the SPI bus; its output feeds the speaker amplifier by default.
 *   SPI bus : COM-section SPI0 (MOSI = PA1, MISO = PA2, SCK = PA3)
 *   CS      : Explorer IO-26  (this file assumes a jumper to PC0)
 *   LDAC    : Explorer IO-36  (this file assumes a jumper to PC1)
 *
 * 16-bit write word (MSB first):
 *   bit15 A/B(=0)  bit14 BUF(=0)  bit13 GA(1=1x,2.048V)  bit12 SHDN(1=on)
 *   bits 11..0 = data.  High byte = 0x30 | data[11:8], low byte = data[7:0].
 * LDAC is pulsed low to transfer the latched value to the output.
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o mcp4821_dac.o mcp4821_dac.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o mcp4821_dac.elf mcp4821_dac.o
 */

#include <avr/io.h>

.equ CS_PIN,    0               /* PC0 <- Explorer IO-26 (DAC CS)             */
.equ LDAC_PIN,  1               /* PC1 <- Explorer IO-36 (DAC LDAC)          */

.section .text
.global main

main:
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    rcall spi_init
    rcall dac_init

    /* Output mid-scale (0x800 of 0x0FFF) */
    ldi   r25, 0x08
    ldi   r24, 0x00
    rcall dac_write

.Lhalt:
    rjmp  .Lhalt

/* ------------------------------------------------------------------------- */
spi_init:
    /* MOSI (PA1), SCK (PA3) outputs; MISO (PA2) input */
    ldi   r16, (1 << 1) | (1 << 3)
    out   VPORTA_DIR, r16
    /* CS and LDAC outputs, idle high */
    sbi   VPORTC_DIR, CS_PIN
    sbi   VPORTC_OUT, CS_PIN
    sbi   VPORTC_DIR, LDAC_PIN
    sbi   VPORTC_OUT, LDAC_PIN
    /* SSD = 1 (manual CS), SPI mode 0 */
    ldi   r16, SPI_SSD_bm
    sts   SPI0_CTRLB, r16
    /* master, enable */
    ldi   r16, SPI_MASTER_bm | SPI_ENABLE_bm
    sts   SPI0_CTRLA, r16
    ret

dac_init:
    ret                         /* nothing else needed; config is per-write   */

/* dac_write — r25:r24 = 12-bit value (only low 12 bits used) */
dac_write:
    mov   r18, r25
    andi  r18, 0x0F
    ori   r18, 0x30            /* GA=1 (1x, 2.048V ref), SHDN=1 (active)      */

    cbi   VPORTC_OUT, CS_PIN    /* select                                    */
    mov   r16, r18
    rcall spi_xfer             /* high byte                                  */
    mov   r16, r24
    rcall spi_xfer             /* low byte                                   */
    sbi   VPORTC_OUT, CS_PIN    /* deselect (latches input register)         */

    cbi   VPORTC_OUT, LDAC_PIN  /* transfer to output                        */
    nop
    nop
    sbi   VPORTC_OUT, LDAC_PIN
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
