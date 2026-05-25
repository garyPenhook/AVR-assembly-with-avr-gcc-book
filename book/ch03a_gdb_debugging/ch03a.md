# Chapter 3A: Debugging AVR Assembly with GDB {.unnumbered}

Assembly debugging is different from source-level debugging in a high-level
language. There is no hidden runtime to explain what happened. The evidence is
the program counter, the registers, the status flags, SRAM, I/O registers, the
stack pointer, and the instruction stream in flash.

This chapter shows how to use GDB as an assembly debugger. The focus is
hand-written AVR assembly for the ATtiny3217, but the habits carry over to
other AVR devices: build an ELF with symbols, keep labels at meaningful
locations, stop at instruction boundaries, inspect the CPU state, and prove
what changed after each instruction.

GDB is not the only debugger in the Microchip world. MPLAB X IDE and Microchip
Studio provide the supported graphical debug front ends for Microchip hardware.
Microchip also provides the Microchip Debugger, MDB, as a command-line
interface to MPLAB X debug tools. MDB is modeled after GDB and uses similar
debugging ideas, but it is a Microchip tool rather than GNU GDB itself. This
chapter uses GDB terminology because it is precise, scriptable, and matches the
local GDB manual included with this book.

---

## Why This Chapter Belongs Here

By this point you have seen the source format, sections, labels, symbols, and
the build flow that produces an ELF file. That is the right moment to learn
debugging. If you wait until after timers, USART, SPI, interrupts, and
bootloaders, you will have too many moving parts. If you learn GDB now, every
later chapter becomes easier to verify.

The goal is not to memorize every GDB command. The goal is to build a repeatable
inspection loop:

1. Build an ELF with useful debug information.
2. Load the ELF into GDB.
3. Stop at a named label.
4. Inspect registers, flags, memory, and disassembly.
5. Step one instruction.
6. Inspect again.
7. Explain exactly what changed.

That loop catches most assembly mistakes faster than guessing.

---

## The Files GDB Needs

GDB works from an ELF file, not from the final Intel HEX file alone.

The HEX file contains bytes to program into flash. It is good for programming
the device, but it does not carry the full symbolic view you want while
debugging. The ELF file can contain:

- section addresses
- symbol names such as `main`, `sum_loop`, and `break_here`
- line information connecting source lines to machine instructions
- relocation and address information useful to `objdump`, `avr-nm`, and GDB

For this book's assembly examples, keep the ELF file and debug that:

```bash
avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -g3 -Wa,--gdwarf-2 \
    -c -o gdb_demo.o src/gdb_demo.S

avr-gcc -mmcu=attiny3217 -nostartfiles -g3 \
    -o gdb_demo.elf gdb_demo.o
```

The important pieces are:

| Option | Purpose |
|--------|---------|
| `-mmcu=attiny3217` | Selects the device memory layout and instruction variant. |
| `-x assembler-with-cpp` | Treats the file as preprocessed assembly. |
| `-g3` | Keeps rich debug information in the object and ELF files. |
| `-Wa,--gdwarf-2` | Asks the assembler to emit DWARF line information. |
| `-nostartfiles` | Keeps the example's reset/vector code under your control. |

Do not strip the ELF you plan to debug. Stripping removes the symbolic
information that makes GDB useful.

Use `avr-objdump` beside GDB. It gives a static view of exactly what was linked:

```bash
avr-objdump -h -t -d -S gdb_demo.elf
```

That command shows section placement, symbols, raw instructions, and source
interleaving when line information is present.

---

## Keep Symbols That Help Debugging

GDB is much easier to use when the assembly file exposes useful names.

Prefer this:

```asm
.global main
.type   main, @function

main:
    ; setup

sum_loop:
    ; loop body

break_here:
    nop
```

Avoid debugging a file where every important place is an anonymous local label:

```asm
1:
    ; body
    brne 1b
```

Numeric local labels are fine for tight, obvious control flow, but they are poor
debugger landmarks. A professional assembly file has labels at state changes,
loop entries, peripheral writes, interrupt entries, error traps, and deliberate
debug stops.

For functions and major routines, add `.type name, @function`. For data you
intend to inspect, give it a symbol and place it in a named section:

```asm
.section .bss
.global sum_result
sum_result:
    .zero 1
```

Then GDB can inspect it by name:

```gdb
(gdb) x/1xb &sum_result
```

---

## Starting GDB

Use the AVR-targeted GDB when your toolchain provides it:

```bash
avr-gdb gdb_demo.elf
```

Some systems package the debugger as `avr-gdb`; others provide a multi-target
GDB that can select AVR with `set architecture`. For day-to-day AVR work,
`avr-gdb` is the clearer command because it loads the AVR register set and
disassembler directly.

Inside GDB, confirm the file:

```gdb
(gdb) info files
(gdb) info functions
(gdb) info variables
```

GDB startup scripts can change behavior. The local GDB tutorial included with
this book notes the normal startup-script order: system init file, user init
file, then the current directory's `.gdbinit`. If a debug session behaves
strangely, start once with startup scripts disabled:

```bash
avr-gdb --nx gdb_demo.elf
```

Useful startup settings for assembly work:

```gdb
set pagination off
set confirm off
set radix 16
set disassemble-next-line on
display/i $pc
```

The most important line is `display/i $pc`. GDB's own manual recommends it when
stepping by machine instruction because it keeps the next instruction visible
after every stop.

---

## Three Debugging Targets

There are three different ways to use GDB-like debugging with this material.

### 1. Static ELF Inspection

This does not run the program. It only inspects the linked ELF:

```bash
avr-gdb gdb_demo.elf
```

Useful commands:

```gdb
(gdb) disassemble /r main
(gdb) info address sum_loop
(gdb) info files
(gdb) x/12i main
```

This mode is still valuable. Many assembly bugs are visible before execution:
wrong section, unexpected instruction encoding, missing symbol, incorrect
vector placement, a branch target in the wrong place, or data linked into flash
when it was meant for SRAM.

### 2. Simulator or Emulated Target

Some AVR GDB builds support a simulator target. If yours does, the basic flow is:

```gdb
(gdb) target sim
(gdb) load
(gdb) break main
(gdb) run
```

Simulator support is toolchain-dependent. If `target sim` is unavailable in
your installed debugger, use static inspection, MPLAB X simulator, MDB, or real
hardware debugging instead.

Microchip documents the MPLAB X simulator as a discrete-event simulator for
Microchip MCU families, including AVR devices, with features such as object-code
execution, stimulus injection, trace, code coverage, and data extraction. Not
every device and peripheral is modeled, so simulator results must be checked
against the supported-device and supported-peripheral documents for the tool
version you use.

### 3. Hardware Debugging Through a Remote Target

GDB connects to embedded hardware through a remote protocol endpoint:

```gdb
(gdb) target remote :1234
```

The exact program that provides that TCP or serial endpoint depends on the debug
probe and toolchain. Once connected, the common flow is:

```gdb
(gdb) file gdb_demo.elf
(gdb) target remote :1234
(gdb) load
(gdb) break main
(gdb) continue
```

Many embedded remote targets also accept monitor commands:

```gdb
(gdb) monitor reset halt
```

Monitor commands are not standardized by GDB; they are interpreted by the remote
server. Check the debug-server documentation before assuming a command exists.

For Microchip hardware, the supported path is usually MPLAB X IDE, Microchip
Studio, or MDB. MDB is especially relevant when you want command-line debugging
or scripted tests using Microchip debug tools.

---

## Microchip Debug Paths for ATtiny3217

The ATtiny3217 uses UPDI, the Unified Program and Debug Interface. Microchip
describes UPDI as the single-pin programming and debugging interface for this
device family. The ATtiny3217 product documentation lists the device as an
8-bit AVR running up to 20 MHz, with up to 32 KB flash, 2 KB SRAM, 256 bytes of
EEPROM, and a single-pin UPDI programming/debug interface.

On the ATtiny3217 Curiosity Nano, Microchip documents an on-board debugger that
programs and debugs the ATtiny3217 using UPDI. The on-board debugger also
provides a virtual serial port over UART and debug GPIO support. MPLAB X IDE and
Microchip Studio can be used as front ends for that debugger.

On the ATtiny3217 Xplained Pro, Microchip documents an Embedded Debugger, EDBG,
that programs and debugs the ATtiny3217 using UPDI. The board also exposes a
10-pin 50-mil UPDI debug connector. In that connector, PA0 is the UPDI/RESET
connection, VCC target is present, and GND is present. Microchip notes that PA0
is configured as UPDI by default and that changing PA0 into RESET or GPIO can
disable further programming and debugging through the embedded debugger.

General UPDI hardware facts from Microchip documentation:

- UPDI is a Microchip proprietary interface for external programming and
  on-chip debugging.
- It is a single-wire, bidirectional, half-duplex asynchronous interface.
- It succeeded the older PDI two-wire interface used by AVR XMEGA devices.
- Target voltage and ground are still required even though the data interface
  itself is one wire.
- Some fuse states require high-voltage UPDI recovery, so board designs should
  not attach fragile circuitry directly to the UPDI line without considering
  recovery pulses and isolation.

For this book, the practical rule is simple: treat PA0/UPDI as a debug lifeline.
Do not use it as an ordinary GPIO pin in examples unless you also explain how
the board can be recovered.

---

## MDB: Microchip's GDB-Like Command Line

Microchip Debugger, MDB, is installed with MPLAB X IDE. Microchip describes it
as a command-line debugger interface to Microchip hardware and software
development tools. It can interact with supported Microchip probes, embedded
debuggers, the MPLAB simulator, and scripted debug sessions.

MDB is not a drop-in replacement for `avr-gdb`, but the mental model is close:

| Task | GDB idea | MDB idea |
|------|----------|----------|
| Select program | Load an ELF | Load project or image context |
| Select target | `target remote` or simulator | Select Microchip tool/simulator |
| Start execution | `run` or `continue` | Run/continue command |
| Stop execution | breakpoint/watchpoint | breakpoint/watchpoint |
| Inspect state | registers/memory/disassembly | registers/memory/disassembly |
| Automate | `.gdbinit`, command files | MDB scripts |

Use GDB when your workflow has a GDB-compatible target. Use MDB when you want
Microchip's command-line access to MPLAB X-supported debug hardware. Use the
IDE when you need the most direct vendor-supported path for configuring a probe,
fuses, memories, and device-specific debug features.

---

## Core GDB Commands for Assembly

This table is the daily working set.

| Command | Use |
|---------|-----|
| `help command` | Show built-in help for one command. |
| `apropos word` | Search command help by topic. |
| `file firmware.elf` | Load symbol and section information. |
| `info files` | Show loaded sections and entry information. |
| `info functions` | List known function symbols. |
| `info variables` | List known data symbols. |
| `break label` | Stop when execution reaches a label. |
| `hbreak label` | Request a hardware breakpoint when supported. |
| `delete` | Delete breakpoints. |
| `continue` | Resume execution until the next stop. |
| `stepi` or `si` | Execute one machine instruction, entering calls. |
| `nexti` or `ni` | Execute one machine instruction, stepping over calls when possible. |
| `finish` | Run until the current routine returns. |
| `disassemble /r label` | Show instructions and raw opcode bytes. |
| `x/8i $pc` | Examine eight instructions at the program counter. |
| `info registers` | Show register state. |
| `p/x $pc` | Print the program counter in hexadecimal. |
| `x/16xb address` | Examine 16 bytes of memory in hexadecimal. |
| `set $reg = value` | Change a register, using the target's register names. |
| `set {unsigned char}addr = value` | Patch one byte in writable memory. |

Register names are target-specific. The GDB manual explicitly points out that
`info registers` shows the canonical names for the selected machine. On AVR,
check `info registers` before assuming exactly how your GDB build names `r0`,
`r1`, `SREG`, `SP`, or `PC`.

---

## Instruction-Level Stepping

Use instruction stepping when debugging assembly:

```gdb
(gdb) break main
(gdb) continue
(gdb) display/i $pc
(gdb) info registers
(gdb) stepi
(gdb) info registers
```

The difference between `stepi` and `nexti` matters:

| Command | Behavior |
|---------|----------|
| `stepi` / `si` | Execute one instruction. If the instruction calls a subroutine, stop inside it. |
| `nexti` / `ni` | Execute one instruction, but try to step over subroutine calls. |

For branch debugging, use `stepi` until you trust the flags. A conditional
branch is only as correct as the flags set by the previous instruction.

Example:

```asm
    dec     r18
    brne    sum_loop
```

After `dec r18`, inspect `SREG` or the named flags your GDB exposes. The branch
does not test `r18` directly; it tests the Z flag produced by `DEC`.

For call/return debugging, inspect the stack pointer before and after `CALL`,
`RCALL`, `RET`, and `RETI`. On AVR, the return address is stored on the stack.
The return-address size depends on the device's program counter width, so avoid
hard-coding a stack-byte assumption across all AVR families. On the ATtiny3217,
the flash size is small enough that ordinary examples use a two-byte return
address.

---

## Reading Disassembly

GDB has two common disassembly views:

```gdb
(gdb) disassemble main
(gdb) disassemble /r main
```

The `/r` form shows raw instruction bytes as well as mnemonics. That is useful
when you are checking instruction encoding, word order, or whether the linker
relaxed a branch or call.

To look around the current program counter:

```gdb
(gdb) x/10i $pc
```

To look at a label:

```gdb
(gdb) x/12i sum_loop
```

Remember that AVR flash is word-oriented at the instruction-set level but ELF
tools and GDB often present addresses in bytes. The instruction set manual gives
instruction sizes in words; the debugger may display byte addresses. When an
address appears to move by 2 for a single instruction, that usually means one
16-bit instruction word.

---

## Inspecting Registers and Flags

The fastest way to debug AVR assembly is to predict register changes before
stepping:

```gdb
(gdb) info registers
(gdb) stepi
(gdb) info registers
```

For a small sequence:

```asm
    ldi     r19, 0x11
    ldi     r20, 0x22
    add     r19, r20
```

You should predict:

- `r19` becomes `0x33`
- `r20` stays `0x22`
- `SREG` changes according to the `ADD` result
- `PC` advances by one instruction after each single-word instruction

For flag-heavy code, write down which instruction last set the flags. Common
mistakes include:

- expecting `LDI` to set flags
- forgetting that `INC`, `DEC`, `ADD`, `SUB`, `CP`, `CPI`, `LSL`, and shifts
  affect flags
- placing a harmless-looking instruction between a compare and branch, then
  accidentally overwriting the flags
- treating carry as a generic error bit instead of the exact carry/borrow state
  produced by the last arithmetic instruction

When in doubt, single-step and read `SREG`.

---

## Inspecting SRAM

Use named symbols for SRAM locations:

```asm
.section .bss
.global sum_result
sum_result:
    .zero 1
```

Then inspect the byte:

```gdb
(gdb) x/1xb &sum_result
```

Other useful memory formats:

```gdb
(gdb) x/16xb &sum_result     # 16 bytes, hex, byte width
(gdb) x/8xh  &sum_result     # 8 halfwords
(gdb) x/4xw  &sum_result     # 4 words in GDB's display format
```

For I/O registers, use the named address from the device header or a symbol you
define yourself. Be aware that reading some peripheral registers has side
effects. Status registers often clear flags by writing a one, and some data
register reads advance FIFOs or clear interrupt states. A debugger memory window
is not always passive.

This is especially important when debugging peripherals in later chapters:

- Read the datasheet before repeatedly inspecting a status or data register.
- Know whether a flag is cleared by writing one.
- Know whether a register is synchronized to a peripheral clock domain.
- Know whether a register is protected by a configuration-change mechanism.

---

## Inspecting Flash Data

AVR has separate program and data address spaces. Instructions live in flash.
Ordinary SRAM variables live in data memory. Constants may live in flash and be
read by `LPM`.

GDB can disassemble flash reliably because instructions are the normal execution
stream:

```gdb
(gdb) x/8i main
```

Raw flash data can be more target-dependent because different tools expose AVR
program memory through different address mappings. If GDB's memory view is not
obvious, confirm flash contents with `avr-objdump`:

```bash
avr-objdump -s -j .text gdb_demo.elf
```

For assembly examples, make flash data easy to find:

```asm
.section .progmem.data, "a", @progbits
.global table_bytes
table_bytes:
    .byte 0x11, 0x22, 0x33, 0x44
```

Then use both tools:

```bash
avr-nm -n gdb_demo.elf
avr-objdump -s -j .text gdb_demo.elf
```

The default AVR linker script places program-memory input sections into the
final flash image, commonly the `.text` output section. That is why the linked
ELF is inspected with `-j .text` even though the source used `.progmem.data`.
GDB shows what the current target exposes. `objdump` shows what the ELF
contains.

---

## Breakpoints on Microcontrollers

Breakpoints are easy on a desktop process and less abstract on a
microcontroller.

A software breakpoint usually means patching code memory with a trap
instruction. On a flash-based MCU, that may require special handling because
flash is not ordinary writable SRAM. A hardware breakpoint uses on-chip debug
resources. Those resources are limited.

Practical rules:

- Prefer breakpoints at labels, not raw numeric addresses.
- Use `hbreak` when the target requires hardware breakpoints.
- Do not assume unlimited breakpoints on a small MCU.
- Keep a deliberate `break_here:` label near important end states.
- For unexpected interrupts, route unused vectors to a trap label such as
  `unexpected_interrupt: rjmp unexpected_interrupt`.
- Remove stale breakpoints when changing code layout.

Microchip's MPLAB X debugging documentation includes specific topics for
breakpoints, software breakpoints, debug disassembly, memory windows, simulator
debugging, and device-specific debug resources. Use those documents when the
behavior depends on a particular Microchip probe or device.

---

## Watchpoints and Data Breaks

Watchpoints stop when memory changes:

```gdb
(gdb) watch sum_result
```

On embedded targets, watchpoint support depends on the CPU and debug hardware.
If a watchpoint is implemented in hardware, there may only be a small number
available. If it is implemented in software, it may slow execution heavily or be
unavailable on a remote target.

When watchpoints are limited, instrument the assembly instead:

```asm
store_result:
    sts     sum_result, r19
break_after_store:
    nop
```

Then break at `break_after_store`.

The label costs nothing in the final instruction stream unless you add an
instruction for it. Labels are free debugging handles.

---

## Debugging the Stack

Stack bugs are common in assembly because the assembler will not protect you
from an unbalanced `PUSH`, `POP`, `CALL`, `RET`, interrupt entry, or manual stack
write.

Before stepping through subroutines, initialize the stack pointer:

```asm
    ldi     r16, lo8(RAMEND)
    out     SPL, r16
    ldi     r16, hi8(RAMEND)
    out     SPH, r16
```

Then in GDB:

```gdb
(gdb) info registers
(gdb) p/x $sp
(gdb) x/16xb $sp
```

Register naming can vary, so use `info registers` to confirm whether your GDB
build calls the stack pointer `$sp`, shows `SPL`/`SPH`, or exposes both forms.

Checklist for stack debugging:

- Is `SP` initialized before the first `CALL`, `PUSH`, or interrupt?
- Does every `PUSH` have a matching `POP` on every exit path?
- Is `SREG` saved before enabling nested behavior or modifying flags in an ISR?
- Does the routine return with `RET` while an ISR returns with `RETI`?
- Did the code accidentally store ordinary data into the current stack area?

If a return jumps to nonsense, inspect the bytes at the stack pointer before the
return instruction. The return address is the evidence.

---

## Debugging Interrupts

Interrupt debugging requires more discipline than straight-line code.

Give every vector a visible target:

```asm
.section .vectors, "ax", @progbits
__vectors:
    jmp     main
    jmp     unexpected_interrupt
    jmp     tca0_ovf_isr
```

Give every ISR a visible entry and exit:

```asm
.global tca0_ovf_isr
.type   tca0_ovf_isr, @function

tca0_ovf_isr:
    push    r16
    in      r16, SREG
    push    r16

    ; ISR body

tca0_ovf_isr_exit:
    pop     r16
    out     SREG, r16
    pop     r16
    reti
```

Then you can use:

```gdb
(gdb) break tca0_ovf_isr
(gdb) break tca0_ovf_isr_exit
(gdb) continue
```

At ISR entry, inspect:

- `PC`
- `SP`
- saved return address bytes
- `SREG`
- peripheral interrupt flag register
- interrupt enable register

At ISR exit, inspect:

- whether the peripheral flag was cleared correctly
- whether saved registers were restored
- whether `SREG` was restored
- whether the stack pointer returned to its entry value
- whether the final instruction is `RETI`, not `RET`

When an interrupt never fires, debug in this order:

1. Is the peripheral clocked?
2. Is the peripheral configured?
3. Is the peripheral interrupt flag set?
4. Is the peripheral interrupt enable bit set?
5. Is the global interrupt enable bit set in `SREG`?
6. Is the vector table at the address the CPU is using?
7. Does the vector point to the intended ISR label?

---

## Debugging Peripheral Code

For GPIO, timers, USART, SPI, TWI, and NVM code, the debugger can mislead you if
you inspect only the instruction stream. Peripheral state often changes outside
the CPU pipeline.

Use a three-part method:

1. Step the instruction that writes the control register.
2. Inspect the written register if it is safe to read.
3. Confirm the external effect when possible.

For example, after writing `PORTA_DIRSET`, read back the relevant direction
state. After writing `PORTA_OUTTGL`, inspect the output latch and check the pin
or LED. After enabling a timer, inspect the timer's control register, then let
time pass and inspect the count or interrupt flag.

For communication peripherals, combine GDB with a second observation path:

- virtual COM port for USART
- logic analyzer for SPI/TWI
- oscilloscope for timing-sensitive pins
- Microchip Data Visualizer when using supported board debug features

GDB tells you what the CPU did. External tools tell you what the circuit saw.

---

## A Minimal Assembly Debug Example

The companion file `src/gdb_demo.S` is intentionally small. It:

- installs a reset vector
- initializes the stack pointer
- loads four flash bytes with `LPM`
- accumulates them into an 8-bit sum
- stores the result in SRAM
- stops at a named debug label

Build it from this chapter directory:

```bash
avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -g3 -Wa,--gdwarf-2 \
    -c -o gdb_demo.o src/gdb_demo.S

avr-gcc -mmcu=attiny3217 -nostartfiles -g3 \
    -o gdb_demo.elf gdb_demo.o
```

Inspect it statically:

```bash
avr-nm -n gdb_demo.elf
avr-objdump -d -S gdb_demo.elf
```

Start GDB:

```bash
avr-gdb --nx gdb_demo.elf
```

Then run these commands:

```gdb
set pagination off
set radix 16
set disassemble-next-line on
display/i $pc

break main
break sum_loop
break break_here

info files
disassemble /r main
```

If your GDB has a simulator:

```gdb
target sim
load
run
```

If you are connected to a hardware remote target:

```gdb
target remote :1234
load
continue
```

At `sum_loop`, step one instruction at a time:

```gdb
info registers
si
info registers
x/8i $pc
```

At `break_here`, inspect the result:

```gdb
x/1xb &sum_result
```

The expected result is `0xaa` because:

```text
0x11 + 0x22 + 0x33 + 0x44 = 0xaa
```

If the result differs, debug from evidence:

- Was `Z` initialized to the flash table address?
- Did `LPM r20, Z+` load the expected byte?
- Did `ADD r19, r20` update the accumulator?
- Did `DEC r18` set Z only on the final iteration?
- Did `BRNE sum_loop` branch exactly three times?
- Did `STS sum_result, r19` write SRAM?

Do not guess. Step and inspect.

---

## A Useful `.gdbinit` for AVR Assembly

For a project directory, this is a good starting point:

```gdb
set pagination off
set confirm off
set radix 16
set disassemble-next-line on
display/i $pc

define regs
    info registers
end

define around
    x/8i $pc
end

define hook-stop
    x/i $pc
end
```

The `hook-stop` command runs every time execution stops. Keep it short. If it
prints too much, stepping becomes noisy.

Start with `--nx` when you want to rule out startup-script effects:

```bash
avr-gdb --nx gdb_demo.elf
```

Start normally when you want the project helpers:

```bash
avr-gdb gdb_demo.elf
```

---

## Failure Patterns and What to Inspect

| Symptom | Likely area | First inspection |
|---------|-------------|------------------|
| Program starts at the wrong code | vector table or entry address | `info files`, `x/4i 0` |
| Breakpoint never hits | wrong symbol, optimized/changed layout, wrong target image | `info break`, `info address label`, `compare-sections` if supported |
| Branch goes the wrong way | flags | `info registers` before and after the flag-setting instruction |
| Return jumps to nonsense | stack corruption | `p/x $sp`, `x/16xb $sp`, inspect push/pop balance |
| SRAM variable unchanged | store not reached or wrong address | break before `STS`, inspect pointer/address |
| `LPM` reads unexpected value | flash table address or address-space mapping | `avr-nm`, `avr-objdump -s`, inspect `Z` |
| ISR never runs | interrupt enable chain | peripheral flag, peripheral enable bit, global I bit, vector |
| Debug probe cannot connect | UPDI wiring/fuse/power | target VCC, GND, PA0/UPDI path, fuse state |
| Debug works once then stops | UPDI pin reused or fuse changed | check PA0 configuration and fuse writes |

The point of the table is not to replace thinking. It gives you the first piece
of evidence to collect.

---

## Professional Debug Habits

Write assembly so it can be debugged:

- Use stable labels at important states.
- Keep one instruction per source line.
- Use named SRAM symbols for values you will inspect.
- Keep reset and interrupt vectors readable.
- Save and restore registers in a visible order.
- Keep deliberate trap labels for impossible paths.
- Build with debug information during development.
- Keep the ELF, map file, and objdump listing for every important test image.
- Record the debugger commands that prove a bug is fixed.

When a bug is hard, make the code more observable. Add a label. Store an
intermediate value. Toggle a debug pin. Split a dense block into smaller named
blocks. Assembly is not self-explaining unless you make the important states
visible.

---

## Source Notes

Facts in this chapter are based on:

- Microchip ATtiny3217 product documentation for device memory sizes, UPDI, and
  supported development tools.
- Microchip ATtiny3217 Curiosity Nano Hardware User Guide sections describing
  the on-board debugger, UPDI programming/debugging, virtual serial port, and
  debug GPIO.
- Microchip ATtiny3217 Xplained Pro documentation for the UPDI connector and
  PA0/UPDI default behavior.
- Microchip Power Debugger documentation for UPDI as a single-wire,
  bidirectional, half-duplex interface for external programming and on-chip
  debugging.
- Microchip MPLAB X debugging documentation for breakpoints, debug disassembly,
  memory inspection, simulator, and UPDI/debugWIRE topics.
- Microchip Debugger, MDB, documentation for the command-line debugger role,
  MPLAB X installation path, scripting purpose, and GDB-like command model.
- The local GDB 17.2 manual for `target remote`, `stepi`, `nexti`, `x/i`,
  `display/i $pc`, `info registers`, `set architecture`, and `hook-stop`.
- The local Red Hat GDB tutorial PDF for practical startup-script behavior,
  `--nx`, `help`, `apropos`, and basic debug-session setup.
