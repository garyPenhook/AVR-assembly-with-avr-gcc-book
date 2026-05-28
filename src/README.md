# Book Source Code

This directory contains all assembly source files from the book
**AVR Assembly Programming** (ATtiny3217 / Curiosity Nano).

Files are organised by the chapter that introduces and explains them.
Each subdirectory name matches the corresponding chapter directory in `book/`.

## Contents

```
ch01_intro/
    blink.S                 LED blink — first bare-metal firmware

ch01a_number_systems/
    number_systems.S        Binary, hex, and two's-complement examples

ch03_syntax/
    syntax_demo.S           GAS assembler syntax and directive examples

ch03a_gdb_debugging/
    gdb_demo.S              GDB remote debugging walkthrough target

ch04_isa/
    arithmetic.S            ISA arithmetic instruction examples

ch05_loadstore/
    loadstore.S             Load and store addressing modes

ch05a_unsigned_arith/
    unsigned_arith.S        Unsigned 8-bit and 16-bit arithmetic

ch05b_signed_arith/
    signed_arith.S          Signed arithmetic and overflow detection

ch05c_multibyte_arith/
    multibyte_arith.S       Multi-byte (24-bit and 32-bit) arithmetic

ch05d_bit_math/
    bit_math.S              Bit manipulation and shift operations

ch06_arith/
    arith16.S               16-bit arithmetic patterns

ch07_branches/
    control.S               Conditional branches and loop patterns

ch08_subroutines/
    subroutines.S           Call/return, stack discipline, local variables

ch09_gpio/
    gpio.S                  GPIO input, output, and VPORT fast access

ch10_interrupts/
    interrupts.S            Interrupt vector table and ISR structure

ch10a_power_clock/
    clock_prescale.S        CLKCTRL prescaler and clock configuration
    sleep_pit.S             Sleep modes and RTC/PIT wakeup

ch11_timer/
    timer_ctc.S             TCA0 timer: CTC and PWM modes

ch12_usart/
    usart_echo.S            USART0 transmit/receive at 9600 baud

ch13_spi_twi/
    spi_eeprom.S            SPI0 bit-bang and hardware SPI to EEPROM

ch14_c_asm/
    crc8.S                  CRC-8 routine callable from C (ABI example)

ch15_optimisation/
    bench_harness.S         Cycle-count benchmark harness
    lut_sin.S               Flash lookup table for sine approximation
    memcpy_fast.S           Optimised block copy using MOVW and LPM
    memcpy_naive.S          Baseline byte-at-a-time block copy

ch16_bootloader/
    bootloader.S            NVMCTRL self-programming bootloader
    nvmctrl_write.S         Flash page write and erase primitives
    selfupdate.S            Application-side firmware update trigger

ch17_bitmath/
    bin16_to_bcd.S          Binary to BCD conversion (double-dabble)
    display.S               7-segment display driver
    fixedpoint.S            Fixed-point multiply and format conversion
    mul8u.S                 8x8 unsigned multiply using MUL

ch18_realtime/
    scheduler.S             Two-task cooperative scheduler (blocking UART)
    scheduler_nb.S          Non-blocking UART variant with ring buffer

ch18a_dds/
    dds.S                   Direct Digital Synthesis — 440 Hz sine on PB0

ch19_cordic/
    cordic_helpers.S        CORDIC signed 16-bit shift helper and skeleton

ch20_adc/
    adc_poll.S              ADC0 single-conversion polling loop
    adc_freerun.S           ADC0 free-running mode
    adc_accum16.S           ADC0 16-sample hardware accumulation
    adc_window.S            ADC0 window comparator
    adc_event_pit.S         RTC/PIT event-triggered ADC conversion

ch20a_filters/
    filters.S               Integer filter library: EMA, box, median, PID
```

## Building

All files target the **ATtiny3217** (`-mmcu=attiny3217`).
The standard build line is:

```bash
avr-gcc -mmcu=attiny3217 -nostartfiles -nodefaultlibs -o out.elf <file.S>
avr-objcopy -O ihex out.elf out.hex
avrdude -p t3217 -c serialupdi -P /dev/ttyUSB0 -U flash:w:out.hex:i
```

Files that are library/helper routines rather than complete firmware images
(e.g. `cordic_helpers.S`, `filters.S`) should be linked with `-Wl,-r`
(relocatable output) for inspection, or linked with a calling application.

## Hardware

- **MCU:** ATtiny3217
- **Board:** Curiosity Nano (nEDBG on-board debugger)
- **Programmer:** SerialUPDI via on-board CDC or external USB-UART adapter
- **CPU clock:** 3,333,333 Hz (internal 20 MHz oscillator / 6, default Nano setting)
