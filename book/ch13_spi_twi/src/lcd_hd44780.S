/*
 * lcd_hd44780.S — Drive a 16x2 HD44780 character LCD over I2C.
 *
 * The display sits behind a PCF8574 I/O expander ("I2C LCD backpack").
 * The HD44780 is wired to the expander in 4-bit mode:
 *
 *     PCF8574 bit   HD44780 signal
 *     ──────────────────────────────
 *     P0            RS  (0 = command, 1 = data)
 *     P1            RW  (tied low — write only)
 *     P2            E   (enable strobe, latches on falling edge)
 *     P3            Backlight (1 = on)
 *     P4..P7        D4..D7 (high data nibble)
 *
 * Each byte sent to the LCD is two 4-bit nibbles (high first). Each nibble is
 * clocked in by raising E, then lowering it. Because every nibble is a full
 * I2C transaction (~hundreds of microseconds at 100 kHz), the E pulse easily
 * meets the HD44780's ~450 ns minimum high time with no explicit delay.
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o lcd_hd44780.o lcd_hd44780.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o lcd_hd44780.elf lcd_hd44780.o
 *   avr-objcopy -O ihex lcd_hd44780.elf lcd_hd44780.hex
 */

#include <avr/io.h>

.equ LCD_ADDR,      0x27        /* common PCF8574 backpack 7-bit address     */
.equ LCD_BL,        0x08        /* P3 — backlight on                          */
.equ LCD_EN,        0x04        /* P2 — enable strobe                         */
.equ LCD_RS,        0x01        /* P0 — register select (1 = data)            */

.equ TWI_BAUD_100K, 12          /* ~98 kHz SCL at 3.333 MHz                    */
.equ TWI_BUSSTATE_IDLE_gc, 0x01    /* group code: bus state = idle (enum in C) */
.equ TWI_MCMD_STOP_gc,     0x03    /* group code: ACK action + STOP            */

/* ------------------------------------------------------------------------- */
.section .rodata
msg:    .asciz "AVR ASM ROCKS"

/* ------------------------------------------------------------------------- */
.section .text
.global main

main:
    /* Stack pointer */
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    rcall twi_init
    rcall lcd_init

    /* Print the flash string at the cursor (home position) */
    ldi   ZL, lo8(msg)
    ldi   ZH, hi8(msg)
    rcall lcd_puts

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
 * twi_write_byte — one self-contained TWI write transaction
 * r24 = 7-bit slave address, r22 = data byte
 * Clobbers: r24, r17
 */
twi_write_byte:
    lsl   r24
    sts   TWI0_MADDR, r24
.Lwb_a:
    lds   r17, TWI0_MSTATUS
    sbrs  r17, TWI_WIF_bp
    rjmp  .Lwb_a
    sts   TWI0_MDATA, r22
.Lwb_d:
    lds   r17, TWI0_MSTATUS
    sbrs  r17, TWI_WIF_bp
    rjmp  .Lwb_d
    ldi   r17, TWI_MCMD_STOP_gc
    sts   TWI0_MCTRLB, r17
    ret

/* ------------------------------------------------------------------------- */
/*
 * lcd_write4 — push one nibble to the LCD and strobe E
 * r18 = nibble (low 4 bits), r19 = RS bit (0 or LCD_RS)
 * Clobbers: r20, r22, r24, r17
 */
lcd_write4:
    mov   r20, r18
    swap  r20                   /* nibble -> D4..D7 (high bits)               */
    andi  r20, 0xF0
    ori   r20, LCD_BL           /* keep backlight on                          */
    or    r20, r19              /* mix in RS                                  */

    mov   r22, r20
    ori   r22, LCD_EN           /* E high                                     */
    ldi   r24, LCD_ADDR
    rcall twi_write_byte

    mov   r22, r20              /* E low — falling edge latches the nibble    */
    ldi   r24, LCD_ADDR
    rcall twi_write_byte
    ret

/* ------------------------------------------------------------------------- */
/*
 * lcd_send — send a full byte as two nibbles (high first)
 * r17 = byte, r19 = RS bit
 * Clobbers: r16, r18, r20, r22, r24
 */
lcd_send:
    mov   r16, r17              /* preserve the byte across lcd_write4         */
    mov   r18, r16
    swap  r18
    andi  r18, 0x0F             /* high nibble                                */
    rcall lcd_write4
    mov   r18, r16
    andi  r18, 0x0F             /* low nibble                                 */
    rcall lcd_write4
    ret

lcd_cmd:                        /* r17 = command byte                         */
    ldi   r19, 0
    rjmp  lcd_send

lcd_data:                       /* r17 = data byte                            */
    ldi   r19, LCD_RS
    rjmp  lcd_send

/* ------------------------------------------------------------------------- */
/*
 * lcd_init — HD44780 power-up sequence in 4-bit mode
 */
lcd_init:
    ldi   r24, 50
    rcall delay_ms              /* >40 ms after power-on                      */

    /* Three "function set 0x3" nibbles wake the controller into 8-bit mode  */
    ldi   r19, 0
    ldi   r18, 0x03
    rcall lcd_write4
    ldi   r24, 5
    rcall delay_ms
    ldi   r18, 0x03
    rcall lcd_write4
    ldi   r24, 1
    rcall delay_ms
    ldi   r18, 0x03
    rcall lcd_write4
    ldi   r24, 1
    rcall delay_ms

    ldi   r18, 0x02             /* now switch to 4-bit mode                   */
    rcall lcd_write4

    ldi   r17, 0x28             /* function set: 4-bit, 2 lines, 5x8 font     */
    rcall lcd_cmd
    ldi   r17, 0x0C             /* display on, cursor off, blink off          */
    rcall lcd_cmd
    ldi   r17, 0x06             /* entry mode: increment, no shift            */
    rcall lcd_cmd
    ldi   r17, 0x01             /* clear display                              */
    rcall lcd_cmd
    ldi   r24, 2
    rcall delay_ms              /* clear needs ~1.52 ms                       */
    ret

/* ------------------------------------------------------------------------- */
/*
 * lcd_puts — print a NUL-terminated flash string at the cursor
 * Z = data-space address of the string (flash)
 */
lcd_puts:
.Lps:
    ld    r17, Z+
    tst   r17
    breq  .Lps_done
    rcall lcd_data
    rjmp  .Lps
.Lps_done:
    ret

/* ------------------------------------------------------------------------- */
/*
 * delay_ms — crude busy-wait, r24 = milliseconds (approx, at 3.333 MHz)
 * Inner loop ~3 cycles; 1111 iterations ~= 1 ms.
 */
delay_ms:
    tst   r24
    breq  .Ldm_done
.Ldm_outer:
    ldi   r26, lo8(1111)
    ldi   r27, hi8(1111)
.Ldm_inner:
    sbiw  r26, 1
    brne  .Ldm_inner
    dec   r24
    brne  .Ldm_outer
.Ldm_done:
    ret
