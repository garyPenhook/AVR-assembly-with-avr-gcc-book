# jtag2updi and SerialUPDI: DIY UPDI Programmers

This document covers both historical jtag2updi firmware programming and the
modern SerialUPDI approach that replaced it, including full wiring schematics
for every common case.

---

## Background: Two DIY Approaches to UPDI Programming

### jtag2updi (2018–2021, Legacy)

**jtag2updi** is open-source firmware (by ElTangas) that converts a spare Arduino
or AVR development board into a UPDI programmer. The host PC runs avrdude and
talks to the Arduino over USB-serial using the JTAG2 protocol; the Arduino
firmware translates JTAG2 commands to raw UPDI frames and drives the single
UPDI wire to the target.

It works, but:
- Maximum practical write speed: ~6 kb/s (limited by firmware overhead).
- The C++ firmware is complex and had known stability issues.
- Requires a second AVR microcontroller, not just a USB serial adapter.
- Superseded in 2021 by SerialUPDI, which is 2–5× faster and requires no extra
  microcontroller.

The jtag2updi GitHub repository (`github.com/ElTangas/jtag2updi`) is archived
in maintenance-only mode as of late 2021. New projects should use SerialUPDI.

### SerialUPDI (2021–present, Recommended)

**SerialUPDI** (by Spence Konde and Quentin Bolsée) eliminates the intermediary
AVR microcontroller entirely. A plain USB-to-serial adapter's TX and RX lines
are tied together through a Schottky diode (or resistor). The UPDI protocol
runs directly over the serial port.

Speed comparison at 230400 baud, ATtiny3217 full 32 kB flash:

```
Programmer       Write     Read     Notes
──────────────────────────────────────────────────────────
jtag2updi        ~6 kb/s   ~7 kb/s  16 MHz Arduino Nano
SerialUPDI CH340 15 kb/s  17 kb/s  at 230400 baud
SerialUPDI FT232 17 kb/s  16 kb/s  after latency timer fix
Curiosity Nano   ~3 kb/s   ~6 kb/s  nEDBG via avrdude
```

---

## jtag2updi Schematics and Setup

### Supported Host Boards

jtag2updi firmware has been tested on:
- Arduino Nano (ATmega328P) — most common
- Arduino Uno
- Arduino Mega
- SparkFun Pro Micro (ATmega32U4)
- ATmega4809 Nano Every

### Wiring: Arduino Nano (ATmega328P) as jtag2updi Programmer

```
Arduino Nano (jtag2updi firmware)         Target (e.g. ATtiny3217)
 ┌──────────────────────┐                 ┌─────────────────────────┐
 │                      │                 │                         │
 │           D6 (TX) ───┼── 4.7 kΩ ──────┼─ PA0 (UPDI/RESET)      │
 │                      │                 │                         │
 │              GND ────┼─────────────────┼─ GND                   │
 │                      │                 │                         │
 │          5V / 3V3 ───┼─────────────────┼─ VCC                   │
 │     (match target!)  │                 │                         │
 │                      │                 │                         │
 │       USB to PC ─────┼                 └─────────────────────────┘
 └──────────────────────┘

IMPORTANT: Match VCC to target voltage. ATtiny3217 Curiosity Nano target
runs at 3.3V; use the Arduino 3V3 pin, not 5V.
```

ASCII breadboard detail:

```
                                    4.7 kΩ
Arduino D6 ─────────────────────── ┌───┐ ─────── PA0 (UPDI)
Arduino GND ─────────────────────────────────── GND
Arduino 3V3 ─────────────────────────────────── VCC (3.3 V target)

( The 4.7 kΩ resistor limits current if programmer and target
  drive the line simultaneously. This value is specific to jtag2updi.
  Do NOT use 4.7 kΩ with SerialUPDI — use 470 Ω or the diode method. )
```

### Flashing jtag2updi onto the Arduino

1. Download the firmware: `github.com/ElTangas/jtag2updi`
2. Open `source/jtag2updi.ino` in the Arduino IDE.
3. Select the correct board (e.g. "Arduino Nano" with ATmega328P).
4. Upload.

After flashing, the Arduino is a UPDI programmer. avrdude uses it as a
`jtag2updi`-type programmer on the serial port the Arduino occupies.

### avrdude Commands (jtag2updi)

```bash
# Write flash
avrdude -c jtag2updi -p t3217 -P /dev/ttyUSB0 -b 115200 \
        -U flash:w:firmware.hex:i

# Read flash
avrdude -c jtag2updi -p t3217 -P /dev/ttyUSB0 -b 115200 \
        -U flash:r:readback.hex:i

# Chip erase
avrdude -c jtag2updi -p t3217 -P /dev/ttyUSB0 -b 115200 -e

# Write fuses (e.g. FUSE2 = 0x02 for 20 MHz oscillator)
avrdude -c jtag2updi -p t3217 -P /dev/ttyUSB0 -b 115200 \
        -U fuse2:w:0x02:m
```

On Windows, substitute `COM3` (or the correct port) for `/dev/ttyUSB0`.

---

## SerialUPDI Schematics

A USB-to-serial adapter is connected to the UPDI pin via a Schottky diode (or
resistor) that ties TX and RX into a single bidirectional wire. The diode lets
the adapter drive the UPDI line while still allowing the target's weak output
to pull it in the other direction on RX.

### Case 1: Adapter With Internal TX Resistor — Diode Method (Recommended)

Most CH340, CP2102, and many FT232 adapters have a 1–2.2 kΩ resistor in series
with TX. Check with a multimeter if unsure.

```
USB Serial Adapter                              Target
 ┌───────────────────────────────┐             ┌─────────────────────────┐
 │                               │             │                         │
 │  RX ──────────────────────────┼─────────────┼─ PA0 (UPDI/RESET)      │
 │                               │     ┌───────┘                         │
 │  TX ── [1-2kΩ internal] ──────┼──┤►├┘  (Schottky diode, band → TX)   │
 │                               │             │                         │
 │  VCC ─────────────────────────┼─────────────┼─ VCC                   │
 │  GND ─────────────────────────┼─────────────┼─ GND                   │
 └───────────────────────────────┘             └─────────────────────────┘

Diode: BAT43, BAT54, 1N5817, or equivalent fast Schottky.
Band (cathode) of diode points toward TX. Anode toward RX junction.
```

Compact ASCII:

```
                    ┤►├  (Schottky, band toward TX)
  TX ── [1-2kΩ] ──┤►├──┬──── PA0 (UPDI)
  RX ─────────────────┘
  VCC ─────────────────────── VCC
  GND ─────────────────────── GND
```

Optional: add a 470 Ω resistor between the diode junction and PA0 for
short-circuit protection (especially useful if you ever accidentally plug
the connector in backward against an externally powered board).

### Case 2: Adapter Without Internal TX Resistor — Diode + External Resistor

Rare but possible (usually bare FT232RL modules without a built-in resistor):

```
  TX ──┤►├── 470 Ω ──┬──── PA0 (UPDI)
  RX ─────────────────┘
  VCC ─────────────────────── VCC
  GND ─────────────────────── GND
```

Add 470 Ω between diode and UPDI junction. Without any resistance, bus
contention during baud-rate negotiation can stress both the adapter and target.

### Case 3: Resistor-Only Method (No Diode Available)

Total resistance TX → RX junction must be approximately **4.7 kΩ**:

```
No internal resistor in adapter:
  TX ──── 4.7 kΩ ─────┬──── PA0 (UPDI)
  RX ─────────────────┘
  VCC ─────────────────────── VCC
  GND ─────────────────────── GND

Adapter has 1-2 kΩ internal TX resistor:
  TX ──[1-2kΩ]── added R ──┬──── PA0 (UPDI)
  (total = 4.7 kΩ)         │
  RX ──────────────────────┘
```

The resistor method has a narrower operating margin than the diode method and
is more likely to fail at higher baud rates (> 230400 bps). Use it only when
no Schottky diode is available.

**Do not use the 4.7 kΩ resistor-only method with SerialUPDI for tinyAVR
parts running at low voltages (< 3.3 V)** — the line may not pull fully to VDD.

### Case 4: Target Board Has On-Board Series Resistor (> 470 Ω)

Some breakout boards have a large series resistor (4.7 kΩ was once common
and incorrectly recommended). This will prevent SerialUPDI from working.
Solutions:

```
Option A: Bypass the on-board resistor with a wire or solder bridge.
Option B: Connect RX directly to the UPDI pin, bypassing the resistor.
Option C: Use jtag2updi, which tolerates larger series resistance.

Option B schematic:

   Adapter TX ── [diode] ──┬──── adapter-side of large resistor
   Adapter RX ─────────────┼──── UPDI pin side (after large R)
                            (separate connection)
```

### Three-Pin UPDI Connector Standard

If making a dedicated UPDI cable, use this three-pin order:

```
Pin 1: GND
Pin 2: VCC
Pin 3: UPDI

(1.27 mm or 2.54 mm pitch header; or JST-PH 3-pin)
```

This matches the Curiosity Nano edge connector pinout and the pinout used by
MegaTinyCore and DxCore for their serial programmer connectors.

---

## Adapter Selection Guide

```
Adapter     Typical Cost   VCC Out   TX Resistor   Speed at 460800   Notes
──────────────────────────────────────────────────────────────────────────
CH340G      $0.50–$1.50    5V*       1–2.2 kΩ      10 W / 27 R kb/s  Best value
FT232RL     $2–$5          3.3/5V    None usually  10 W / 28 R kb/s  Change latency
CP2102      $1–$3          3.3/5V    None usually  N/A at 460800      No 345600 baud
PL2303      $1–$2          3.3/5V    Varies        Avoid             Driver problems
MCP2200     —              —         —             CANNOT USE        No 2-stop-bit support
MCP2221     —              —         —             CANNOT USE        No 2-stop-bit support

* Most CH340G adapters output 5V logic even with 3V3 VCC jumper set.
  The 1–2 kΩ TX resistor + 470 Ω target-side resistor prevents damage to
  a 3.3 V target in most cases, but a level shifter is cleaner.
```

UPDI requires 2 stop bits and even parity. Adapters that cannot be
configured for 2 stop bits (MCP2200, MCP2221, Bluetooth serial) will not work.

---

## Software Setup

### avrdude (SerialUPDI)

avrdude 7.0+ includes native SerialUPDI support via `-c serialupdi`:

```bash
# Linux
avrdude -c serialupdi -p t3217 -P /dev/ttyUSB0 -b 230400 \
        -U flash:w:firmware.hex:i

# macOS
avrdude -c serialupdi -p t3217 -P /dev/cu.usbserial-0001 -b 230400 \
        -U flash:w:firmware.hex:i

# Windows
avrdude -c serialupdi -p t3217 -P COM3 -b 230400 \
        -U flash:w:firmware.hex:i

# With write delay (needed on some adapter/OS combinations at > 230400 baud)
avrdude -c serialupdi -p t3217 -P /dev/ttyUSB0 -b 460800 \
        -x wd_extra=yes \
        -U flash:w:firmware.hex:i
```

### pymcuprog (SerialUPDI)

```bash
pip install pymcuprog

pymcuprog write -t uart -u /dev/ttyUSB0 --clk 230400 \
         -d attiny3217 --filename firmware.hex

pymcuprog erase -t uart -u /dev/ttyUSB0 --clk 230400 -d attiny3217

pymcuprog ping -t uart -u /dev/ttyUSB0 --clk 230400 -d attiny3217
```

### MegaTinyCore / DxCore (Arduino IDE)

If using the Arduino IDE with MegaTinyCore or DxCore, select:
- **Tools → Programmer → SerialUPDI - 230400 baud** (or slower for reliability)
- **Tools → Port → /dev/ttyUSB0** (or COM port on Windows)
- **Sketch → Upload Using Programmer** (NOT the standard Upload button)

---

## Troubleshooting Quick Reference

```
Symptom                      Likely Cause                Fix
─────────────────────────────────────────────────────────────────────────
No connection at any speed   RSTPINCFG = 0x0 (GPIO mode) Need HV programmer
Timeout at start             Cable reversed / no GND     Check all 3 connections
"avrdude: jtagmkII_recv()"   Wrong programmer type       Use -c serialupdi
Slow write (< 5 kb/s)        FT232 latency = 16 ms       Set latency timer to 1 ms
Contention errors            LED on RX line              Remove RX LED from adapter
Contention errors            Wrong diode orientation     Band toward TX, not RX
Frame/parity errors          Baud too high for V/temp    Try -b 57600
Write fails mid-page         No write delay on tinyAVR   Add -x wd_extra=yes
Device locked                Lock bits set               Chip erase first
```

---

## Notes on the 4.7 kΩ Resistor Misconception

Early UPDI documentation and tutorials widely recommended a 4.7 kΩ series
resistor between the programmer and the UPDI pin. This value is:

- **Correct** for jtag2updi (the firmware is designed around it and has push-pull
  drive strength that can overcome it).
- **Wrong** for SerialUPDI / pyupdi-style adapters. The target's UPDI output
  driver is very weak (low drive current). With 4.7 kΩ, the target's output
  does not pull the line to a logic-valid level, causing receive errors.

The correct resistor for SerialUPDI is **470 Ω** on the UPDI line (or 0 Ω if
the adapter already has an internal TX resistor and you are using the diode
method). The Schottky diode eliminates the need for any external resistor on
most adapters.
