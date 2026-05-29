# AVR Assembly Book — Task Plan

## Goal

Produce a detailed, example-driven PDF teaching AVR assembly with `avr-as` (GNU Assembler,
part of `avr-gcc` toolchain). Beginner → Advanced progression. Every concept paired with
runnable code.

## Target Toolchain

- Assembler: `avr-as` (binutils, part of `avr-gcc` suite)
- Linker: `avr-ld`
- Object copy: `avr-objcopy` (generate Intel HEX for flashing)
- Disassembler: `avr-objdump`
- Debugger: `avr-gdb` on hardware via the Curiosity Nano nEDBG (UPDI).
  Note: simavr does NOT support the ATtiny3217 (AVRxt/avrxmega3) core, so it is
  not used in this book; verify on hardware or by tracing the disassembly.
- Target MCU: ATtiny3217 (tinyAVR 1-series, avrxmega3 core)

## Chapter Outline

### Part I — Foundations

#### Chapter 1 — Why Assembly? Toolchain Setup
- What assembly is and when to use it
- Install `avr-gcc`, `avr-binutils`, `avrdude`
- Hello-world build pipeline: `.S` → `.o` → `.elf` → `.hex`
- First blink: toggle PB5 (Arduino Uno LED) — full annotated example

#### Chapter 2 — AVR Architecture Overview
- Harvard architecture: separate program / data memory
- CPU registers: R0–R31, special roles (R26–R31 = X/Y/Z pairs)
- Status Register (SREG): C, Z, N, V, S, H, T, I flags
- Stack and Stack Pointer (SP)
- Program Counter (PC)
- Diagram: register file layout

#### Chapter 3 — AVR-AS Syntax & Directives
- GAS syntax vs Intel syntax
- File structure: `.section`, `.text`, `.data`, `.bss`
- Directives: `.byte`, `.word`, `.string`, `.equ`, `.set`, `.org`
- Labels, local labels (`1:`, `1f`, `1b`)
- Comments: `;` and `/* */`
- Including header files: `#include <avr/io.h>` in `.S` files
- Example: define constants and data in flash

#### Chapter 4 — Instruction Set Basics
- Instruction categories: arithmetic, logic, branch, load/store, bit ops
- Encoding: 16-bit words (most), 32-bit (LDS/STS, CALL, JMP)
- Registers as operands
- Immediate vs register operands
- Example: add, subtract, compare two numbers

#### Chapter 5 — Load & Store
- `LD`, `LDS`, `LDD` — load from SRAM
- `ST`, `STS`, `STD` — store to SRAM
- `LPM` — load from flash (program memory)
- X/Y/Z pointer registers, pre/post increment/decrement
- Example: copy array from flash to SRAM

#### Chapter 6 — Arithmetic & Logic
- `ADD`, `ADC`, `SUB`, `SBC`, `MUL`, `MULS`, `MULSU`
- `AND`, `OR`, `EOR`, `COM`, `NEG`
- `INC`, `DEC`
- 16-bit arithmetic using register pairs
- Example: multiply two 8-bit numbers, store 16-bit result

#### Chapter 7 — Branches & Control Flow
- Unconditional: `RJMP`, `JMP`
- Conditional: `BRBS`, `BRBC`, mnemonics (`BREQ`, `BRNE`, `BRLO`, `BRSH`, etc.)
- Skip instructions: `CPSE`, `SBRC`, `SBRS`, `SBIC`, `SBIS`
- Structured loops: `for`, `while` patterns in assembly
- Example: sum array of 8-bit values with loop

#### Chapter 8 — Subroutines & Stack
- `CALL`/`RCALL`, `RET`
- `PUSH`/`POP`
- Calling convention (GCC AVR ABI)
- Frame pointer with Y register
- Example: subroutine to compute factorial (recursive)

### Part II — I/O and Peripherals

#### Chapter 9 — GPIO
- I/O register map: DDRx, PORTx, PINx
- `IN`, `OUT`, `SBI`, `CBI`
- Reading button state, debounce loop
- Example: button-controlled LED

#### Chapter 10 — Interrupts
- Interrupt vector table in `.S`
- `RETI`, `SEI`, `CLI`
- ISR prologue/epilogue: save/restore SREG and registers
- Example: INT0 external interrupt toggles LED

#### Chapter 11 — Timer/Counter
- Timer0 basics: normal, CTC, PWM modes
- Setting prescaler, configuring TCCR0A/B
- Output Compare and Overflow interrupts
- Example: 1 Hz blink using Timer0 CTC interrupt

#### Chapter 12 — USART (Serial Communication)
- USART register setup: UBRR, UCSR
- Polling TX/RX
- ISR-driven RX
- Example: echo terminal — receive byte, send back

#### Chapter 13 — SPI & TWI (I2C) Overview
- SPI master mode: SPCR, SPSR, SPDR
- TWI (I2C): TWCR, TWDR, TWSR, TWAR
- Example: write byte to SPI EEPROM (25LC010A)

### Part III — Advanced Topics

#### Chapter 14 — Mixing C and Assembly
- Call assembly subroutine from C
- Inline assembly (`asm volatile`) in C
- GCC AVR calling convention detail: which registers clobbered
- Example: C main() calls ASM fast CRC-8 routine

#### Chapter 15 — Optimisation Techniques
- Cycle counting with `avr-objdump`
- Avoid SRAM: keep variables in registers
- Loop unrolling
- Lookup tables in flash (`PROGMEM`)
- Example: optimised memcpy vs naive version — cycle comparison

#### Chapter 16 — Bootloaders
- Bootloader section: `BOOTSZ` fuse bits
- SPM instruction — self-program flash
- Minimal UART bootloader skeleton
- Example: read HEX record over UART, write page to flash

#### Chapter 17 — Bit Manipulation & Fixed-Point Math
- Shift-and-add multiply
- Fixed-point Q8.8 addition/multiplication
- BCD arithmetic
- Example: convert 16-bit binary to BCD for 7-segment display

#### Chapter 18 — Real-Time Patterns
- Cooperative task scheduler in assembly
- Deterministic ISR latency analysis
- Example: two-task scheduler with Timer1

#### Chapter 19 — CORDIC and Trig
- CORDIC rotation and vectoring modes
- BAM16 angle representation and Q1.15 vectors
- Sine, cosine, atan2, magnitude, and rotation examples
- Quadrant reduction and fixed-iteration math

### Appendices

- A: ATmega328P register reference (quick lookup)
- B: AVR instruction set summary table (opcode, cycles, flags)
- C: GAS directive reference
- D: Linker script walkthrough
- E: `avrdude` flashing cheat-sheet

## File Structure (repo layout)

```
asm_book/
├── TASK.md              ← this file
├── book/
│   ├── ch01_intro/
│   │   ├── ch01.md
│   │   └── src/
│   │       └── blink.S
│   ├── ch02_arch/
│   │   └── ch02.md
│   ...
├── build/               ← generated PDFs, object files
└── Makefile             ← build all chapters → combined PDF
```

## Build Pipeline (planned)

1. Write each chapter as Markdown with embedded code blocks
2. Code examples live in `src/` dirs — assembled and tested independently
3. `pandoc` + LaTeX → PDF with syntax highlighting (`--highlight-style=tango`)
4. Single combined PDF assembled with pandoc `--toc`

## Style Rules

- Every new instruction introduced with: opcode, operands, cycles, flags affected
- Runnable examples only — no pseudo-code without real equivalent
- Side-by-side: C equivalent shown where helpful to build intuition
- Register diagrams as ASCII art (pandoc-compatible)
- Build command shown for every example

## Status

- [ ] Chapter 1 draft
- [ ] Chapter 2 draft
- [ ] Chapter 3 draft
- [ ] Chapter 4 draft
- [ ] Chapter 5 draft
- [ ] Chapter 6 draft
- [ ] Chapter 7 draft
- [ ] Chapter 8 draft
- [ ] Chapter 9 draft
- [ ] Chapter 10 draft
- [x] Chapter 11 draft
- [x] Chapter 12 draft
- [x] Chapter 13 draft
- [x] Chapter 14 draft
- [x] Chapter 15 draft
- [x] Chapter 16 draft
- [x] Chapter 17 draft
- [x] Chapter 18 draft
- [x] Chapter 19 draft
- [x] Appendices
- [ ] Pandoc build pipeline
- [ ] Final PDF review
