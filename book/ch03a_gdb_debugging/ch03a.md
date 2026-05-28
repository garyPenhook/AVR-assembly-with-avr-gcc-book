# Chapter 3A: Debugging AVR Assembly with GDB {.unnumbered}

Assembly debugging is different from source-level debugging in a high-level
language. There is no hidden runtime to explain what happened. The evidence is
the program counter, the registers, the status flags, SRAM, I/O registers, the
stack pointer, and the instruction stream in flash.

This chapter shows how to debug the assembly style used in this book: GNU AVR
assembly syntax in `.S` files, preprocessed through `avr-gcc` and assembled by
`avr-as`. The target board is the ATtiny3217 Curiosity Nano, using its on-board
debugger over UPDI. The core habit is simple: build an ELF with symbols, keep
labels at meaningful locations, stop at instruction boundaries, inspect the CPU
state, and prove what changed after each instruction.

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

This chapter assumes `avr-gdb`. It matches the rest of the AVR GNU toolchain and
loads the AVR register set and disassembler directly.

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

## Debugging Targets Used Here

This book assumes one assembly syntax and one hardware debug board:

- source files use GNU AVR assembly accepted by `avr-as`
- the build driver is `avr-gcc`
- the debug image is the linked ELF file
- the hardware target is the ATtiny3217 Curiosity Nano and its on-board debugger

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

### 2. ATtiny3217 Curiosity Nano Hardware

The ATtiny3217 uses UPDI, the Unified Program and Debug Interface. Microchip
describes UPDI as the single-pin programming and debugging interface for this
device family. The ATtiny3217 product documentation lists the device as an
8-bit AVR running up to 20 MHz, with up to 32 KB flash, 2 KB SRAM, 256 bytes of
EEPROM, and a single-pin UPDI programming/debug interface.

The ATtiny3217 Curiosity Nano hardware guide documents the board's on-board
debugger as the programming and debugging path for the ATtiny3217 using UPDI.
That same on-board debugger also provides a virtual serial port over UART and
debug GPIO. Those are the observation paths assumed in the rest of this book.

Debugger-to-target connections on the ATtiny3217 Curiosity Nano:

| ATtiny3217 pin | Debugger function | Book use |
|----------------|-------------------|----------|
| `PA0` | `DBG0`, UPDI | program/debug lifeline |
| `PB2` | CDC RX, ATtiny3217 USART0 TX | serial output to host |
| `PB3` | CDC TX, ATtiny3217 USART0 RX | serial input from host |
| `PA3` | debug GPIO1 | LED0 and timing/debug marks |
| `PB7` | debug GPIO0 | optional timing/debug marks |

Microchip documents that these debugger connections are tri-stated when the
debugger is not actively using the interface. The board also exposes the signals
on the edge connector, but the default assumption here is the unmodified
Curiosity Nano board with the on-board debugger still connected.

Do not cut the debugger straps for the examples in this book. Microchip notes
that disconnecting those straps disables programming, debugging, virtual serial
port, and data streaming for the ATtiny3217 mounted on the board.

For this book, the practical rule is simple: treat PA0/UPDI as a debug lifeline.
Do not use it as an ordinary GPIO pin in examples unless you also explain how
the board can be recovered.

### 3. PyAvrOCD Debugging Guide

PyAvrOCD is a GDB server for 8-bit AVR targets. GDB does not talk directly to
the ATtiny3217 Curiosity Nano. GDB talks to a server over a local TCP port, and
the server talks to the board's debug probe over USB. On this board the probe
is the on-board nEDBG, and the MCU debug interface is UPDI.

The debug path is:

```text
avr-gdb or a GDB GUI
        |
        | GDB remote serial protocol on localhost:2000
        v
pyavrocd
        |
        | USB to the Curiosity Nano nEDBG probe
        v
ATtiny3217 over UPDI on PA0
```

This means there are three separate pieces to debug when a session fails:

- the ELF file and symbols that GDB sees
- the PyAvrOCD server process and its command-line options
- the physical/debug connection from nEDBG to the ATtiny3217 UPDI pin

#### Install and Sanity Check

PyAvrOCD supports several install paths. The recommended method is `pipx`, which
isolates the package in its own Python environment:

```bash
pipx install pyavrocd
pipx ensurepath
```

If `pipx` is not available, `pip install pyavrocd` also works. Pre-compiled
binary archives are published on the GitHub releases page and can be extracted
directly to `~/.local/bin/`. Any of those paths are fine as long as `pyavrocd`
and `avr-gdb` are available from the shell you use for the book examples.

Check the tools first:

```bash
pyavrocd --version
pyavrocd --help
avr-gdb --version
```

On Linux, PyAvrOCD may need udev rules before a normal user can access
Microchip debug probes. Download the rules file from
`https://pyavrocd.io/99-edbg-debuggers.rules` and copy it to
`/etc/udev/rules.d/`, then replug the board. If the board is plugged in and
PyAvrOCD still reports that no compatible tool was discovered, fix host USB
permissions before changing code, fuses, or wiring.

#### Curiosity Nano Setup

The ATtiny3217 Curiosity Nano already has the necessary debug probe on the
board. For the unmodified board:

- connect the board by USB
- leave the debugger straps intact
- leave PA0/UPDI available for programming and debugging
- do not add capacitive loads, strong resistive loads, or active circuitry to
  the UPDI line

External UPDI wiring is not needed for this board. PyAvrOCD can also work with
external probes on other boards, but the Curiosity Nano case is simpler: USB to
the board is the debug connection.

#### Build an ELF for Debugging

Debug the ELF file, not only the HEX file. The ELF carries the sections,
symbols, line information, and addresses GDB needs.

Build the companion example from `book/ch03a_gdb_debugging`:

```bash
avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -g3 -Wa,--gdwarf-2 \
    -c -o gdb_demo.o src/gdb_demo.S

avr-gcc -mmcu=attiny3217 -nostartfiles -g3 \
    -o gdb_demo.elf gdb_demo.o
```

For C or mixed C/assembly projects, PyAvrOCD's documentation recommends
debug-friendly compiler settings: use debug information, prefer `-Og` while
debugging, and avoid `-flto` and `-mrelax`. Passing `-e gdb_demo.elf` is not
just advisory: PyAvrOCD inspects the ELF and actively rejects files compiled
with `-mrelax` because that option garbles line-number information. For pure
assembly, the equivalent discipline is: keep named labels, keep line
information, and do not let the linker rewrite jump layout while you are
matching source, symbols, and addresses.

#### Start the PyAvrOCD Server

Run PyAvrOCD from the directory that contains `gdb_demo.elf`:

```bash
pyavrocd -d attiny3217 -i updi -t nedbg -p 2000 -e gdb_demo.elf
```

PyAvrOCD should connect to the probe, identify the target, start the server,
and listen for a GDB connection on port 2000.

The options used here are deliberately explicit:

| Option | Long form | Meaning |
|--------|-----------|---------|
| `-d attiny3217` | `--device attiny3217` | Selects the target MCU. This is the only mandatory option. Use `-d ?` to list all supported devices. |
| `-i updi` | `--interface updi` | Selects UPDI. This is the ATtiny3217 debug interface. |
| `-t nedbg` | `--tool nedbg` | Selects the Curiosity Nano on-board debugger. Required when multiple probes are attached. |
| `-p 2000` | `--port 2000` | Selects the TCP port where GDB connects. Port 2000 is the default. |
| `-e gdb_demo.elf` | `--elf-file gdb_demo.elf` | Lets PyAvrOCD inspect the ELF and actively reject files compiled with `-mrelax`. |
| `-v debug` | `--verbose debug` | Sets log verbosity. Levels: `critical`, `error`, `warning`, `info` (default), `debug`, `all`. |
| (none) | `--reboot-debugger` | Reboots the probe before the session. Helps when the probe appears stuck. |
| `-a` | `--attach` | Reconnects without resetting the target. Requires a prior session ended with `monitor atexit stay`. |
| `-C 750` | `--comm-speed 750` | UPDI communication speed in kbps. Default 750. Avoid values at or below 400 at 16 MHz. |

Only `-d` is mandatory. This book keeps the other options visible because
visible choices are easier to audit when several probes, ports, or target
boards are attached.

Useful variations:

```bash
pyavrocd -d attiny3217 -i updi -t nedbg -p 2001 -e gdb_demo.elf
pyavrocd -d attiny3217 -i updi -t nedbg -e gdb_demo.elf --verbose debug
pyavrocd -d attiny3217 -i updi -t nedbg -e gdb_demo.elf --reboot-debugger
```

Use a different port if another server still owns port 2000. Use verbose
logging when the server starts but the behavior is unclear. Rebooting the
debugger can help when the host-side probe state is stale.

#### Connect GDB

Open a second terminal in the same directory:

```bash
avr-gdb --nx gdb_demo.elf
```

Then connect to PyAvrOCD:

```gdb
set pagination off
set radix 16
set disassemble-next-line on
display/i $pc

target remote :2000
```

At this point GDB is connected to the server, but the target flash may still
contain an old image. Load the ELF through PyAvrOCD:

```gdb
load
```

The `load` command matters. It sends the ELF contents through PyAvrOCD so the
target flash matches the symbols, addresses, and disassembly GDB is using. A
common embedded-debugging mistake is to rebuild the ELF but forget to program
the target. After that mistake, breakpoints and symbols describe one program
while the chip runs another one.

Now break at a named label and run:

```gdb
break main
break sum_loop
break break_here
continue
```

Then debug at instruction level:

```gdb
si
info registers
x/8i $pc
x/1xb &sum_result
```

The same commands work from a GUI front end, because the GUI is still driving
GDB underneath.

#### Optional: Start a GDB Front End

PyAvrOCD can start another program after the server is up:

```bash
pyavrocd -d attiny3217 -i updi -t nedbg -p 2000 -e gdb_demo.elf --start gede
```

`--start gede` launches Gede if it is installed and in `PATH`. Gede is a GDB
front end; PyAvrOCD is still the GDB server. In Gede, configure the program as
`gdb_demo.elf`, use `avr-gdb` as the debugger, connect to `:2000`, and run the
same startup commands:

```gdb
target remote :2000
load
break main
continue
```

Do not add `monitor debugwire enable` for the ATtiny3217 Curiosity Nano. That
command is for debugWIRE targets. The ATtiny3217 uses UPDI.

#### Monitor Commands

GDB commands control GDB. `monitor` commands are passed through GDB to
PyAvrOCD. They control server behavior.

Useful commands for this book:

| Command | Use |
|---------|-----|
| `monitor help` | Print PyAvrOCD monitor help. |
| `monitor info` | Show target and debugger state. |
| `monitor version` | Show the PyAvrOCD version. |
| `monitor reset` | Reset the MCU. |
| `monitor breakpoints all` | Permit both software and hardware breakpoints (default). |
| `monitor breakpoints hardware` | Use only hardware breakpoints. |
| `monitor breakpoints software` | Use only software breakpoints. |
| `monitor load readbeforewrite` | Compare flash pages and skip unchanged writes when loading (default for UPDI). |
| `monitor load writeonly` | Write flash pages without comparing first. |
| `monitor load noinitialload` | Skip the first load when the exact image is already present. |
| `monitor erasebeforeload` | Erase flash before loading. Default on JTAG targets; ignored on debugWIRE. |
| `monitor verify enable` | Verify flash after loading pages (enabled by default). |
| `monitor verify disable` | Disable flash verification. |
| `monitor timer run` | Let timers continue running while the CPU is stopped (default). |
| `monitor timer freeze` | Freeze timers when the CPU is stopped. |
| `monitor atexit stay` | Leave the target in debug mode when the server exits. |
| `monitor atexit leave` | Leave debug mode on exit where the interface supports it. |
| `monitor singlestep safe` | Protect single stepping against interrupt surprises (default). |
| `monitor singlestep interruptible` | Allow interrupts to affect single stepping. |
| `monitor rangestepping enable` | Enable GDB range-stepping support (enabled by default). |
| `monitor caching enable` | Cache executable sections in PyAvrOCD (enabled by default). |
| `monitor onlywhenloaded enable` | Require a program to be loaded before execution is permitted (enabled by default). |

Most monitor settings can also be supplied as PyAvrOCD command-line options.
For example:

```bash
pyavrocd -d attiny3217 -i updi -t nedbg -e gdb_demo.elf --verify enable
```

For UPDI targets, PyAvrOCD uses `readbeforewrite` as the default load mode.
Unlike some other debug interfaces, PyAvrOCD defaults to letting timers continue
running while the CPU is stopped (`monitor timer run` is the default). If you
want timers frozen during single-stepping, use `monitor timer freeze`. Keep
these defaults in mind when timing-sensitive code behaves differently under
debug.

#### Persistent Attach

The normal teaching workflow is a fresh session:

1. rebuild the ELF
2. restart PyAvrOCD
3. connect GDB
4. run `load`
5. set breakpoints by symbol

For bugs that appear only after the program has been running for a while, you
may want to leave the target in debug mode and attach later. Before leaving the
first GDB session:

```gdb
monitor atexit stay
```

Later, restart PyAvrOCD with attach mode:

```bash
pyavrocd -d attiny3217 -i updi -t nedbg -p 2000 --attach
```

Then reconnect:

```gdb
target remote :2000
```

Use attach mode deliberately. It is useful when you need it, but it is a poor
default for examples because it preserves target state that a beginner may not
remember creating.

#### Troubleshooting PyAvrOCD Sessions

If the server does not start:

- Confirm the board is attached by USB and powered.
- Confirm no other program is using the debug probe.
- On Linux, check udev rules and user permissions.
- If several probes are attached, specify `--tool nedbg` and, if needed,
  `--usbsn`.
- Use `--verbose debug` and read the first critical error.
- Try `--reboot-debugger` if the probe appears stuck.

If GDB cannot connect:

- Confirm PyAvrOCD is still running.
- Confirm the port number in `target remote :PORT` matches `--port`.
- Use a different port if the old one is still busy.
- Start GDB with `--nx` once to rule out startup-script effects.

If breakpoints do not hit:

- Run `load` after every rebuild.
- Use `info address label` and `disassemble /r label` to confirm the symbol.
- Break at named labels, not guessed numeric addresses.
- Avoid `-mrelax` while debugging.
- If a reset happens while running, set breakpoints again.
- If needed, try `monitor breakpoints hardware`.

If stepping or timing looks wrong:

- Remember that stopped debugging changes timing.
- Do not single-step timing-critical peripheral sequences as proof of real-time
  behavior.
- On UPDI targets, timers continue running while the CPU is stopped by default. Use `monitor timer freeze` if you need them stopped.
- Use GPIO marks, USART output, a logic analyzer, or an oscilloscope for timing
  evidence.

If the image looks wrong:

- Rebuild the ELF.
- Restart PyAvrOCD.
- Reconnect GDB.
- Run `load`.
- Use `compare-sections` if your GDB/target combination supports it.
- Confirm with `avr-objdump -d -S gdb_demo.elf`.

If GDB stops with an unexpected signal:

| Signal | Meaning |
|--------|---------|
| `SIGHUP` | No OCD connection. The debug probe disconnected or was never enabled. |
| `SIGILL` | A `BREAK` instruction is at the current location. A software breakpoint was not restored after a previous session ended abruptly. Reflash to fix. |
| `SIGBUS` | Stack pointer is too low and threatens I/O register space. |
| `SIGSEGV` | No program is loaded. Use `load`, or set `monitor onlywhenloaded disable` if you intentionally want to run without a loaded image. |

If the MCU behaves strangely after a debug session that ended abruptly (for
example due to power loss), software breakpoints may not have been restored.
Reflash the MCU completely to recover a known-good state.

#### Persistent PyAvrOCD Options

If you always use the same set of options, create a file named
`pyavrocd.options` in the project directory and list arguments there one per
line using the `@` prefix notation:

```
@pyavrocd.options
```

Where `pyavrocd.options` contains, for example:

```text
--device attiny3217
--interface updi
--tool nedbg
--port 2000
```

Then invoke PyAvrOCD with just the ELF:

```bash
pyavrocd @pyavrocd.options -e gdb_demo.elf
```

This keeps the command short without hiding the choices from version control.

#### A Repeatable Debug Script

You can put the GDB side of the session in a small command file, for example
`gdb_demo.gdb`:

```gdb
set pagination off
set radix 16
set disassemble-next-line on
display/i $pc

target remote :2000
load
break main
break sum_loop
break break_here
continue
```

Then start the server:

```bash
pyavrocd -d attiny3217 -i updi -t nedbg -p 2000 -e gdb_demo.elf
```

And start GDB:

```bash
avr-gdb --nx -x gdb_demo.gdb gdb_demo.elf
```

This makes the debug setup repeatable. If the script stops working, inspect the
server output and the first failing GDB command before changing the assembly.

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

On the Curiosity Nano, treat breakpoints as a scarce debug resource and keep
your assembly easy to inspect statically with `avr-objdump` even when the
hardware session is not attached.

---

## Watchpoints and Data Breaks

Watchpoints stop when memory changes:

```gdb
(gdb) watch sum_result
```

On embedded targets, watchpoint support depends on the CPU and debug hardware.
If a watchpoint is implemented in hardware, there may only be a small number
available. If it is implemented in software, it may slow execution heavily.

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

The flash table is deliberately placed after the halt loop in `.text`, not
immediately after the reset vector. This example still installs only the reset
vector because interrupts remain disabled, but the table is no longer sitting
where a reader would expect interrupt-vector code.

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

For static inspection, start GDB:

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

For hardware confirmation, start PyAvrOCD in one terminal:

```bash
pyavrocd -d attiny3217 -i updi -t nedbg -p 2000 -e gdb_demo.elf
```

Then connect from GDB in a second terminal and load the ELF into target flash:

```gdb
target remote :2000
load
break main
break sum_loop
break break_here
continue
```

The `load` command programs the target through the on-board debugger. If you
also need a standalone HEX file for a separate programming tool, generate it
explicitly:

```bash
avr-objcopy -O ihex gdb_demo.elf gdb_demo.hex
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
| Curiosity Nano debugger cannot connect | UPDI wiring/fuse/power | target VCC, GND, PA0/UPDI path, fuse state |
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

- Microchip ATtiny3217 product documentation for device memory sizes and UPDI.
- Microchip ATtiny3217 Curiosity Nano Hardware User Guide sections describing
  the on-board debugger, UPDI programming/debugging, virtual serial port, and
  debug GPIO, including PA0/UPDI, PB2/PB3 CDC UART, PA3 debug GPIO1, and PB7
  debug GPIO0 connections.
- Microchip ATtiny3217 Curiosity Nano Hardware User Guide sections describing
  debugger strap disconnection and the warning that cutting the straps disables
  programming, debugging, virtual serial port, and data streaming for the
  on-board ATtiny3217.
- PyAvrOCD documentation for its role as an AVR GDB server, support for
  Curiosity Nano on-board nEDBG probes, command-line options such as `--device`,
  `--interface`, `--tool`, and `--port`, and the `avr-gdb` remote debugging
  flow through `target remote`.
- The local GDB 17.2 manual for `stepi`, `nexti`, `x/i`, `display/i $pc`,
  `info registers`, and `hook-stop`.
- The local Red Hat GDB tutorial PDF for practical startup-script behavior,
  `--nx`, `help`, `apropos`, and basic debug-session setup.
