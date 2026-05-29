# Curiosity Nano Explorer Examples

Assembly examples for every peripheral on the **Curiosity Nano Explorer**
(EV58G97A) base board, driven by an **ATtiny3217 Curiosity Nano** seated in the
CNANO socket. One self-contained file per peripheral.

Source for the board details: `CNANO-Explorer-UserGuide-DS50003716` (in the
repo root).

## How the board connects to the MCU

The Explorer is **fully remappable** — every peripheral signal reaches the
CNANO socket through the remapping area and can be jumpered to any MCU pin. The
shared buses use the socket's standard COM section, which on the ATtiny3217 is:

```
I2C  (TWI0)   SDA = PB1   SCL = PB0
SPI  (SPI0)   MOSI = PA1  MISO = PA2  SCK = PA3   SS = PA4
UART (USART0) TX  = PB2   RX  = PB3
```

GPIO-style signals (chip selects, interrupt/alert lines, the WS2812B data line,
PWM outputs, ADC channels) are assigned per file and documented in each file's
header — wire them with jumpers as noted. Because you only run one example at a
time, pin choices may overlap between files.

## Peripheral map

### I2C bus (TWI0)

```
mcp9808_temp.S         0x1C  MCP9808 temperature sensor
pac1944_power.S        0x1F  PAC1944 4-channel power monitor
mcp23008_buttons.S     0x24  I/O Expander 2 -> joystick + SW1/2/3
mcp23008_led_row.S     0x25  I/O Expander 1 -> 8 yellow LEDs (active-low)
vcnl4200_prox_als.S    0x51  VCNL4200 proximity + ambient light
at24cm02_eeprom.S      0x54  AT24CM02 2 Mbit I2C EEPROM (18-bit addressing)
atecc608b_secure.S     0x58  ATECC608B secure element (wake + Info, CRC16)
ssd1306_oled.S         0x3D  SSD1306 128x64 OLED (init + clear)
```

### SPI bus (SPI0)

```
eeprom_25csm04.S             25CSM04 4 Mbit SPI EEPROM (CS = PA4)
mcp4821_dac.S                MCP4821 12-bit DAC (CS = IO-26, LDAC = IO-36)
microsd_spi.S                microSD card SPI-mode init skeleton (CS = IO-25)
```

### LEDs, PWM, analog, touch

```
ws2812b_leds.S         8 addressable RGB LEDs (data = IO-27; switches to 20 MHz)
rgb_led_pwm.S          single RGB LED via TCA0 PWM (PWM-A/B/C = PB0/PB1/PB2)
servo_pwm.S            servo headers, 50 Hz PWM via TCA0
potentiometer_adc.S    rotary pot on ADC7 (AIN7/PA7)
microphone_adc.S       MEMS mic + amp on ADC6 (AIN6/PA6), free-running
mtch1030_touch.S       three capacitive touch buttons (read OUTx lines)
```

### Not driven in software

- **USB bridge (MCP2221A)** — a USB-to-UART/I2C bridge for the host PC; hold it
  in reset by pulling IO-37 low. No MCU-side driver needed.
- **Voltage reference (MCP1501)** — passive 1.5V/3.0V references; route to the
  ADC's VREFA pin (used by `potentiometer_adc.S` / `microphone_adc.S`).
- **Speaker** — driven by the MCP4821 DAC output; generate tones by updating the
  DAC (`mcp4821_dac.S`) in a loop.
- **CNANO reset button** — wired to the MCU reset pin; hardware only.
- **mikroBUS / Grove / Qwiic / PICkit** — connectors, not fixed devices.

## Building

All files target the **ATtiny3217**:

```bash
avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o <name>.o <name>.S
avr-gcc -mmcu=attiny3217 -nostartfiles -o <name>.elf <name>.o
avr-objcopy -O ihex <name>.elf <name>.hex
avrdude -p t3217 -c serialupdi -P /dev/ttyUSB0 -U flash:w:<name>.hex:i
```

## Notes and caveats

- `_gc` group codes (e.g. `TWI_MCMD_STOP_gc`) are C enums in `<avr/io.h>` and
  are invisible to the assembler, so each file `.equ`s the few it uses. `_bm` /
  `_bp` symbols are macros and work directly.
- `atecc608b_secure.S` and `microsd_spi.S` are advanced skeletons with
  simplified timing/response handling — verify against hardware.
- `ws2812b_leds.S` is timing-critical: it raises CLK_PER to 20 MHz and counts
  cycles. Check the waveform on a scope and tune the NOP padding.
- The ADC examples use the external VREFA reference (route the board's 3.0V
  MCP1501 reference to VREFA) for the full 0..3.3V range.
