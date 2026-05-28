# TODO

## Math Topics for AVR Assembly

7. Linear interpolation between LUT entries
8. Polynomial approximation with Horner's method
9. Fast integer square root

## Missing Subject Matter To Add Later

- Chapter 15: interpolation between LUT entries and Horner-style polynomial
  approximation. Lookup tables are covered; these two topics are not yet written.
- EEPROM / nonvolatile user data: wear limits, update patterns, checksums,
  parameter blocks, and safe write workflows.
- Watchdog and reset recovery: WDT setup, timeout choices, reset cause handling,
  and fault-counter policy.
- Fuses and device configuration: read/modify/write workflow, recovery risks,
  BOOTEND, clock-related fuses, and UPDI-safe habits.
- Practical build and linker workflow: multi-file assembly projects, map files,
  section placement, symbol exchange, and reproducible builds.
- Testing and simulation: simavr or equivalent workflows, unit-style tests for
  assembly routines, and regression checks for examples.
- C and assembly integration: callable assembly functions, inline asm constraints,
  ABI examples, structs, pointers, clobbers, and linker symbols.
- Defensive firmware: watchdog recovery, fault counters, CRC/version metadata,
  boot failure paths, and safe peripheral initialization.
- Advanced peripherals: event system, analog comparator, DAC, configurable
  custom logic, and deeper PWM patterns.

## Missing Math Topics To Add Later

- Polynomial and rational approximations beyond Horner's method
- Fixed-point matrix transforms for control and graphics-style projections
