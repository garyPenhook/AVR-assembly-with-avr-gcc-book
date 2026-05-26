# TODO

## Math Topics for AVR Assembly

1. Number systems: binary, hex, decimal, and BCD
2. Unsigned integer arithmetic on 8-bit and 16-bit registers
3. Signed arithmetic with two's complement and sign extension
4. Multi-byte addition, subtraction, comparison, and negation
5. Bit math: masks, shifts, rotates, packing, and field extraction
6. Fixed-point arithmetic on AVR
7. Fixed-point formats: Q8.8, Q1.15, and scaling conventions
8. Rounding, saturation, overflow, and quantization error
9. Fast multiply and divide techniques
10. Lookup tables and interpolation
11. Polynomial approximation with Horner's method
12. Fast integer square root and vector math
13. Coordinate transforms and projections
14. CORDIC for sine, cosine, atan2, and vector rotation
15. DDS and phase accumulator math
16. Integer filters for ADC and control
17. Fixed-point PID math
18. Calibration math in fixed-point
19. Timer, prescaler, baud-rate, and PWM scaling math
20. Modular arithmetic for wraparound counters and phase
21. BCD and decimal conversion math
22. Checksums, CRCs, and other integrity math

## Chapter Roadmap

- Chapter 1: toolchain setup, simulator workflow, and detailed GDB usage
- Chapter 4: number systems, integer representation, and basic arithmetic rules
- Chapter 3: strings, null termination, and `.ascii` / `.asciz` usage
- Chapter 5: bit-level load/store patterns, masks, field packing, and extraction
- Chapter 6: unsigned and signed arithmetic, multi-byte math, and multiply support
- Chapter 7: modular arithmetic, wraparound logic, and compare/branch math
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
- Clock system and power: CLKCTRL, prescalers, oscillator choices, sleep modes, wake sources, watchdog, brown-out, and low-power design.
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
