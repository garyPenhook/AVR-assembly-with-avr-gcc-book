# avrdude Flashing Cheat-Sheet

`avrdude` is the standard tool for programming AVR microcontrollers. It
communicates with the device via a programmer (USB, serial, SPI ISP) and can
read/write flash, EEPROM, and fuse bytes.

---

## Basic Syntax

```bash
avrdude -p PARTNO -c PROGRAMMER [-P PORT] [-b BAUD] -U MEMTYPE:OP:FILE[:FORMAT]
```

```
-p PARTNO     Device (e.g. m328p, t3217, m2560). See Section E.4 for list.
-c PROGRAMMER Programmer type. See Section E.3.
-P PORT       Port (e.g. /dev/ttyUSB0, /dev/ttyACM0, usb).
-b BAUD       Baud rate (for serial programmers; default depends on programmer).
-U            Memory operation (can be repeated for multiple operations).
-v            Verbose output. -vv for more detail.
-n            Dry run: do not write anything.
-e            Erase flash before programming.
-F            Override signature check (use with caution).
```

### -U Flag Format

```
MEMTYPE:OP:FILE[:FORMAT]

MEMTYPE:
  flash    — program memory
  eeprom   — EEPROM
  lfuse    — low fuse byte
  hfuse    — high fuse byte
  efuse    — extended fuse byte
  lock     — lock bits
  signature — device signature (read only)
  calibration — oscillator calibration (read only)

OP:
  r — read from device, write to FILE
  w — write FILE to device
  v — verify device matches FILE

FORMAT (optional, auto-detected if omitted):
  i — Intel HEX
  s — Motorola S-record
  r — raw binary
  e — ELF
  h — hex string
  b — byte value (for single-byte ops like fuses)
  m — immediate value (e.g. 0xDE)
```

---

## Most-Used Commands

### Flash a HEX file

```bash
# Arduino Uno (ATmega328P, USB-serial bootloader on /dev/ttyUSB0)
avrdude -p m328p -c arduino -P /dev/ttyUSB0 -b 115200 \
        -U flash:w:firmware.hex:i

# USBasp programmer (no port needed)
avrdude -p m328p -c usbasp \
        -U flash:w:firmware.hex:i

# AVRISP mkII (USB)
avrdude -p m328p -c avrispmkII \
        -U flash:w:firmware.hex:i
```

### Read flash to file

```bash
avrdude -p m328p -c usbasp \
        -U flash:r:backup.hex:i
```

### Verify only (no write)

```bash
avrdude -p m328p -c usbasp \
        -U flash:v:firmware.hex:i
```

### Erase then write

```bash
avrdude -p m328p -c usbasp -e \
        -U flash:w:firmware.hex:i
```

### Write EEPROM

```bash
avrdude -p m328p -c usbasp \
        -U eeprom:w:data.hex:i
```

### Read fuse bytes

```bash
avrdude -p m328p -c usbasp \
        -U lfuse:r:-:h -U hfuse:r:-:h -U efuse:r:-:h
# Output: e.g. 0xff 0xd9 0x07 (lfuse hfuse efuse)
# '-' = stdout, 'h' = hex string format
```

### Write fuse bytes

```bash
# WARNING: incorrect fuse values can brick the device.
# Always calculate fuses with an online calculator and verify before writing.

# Set hfuse = 0xDE (BOOTRST=0, BOOTSZ=10 for 1KB bootloader section)
avrdude -p m328p -c usbasp \
        -U hfuse:w:0xDE:m

# Restore ATmega328P factory fuses (lfuse=0xFF, hfuse=0xD9, efuse=0x07)
avrdude -p m328p -c usbasp \
        -U lfuse:w:0xFF:m \
        -U hfuse:w:0xD9:m \
        -U efuse:w:0x07:m
```

**Warning:** Fuses control clock source, brown-out detection, bootloader
region, and JTAG. Setting `CKSEL` bits for an external crystal when no crystal
is connected will make the device unresponsive — recovery requires an ISP
programmer that provides a clock signal (High-Voltage Serial Programming).

### Multiple operations in one command

```bash
avrdude -p m328p -c usbasp \
        -U flash:w:firmware.hex:i \
        -U eeprom:w:eeprom_data.hex:i
```

---

## Common Programmers

```
Programmer ID    Description
──────────────────────────────────────────────────────────────────────────────
arduino          Arduino bootloader via serial (auto-reset on DTR)
arduino-ft232r   Arduino via FTDI FT232R cable
avrisp           Atmel AVRISP v1 (serial)
avrisp2          Atmel AVRISP mkII (USB HID); also: avrispmkII
usbasp           USBasp (cheap USB ISP clone, widely available)
usbtiny          USBtiny / Adafruit USBtinyISP
dragon_isp       AVR Dragon in ISP mode
dragon_jtag      AVR Dragon in JTAG mode
jtag2isp         JTAGICE mkII in ISP mode
jtag2            JTAGICE mkII
atmelice_isp     Atmel-ICE in ISP mode
atmelice_pdi     Atmel-ICE in PDI mode (XMEGA)
atmelice_updi    Atmel-ICE in UPDI mode (tinyAVR/megaAVR 0/1/2-series)
pymcuprog        Microchip MPLAB Snap / Curiosity Nano via pymcuprog bridge
serialupdi       UPDI via USB-serial adapter (cheap, 1-wire)
```

### UPDI Devices (ATtiny3217 and tinyAVR 1-series)

The ATtiny3217 uses UPDI (Unified Program and Debug Interface), a single-wire
protocol. Use `serialupdi` with a USB-serial adapter connected to the UPDI pin
via a 4.7kΩ resistor:

```bash
# ATtiny3217 via serialupdi on /dev/ttyUSB0
avrdude -p t3217 -c serialupdi -P /dev/ttyUSB0 \
        -U flash:w:firmware.hex:i

# Read fuses
avrdude -p t3217 -c serialupdi -P /dev/ttyUSB0 \
        -U fuse0:r:-:h -U fuse1:r:-:h -U fuse2:r:-:h \
        -U fuse4:r:-:h -U fuse5:r:-:h -U fuse6:r:-:h -U fuse7:r:-:h
```

UPDI wiring (1-wire):

```
USB-serial TX ──┐
                ├── 4.7kΩ ── UPDI pin (ATtiny3217 pin 16)
USB-serial RX ──┘
USB-serial GND ─── GND
```

Alternatively, use the Atmel-ICE or MPLAB PICkit 4 for UPDI.

---

## Device Part Numbers

```
Part Number   Device
──────────────────────────────────────────────────────────────────────────────
m328p         ATmega328P (Arduino Uno, Nano)
m328pb        ATmega328PB
m2560         ATmega2560 (Arduino Mega)
m32u4         ATmega32U4 (Arduino Leonardo, Pro Micro)
m168p         ATmega168P
m88p          ATmega88P
m48p          ATmega48P
t3217         ATtiny3217 (book target for tinyAVR 1-series)
t1616         ATtiny1616
t816          ATtiny816
t416          ATtiny416
t85           ATtiny85
t84           ATtiny84
t45           ATtiny45
t13           ATtiny13
x128a4u       ATxmega128A4U
```

Full list: `avrdude -p ?`

---

## Fuse Byte Reference (ATmega328P)

> **This section is ATmega328P only.** Classic ATmega parts use three fuse
> bytes (LFUSE/HFUSE/EFUSE) with the bit fields below. The book's ATtiny3217
> does **not** have these — it uses the named fuses (WDTCFG, BODCFG, OSCCFG,
> SYSCFG0/1, APPEND, BOOTEND, LOCKBIT) documented in Appendix A. Do not apply
> the values below to the ATtiny3217.

### Low Fuse (LFUSE)

```
Bit   Name     Description
──────────────────────────────────────────────────────────────────────────────
7     CKDIV8   Divide clock by 8 (0 = enabled; factory default)
6     CKOUT    Clock output on PB0 (0 = enabled)
5:4   SUT1:0   Start-up time (10 = default 14CK + 65ms)
3:0   CKSEL3:0 Clock source (0010 = internal 8MHz RC; 1111 = external crystal)

Factory default (internal RC, /8): LFUSE = 0x62
No divide (internal 8MHz full speed): LFUSE = 0xE2
External 16MHz crystal (Arduino): LFUSE = 0xFF
```

### High Fuse (HFUSE)

```
Bit   Name      Description
──────────────────────────────────────────────────────────────────────────────
7     RSTDISBL  Disable reset pin (0 = PC6 becomes I/O; DANGEROUS)
6     DWEN      debugWIRE enable (0 = enabled; disables ISP when set)
5     SPIEN     SPI programming enable (0 = enabled; keep this 0)
4     WDTON     Watchdog always on (0 = always on)
3     EESAVE    Preserve EEPROM during chip erase (0 = preserved)
2:1   BOOTSZ1:0 Boot section size (11=256B, 10=512B, 01=1KB, 00=2KB)
0     BOOTRST   Boot reset vector (0 = reset jumps to boot section)

Factory default: HFUSE = 0xD9
  (SPI enabled, WDT off, EEPROM erased, 2KB boot, reset to 0x0000)
Bootloader (1KB boot, reset to boot section): HFUSE = 0xDE
```

### Extended Fuse (EFUSE)

```
Bit   Name       Description
──────────────────────────────────────────────────────────────────────────────
2:0   BODLEVEL2:0 Brown-out detection level
      111 = BOD disabled (factory)
      110 = 1.8V
      101 = 2.7V
      100 = 4.3V

Factory default: EFUSE = 0x07 (BOD disabled; only bits 2:0 used)
```

### Online Fuse Calculator

The Engbedded AVR Fuse Calculator provides a GUI for calculating fuse values.
Search "AVR fuse calculator" — cross-check with the device datasheet before
programming.

---

## Generating Intel HEX from ELF

```bash
avr-objcopy -O ihex firmware.elf firmware.hex

# EEPROM section separately
avr-objcopy -O ihex -j .eeprom \
            --set-section-flags=.eeprom=alloc,load \
            --change-section-lma .eeprom=0 \
            firmware.elf eeprom.hex
```

---

## Complete Build + Flash Script

```bash
#!/bin/bash
# build_flash.sh — assemble, link, and flash ATmega328P
set -e

MCU=atmega328p
PORT=/dev/ttyUSB0
BAUD=115200
SRC=firmware.S

avr-gcc -mmcu=${MCU} -nostartfiles -o firmware.elf ${SRC}
avr-size firmware.elf
avr-objcopy -O ihex firmware.elf firmware.hex
avrdude -p ${MCU} -c arduino -P ${PORT} -b ${BAUD} \
        -U flash:w:firmware.hex:i
echo "Done."
```

```bash
# For ATtiny3217 via serialupdi
MCU=attiny3217
PORT=/dev/ttyUSB0

avr-gcc -mmcu=${MCU} -nostartfiles -o firmware.elf firmware.S
avr-objcopy -O ihex firmware.elf firmware.hex
avrdude -p ${MCU} -c serialupdi -P ${PORT} \
        -U flash:w:firmware.hex:i
```

---

## Troubleshooting

```
Problem                           Likely cause / fix
──────────────────────────────────────────────────────────────────────────────
avrdude: stk500_recv(): timeout   Wrong port, wrong baud, board not reset.
                                  Try -P /dev/ttyACM0, check USB cable.

avrdude: Expected signature       Wrong -p part number; use avrdude -p ? to list
for ATmega328P is 1E 95 0F        all; read signature with -U signature:r:-:h.

avrdude: verification error       Flash write failed; bad connection, insufficient
                                  power, or write-protected region.

avrdude: error: usbasp, Error:    USBasp firmware too old for target; update
Could not find USB device          USBasp firmware, or add -B 10 flag (slow SCK).

avrdude: initialization failed    Target not responding; check power, RESET pin,
rc=-1; check connections          JTAG enable fuse (JTAGEN=0 disables ISP on some
and try again, or use -F          devices).

Can't open device /dev/ttyUSB0    Add user to dialout group:
Permission denied                 sudo usermod -a -G dialout $USER
                                  Then log out and back in.
```

### USBasp Slow Clock

If ISP communication fails with a freshly-soldered board or a device that has
been running at low speed (CKDIV8 fuse set):

```bash
# Slow down SCK to 125 kHz (-B = bitclock period in µs; -B 8 = 125kHz SCK)
avrdude -p m328p -c usbasp -B 8 \
        -U lfuse:w:0xFF:m   # then reprogram fuses for 16MHz crystal
```

### Arduino Auto-Reset Circuit

Arduino boards use a 100 nF capacitor on DTR/RST. `avrdude -c arduino` toggles
DTR to reset the MCU before uploading. If the reset does not trigger:

```bash
# Manual: press reset button 2 seconds before avrdude starts, then release
avrdude -p m328p -c arduino -P /dev/ttyUSB0 -b 115200 \
        -U flash:w:firmware.hex:i
```

Or disable the auto-reset capacitor (cut the RESET EN trace on the Arduino PCB)
when running a custom bootloader that does not expect the timing.
