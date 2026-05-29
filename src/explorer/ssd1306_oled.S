/*
 * ssd1306_oled.S — Initialise and clear the Explorer's SSD1306 OLED.
 *
 * Curiosity Nano Explorer (EV58G97A). 1.3" 128x64 OLED on the shared I2C bus.
 *   I2C address : 0x3D (7-bit)  [0x3C if pin A0 is tied to GND]
 *   Bus         : COM-section I2C -> TWI0 (SDA = PB1, SCL = PB0)
 *   RESET pin   : Explorer IO-35 (this file assumes a jumper to PA6)
 *
 * This brings up the panel and clears it. Full text rendering with a flash
 * font is in ../oled/oled_ssd1306.S — set its address to 0x3D to reuse it
 * on the Explorer.
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o ssd1306_oled.o ssd1306_oled.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o ssd1306_oled.elf ssd1306_oled.o
 */

#include <avr/io.h>

.equ OLED_ADDR,     0x3D
.equ OLED_CMD,      0x00
.equ OLED_DATA,     0x40
.equ RST_PIN,       6           /* PA6 <- jumper from Explorer IO-35          */
.equ TWI_BAUD_100K, 12

.equ TWI_BUSSTATE_IDLE_gc,  0x01
.equ TWI_MCMD_STOP_gc,      0x03

.section .rodata
initcmds:
    .byte 0xAE, 0xD5, 0x80, 0xA8, 0x3F, 0xD3, 0x00, 0x40
    .byte 0x8D, 0x14, 0x20, 0x00, 0xA1, 0xC8, 0xDA, 0x12
    .byte 0x81, 0x7F, 0xD9, 0xF1, 0xDB, 0x40, 0xA4, 0xA6, 0xAF
.equ INITLEN, . - initcmds

.section .text
.global main

main:
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    rcall twi_init
    rcall oled_reset
    rcall oled_init
    rcall oled_clear

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

/* oled_reset — pulse the RESET line low then high */
oled_reset:
    sbi   VPORTA_DIR, RST_PIN
    cbi   VPORTA_OUT, RST_PIN    /* reset low                                 */
    rcall delay_short
    sbi   VPORTA_OUT, RST_PIN    /* release                                   */
    rcall delay_short
    ret

/* oled_init — stream the power-up command list */
oled_init:
    rcall oled_cmd_start
    ldi   ZL, lo8(initcmds)
    ldi   ZH, hi8(initcmds)
    ldi   r20, INITLEN
.Lic:
    ld    r22, Z+
    rcall twi_write
    dec   r20
    brne  .Lic
    rjmp  twi_stop

/* oled_clear — set the full window and write 1024 zero bytes */
oled_clear:
    rcall oled_cmd_start
    ldi   r22, 0x21
    rcall twi_write
    ldi   r22, 0
    rcall twi_write
    ldi   r22, 127
    rcall twi_write
    ldi   r22, 0x22
    rcall twi_write
    ldi   r22, 0
    rcall twi_write
    ldi   r22, 7
    rcall twi_write
    rcall twi_stop

    rcall oled_data_start
    ldi   r26, lo8(1024)
    ldi   r27, hi8(1024)
    clr   r22
.Lcl:
    rcall twi_write
    sbiw  r26, 1
    brne  .Lcl
    rjmp  twi_stop

/* ------------------------------------------------------------------------- */
oled_cmd_start:
    ldi   r24, OLED_ADDR
    rcall twi_start_w
    ldi   r22, OLED_CMD
    rjmp  twi_write
oled_data_start:
    ldi   r24, OLED_ADDR
    rcall twi_start_w
    ldi   r22, OLED_DATA
    rjmp  twi_write

twi_start_w:
    lsl   r24
    sts   TWI0_MADDR, r24
.Lsw:
    lds   r17, TWI0_MSTATUS
    sbrs  r17, TWI_WIF_bp
    rjmp  .Lsw
    ret
twi_write:
    sts   TWI0_MDATA, r22
.Lw:
    lds   r17, TWI0_MSTATUS
    sbrs  r17, TWI_WIF_bp
    rjmp  .Lw
    ret
twi_stop:
    ldi   r17, TWI_MCMD_STOP_gc
    sts   TWI0_MCTRLB, r17
    ret

delay_short:
    ldi   r26, 0
    ldi   r27, 0
.Lds:
    sbiw  r26, 1
    brne  .Lds
    ret
