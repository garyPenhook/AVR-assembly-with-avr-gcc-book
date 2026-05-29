# TODO

## Math Topics for AVR Assembly

7. [DONE] Linear interpolation between LUT entries (ch15, interp8 / lut_interp.S)
8. [DONE] Polynomial approximation with Horner's method (ch15, horner8 / horner.S)
9. [DONE] Fast integer square root (ch17, isqrt16 / src/ch17_bitmath/isqrt16.S).
   Digit-by-digit, no MUL/divide; algorithm verified exhaustively against
   floor(sqrt) for all 0..65535 via a host-C model; disassembly matches source.

## Missing Subject Matter To Add Later

- [DONE] Chapter 15: interpolation between LUT entries and Horner-style
  polynomial approximation. Added sections "Interpolating Between Table Entries"
  (interp8 / src/lut_interp.S, MULSU-based) and "Horner's Method for Polynomials"
  (horner8 / src/horner.S). Disassembly and symbol sizes verified against the
  real linked bench.elf (avr-gcc 16.1.0 / binutils 2.45).
- EEPROM / nonvolatile user data: wear limits, update patterns, checksums,
  parameter blocks, and safe write workflows.
- Watchdog and reset recovery: WDT setup, timeout choices, reset cause handling,
  and fault-counter policy.
- Fuses and device configuration: read/modify/write workflow, recovery risks,
  BOOTEND, clock-related fuses, and UPDI-safe habits.
- Practical build and linker workflow: multi-file assembly projects, map files,
  section placement, symbol exchange, and reproducible builds.
- Toolchain binary inspection (new appendix "Appendix F: Inspecting Your
  Binaries", appendix_f_inspecting_binaries.md), built around one consistent
  worked binary (blink.S on PA3) so all output matches:
  [DONE] Tier 1 essential: avr-objdump (-d/-S/-h), avr-objcopy (-O ihex),
         avr-size (-C --mcu=).
  [DONE] Tier 2 supporting: avr-nm, avr-readelf, avr-addr2line.
  [DONE] Tier 3 brief/skip: avr-gcc as assembler/linker driver (sidebar),
         avr-ar/ranlib (one line), skip c++filt/strings.
  Already covered: avr-as (App C), avr-ld (App D), avrdude (App E),
  avr-gdb (ch03a). Also consider an inline objdump/size "look at what you just
  made" sidebar early in ch03.
  NOTE: Tier 1 listings verified against real avr-gcc 16.1.0 / binutils output;
  worked source at src/appendix_f/blink.S (build: avr-gcc -mmcu=attiny3217
  -nostartfiles -e main blink.S -o blink.elf). Verified exactly: avr-objdump -d
  (__ctors_end label, fb cf rjmp, .L1^B1), avr-objcopy .hex (B4 checksum),
  avr-size Berkeley (22 0 0 22 16). NOT fully verifiable here: avr-size -C
  device name + "% Full" -- the only avr-size on this box is the XC8 build,
  which prints "Device: Unknown" / no percent for attiny3217; appendix shows
  the device-aware output and notes the XC8 wrinkle. avr-size is absent from
  ~/.local/bin; it lives at /opt/microchip/xc8/.../avr/bin.
- Testing and simulation: unit-style tests for assembly routines and regression
  checks for examples. NOTE: simavr does not support the ATtiny3217 (AVRxt /
  avrxmega3) core, so it is not an option here; rely on on-hardware avr-gdb
  (Curiosity Nano nEDBG) or host-side algorithm models for verification.
- C and assembly integration: callable assembly functions, inline asm constraints,
  ABI examples, structs, pointers, clobbers, and linker symbols.
- Defensive firmware: watchdog recovery, fault counters, CRC/version metadata,
  boot failure paths, and safe peripheral initialization.
- Advanced peripherals: event system, analog comparator, DAC, configurable
  custom logic, and deeper PWM patterns.

## Missing Math Topics To Add Later

- Polynomial and rational approximations beyond Horner's method
- Fixed-point matrix transforms for control and graphics-style projections
