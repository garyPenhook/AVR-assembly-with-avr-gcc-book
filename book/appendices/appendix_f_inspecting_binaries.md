# Appendix F: Inspecting Your Binaries

Assembling and linking turn your source into an ELF file, but an ELF file is
not the end of the story. Before you flash a part you usually want to answer
three questions:

  1. How much flash and RAM did this use?
  2. Did the assembler and linker actually produce the machine code I expected?
  3. How do I turn the ELF into something a programmer can write to flash?

The GNU AVR toolchain answers each of these with a small, sharp tool:
avr-size, avr-objdump, and avr-objcopy. The assembler (avr-as, see Appendix C),
the linker (avr-ld, see Appendix D), the debugger (avr-gdb, see Chapter 5),
and avrdude (Appendix E) are covered elsewhere. This appendix covers those three
core tools and three supporting tools---avr-nm, avr-readelf, and
avr-addr2line---that help you understand and diagnose the ELF the linker
produces.

The whole loop looks like this:

    source.S  --avr-as-->  object.o  --avr-ld-->  program.elf
                                                       |
                              +------------------------+------------------------+
                              |                        |                        |
                          avr-size                avr-objdump             avr-objcopy
                         (how big?)             (what code?)            (make .hex)
                                                                             |
                                                                         avrdude
                                                                        (flash it)


## The worked example

Every command in this appendix runs against the same small program so you can
match output to source. It blinks the user LED on PA3 of the ATtiny3217
Curiosity Nano with a crude busy-wait delay.

    ; blink.S - ATtiny3217: blink the LED on PA3 with a busy-wait delay.
    ;
    ; VPORTA is in the low I/O space, so we can reach it with the
    ; single-cycle bit instructions sbi/cbi.  Addresses are written out
    ; by hand here so the file is self-contained.

            .equ    VPORTA_DIR, 0x00        ; VPORTA.DIR  - data direction
            .equ    VPORTA_OUT, 0x01        ; VPORTA.OUT  - output drive

            .section .text
            .global main

    main:
            sbi     VPORTA_DIR, 3           ; PA3 as output
    loop:
            sbi     VPORTA_OUT, 3           ; LED on
            rcall   delay
            cbi     VPORTA_OUT, 3           ; LED off
            rcall   delay
            rjmp    loop

    delay:
            ldi     r24, lo8(40000)
            ldi     r25, hi8(40000)
    1:      sbiw    r24, 1
            brne    1b
            ret

Build it in one step with avr-gcc acting as the assembler-and-linker driver:

    avr-gcc -mmcu=attiny3217 -nostartfiles -e main blink.S -o blink.elf

The -nostartfiles flag drops the C runtime so the listings stay short and
start at address 0. This is safe on the ATtiny3217 because the AVRXMEGA3 core
resets the stack pointer to RAMEND in hardware; on classic AVRs the runtime
does that job and you would leave -nostartfiles off. A normal build (without
-nostartfiles) prepends the interrupt vector table and startup code, which
shifts every address you see below but changes nothing about how the tools are
used.


## avr-size - how much flash and RAM

Run avr-size with no options for the classic "Berkeley" format:

    $ avr-size blink.elf
       text    data     bss     dec     hex filename
         22       0       0      22      16 blink.elf

The columns mean:

    Column   Meaning
    ------   ---------------------------------------------------------------
    text     Code and read-only data that lives in flash.
    data     Initialised variables. Counts TWICE: the initial values are
             stored in flash, and a copy lives in RAM at run time.
    bss      Zero-initialised variables. RAM only, costs no flash.
    dec      text + data + bss, in decimal.
    hex      The same total in hexadecimal.

The data column is the classic trap: a byte of initialised data costs you one
byte of flash AND one byte of RAM. For flash budgeting, flash used = text +
data; for RAM budgeting, RAM used = data + bss.

The friendlier view tells you how full the device is. Pass -C and the part
name:

    $ avr-size -C --mcu=attiny3217 blink.elf
    AVR Memory Usage
    ----------------
    Device: attiny3217

    Program:      22 bytes (0.1% Full)
    (.text + .data + .bootloader)

    Data:          0 bytes (0.0% Full)
    (.data + .bss + .noinit)

Here Program is the flash figure (the ATtiny3217 has 32 KB) and Data is the
RAM figure (2 KB). This is the form to watch as a project grows; when Program
approaches 100% you are out of flash.

A wrinkle worth knowing: the percentages and the device name come from
avr-size's own internal device table, and not every build of the tool knows
the newer tinyAVR parts. The avr-size bundled with Microchip's XC8 toolchain,
for instance, prints "Device: Unknown" and omits the "% Full" figures for
attiny3217. The raw byte counts are always correct; if you want the
percentages, use the avr-size that ships with a device-aware avr-gcc/avr-libc
toolchain. The Berkeley output (avr-size with no -C) never depends on the
device table and is portable across builds.

A second gotcha: `avr-size` is part of *binutils*, not GCC. Some popular AVR
toolchains are GCC-only builds that bundle just enough binutils for the
compiler to run and omit `avr-size` (along with `addr2line`, `readelf`, and
`strings`). If `avr-size` is "command not found", install a full binutils for
AVR — or remember that `avr-objdump -h` already prints every section's size, so
you can always read the byte counts from there.

A useful habit is to print the size on every build so a sudden jump is
obvious. Make this the last line of your build rule:

    avr-size -C --mcu=attiny3217 blink.elf


## avr-objdump - see the machine code

avr-objdump is the most valuable tool in this appendix for an assembly
programmer: it shows the exact bytes the assembler emitted and disassembles
them back into mnemonics. It is how you confirm that an instruction encoded the
way Appendix B says it should, and how you check what the linker did to
relative branches.

Disassemble the code section with -d:

    $ avr-objdump -d blink.elf

    blink.elf:     file format elf32-avr

    Disassembly of section .text:

    00000000 <__ctors_end>:
       0:   03 9a           sbi     0x00, 3         ; 0

    00000002 <loop>:
       2:   0b 9a           sbi     0x01, 3         ; 1
       4:   03 d0           rcall   .+6             ; 0xc <delay>
       6:   0b 98           cbi     0x01, 3         ; 1
       8:   01 d0           rcall   .+2             ; 0xc <delay>
       a:   fb cf           rjmp    .-10            ; 0x2 <loop>

    0000000c <delay>:
       c:   80 e4           ldi     r24, 0x40       ; 64
       e:   9c e9           ldi     r25, 0x9C       ; 156

    00000010 <.L1^B1>:
      10:   01 97           sbiw    r24, 0x01       ; 1
      12:   f1 f7           brne    .-4             ; 0x10 <.L1^B1>
      14:   08 95           ret

The first block is labelled <__ctors_end> rather than <main>: the linker
places that constructor-table marker at address 0, our main lands at the same
address, and avr-objdump prints whichever symbol it finds there first. The code
is still your main.

Read one line left to right:

    address    raw bytes      mnemonic + operands     ; objdump comment
    -------    -----------    --------------------     ----------------------
      4:       03 d0          rcall  .+6               ; 0xc <delay>

  - address: byte offset of the instruction in flash.
  - raw bytes: the machine-code word, little-endian. 03 d0 is the 16-bit
    word 0xd003.
  - mnemonic: the decoded instruction. Note rcall shows .+6, a PC-relative
    offset in bytes from the NEXT instruction, not the symbol you wrote.
  - comment: avr-objdump helpfully resolves the target to an address and
    symbol, 0xc <delay>.

Three things worth pointing out in this listing:

  - The numeric local label 1: shows up as <.L1^B1>, which is how GAS spells
    its internal name for a numeric local label. You wrote 1:/1b; the assembler
    keeps it under that mangled name rather than a label you would recognise.
  - sbi 0x00, 3 and sbi 0x01, 3 are your VPORTA_DIR and VPORTA_OUT writes.
    objdump prints the raw I/O address because the .equ names are not in the
    binary; this is exactly why VPORT registers must sit in low I/O for
    sbi/cbi to reach them (see Chapter 16).
  - The two rcall delay lines encode to different offsets (.+6 and .+2) even
    though they call the same routine, because the offset is measured from
    each call site. This is the relative-branch behaviour discussed in
    Chapter 14.

If you assemble with debug info (-g), avr-objdump can interleave your source
lines with the disassembly using -S:

    avr-gcc -mmcu=attiny3217 -nostartfiles -e main -g blink.S -o blink.elf
    avr-objdump -S blink.elf

Each block of machine code is then preceded by the source line that produced
it, which is the clearest way to see how one line of assembly maps to one
instruction.

To see the layout of the file rather than the code, use -h for section
headers:

    $ avr-objdump -h blink.elf

    blink.elf:     file format elf32-avr

    Sections:
    Idx Name          Size      VMA       LMA       File off  Algn
      0 .data         00000000  00803800  00000016  0000008a  2**0
                      CONTENTS, ALLOC, LOAD, DATA
      1 .text         00000016  00000000  00000000  00000074  2**1
                      CONTENTS, ALLOC, LOAD, READONLY, CODE

This confirms .text is 0x16 (22) bytes and lives at address 0. VMA is the
run-time address and LMA is the load address. Notice .data: it is empty here
(this program has no initialised variables), but its VMA is 0x00803800 - the
AVR data-space address of RAM, 0x3800, with the 0x800000 tag avr-objdump uses
to mark "this lives in the data address space" - while its LMA is 0x16, right
after .text in flash. That VMA/LMA split is exactly the case where initialised
values are stored in flash (LMA) but used from RAM (VMA); it is how you reason
about the copy-down that startup code performs.

Common avr-objdump flags:

    Flag   Purpose
    ----   --------------------------------------------------------------
    -d     Disassemble executable (code) sections.
    -D     Disassemble ALL sections, including data.
    -S     Interleave source with disassembly (needs -g at build time).
    -h     Section headers: names, sizes, addresses.
    -t     Symbol table.
    -s     Full hex dump of section contents.
    -j .x  Restrict output to section .x (e.g. -j .text).
    -m avr Force the AVR architecture if it is not auto-detected.


## avr-objcopy - make something to flash

An ELF file carries symbols, section names, and debug information that a
programmer neither needs nor understands. avrdude wants a plain image, almost
always in Intel HEX format. avr-objcopy strips the ELF down to that image.

    $ avr-objcopy -O ihex -j .text -j .data blink.elf blink.hex

  - -O ihex selects Intel HEX output.
  - -j .text -j .data keep only the sections that actually go to flash;
    everything else (debug info, comments) is dropped.

The result is a short text file:

    $ cat blink.hex
    :10000000039A0B9A03D00B9801D0FBCF80E49CE9B4
    :060010000197F1F70895CD
    :00000001FF

Each line is one Intel HEX record. Taking the first record apart:

    :10 0000 00 039A0B9A03D00B9801D0FBCF80E49CE9 B4
     |   |    |  |                                |
     |   |    |  16 bytes of data (your code)     checksum
     |   |    record type 00 = data
     |   load address 0x0000
     byte count 0x10 = 16

The middle record holds the last 6 bytes, and :00000001FF is the
end-of-file record. Notice the data bytes match the raw bytes in the
avr-objdump listing exactly: 03 9A 0B 9A 03 D0 ... That is the whole point;
avr-objcopy changes the container, not the content.

You can flash blink.hex directly (see Appendix E):

    avrdude -c curiosity_updi -p t3217 -U flash:w:blink.hex:i

Other things avr-objcopy does:

    Command fragment                      Effect
    -----------------------------------   ------------------------------------
    -O binary blink.elf blink.bin         Raw binary image, no addresses.
                                          Useful for bootloaders and CRCs.
    -O srec ... blink.srec                Motorola S-record output.
    --gap-fill 0xFF                       Fill gaps between sections with 0xFF
                                          (erased-flash value) so the image is
                                          contiguous.
    -R .eeprom blink.elf trimmed.elf      Remove a section (here EEPROM data,
                                          which is programmed separately).
    -j .eeprom -O ihex e.elf eeprom.hex   Extract just the EEPROM section into
                                          its own hex file.

A note on size: never judge "how big is my program" from the byte count of the
.hex or .bin file. Intel HEX is ASCII and roughly doubles the size; a binary
may be padded by --gap-fill. Use avr-size for the real flash and RAM figures.


## avr-nm - list symbols and their addresses

avr-nm reads an object file or ELF and prints every symbol: its value
(usually an address in flash or RAM), type, and name. The fastest way to answer
"where did the linker put delay?" or "is this label visible to other files?" is
avr-nm.

The full output of avr-nm on blink.elf runs to about thirty lines because the
linker script populates boundary and region symbols (type A, uppercase). The
entries that come from your source are:

    value    type  name
    --------  ---  -------------------------
    00000000   T   main
    00000002   t   loop
    0000000c   t   delay
    00000010   t   .L11
    00000000   a   VPORTA_DIR
    00000001   a   VPORTA_OUT

Type codes worth knowing:

    Code   Meaning
    ----   --------------------------------------------------------
    T      Symbol in .text (code), global -- visible at link time.
    t      Symbol in .text (code), local -- invisible outside the file.
    D      Symbol in .data (initialised variable), global.
    d      Symbol in .data, local.
    B      Symbol in .bss (zero-initialised variable), global.
    b      Symbol in .bss, local.
    A      Absolute constant (linker-script boundary or region size).
    a      Absolute constant, local. .equ symbols appear with this type.
    U      Undefined -- referenced here but not defined in this file.

Uppercase is global; lowercase is local. main is T because the source
declares .global main. delay and loop are t because they have no .global
directive and cannot be linked against from another file.

Two details worth noticing:

  - VPORTA_DIR and VPORTA_OUT appear as type a. A .equ constant is not
    code or data: it is a named value resolved entirely at assembly time.
    avr-nm includes it in the symbol table so a debugger can display the
    name when it appears in an expression.

  - .L11 is avr-nm's rendering of the numeric local label 1: on line 33 of
    the source. avr-objdump renders the same symbol as <.L1^B1> -- both are
    the assembler's internal name for the same label, displayed differently by
    the two tools.

Add -n to sort by address instead of alphabetically. This shows the flash
layout in the order the linker placed things, which is easier to read when
checking function order or looking for gaps:

    $ avr-nm -n blink.elf | grep " t "
    00000002 t loop
    0000000c t delay
    00000010 t .L11

Lowercase t selects only local text symbols. Using [tT] would also produce the
many linker-generated global T entries that clutter the sorted output. To locate
a specific global symbol, grep by name:

    $ avr-nm blink.elf | grep " main$"
    00000000 T main

Add -u to print only undefined symbols. An empty result means the ELF has
no unresolved references and will link cleanly:

    $ avr-nm -u blink.elf
    (no output -- all symbols are defined)

For multi-file projects, run avr-nm -u on each .o before linking to find which
module references a missing symbol before the linker errors.


## avr-readelf - inspect the ELF structure

avr-objdump works on section contents; avr-readelf works on the ELF container
itself. The distinction matters when you want to check architecture metadata,
section flags, or program-header layout rather than the bytes those sections
hold.

The -h flag prints the ELF header:

    $ avr-readelf -h blink.elf
    ELF Header:
      Magic:   7f 45 4c 46 01 01 01 00 00 00 00 00 00 00 00 00
      Class:                             ELF32
      Data:                              2's complement, little endian
      Version:                           1 (current)
      OS/ABI:                            UNIX - System V
      ABI Version:                       0
      Type:                              EXEC (Executable file)
      Machine:                           Atmel AVR 8-bit microcontroller
      Version:                           0x1
      Entry point address:               0x0
      Start of program headers:          52 (bytes into file)
      Start of section headers:          1264 (bytes into file)
      Flags:                             0x67, avr:103
      Size of this header:               52 (bytes)
      Size of program headers:           32 (bytes)
      Number of program headers:         2
      Size of section headers:           40 (bytes)
      Number of section headers:         6
      Section header string table index: 5

The fields to verify for AVR work:

    Field           What to check
    -----------     ---------------------------------------------------------
    Machine         Should read "Atmel AVR 8-bit microcontroller". A non-AVR
                    ELF will not disassemble correctly and avrdude will refuse
                    it.
    Entry point     Address where execution begins after reset. 0x0 here
                    because -nostartfiles places main at the start of flash.
    Flags: avr:NNN  The architecture variant number. 103 is AVRXMEGA3, the
                    family containing the ATtiny3217. A mismatch between this
                    number and your target device means the code was not
                    compiled for the right core.

The -S flag prints section headers -- the same information as avr-objdump -h
but in a fixed-column format that is easier to parse with shell scripts or
Python:

    $ avr-readelf -S blink.elf
    There are 6 section headers, starting at offset 0x4f0:

    Section Headers:
      [Nr] Name       Type      Addr     Off    Size   ES Flg Lk Inf Al
      [ 0]            NULL      00000000 000000 000000 00      0   0  0
      [ 1] .data      PROGBITS  00803800 00008a 000000 00  WA  0   0  1
      [ 2] .text      PROGBITS  00000000 000074 000016 00  AX  0   0  2
      [ 3] .symtab    SYMTAB    00000000 00008c 000240 10      4   9  4
      [ 4] .strtab    STRTAB    00000000 0002cc 0001fd 00      0   0  1
      [ 5] .shstrtab  STRTAB    00000000 0004c9 000027 00      0   0  1

The Flg column records section flags:

    Flag   Meaning
    ----   ---------------------------------------------------------------
    A      Alloc -- the section occupies device memory at run time.
    X      Execute -- the CPU can fetch and run instructions from it.
    W      Write -- the section is writable (RAM).

.text is AX: code in flash that is executable. .data is WA: RAM that is
writable. The three remaining sections (.symtab, .strtab, .shstrtab) carry
no flags; they exist only in the ELF file and avr-objcopy drops them before
producing the .hex.

Building with -g adds several .debug_* sections (also flagged as no-alloc).
They do not change what goes into flash; they are debug metadata consumed by
avr-gdb and avr-addr2line.

avr-readelf is most useful when a linker script section directive or
__attribute__((section("..."))) is not behaving as expected. The -S output
shows exactly where each section landed, its actual size, and whether it
received the flags you intended.


## avr-addr2line - translate an address to source

avr-addr2line takes an address from a listing, a debugger, or a crash log and
tells you the source file and line that produced the code at that address. It
is faster than scrolling through avr-objdump -S when you only need to
cross-reference a handful of addresses.

The ELF must include debug information. Build with -g:

    avr-gcc -mmcu=attiny3217 -nostartfiles -e main -g blink.S -o blink.elf

Pass one or more addresses with -e to name the ELF file:

    $ avr-addr2line -e blink.elf 0x10
    /path/to/blink.S:33

Address 0x10 is the sbiw instruction at line 33 -- the body of the countdown
loop. avr-addr2line resolved it without opening the full disassembly.

You can give several addresses in one call, which is useful when reviewing
output from avr-gdb's info registers:

    $ avr-addr2line -e blink.elf 0x04 0x08 0x10
    /path/to/blink.S:24
    /path/to/blink.S:26
    /path/to/blink.S:33

The -f flag adds the enclosing function name above each result. addr2line takes
that name from the ELF symbol table: it reports the nearest function-typed
(STT_FUNC) symbol at or before the address. A plain assembly label is not
function-typed unless you mark it with a .type directive:

    .type main, @function
    .type delay, @function

avr-gcc emits that marking automatically for every C function. A hand-written
.S file like blink.S has none, so its labels stay untyped and addr2line -f
prints ?? in place of the name. The file and line still resolve correctly --
those come from the DWARF .debug_line table that -g always generates; only the
function name depends on the symbol type. Add a .type directive to any .S
subroutine you want addr2line -f to name.

If avr-addr2line is missing from your toolchain -- it is part of GNU binutils
and some GCC-only packages omit it -- the same information is available inside
avr-gdb: load the ELF and run info line *0x10. avr-addr2line is the faster
option when you are not already in a debug session.


## Other tools at a glance

**avr-gcc as driver.** The build command throughout this appendix is avr-gcc
rather than avr-as. avr-gcc is a compiler driver: it detects a .S file and
passes it to avr-as, then passes the resulting .o to avr-ld. It is more
convenient than calling the tools directly for single-file projects because
-mmcu=attiny3217 is written once and the driver selects the right linker
script automatically. Appendices C and D cover avr-as and avr-ld directly;
use them when you need options the driver does not expose.

**avr-ar and avr-ranlib.** These pack multiple .o files into a static library
(.a archive) and index it so the linker can extract only the objects it needs.
For most bare-metal assembly projects you list the .o files directly on the
linker command line and need no archive. If you build a reusable collection of
subroutines shared across several projects, create and index the archive with:

    avr-ar cr libfoo.a util1.o util2.o
    avr-ranlib libfoo.a

Then link against it with avr-ld ... -L. -lfoo.


## Putting it together

A typical build rule chains all of this:

    blink.elf: blink.S
        avr-gcc -mmcu=attiny3217 -nostartfiles -e main -g blink.S -o blink.elf
        avr-size -C --mcu=attiny3217 blink.elf

    blink.hex: blink.elf
        avr-objcopy -O ihex -j .text -j .data blink.elf blink.hex

    disasm: blink.elf
        avr-objdump -S blink.elf

With these three tools you can answer, for any program, exactly how much room
it takes, exactly what machine code it became, and produce exactly the file
your programmer expects, closing the gap between "it assembled" and "it runs on
the chip."
