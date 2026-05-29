/*
 * oled_ssd1306.S — Render text on a 128x64 SSD1306 OLED over I2C.
 *
 * The SSD1306 uses one I2C address (0x3C). Every transaction begins with a
 * single control byte that says whether the bytes that follow are COMMANDS or
 * DISPLAY DATA:
 *
 *     control 0x00  → the rest of the transaction is commands
 *     control 0x40  → the rest of the transaction is pixel data
 *
 * The panel is organised as 8 horizontal "pages", each 8 pixels tall and 128
 * columns wide. In horizontal addressing mode (set in oled_init) the column
 * pointer auto-increments after every data byte, so we can stream a whole
 * line — or the whole screen — inside one I2C transaction.
 *
 * Text is rendered from a 5x8 font table in flash. Each glyph is 5 column
 * bytes (LSB = top pixel); we add a 6th blank column as inter-character space.
 * A character's glyph lives at  font + (char - 0x20) * 5.
 *
 * The bundled font defines glyphs for the demo string only (0x20..0x5A);
 * undefined codes are blank. A full font fills all of 0x20..0x7E the same way.
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o oled_ssd1306.o oled_ssd1306.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o oled_ssd1306.elf oled_ssd1306.o
 *   avr-objcopy -O ihex oled_ssd1306.elf oled_ssd1306.hex
 */

#include <avr/io.h>

.equ OLED_ADDR,     0x3C
.equ OLED_CMD,      0x00        /* control byte: command stream               */
.equ OLED_DATA,     0x40        /* control byte: data stream                  */
.equ TWI_BAUD_100K, 12
.equ TWI_BUSSTATE_IDLE_gc, 0x01    /* group code: bus state = idle (enum in C) */
.equ TWI_MCMD_STOP_gc,     0x03    /* group code: ACK action + STOP            */

/* ------------------------------------------------------------------------- */
.section .rodata

msg:    .asciz "HELLO WORLD"

/* SSD1306 power-up command list (128x64, horizontal addressing) */
initcmds:
    .byte 0xAE                  /* display off                                */
    .byte 0xD5, 0x80            /* clock divide / oscillator                  */
    .byte 0xA8, 0x3F            /* multiplex ratio = 63 (64 rows)             */
    .byte 0xD3, 0x00            /* display offset = 0                         */
    .byte 0x40                  /* start line = 0                             */
    .byte 0x8D, 0x14            /* charge pump on                             */
    .byte 0x20, 0x00            /* memory addressing mode = horizontal        */
    .byte 0xA1                  /* segment remap (column 127 = SEG0)          */
    .byte 0xC8                  /* COM scan direction reversed                */
    .byte 0xDA, 0x12            /* COM pins config                            */
    .byte 0x81, 0x7F            /* contrast                                   */
    .byte 0xD9, 0xF1            /* pre-charge period                          */
    .byte 0xDB, 0x40            /* VCOMH deselect level                       */
    .byte 0xA4                  /* resume from RAM                            */
    .byte 0xA6                  /* normal (non-inverted)                      */
    .byte 0xAF                  /* display on                                 */
.equ INITLEN, . - initcmds

/* 5x8 font, column-major, LSB = top pixel. Index = (char - 0x20).           */
font:
    .fill (0x44-0x20)*5, 1, 0           /* 0x20..0x43 blank                    */
    .byte 0x7F,0x41,0x41,0x22,0x1C      /* 0x44 'D'                            */
    .byte 0x7F,0x49,0x49,0x49,0x41      /* 0x45 'E'                            */
    .fill (0x48-0x46)*5, 1, 0           /* 0x46..0x47 blank                    */
    .byte 0x7F,0x08,0x08,0x08,0x7F      /* 0x48 'H'                            */
    .fill (0x4C-0x49)*5, 1, 0           /* 0x49..0x4B blank                    */
    .byte 0x7F,0x40,0x40,0x40,0x40      /* 0x4C 'L'                            */
    .fill (0x4F-0x4D)*5, 1, 0           /* 0x4D..0x4E blank                    */
    .byte 0x3E,0x41,0x41,0x41,0x3E      /* 0x4F 'O'                            */
    .fill (0x52-0x50)*5, 1, 0           /* 0x50..0x51 blank                    */
    .byte 0x7F,0x09,0x19,0x29,0x46      /* 0x52 'R'                            */
    .fill (0x57-0x53)*5, 1, 0           /* 0x53..0x56 blank                    */
    .byte 0x7F,0x20,0x18,0x20,0x7F      /* 0x57 'W'                            */
    .fill (0x5B-0x58)*5, 1, 0           /* 0x58..0x5A blank                    */

/* ------------------------------------------------------------------------- */
.section .text
.global main

main:
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    rcall twi_init
    rcall oled_init
    rcall oled_clear
    rcall oled_home

    ldi   ZL, lo8(msg)
    ldi   ZH, hi8(msg)
    rcall oled_puts

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
/* TWI transaction primitives (split, so we can stream many bytes)            */

/* twi_start_w — START + (r24<<1)|W, wait for WIF. Clobbers r17.              */
twi_start_w:
    lsl   r24
    sts   TWI0_MADDR, r24
.Lsw:
    lds   r17, TWI0_MSTATUS
    sbrs  r17, TWI_WIF_bp
    rjmp  .Lsw
    ret

/* twi_write — write data byte r22, wait for WIF. Clobbers r17.               */
twi_write:
    sts   TWI0_MDATA, r22
.Lw:
    lds   r17, TWI0_MSTATUS
    sbrs  r17, TWI_WIF_bp
    rjmp  .Lw
    ret

/* twi_stop — issue STOP. Clobbers r17.                                       */
twi_stop:
    ldi   r17, TWI_MCMD_STOP_gc
    sts   TWI0_MCTRLB, r17
    ret

/* ------------------------------------------------------------------------- */
/* oled_cmd_start / oled_data_start — open a transaction of the given type   */
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

/* ------------------------------------------------------------------------- */
/* oled_init — stream the power-up command list                              */
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
    rcall twi_stop
    ret

/* ------------------------------------------------------------------------- */
/* oled_clear — set the full window and write 1024 zero bytes                */
oled_clear:
    rcall oled_cmd_start
    ldi   r22, 0x21             /* column address range                       */
    rcall twi_write
    ldi   r22, 0
    rcall twi_write
    ldi   r22, 127
    rcall twi_write
    ldi   r22, 0x22             /* page address range                         */
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
    rcall twi_stop
    ret

/* ------------------------------------------------------------------------- */
/* oled_home — restrict drawing to page 0, columns 0..127                    */
oled_home:
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
    ldi   r22, 0               /* page 0 only                                */
    rcall twi_write
    rjmp  twi_stop

/* ------------------------------------------------------------------------- */
/*
 * oled_putc — draw one glyph (6 columns: 5 from the font + 1 blank)
 * r17 = character
 * Clobbers r0, r1, r17, r18, r20, r22, Z
 */
oled_putc:
    cpi   r17, 0x20
    brlo  .Lpc_blank
    cpi   r17, 0x5B             /* > 'Z' is undefined in the bundled font     */
    brsh  .Lpc_blank
    rjmp  .Lpc_ok
.Lpc_blank:
    ldi   r17, 0x20             /* substitute a space                         */
.Lpc_ok:
    subi  r17, 0x20             /* index into font table                      */
    ldi   r18, 5
    mul   r17, r18              /* r1:r0 = index * 5                          */
    ldi   ZL, lo8(font)
    ldi   ZH, hi8(font)
    add   ZL, r0
    adc   ZH, r1
    clr   r1                    /* restore the r1 == 0 convention             */

    rcall oled_data_start
    ldi   r20, 5
.Lpc_col:
    ld    r22, Z+
    rcall twi_write
    dec   r20
    brne  .Lpc_col
    clr   r22                   /* inter-character gap                        */
    rcall twi_write
    rjmp  twi_stop

/* ------------------------------------------------------------------------- */
/*
 * oled_puts — render a NUL-terminated flash string
 * Z = data-space address of the string
 */
oled_puts:
    movw  r24, ZL               /* keep the string pointer in r25:r24         */
.Lpts:
    movw  ZL, r24
    ld    r17, Z+
    movw  r24, ZL               /* save advanced pointer (oled_putc reuses Z) */
    tst   r17
    breq  .Lpts_done
    rcall oled_putc
    rjmp  .Lpts
.Lpts_done:
    ret
