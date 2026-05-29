# OLED / Display Examples

Standalone assembly examples for small graphical displays. All target the
**ATtiny3217** (Curiosity Nano) and build on the TWI0 (I²C) material from
Chapter 13, including the flash-mapped string-rendering pattern.

Pair these with the sensor drivers in [`../sensors/`](../sensors/) for a
"read a value, draw it on screen" project.

## Contents

```
oled_ssd1306.S      SSD1306 128x64 OLED over I2C — text from a flash font
                    (init, screen clear, 5x8 font, oled_putc / oled_puts).
                    This is the worked example from Chapter 13.
```

## Planned / good candidates to add

```
ssd1306_graphics.S  Pixels, lines, and a framebuffer for the SSD1306
sh1106.S            SH1106 variant (1.3" modules; 132-col RAM, +2 col offset)
ssd1331_spi.S       SSD1331 96x64 colour OLED over SPI
```

## Hardware

The reference part is the **0.96" 128x64 SSD1306 I²C module** (4 pins:
GND/VCC/SCL/SDA, address `0x3C`). The Solomon Systech SSD1306 datasheet is the
authoritative reference for the command set and init sequence. Note that 1.3"
modules often use the **SH1106**, which is command-compatible except for a
132-column RAM with a 2-pixel column offset and no horizontal addressing mode —
`oled_clear`/`oled_home` need small changes for it.

## Building

```bash
avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o oled_ssd1306.o oled_ssd1306.S
avr-gcc -mmcu=attiny3217 -nostartfiles -o oled_ssd1306.elf oled_ssd1306.o
avr-objcopy -O ihex oled_ssd1306.elf oled_ssd1306.hex
avrdude -p t3217 -c serialupdi -P /dev/ttyUSB0 -U flash:w:oled_ssd1306.hex:i
```

The bundled font defines glyphs for the demo string (`0x20`–`0x5A`); undefined
codes render blank. Extend the table to cover the full printable ASCII range
the same way.
