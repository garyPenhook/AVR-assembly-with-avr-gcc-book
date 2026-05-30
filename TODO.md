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
- Advanced peripherals. NOTE: the book uses sequential chapter numbers only
  (directory letters like ch20a are just a sort key; pandoc --number-sections
  renumbers 1..N). Do not add user-visible "lettered" chapters. Placement:
  - [DONE] Deeper PWM patterns -> ch11_timer. timer_pwm.S (single-slope, WO0=PB0,
    PER=999/CMP0=250, 25% @ ~3.33kHz) is now wired into "Extending: Single-Slope
    PWM" as a complete runnable listing (replaced the old inconsistent inline
    snippet that used PER=204/CMP0=102). Added center-aligned dual-slope: new
    companion src/ch11_timer/timer_pwm_ds.S (WGMODE DSBOTTOM=0x7, PER=500/CMP0=125,
    same 25% @ ~3.33kHz, builds clean), expanded "WO pins, more channels, and
    dual-slope" subsection with the DSTOP=0x5/DSBOTH=0x6/DSBOTTOM=0x7 table +
    counter behavior + dual-slope math (f = f_cpu/(presc × 2 × PER), duty =
    CMP0/PER) + CMP0BUF-transfers-at-BOTTOM note, and updated the Summary block.
    Both .S verified to assemble+link clean with avr-gcc 16.1.0 (40 bytes text).
    Note: Makefile builds only the PDF from .md; src files aren't compiled by it.
    [DONE] PDF rebuilt 2026-05-29 (make pdf, 541 pages, clean). WGMODE SINGLESLOPE=0x3 (verified header+
    datasheet p.188). TCA0 WO default pins: WO0=PB0,WO1=PB1,WO2=PB2 (alt PB3/4/5
    via PORTMUX); on-board LED is PA3 (NOT a normal-mode WO pin).
  - Analog comparator (AC) + DAC -> new sections inside ch20_adc (NOT STARTED).
    VERIFIED FACTS for next session (datasheet sec.29 AC, + ATDF, + header):
      AC0 pins: AINP0=PA7, AINP1=PB5, AINP2=PB1, AINP3=PB6; AINN0=PA6, AINN1=PB4;
                OUT=PA5. DAC0 OUT=PA6 (shared w/ AC0 AINN0; DAC can feed AC neg).
      AC0.CTRLA bits: RUNSTDBY OUTEN INTMODE[5:4] LPMODE HYSMODE[2:1] ENABLE.
      AC0.MUXCTRLA: INVERT(7) MUXPOS[4:3] MUXNEG[1:0].
        MUXPOS: 0=AINP0,1=AINP1,2=AINP2,3=AINP3. MUXNEG:0=AINN0,1=AINN1,2=VREF,3=DAC.
      AC0.STATUS: STATE(bit4)=live comparator output; CMP(bit0)=int flag (W1C).
      group-config names (enum-> use .equ or value): AC_MUXPOS_PIN0..3_gc,
        AC_MUXNEG_PIN0/PIN1/VREF/DAC_gc; bit masks AC_ENABLE_bm, AC_OUTEN_bm exist.
      DAC ref via VREF: VREF_DAC0REFSEL_0V55/1V1/1V5/2V5/4V34_gc; VREF.CTRLB has
        DAC0REFEN. DAC0.CTRLA: ENABLE(0)/OUTEN(6)/RUNSTDBY(7); DAC0.DATA 8-bit.
        (CONFIRM DAC0.DATA alignment + VREF register names against datasheet
        sec.28 DAC / VREF chapter before writing.)
  - [DRAFT] Event System (EVSYS) + Configurable Custom Logic (CCL) ->
    book/ch20b_event_ccl/ch20b.md, wired into Makefile after ch20a_filters.
    First draft written; concepts + symbolic-constant listings complete.
    CCL CONFIRMED (datasheet p.409): 2 LUTs + 1 SEQ; full register layout.
    EVSYS AUDIT DONE (datasheet sec.15): generator lists (async: CCL/AC0/TCD0/
    RTC/PORT; sync: TCB0/TCA0/PORT), user index tables (ASYNCUSER0..12,
    SYNCUSER0..1) all in the chapter. KEY FIX: ADC0 is an async user; TCA0/TCB0
    are sync gens -> original TCA0->ADC example was invalid, changed to RTC_OVF.
    src examples written: src/ch20b_event_ccl/{evsys_pin_mirror,
    ccl_not_via_evsys,adc_event_trigger}.S (use only verified EVSYS paths;
    CCL demo routes output via EVSYS->EVOUTA/PA2 to avoid unconfirmed CCL pins).
    BUILD-VERIFIED: all three .S assemble+link clean with stock avr-gcc 16.1.0.
    Constants: _gc group-config names in iotn3217.h are C ENUM members (not
    #define), so they are invisible to the assembler ("undefined reference");
    _bm/_bp are #define and work in .S. Examples therefore use .equ from the
    datasheet. (Original "not defined in iotn3217.h" claim was wrong — they ARE
    defined, just as enums; identical in avr-libc and Microchip DFP headers.)
    CCL PINS CONFIRMED (24-pin): LUT0 IN0=PA0 IN1=PA1 IN2=PA2 OUT=PA4(alt PB4);
    LUT1 IN0=PC3 IN1=PC4 IN2=PC5 OUT=PA7(alt PC1). 20-pin SOIC omits PC4/PC5.
    Source: datasheet Table 5-1 (printed p.16) via get_document_page (text DID
    extract), cross-checked against DFP ATDF <signal> pad entries — both agree.
    (NOTE: keyword search_documents fails on that table; get_document_page works.
    Beware printed-page vs PDF-page off-by-one when rendering.)
    [DONE] PDF rebuilt 2026-05-29 (make pdf, 541 pages, clean).

## Missing Math Topics To Add Later

- Polynomial and rational approximations beyond Horner's method
- Fixed-point matrix transforms for control and graphics-style projections
