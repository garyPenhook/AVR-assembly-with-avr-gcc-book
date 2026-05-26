# AVR Assembly Programming

An example-driven book about writing AVR assembly with the GNU AVR toolchain.
The book targets the ATtiny3217 Curiosity Nano and focuses on practical
firmware: registers, memory, instruction behavior, peripheral setup, debugging,
timing, and build artifacts you can inspect.

Author: Dazed_N_Confused

## What the Book Covers

- AVR architecture: register file, SREG, stack, program counter, memory map
- GNU assembler syntax, directives, sections, labels, macros, and objdump use
- Instruction-set basics, operand restrictions, flags, branches, skips, and ABI
- Load/store addressing, pointer registers, flash reads, and SRAM access
- Multi-byte arithmetic, multiplication, division, fixed-point, BCD, and CORDIC
- GPIO, interrupts, timers, USART, SPI, TWI/I2C, ADC, and boot/self-programming
- GDB debugging, cycle counting, optimization, linker scripts, and flashing
- Appendices for ATtiny3217 registers, instruction summaries, GAS directives,
  linker scripts, and avrdude workflows

## Target

The primary target is the ATtiny3217 Curiosity Nano using `avr-gcc`,
`avr-as`, `avr-objdump`, `avr-objcopy`, and related AVR binutils. Most concepts
carry over to other AVR parts, but register names, memory maps, interrupt
vectors, and peripheral details are ATtiny3217-specific unless noted.

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
book/output/pdf/avr-assembly-programming-v1.5.pdf
book/output/pdf/avr-assembly-programming.pdf
```

The build log is written to:

```text
book/output/pdf/build-v1.5.log
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
EEPROM, clock/power, fuses, UPDI workflows, deeper C/assembly integration,
testing/simulation, and additional advanced peripherals.
