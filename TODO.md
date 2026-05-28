# TODO

## Math Topics for AVR Assembly

1. Fixed-point arithmetic on AVR
4. Fixed-point formats: Q8.8, Q1.15, and scaling conventions
5. Rounding, saturation, overflow, and quantization error
6. Fast multiply and divide techniques
7. Lookup tables and interpolation
8. Polynomial approximation with Horner's method
9. Fast integer square root and vector math
10. Coordinate transforms and projections
11. CORDIC for sine, cosine, atan2, and vector rotation
12. DDS and phase accumulator math
13. Integer filters for ADC and control
14. Fixed-point PID math
15. Calibration math in fixed-point
16. Timer, prescaler, baud-rate, and PWM scaling math
17. Modular arithmetic for wraparound counters and phase
18. BCD and decimal conversion math
19. Checksums, CRCs, and other integrity math

## Chapter Roadmap

- Chapter 1: toolchain setup, simulator workflow, and detailed GDB usage
- Chapter 4: number systems, integer representation, and basic arithmetic rules
- Chapter 3: strings, null termination, and `.ascii` / `.asciz` usage
- Chapter 5: bit-level load/store patterns, masks, field packing, and extraction
- Chapter 6: unsigned and signed arithmetic, multi-byte math, and multiply support
- Chapter 7: modular arithmetic, wraparound logic, and compare/branch math
- Chapter 10a: clock system, sleep modes, PIT wakeups, and BOD/VLM overview
- Chapter 11: timer math, prescalers, and PWM scaling
- Chapter 12: baud-rate math and serial timing
- Chapter 14: checksum and CRC routines, plus C/ASM math handoff
- Chapter 15: lookup tables, interpolation, Horner's method, and approximation
- Chapter 17: fixed-point formats, rounding, saturation, BCD, calibration, and control math
- Chapter 18: scheduler timing, phase math, and deterministic real-time calculations
- Chapter 19: CORDIC, vector math, trig, magnitude, and coordinate transforms
- Chapter 20: ADC / analog input, references, sampling, polling, interrupts, and filtering

## Missing Subject Matter To Add Later

- ADC / analog input: sampling, references, prescalers, channel selection, result handling, calibration, filtering, and ISR vs polling. Started in Chapter 20.
- EEPROM / nonvolatile user data: wear limits, update patterns, checksums, parameter blocks, and safe write workflows.
- Watchdog and reset recovery: WDT setup, timeout choices, reset cause handling, and fault-counter policy.
- Fuses and device configuration: read/modify/write workflow, recovery risks, BOOTEND, clock-related fuses, and UPDI-safe habits.
- UPDI / programming workflows: Curiosity Nano, serial UPDI, pymcuprog, avrdude, connection failures, and troubleshooting.
- Practical build and linker workflow: multi-file assembly projects, map files, section placement, symbol exchange, and reproducible builds.
- Testing and simulation: simavr or equivalent workflows, unit-style tests for assembly routines, and regression checks for examples.
- C and assembly integration: callable assembly functions, inline asm constraints, ABI examples, structs, pointers, clobbers, and linker symbols.
- Defensive firmware: watchdog recovery, fault counters, CRC/version metadata, boot failure paths, and safe peripheral initialization.
- Advanced peripherals: RTC/PIT, event system, analog comparator, DAC, configurable custom logic, and deeper PWM patterns.

## Missing Math Topics To Add Later

- Fast integer division and reciprocal methods
- Polynomial and rational approximations beyond Horner's method
- Fixed-point matrix transforms for control and graphics-style projections
- Noise, averaging, and filter design for ADC streams
