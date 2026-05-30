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
- [DRAFT] EEPROM / nonvolatile user data -> NEW chapter book/ch21_eeprom/ch21.md,
  wired into Makefile after ch20b. Covers: memory-mapped read (LDS @0x1400),
  NVMCTRL write sequence (EEBUSY wait -> fill page buffer -> CPU_CCP=0x9D SPM key
  -> ERWP within 4-instr window), CMD table (WP/ER/ERWP/PBC/EEER), wear (~100k
  cyc/byte, read-before-write update, wear-leveling ring), integrity (additive
  checksum, write-marker-last), erase (ER/EEER, blank=0xFF), pitfalls, 8 exercises.
  Companion src/ch21_eeprom/eeprom_rw.S BUILD-VERIFIED clean (avr-gcc 16.1.0,
  50 bytes); disasm confirms CCP store -> ERWP store within window.
  VERIFIED FACTS (datasheet p.61-63 + header): EEPROM 256B @0x1400, 64B page x4;
  NVMCTRL CTRLA(0x1000)/STATUS(0x1002 EEBUSY=bit1)/DATA(0x1006)/ADDR(0x1008);
  CMD enum NONE=0,WP=1,ER=2,ERWP=3,PBC=4,CHER=5,EEER=6,FUSEWRITE=7(PDI only);
  CPU_CCP=0x0034, key CCP_SPM=0x9D (CCP_IOREG=0xD8 is the OTHER key). EEPROM write
  lets CPU keep running (unlike Flash); only touched page-buffer bytes are written.
  [DONE] fuses chapter (ch22) + watchdog/reset (ch23) written; PDF rebuilt (559 pp).
- [DONE] Watchdog and reset recovery -> NEW chapter book/ch23_watchdog_reset/ch23.md
  (Makefile-wired, in PDF as ch34). WDT mental model, 11 periods (8ms-8.2s),
  arm via CCP IOREG key 0xD8 + SYNCBUSY wait, WDR petting (from main flow, not
  ISR), window mode + LOCK, RSTCTRL.RSTFR cause decode (PORF/BORF/EXTRF/WDRF/
  SWRF/UPDIRF, W1C, clear-at-startup), software reset via RSTCTRL.SWRR SWRE,
  EEPROM-backed fault-counter policy. src/ch23_watchdog_reset/wdt_demo.S
  BUILD-VERIFIED (52 bytes); disasm confirms CCP->CTRLA window. KEY FACT: WDT/
  RSTCTRL use IOREG key 0xD8, NOT NVM's SPM 0x9D. WDT clock = OSCULP32K 1.024kHz
  (async, imprecise). Verified datasheet sec.19 (p.167-170) + sec.12 (p.95-97).
- [DONE] Fuses and device configuration -> NEW chapter book/ch22_fuses/ch22.md
  (Makefile-wired, in PDF as ch33). Fuses read-only at runtime (LDS @0x1280+idx,
  FUSE_* symbols); WRITE is UPDI/PDI-only (FUSEWRITE PDI-only, NOT from firmware)
  -> avrdude -U fuseN:w:0xNN:m read-modify-write workflow. Fuse map (WDTCFG/
  BODCFG/OSCCFG/TCD0CFG/SYSCFG0/SYSCFG1/APPEND/BOOTEND), key fields OSCCFG.FREQSEL
  (16/20MHz), SYSCFG0.RSTPINCFG (GPIO=0/UPDI=1 default/RESET=2 -> brick hazard,
  HV-UPDI recovery), EESAVE, WDTCFG-at-boot+LOCK, BOOTEND/APPEND. src/ch22_fuses/
  fuse_read.S BUILD-VERIFIED (16 bytes). SYSCFG0 default 0xF6. Verified header +
  datasheet. PDF REBUILT 2026-05-29: make pdf, 559 pages, clean (was 541).
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
- [DONE] C and assembly integration -> NEW chapter book/ch25_c_asm_integration/
  ch25.md (Makefile-wired, PDF ch36, 570 pp). NOTE: the existing ch14_c_asm dir is
  MISNAMED — it actually holds "CRC and Data Integrity" (CRC-8 + CRCSCAN), NOT
  C/asm; this new chapter is the real C/asm material. Covers: avr-gcc ABI (call-
  used r0/r18-r27/r30-r31, call-saved r2-r17/r28-r29, r1=0), arg allocation
  (r25 down, even-aligned, low byte low reg), return (8b r24/16b r24:r25/32b
  r22:r25/64b r18:r25), call asm-from-C + C-from-asm, pointer/array passing via
  X/Y/Z, inline asm (constraints r/d/e/w/M/I, =/+ modifiers, cc/memory clobbers,
  volatile), shared data + linker symbols. ALL ABI FACTS EMPIRICALLY VERIFIED by
  compiling C with avr-gcc 16.1.0 and reading disasm. Sources src/ch25_c_asm_
  integration/{asm_funcs.S, driver.c} BUILD+LINK verified (270 bytes). First src
  chapter with a .c file alongside .S.
  [RESOLVED] ch14 dir renamed ch14_c_asm -> ch14_crc (book/ + src/, Makefile
  updated) to match its actual content ("CRC and Data Integrity"). CRCSCAN overlap
  with ch24 fixed by LAYERING: ch14 = CRCSCAN mechanics (register map, CRC-16-CCITT
  algo, checksum placement, NMI vector, fuse pre-boot); ch24 = applying it
  defensively (keeps runnable crc_selfcheck.S + the OK-needs-checksum caveat, but
  defers mechanics to ch14 via cross-ref). Bidirectional forward/back references
  added. PDF still 570 pp, clean.
- [DONE] Defensive firmware -> NEW capstone chapter book/ch24_defensive/ch24.md
  (Makefile-wired, in PDF as ch35, 564 pp). Composes the ch21/22/23 safety nets +
  NEW material: CRCSCAN flash-integrity (CTRLB.SRC -> CTRLA.ENABLE -> poll BUSY ->
  check OK; Priority mode stalls CPU; NMIEN = clear-only-by-reset; checksum CRC-16
  appended at section end FLASHEND-1/-1, BOOTEND*256-2/-1, APPEND*256-2/-1 by a
  post-build tool e.g. srec_cat; fuse-driven pre-boot scan via SYSCFG0.CRCSRC =
  CPU never starts on fail). Version/identity via SIGROW DEVICEID0..2 (0x1100) +
  SERNUM0 (0x1103). Safe peripheral init patterns (configure-before-enable, set-
  what-you-depend-on, disable-unused, verify-critical-writes, honor SYNCBUSY/CCP).
  Defensive-boot orchestration diagram tying reset-cause -> CRC -> fault counter
  -> EEPROM config check -> safe init -> watchdog. src/ch24_defensive/
  crc_selfcheck.S BUILD-VERIFIED (28 bytes; honest caveat that OK=1 needs the
  appended checksum, not demonstrable from a bare .S). Verified datasheet sec.27
  CRCSCAN (p.392-396) + header. CRCSCAN regs: CTRLA(0x120 ENABLE0/NMIEN1/RESET7),
  CTRLB(0x121 SRC[1:0]: FLASH=0/APPLICATION=1/BOOT=2, MODE=PRIORITY only),
  STATUS(0x122 BUSY0/OK1).
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
  - [DRAFT] Analog comparator (AC) + DAC -> two new sections added to ch20_adc
    ("The Analog Comparator (AC0)" + "The Digital-to-Analog Converter (DAC0)"),
    chapter title updated to "ADC, Analog Comparator, and DAC". Added AC/DAC
    pitfalls + 5 exercises (11-15). Companion sources src/ch20_adc/{ac_compare,
    dac_output}.S written and BUILD-VERIFIED clean (avr-gcc 16.1.0; 44/26 bytes).
    CORRECTIONS to the verified-facts block below, confirmed against the
    datasheet this session: VREF.CTRLA holds DAC0REFSEL[2:0] (NOT CTRLA-vs-CTRLB
    ambiguity); VREF.CTRLB bit0 = DAC0REFEN; reference is SHARED by AC0+DAC0.
    DAC0REFSEL enum order is NON-monotonic: 0x0=0.55V,0x1=1.1V,0x2=2.5V,
    0x3=4.34V,0x4=1.5V. DAC0.DATA is a single 8-bit right-aligned SFR (0x06A1);
    DAC0 OUT=PA6 (func A). AC0 has only CTRLA/MUXCTRLA/INTCTRL/STATUS (no CTRLB,
    no separate DACREF reg); AC_STATE_bp=4 (live), AC_CMP=bit0 (flag, W1C).
    STILL TODO: rebuild PDF (make pdf).
    ORIGINAL VERIFIED FACTS (datasheet sec.29 AC, + ATDF, + header):
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
