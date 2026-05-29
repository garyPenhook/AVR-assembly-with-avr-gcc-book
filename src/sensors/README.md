# Sensor Examples

Standalone assembly examples for common, cheap sensors with freely
downloadable datasheets. All target the **ATtiny3217** (Curiosity Nano) and
use the TWI0 (I²C) and SPI0 peripherals introduced in Chapter 13.

These are extras beyond the book chapters; pair them with the display drivers
in [`../oled/`](../oled/) for a complete "read a sensor, show the value"
project.

## Contents

```
lm75_twi.S          LM75 I2C temperature sensor — 2-byte register read
ds3231_twi.S        DS3231 real-time clock — 7-byte multi-read + BCD decode
```

## Planned / good candidates to add

```
bme280_twi.S        Bosch BME280 temp/humidity/pressure (I2C 0x76/0x77)
mpu6050_twi.S       InvenSense MPU-6050 6-axis IMU (I2C 0x68)
bh1750_twi.S        Rohm BH1750 ambient light sensor (I2C 0x23)
```

## Building

```bash
avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o lm75_twi.o lm75_twi.S
avr-gcc -mmcu=attiny3217 -nostartfiles -o lm75_twi.elf lm75_twi.o
avr-objcopy -O ihex lm75_twi.elf lm75_twi.hex
avrdude -p t3217 -c serialupdi -P /dev/ttyUSB0 -U flash:w:lm75_twi.hex:i
```

## Notes

- Most I²C sensors need external 4.7 kΩ pull-ups on SDA/SCL if the breakout
  board does not already provide them.
- The `_gc` group codes (e.g. `TWI_MCMD_STOP_gc`) are C enums in `<avr/io.h>`
  and are not visible to the assembler, so each file defines the few it uses
  with `.equ`. The `_bm`/`_bp` symbols are preprocessor macros and work
  directly.
