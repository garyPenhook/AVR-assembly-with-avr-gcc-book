# Linker Script Walkthrough

The linker script tells `avr-ld` where to place each section in the output ELF
file and ultimately in the device's address space. For most projects `avr-gcc`
selects a built-in script automatically via `-mmcu=`. Understanding linker
scripts is necessary when:

- Writing a bootloader (section placement at a specific flash address).
- Placing variables in a specific SRAM region.
- Using `.noinit` for variables that survive a software reset.
- Adding custom sections (e.g., a parameter page at a known flash address).

> **Note on the target device**: the worked examples below use the ATmega328P
> because its memory map is the one most readers have seen. The concepts are
> identical for the book's ATtiny3217, but two numbers change: flash is still
> 32 KB (0x0000–0x7FFF), while SRAM is 2 KB at hardware address 0x3800, so the
> `avr-ld` data origin is **0x803800** (not 0x800100) and RAMEND is 0x803FFF.
> Substitute those values, and `-mmcu=attiny3217`, when adapting a script.

---

## Anatomy of a Linker Script

A linker script has three main constructs:

```
MEMORY { }        — declares memory regions (name, origin, length)
SECTIONS { }      — maps input sections to output sections and memory regions
PROVIDE() / ENTRY() — define special symbols and the entry point
```

### Minimal AVR Linker Script

```ld
/* minimal_avr.ld — bare-bones script for ATmega328P */

MEMORY
{
  flash  (rx)  : ORIGIN = 0x000000, LENGTH = 32K
  sram   (rw!x): ORIGIN = 0x800100, LENGTH = 2K
}

SECTIONS
{
  /* Interrupt vector table — must be at flash origin */
  .vectors :
  {
    KEEP(*(.vectors))
  } > flash

  /* Executable code */
  .text :
  {
    *(.text)
    *(.text.*)
  } > flash

  /* Read-only data (constants accessed via LPM) */
  .rodata :
  {
    *(.rodata)
    *(.rodata.*)
  } > flash

  /* Initialised data: stored in flash, copied to SRAM at startup */
  .data :
  {
    _data_start = .;
    *(.data)
    *(.data.*)
    _data_end = .;
  } > sram AT > flash          /* VMA in sram, LMA in flash */

  /* Zero-initialised data: only reservation in SRAM */
  .bss :
  {
    _bss_start = .;
    *(.bss)
    *(.bss.*)
    *(COMMON)
    _bss_end = .;
  } > sram

  /* Variables preserved across software reset (not zeroed at startup) */
  .noinit (NOLOAD) :
  {
    *(.noinit)
  } > sram

  /* Stack: grows downward from RAMEND */
  _stack_top = ORIGIN(sram) + LENGTH(sram) - 1;
}
```

---

## MEMORY Region Flags

```
r   — readable
w   — writable
x   — executable
!   — negate following flags

Common combinations:
  (rx)   — read-execute (flash)
  (rw!x) — read-write, not executable (SRAM)
  (rx!w) — read-execute, not writable (flash, explicit)
```

---

## Address Spaces on AVR

AVR uses a **Harvard architecture** with separate address spaces:

```
Flash (program memory):
  avr-ld uses byte addresses with origin 0x000000
  ATmega328P: 0x000000–0x007FFF (32 KB)

SRAM (data memory):
  avr-ld uses byte addresses with origin 0x800000 + hardware_offset
  ATmega328P hardware SRAM starts at 0x0100
  avr-ld SRAM origin: 0x800100

  Registers:   0x0000–0x001F (R0–R31) — not in linker script
  I/O:         0x0020–0x005F — not in linker script
  Ext I/O:     0x0060–0x00FF — not in linker script
  SRAM:        0x0100–0x08FF (2 KB on ATmega328P)
```

The `0x800000` offset is an avr-ld convention to distinguish data addresses
from code addresses in the ELF file. The hardware only sees the lower 16 bits.

---

## VMA vs LMA

**VMA** (Virtual Memory Address): where the section lives at runtime (SRAM for
`.data`).

**LMA** (Load Memory Address): where the section is stored in the ELF output
(flash for `.data`, since flash is what gets programmed).

```ld
.data :
{
  _data_start = .;        /* VMA: SRAM address where data lives at runtime */
  *(.data)
  _data_end = .;
} > sram AT > flash        /* LMA: in flash, immediately after .rodata      */
```

The startup code (`__init` in avr-libc) copies `.data` from its LMA (flash)
to its VMA (SRAM) before `main()` runs:

```asm
/* avr-libc __init pseudo-code */
    ldi   ZL, lo8(_data_lma_start)     /* source: flash LMA */
    ldi   ZH, hi8(_data_lma_start)
    ldi   YL, lo8(_data_start)         /* dest: SRAM VMA */
    ldi   YH, hi8(_data_start)
1:  lpm   r0, Z+
    st    Y+, r0
    cpi   ZL, lo8(_data_lma_end)
    brne  1b
```

If you use `-nostartfiles`, **you must perform this copy yourself** if any
`.data` variables are used. The simplest approach: avoid initialised variables
entirely, or use `.equ` constants in flash and load them explicitly.

---

## KEEP()

The garbage-collector (`--gc-sections`) removes unreferenced sections. `KEEP()`
prevents this:

```ld
KEEP(*(.vectors))    /* never discard the vector table */
```

When building with `avr-gcc -Wl,--gc-sections` (common for size optimisation),
sections not reachable from the entry point are removed. `KEEP()` forces
retention regardless of reachability.

---

## Bootloader Placement

Place the bootloader at the boot section start address by overriding `.text`
origin:

```bash
avr-gcc -Wl,--section-start=.text=0x7C00 ...
```

Or in a dedicated linker script:

```ld
/* bootloader.ld */
MEMORY
{
  boot_flash (rx) : ORIGIN = 0x007C00, LENGTH = 1K
  sram       (rw!x): ORIGIN = 0x800100, LENGTH = 2K
}

SECTIONS
{
  .text : { *(.vectors) *(.text) *(.text.*) } > boot_flash
  .bss  : { *(.bss) }                         > sram
}
```

```bash
avr-gcc -mmcu=atmega328p -nostartfiles \
        -T bootloader.ld \
        -o bootloader.elf bootloader.S
```

---

## Parameter Page at Fixed Flash Address

Store calibration data at a known, fixed flash address so the application can
find it regardless of code size changes:

```ld
SECTIONS
{
  /* ... normal sections ... */

  .params :
  {
    *(.params)
  } > flash
  . = 0x7000;         /* force next section to start at 0x7000 */
  .calibration :
  {
    KEEP(*(.calibration))
  } > flash
}
```

In source:

```asm
.section .calibration
cal_offset: .word 0x0032    /* factory calibration: ADC offset */
cal_gain:   .word 0x0100    /* Q8.8 gain factor */
```

Access at runtime:

```asm
ldi   ZL, lo8(cal_offset)
ldi   ZH, hi8(cal_offset)
lpm   r24, Z+
lpm   r25, Z        /* r25:r24 = cal_offset value */
```

---

## .noinit Section

Variables in `.noinit` are **not zeroed** at startup — they retain whatever
value was in SRAM before reset. Useful for reset reason tracking:

```asm
.section .noinit,"aw",@nobits
reset_reason: .byte 0    /* written before software reset; survives it */
```

Application writes a code before resetting:

```asm
ldi   r16, 0xAA
sts   reset_reason, r16
/* ... trigger watchdog reset ... */
```

After reset, check `reset_reason` before the BSS clear to determine why the
device restarted. BSS clear (zeroing `.bss`) happens in `__init` — `.noinit`
is placed in a separate section that `__init` never touches.

---

## Useful Linker Symbols

These symbols are defined by the default avr-gcc linker script and available
in assembly via `lo8()`/`hi8()`:

```
Symbol             Value
──────────────────────────────────────────────────────────────────────────────
__data_start       VMA start of .data in SRAM
__data_end         VMA end of .data in SRAM
__data_load_start  LMA of .data in flash (copy source for __init)
__bss_start        Start of .bss in SRAM
__bss_end          End of .bss in SRAM
__heap_start       Start of heap (after .bss)
__stack            Initial stack pointer value (= RAMEND)
__TEXT_REGION_ORIGIN__ Start of .text (usually 0)
__DATA_REGION_ORIGIN__ Start of SRAM (usually 0x800100)
```

Access in assembly:

```asm
ldi   r26, lo8(__bss_start)
ldi   r27, hi8(__bss_start)
ldi   r24, lo8(__bss_end - __bss_start)  /* BSS length */
```

---

## Inspecting Linker Output

```bash
# Show section layout (addresses, sizes)
avr-objdump -h firmware.elf

# Show all symbols with addresses
avr-nm --numeric-sort firmware.elf

# Show memory map (verbose linker output)
avr-gcc -Wl,-Map=firmware.map ... && cat firmware.map

# Show disassembly with source interleaved
avr-objdump -dS firmware.elf

# Verify flash usage
avr-size --mcu=atmega328p --format=avr firmware.elf
```

Sample `avr-size` output with AVR format:

```
AVR Memory Usage
────────────────────────────────────────────────────────
Device: atmega328p

Program:    486 bytes (1.5% Full)
(.text + .data + .bootloader)

Data:         3 bytes (0.1% Full)
(.data + .bss + .noinit)
```

---

## Common Linker Errors

```
Error                                  Cause / Fix
──────────────────────────────────────────────────────────────────────────────
undefined reference to `symbol'        Symbol not defined in any linked file;
                                       add the .S or .o file that defines it.

relocation truncated to fit:           Branch offset exceeds range (e.g. RJMP
R_AVR_13_PCREL against `symbol'        only reaches ±2KB); use JMP or
                                       reorganise code.

section `.text' will not fit in        Total code exceeds flash; reduce size
region `flash'                         or use a larger device.

cannot find entry symbol reset_handler Define reset_handler or use
                                       -e reset_handler linker flag.

multiple definition of `__vector_N'   Two .S files both define the same ISR
                                       vector entry; remove the duplicate.
```
