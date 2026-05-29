# AVR Assembly Programming

[![Latest release](https://img.shields.io/github/v/release/garyPenhook/AVR-assembly-with-avr-gcc-book?label=release)](https://github.com/garyPenhook/AVR-assembly-with-avr-gcc-book/releases/latest)
[![Download PDF](https://img.shields.io/badge/download-PDF-red)](https://github.com/garyPenhook/AVR-assembly-with-avr-gcc-book/releases/latest/download/avr-assembly-programming.pdf)
[![License: CC BY-NC-ND 4.0](https://img.shields.io/badge/license-CC%20BY--NC--ND%204.0-lightgrey)](LICENSE)
![Target: ATtiny3217](https://img.shields.io/badge/target-ATtiny3217%20Curiosity%20Nano-blue)
![Toolchain: avr-gcc](https://img.shields.io/badge/toolchain-avr--gcc%20%2F%20avr--as-green)

An example-driven book about writing AVR assembly with the GNU AVR toolchain.
The book targets the ATtiny3217 Curiosity Nano and focuses on practical
firmware: registers, memory, instruction behavior, peripheral setup, debugging,
timing, and build artifacts you can inspect.

**[Download the latest PDF](https://github.com/garyPenhook/AVR-assembly-with-avr-gcc-book/releases/latest/download/avr-assembly-programming.pdf)**
&nbsp;·&nbsp; 21 chapters + appendices &nbsp;·&nbsp; runnable assembly for every topic.

Author: Dazed_N_Confused

Assistance note: ChatGPT was used for datasheet and application-note
extraction, cross-checking, and typing help. Technical claims should still be
checked against the cited Microchip documentation and local build output.

## What the Book Covers

- AVR architecture: register file, SREG, stack, program counter, memory map
- GNU assembler syntax, directives, sections, labels, macros, and objdump use
- Instruction-set basics, operand restrictions, flags, branches, skips, and ABI
- Load/store addressing, pointer registers, flash reads, and SRAM access
- Multi-byte arithmetic, multiplication, division, fixed-point, BCD, and CORDIC
- GPIO, interrupts, clock/power control, timers, USART, SPI, TWI/I2C, ADC, and
  boot/self-programming
- GDB debugging, cycle counting, optimization, linker scripts, and flashing
- Appendices for ATtiny3217 registers, instruction summaries, GAS directives,
  linker scripts, and avrdude workflows

## Target

The primary target is the ATtiny3217 Curiosity Nano using `avr-gcc`,
`avr-as`, `avr-objdump`, `avr-objcopy`, and related AVR binutils. Most concepts
carry over to other AVR parts, but register names, memory maps, interrupt
vectors, and peripheral details are ATtiny3217-specific unless noted.

## Chapters

Each chapter has prose in `book/` and matching buildable examples in `src/`.

| # | Topic | Examples |
|---|-------|----------|
| 1 | Introduction & number systems | [src/ch01_intro](src/ch01_intro), [src/ch01a_number_systems](src/ch01a_number_systems) |
| 2 | AVR architecture | — |
| 3 | GAS syntax & GDB debugging | [src/ch03_syntax](src/ch03_syntax), [src/ch03a_gdb_debugging](src/ch03a_gdb_debugging) |
| 4 | Instruction set | [src/ch04_isa](src/ch04_isa) |
| 5 | Load/store & arithmetic (unsigned, signed, multibyte, bit math, fixed-point) | [src/ch05_loadstore](src/ch05_loadstore) … [src/ch05d_bit_math](src/ch05d_bit_math) |
| 6–8 | Arithmetic, branches, subroutines | [src/ch06_arith](src/ch06_arith), [src/ch07_branches](src/ch07_branches), [src/ch08_subroutines](src/ch08_subroutines) |
| 9–10 | GPIO, interrupts, clock/power | [src/ch09_gpio](src/ch09_gpio), [src/ch10_interrupts](src/ch10_interrupts), [src/ch10a_power_clock](src/ch10a_power_clock) |
| 11–13 | Timers, USART, SPI/TWI | [src/ch11_timer](src/ch11_timer), [src/ch12_usart](src/ch12_usart), [src/ch13_spi_twi](src/ch13_spi_twi) |
| 14–15 | C/assembly integration & optimization | [src/ch14_c_asm](src/ch14_c_asm), [src/ch15_optimisation](src/ch15_optimisation) |
| 16 | UPDI & bootloader/self-programming | [src/ch16_bootloader](src/ch16_bootloader) |
| 17–19 | Bit math, real-time/DDS, CORDIC | [src/ch17_bitmath](src/ch17_bitmath), [src/ch18_realtime](src/ch18_realtime), [src/ch18a_dds](src/ch18a_dds), [src/ch19_cordic](src/ch19_cordic) |
| 20 | ADC & digital filters | [src/ch20_adc](src/ch20_adc), [src/ch20a_filters](src/ch20a_filters) |
| App. | Registers, ISA, GAS directives, linker scripts, avrdude, binary inspection | [src/appendix_f](src/appendix_f) |

Bonus example sets: [src/oled](src/oled), [src/sensors](src/sensors), and
[src/explorer](src/explorer) (Curiosity Nano Explorer board).

## Building the PDF

Requirements:

- `pandoc`
- `xelatex`
- DejaVu fonts
- Poppler tools for optional PDF validation

Build:

```sh
make pdf
```

Generated PDFs are written to:

```text
book/output/pdf/avr-assembly-programming.pdf
```

The build log is written to:

```text
book/output/pdf/build.log
```

## Source Layout

```text
book/ch##_*/ch##.md       chapter source
book/ch##_*/src/          buildable assembly examples
book/appendices/*.md      reference appendices
book/output/pdf/          generated PDFs
Makefile                  combined PDF build
TODO.md                   roadmap and missing subject matter
```

## Current Status

The book has a complete combined PDF build and includes chapters through ADC
and analog input. Some subject areas are still planned in `TODO.md`, including
EEPROM, fuses, UPDI workflows, deeper C/assembly integration,
testing/simulation, and additional advanced peripherals.
