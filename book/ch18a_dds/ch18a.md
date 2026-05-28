# DDS and Phase Accumulator Math

Direct Digital Synthesis (DDS), also called a Numerically Controlled Oscillator
(NCO), is a method of generating a periodic waveform from a fixed-rate clock
using nothing more than an integer counter, an addition, and a table lookup.
On an 8-bit AVR, where there is no floating-point hardware and no built-in
waveform generator, DDS is the standard way to produce audio tones, carrier
signals, PWM audio, or continuously variable-frequency clocking signals with
fine frequency resolution and deterministic timing.

This chapter covers:

1. **The phase accumulator** — the integer counter that lies at the heart of
   every DDS implementation.
2. **The DDS frequency equation** — how accumulator width, sample rate, and the
   tuning word combine to determine output frequency.
3. **Choosing accumulator width** — the trade between resolution, register
   pressure, and ISR cost.
4. **Sample rate selection on ATtiny3217** — setting up TCB0 for a precise
   interrupt-driven sample clock.
5. **Waveform tables** — storing a sine cycle in flash and addressing it from
   the accumulator.
6. **AVR assembly implementation** — register plan, SRAM layout, ISR, and
   output to an 8-bit PWM channel.
7. **Frequency accuracy and phase truncation** — measuring output error,
   understanding spurious tones, and estimating SFDR.
8. **Phase and frequency modulation** — changing frequency mid-stream, sweeping
   through a chirp, and adding a phase offset.
9. **Two-tone mixing** — summing two independent DDS channels in the ISR.
10. **Common pitfalls** — Nyquist aliasing, overflow in tuning word computation,
    and interrupt jitter.

---

## The Phase Accumulator

The phase accumulator is an N-bit unsigned integer held in SRAM. Each time the
sample clock fires, a fixed value M is added to the accumulator:

```
accumulator = (accumulator + M) mod 2^N
```

The modular reduction is free: when the accumulator overflows it wraps back to
zero automatically, exactly like an N-bit unsigned integer on any CPU. There is
no explicit division or modulo instruction needed.

### Mapping Accumulator Value to Phase

Think of the accumulator as representing a phase angle that runs from 0 to
2π continuously:

```
phase = accumulator × (2π / 2^N)
```

When the accumulator holds 0, the phase is 0°. When it holds 2^(N-1), the
phase is 180°. When it overflows from 2^N-1 back to 0, it completes one full
cycle.

This is identical to Binary Angular Measure (BAM), which Chapter 19 uses for
the CORDIC angle format. A 16-bit phase accumulator is a 16-bit BAM counter.

### Visualising the Accumulator

Three snapshots of a 4-bit accumulator (N=4, range 0–15) stepping by M=3:

```
Sample    Accumulator    Fractional phase (× 360°/16)
──────────────────────────────────────────────────────
  0             0            0.0°
  1             3           67.5°
  2             6          135.0°
  3             9          202.5°
  4            12          270.0°
  5        15→ 0 (wrap)    337.5° → 0° (next cycle begins)
  6             3           67.5°
  ...
```

The accumulator completes one full revolution every `2^N / M` samples. If the
sample clock runs at `f_s`, the output repeats at `f_s × M / 2^N` Hz.

---

## The DDS Frequency Equation

The fundamental relationship is:

```
f_out = f_s × M / 2^N
```

Where:

```
f_out    output frequency (Hz)
f_s      sample rate (Hz) — how often the accumulator is updated
M        tuning word (also called phase increment) — the value added each sample
N        accumulator width in bits
2^N      accumulator modulus
```

Rearranging to find the tuning word M for a desired output frequency:

```
M = round( f_out × 2^N / f_s )
```

The rounding means the output frequency may not be exactly `f_out`. The
nearest achievable frequency is constrained by the resolution:

```
Δf = f_s / 2^N          (Hz per tuning word step)
```

With a narrower accumulator the resolution is coarser; with a wider one it
is finer. That trade is the central design decision in any DDS implementation.

### Nyquist Limit

A real periodic signal reconstructed from discrete samples cannot exceed half
the sample rate. The maximum usable output frequency is:

```
f_max = f_s / 2    (Nyquist limit)
```

The corresponding maximum tuning word is `M = 2^(N-1)`. Above this, the output
aliases back to a lower frequency rather than increasing further.

---

## Choosing the Accumulator Width

### 8-bit Accumulator

An 8-bit accumulator maps directly to a 256-entry table with no bit
manipulation: the accumulator byte is the table index. It costs one register
and one SRAM byte. The resolution is very coarse:

```
Δf = f_s / 256
```

At f_s = 8 kHz this is 31.25 Hz per step — useless for musical tones.

### 16-bit Accumulator

Two SRAM bytes, two registers, one ADD and one ADC per update. This is the
standard choice when the output is audio or a control signal measured in Hz:

```
N = 16, 2^N = 65536
Δf = f_s / 65536

At f_s ≈ 8 kHz: Δf = 7992 / 65536 = 0.122 Hz per step
```

The top 8 bits of the 16-bit accumulator are used as the table index, so the
table still has 256 entries. The bottom 8 bits are sub-index precision that
gives fine frequency control without enlarging the table. A 16-bit accumulator
is the practical choice for this chapter.

### 32-bit Accumulator

Four SRAM bytes, four registers, four ADD/ADC instructions per update. The
resolution becomes exceptional:

```
N = 32, 2^N = 4,294,967,296
Δf = f_s / 4,294,967,296

At f_s ≈ 8 kHz: Δf ≈ 1.86 μHz per step
```

A 32-bit accumulator is warranted when long stable tones must hold pitch
within a few millihertz, or when generating a very slow ramp signal where
coarse steps would cause audible pitch jumps. The ISR cost is roughly doubled
compared to 16-bit. Section "32-bit Variant" below shows the register plan.

---

## Sample Rate on ATtiny3217

The ATtiny3217 on the Curiosity Nano runs at 3,333,333 Hz (the internal 20 MHz
RC oscillator divided by 6, set by `CLKCTRL_MCLKCTRLB`). TCB0 in Periodic
Interrupt mode provides the sample clock.

### TCB0 Sample Clock Calculation

```
Target sample rate: 8000 Hz (standard audio)

CCMP = round(F_CPU / f_s) − 1
     = round(3,333,333 / 8000) − 1
     = round(416.67) − 1
     = 417 − 1
     = 416   (0x01A0)

Actual sample rate: F_CPU / (CCMP + 1)
                  = 3,333,333 / 417
                  = 7992 Hz

Sample rate error: (7992 − 8000) / 8000 × 100% = −0.10%
```

A 0.1% sample rate error shifts every output frequency by 0.1%. For A4 at
440 Hz that is a 0.44 Hz error — inaudible for most purposes, and negligible
compared to the quantisation error of the 16-bit tuning word.

### TCB0 Register Map (from ATtiny3217 data sheet)

```
Address   Name             Value for 8 kHz
────────────────────────────────────────────────────────────────────
0x0A40    TCB0_CTRLA       0x01  (ENABLE=1, CLKSEL=CLK_PER)
0x0A41    TCB0_CTRLB       0x00  (CNTMODE=0, Periodic Interrupt)
0x0A45    TCB0_INTCTRL     0x01  (CAPT interrupt enable)
0x0A4C    TCB0_CCMPL       0xA0  (low byte of 416 = 0x01A0)
0x0A4D    TCB0_CCMPH       0x01  (high byte of 416 = 0x01A0)
```

In Periodic Interrupt mode, TCB0 counts from 0 to CCMP inclusive, then
restarts and fires the CAPT interrupt. The period is CCMP+1 = 417 clock cycles.

---

## Tuning Word Computation

Given N=16 and f_s = 7992 Hz:

```
M = round(f_out × 65536 / 7992)
```

### Common Musical Notes

```
Note    Frequency (Hz)    Tuning word M    Actual f_out (Hz)    Error (Hz)
──────────────────────────────────────────────────────────────────────────
C4      261.626           2145             261.63               +0.00
D4      293.665           2407             293.82               +0.15
E4      329.628           2702             329.88               +0.25
A4      440.000           3610             440.24               +0.24
C5      523.251           4289             523.50               +0.25
```

Calculation for A4:

```
M = round(440 × 65536 / 7992)
  = round(28,835,840 / 7992)
  = round(3609.7)
  = 3610

f_actual = 7992 × 3610 / 65536
         = 28,851,120 / 65536
         = 440.24 Hz

Error = 440.24 − 440 = 0.24 Hz   (0.055%)
```

That error is far below the just-noticeable pitch difference for a typical
listener (roughly 0.3% at 440 Hz), so 16-bit DDS with a 7992 Hz sample rate
is adequate for audio synthesis at this scale.

### Overflow Risk in Tuning Word Calculation

The intermediate product `f_out × 65536` can overflow a 16-bit integer for any
frequency above 0.99 Hz. Always compute M in at least 32-bit arithmetic:

```c
uint32_t M = (uint32_t)f_out_hz_times_1000 * 65536UL / 7992 / 1000;
```

Or, if computing offline and loading M as a constant, use Python:

```python
f_s = 7992                    # actual sample rate
N = 16
M = round(440 * (2**N) / f_s)  # M = 3610
```

On AVR, the tuning word is set by the application before the DDS ISR starts
and typically never recomputed in assembly. Frequency changes happen by writing
a new precomputed M value to `phase_step` in SRAM.

---

## The Waveform Table

### Sine Table Format

The waveform table stores one complete cycle of the target waveform. For sine
output to an 8-bit PWM channel, unsigned bytes in the range 0–255 are most
convenient:

```
table[i] = round(127.5 + 127.5 × sin(2π × i / 256))
```

Selected entries:

```
Index    Angle       Value    Notes
──────────────────────────────────────────────────────
    0    0°          128      zero crossing, rising
   32    45°         218
   64    90°         255      positive peak
   96    135°        218
  128    180°        128      zero crossing, falling
  160    225°         37
  192    270°           0     negative peak
  224    315°          37
  255    359.86°     128      approaching next cycle
```

The value 128 corresponds to mid-scale PWM (0 V after low-pass filtering). The
negative peak reaches 0, not 1, because 127.5 × (1 − 1) = 0 exactly.

### Generating the Table

Use Python to compute the 256-entry table and paste it into the assembly source:

```python
import math
table = [round(127.5 + 127.5 * math.sin(2 * math.pi * i / 256))
         for i in range(256)]
print(', '.join(str(v) for v in table))
```

Spot-checking the first ten entries:

```
i=0: 128   i=1: 131   i=2: 134   i=3: 137   i=4: 140
i=5: 143   i=6: 146   i=7: 149   i=8: 152   i=9: 155
```

Each step of 1 in the index advances the angle by 360°/256 = 1.406°. The
value increments approximately `127.5 × 2π/256 ≈ 3.13` per step near the zero
crossings and is flat near the peaks, exactly as expected for a sine wave.

### Table Placement and Alignment

Aligning the 256-byte table to a 256-byte flash boundary allows the ISR to
compute the table address with a single `MOV` rather than an addition:

```asm
.section .text
.balign 256             /* align to 256-byte address boundary */
sine_table:
    .byte 128, 131, 134, 137, 140, 143, 146, 149
    .byte 152, 155, 158, 161, 164, 167, 170, 172
    ...
    /* 256 entries total */
```

With this alignment, `lo8(sine_table)` is always 0x00. Inside the ISR:

```asm
ldi   ZH, hi8(sine_table)   /* page address — fixed for the whole table */
mov   ZL, r_index           /* ZL = table index (top byte of accumulator) */
lpm   r_sample, Z           /* fetch the sample */
```

`ZL` will range over 0x00–0xFF, all within the aligned page, so `ZH` never
changes during the fetch. If alignment is not possible (flash too fragmented),
use the two-step add:

```asm
ldi   ZL, lo8(sine_table)
ldi   ZH, hi8(sine_table)
add   ZL, r_index
adc   ZH, r1               /* r1 = 0; propagate carry into ZH */
lpm   r_sample, Z
```

---

## AVR Assembly Implementation

### SRAM Variable Layout

```asm
.section .bss

/* 16-bit phase accumulator: two sequential bytes */
phase_accum:    .byte 0     /* low byte  */
                .byte 0     /* high byte — addressed as phase_accum+1 */

/* 16-bit phase step (tuning word M): two sequential bytes */
phase_step:     .byte 0     /* low byte  */
                .byte 0     /* high byte — addressed as phase_step+1  */
```

In GAS assembly, `.byte 0` allocates one uninitialised byte in `.bss` (which
the C runtime zeros before main, but in `-nostartfiles` builds you must zero it
yourself in reset_handler). The two-byte layout lets `LDS r, phase_accum` and
`LDS r, phase_accum+1` read the low and high bytes in sequential instructions.
`phase_accum+1` is a valid GAS expression: the label's address plus one.

### Register Plan

The DDS ISR needs:

```
r16     scratch: interrupt flag clear, ISR prologue/epilogue use
r17     phase accumulator high byte (table index after update)
r18     phase accumulator low byte
r19     phase step high byte
r20     phase step low byte
r21     sine sample fetched with LPM
r30/r31 Z: flash pointer for LPM
SREG    saved/restored in prologue/epilogue
```

The ISR saves r16–r21 and Z. Since TCB0 fires every 417 cycles, the ISR must
finish well within that budget.

### Cycle Budget

```
Prologue (save SREG, r16–r21, r30–r31)   9 push + 1 in = 10 cycles
Clear TCB0 interrupt flag (LDI + STS)               1 + 2 = 3 cycles
Load accumulator (2 × LDS)                         2 × 3 = 6 cycles
Load phase step (2 × LDS)                          2 × 3 = 6 cycles
Add step to accumulator (ADD + ADC)                  1+1  = 2 cycles
Store accumulator (2 × STS)                         2 × 2 = 4 cycles
Set up Z and fetch sample (LDI + MOV + LPM)         1+1+3 = 5 cycles
Write sample to PWM (STS)                                  = 2 cycles
Epilogue (restore r30–r31, r16–r21, SREG + RETI)  9+1+4  = 14 cycles
────────────────────────────────────────────────────────────────────
Total                                                      52 cycles
Budget (417 cycles per sample)                            365 cycles remaining
CPU utilisation                                            52/417 = 12.5%
```

At 12.5%, the DDS ISR leaves ample time for a cooperative-scheduler main loop
to handle other tasks between samples.

### TCB0 Initialisation

```asm
/* tcb0_dds_init — configure TCB0 for the DDS sample clock
 *
 * F_CPU = 3,333,333 Hz, target f_s = 8000 Hz, CCMP = 416 = 0x01A0
 * Actual f_s = 3,333,333 / 417 = 7992 Hz
 * Clobbers: R16
 */
tcb0_dds_init:
    ldi   r16, lo8(416)          /* 0xA0 */
    sts   TCB0_CCMPL, r16
    ldi   r16, hi8(416)          /* 0x01 */
    sts   TCB0_CCMPH, r16

    ldi   r16, 0                 /* CNTMODE = 0: Periodic Interrupt */
    sts   TCB0_CTRLB, r16

    ldi   r16, TCB_CAPT_bm       /* enable CAPT interrupt */
    sts   TCB0_INTCTRL, r16

    ldi   r16, TCB_ENABLE_bm     /* CLK_PER (no prescaler), enable */
    sts   TCB0_CTRLA, r16
    ret
```

TCB writes the CCMP register as two separate byte writes. The 16-bit value is
buffered: the hardware copies the low byte to an internal buffer and latches
both bytes atomically when the high byte is written. Always write CCMPL before
CCMPH.

### TCA0 8-bit PWM Initialisation

TCA0 in split mode provides two independent 8-bit PWM channels. The low counter
drives WO0–WO2; the high counter drives WO3–WO5. Using the low counter on WO0
(PB0):

```asm
/* tca0_pwm_init — configure TCA0 low counter for 8-bit PWM on WO0 (PB0)
 *
 * PWM frequency = F_CPU / 256 = 3,333,333 / 256 = 13,021 Hz
 * Clobbers: R16
 */
tca0_pwm_init:
    /* Enable split mode */
    ldi   r16, TCA_SPLIT_SPLITM_bm
    sts   TCA0_SPLIT_CTRLD, r16

    /* Low counter: CLK_PER (no prescaler), enable.
     * TCA_SPLIT_CLKSEL_DIV1_gc = 0x00, so CTRLA = ENABLE_bm only. */
    ldi   r16, TCA_SPLIT_ENABLE_bm
    sts   TCA0_SPLIT_CTRLA, r16

    /* Enable WO0 output compare on low counter */
    ldi   r16, TCA_SPLIT_LCMP0EN_bm
    sts   TCA0_SPLIT_CTRLB, r16

    /* Set low counter period to 255 (8-bit PWM) */
    ldi   r16, 255
    sts   TCA0_SPLIT_LPER, r16

    /* Initial duty cycle = 128 (mid-scale) */
    ldi   r16, 128
    sts   TCA0_SPLIT_LCMP0, r16

    /* PB0 as output */
    sbi   VPORTB_DIR, 0
    ret
```

The PWM frequency is 13,021 Hz, approximately 1.6× the Nyquist limit of the
7992 Hz sample rate. Signals above the Nyquist limit alias; the PWM carrier
itself aliases to audible frequencies unless filtered. Place an RC low-pass
filter on PB0 before any audio output stage:

```
Cut-off frequency: f_c = 1 / (2π × R × C)

For R = 10 kΩ and C = 10 nF:
  f_c = 1 / (2π × 10,000 × 10×10^-9) = 1592 Hz

This passes audio up to 1.6 kHz and suppresses the 13 kHz PWM carrier.
For wider bandwidth (up to 3 kHz), use R = 5.6 kΩ, C = 10 nF → f_c = 2.84 kHz.
```

### DDS Interrupt Service Routine

```asm
/* dds_isr — DDS sample clock ISR (TCB0 CAPT, fires at 7992 Hz)
 *
 * Each call:
 *   1. Adds phase_step to phase_accum (16-bit wrap)
 *   2. Uses high byte of accumulator as index into sine_table
 *   3. Writes the sine sample to TCA0_SPLIT_LCMP0 (8-bit PWM duty)
 *
 * Saves/restores: SREG, R16–R21, R30–R31 (Z)
 * Cycle cost: ~52 cycles of the 417-cycle budget
 */
dds_isr:
    /* ── Prologue ──────────────────────────────────────────────────── */
    push  r16
    in    r16, _SFR_IO_ADDR(SREG)
    push  r16
    push  r17
    push  r18
    push  r19
    push  r20
    push  r21
    push  r30
    push  r31

    /* ── Clear TCB0 interrupt flag ─────────────────────────────────── */
    ldi   r16, TCB_CAPT_bm
    sts   TCB0_INTFLAGS, r16

    /* ── Load phase accumulator ────────────────────────────────────── */
    lds   r18, phase_accum          /* low byte  */
    lds   r17, phase_accum+1        /* high byte */

    /* ── Load phase step ───────────────────────────────────────────── */
    lds   r20, phase_step           /* low byte  */
    lds   r19, phase_step+1         /* high byte */

    /* ── Advance accumulator: accum += step (16-bit wrapping add) ──── */
    add   r18, r20                  /* low:  r18 = r18 + r20            */
    adc   r17, r19                  /* high: r17 = r17 + r19 + C        */

    /* ── Store updated accumulator ─────────────────────────────────── */
    sts   phase_accum,   r18
    sts   phase_accum+1, r17

    /* ── Table lookup: sine_table[r17] ─────────────────────────────── */
    ldi   ZH, hi8(sine_table)       /* flash page address of table      */
    mov   ZL, r17                   /* index = high byte of accumulator */
    lpm   r21, Z                    /* r21 = sine_table[index]          */

    /* ── Output sample to PWM duty register ────────────────────────── */
    sts   TCA0_SPLIT_LCMP0, r21

    /* ── Epilogue ──────────────────────────────────────────────────── */
    pop   r31
    pop   r30
    pop   r21
    pop   r20
    pop   r19
    pop   r18
    pop   r17
    pop   r16
    out   _SFR_IO_ADDR(SREG), r16
    pop   r16
    reti
```

The ordering of the low/high bytes follows the ATtiny3217 little-endian SRAM
layout: low byte at the lower address, high byte at the higher address. Loading
`phase_accum` gives the low byte and `phase_accum+1` gives the high byte. The
ADD/ADC pair updates the pair in one step: ADD updates the low byte and sets
carry; ADC propagates carry into the high byte. Overflow in the high byte is
silently discarded — that is the intended 16-bit wrap.

### Reset Handler and Startup

```asm
/* reset_handler — entry point after power-on or reset */
reset_handler:
    /* Stack pointer */
    ldi   r16, hi8(RAMEND)
    out   _SFR_IO_ADDR(SPH), r16
    ldi   r16, lo8(RAMEND)
    out   _SFR_IO_ADDR(SPL), r16

    clr   r1                        /* zero register convention */

    /* Zero SRAM variables */
    clr   r16
    sts   phase_accum,   r16
    sts   phase_accum+1, r16
    sts   phase_step,    r16
    sts   phase_step+1,  r16

    /* Initialise peripherals */
    rcall tca0_pwm_init
    rcall tcb0_dds_init

    /* Load tuning word for A4 (440 Hz at 7992 Hz sample rate: M = 3610) */
    ldi   r16, lo8(3610)            /* 0x1A */
    sts   phase_step, r16
    ldi   r16, hi8(3610)            /* 0x0E */
    sts   phase_step+1, r16

    sei                             /* enable global interrupts */

.Lmain_idle:
    rjmp  .Lmain_idle               /* main loop: all work done in ISR */
```

Writing the phase step after enabling the peripherals but before `SEI` avoids
a race: the ISR cannot fire until after `SEI`, so the write is always visible
before the first sample.

---

## Complete Source Listing

The full buildable file is in `src/dds.S`. It includes the vector table,
sine table, all initialisation routines, the DDS ISR, and the reset handler.

### Vector Table

```asm
.section .vectors, "ax", @progbits
    jmp   reset_handler          /* 0x0000  RESET       */
    jmp   default_isr            /* 0x0004  CRCSCAN_NMI */
    jmp   default_isr            /* 0x0008  BOD_VLM     */
    jmp   default_isr            /* 0x000C  PORTA_PORT  */
    jmp   default_isr            /* 0x0010  PORTB_PORT  */
    jmp   default_isr            /* 0x0014  PORTC_PORT  */
    jmp   default_isr            /* 0x0018  RTC_CNT     */
    jmp   default_isr            /* 0x001C  RTC_PIT     */
    jmp   default_isr            /* 0x0020  TCA0_LUNF   */
    jmp   default_isr            /* 0x0024  TCA0_OVF    */
    jmp   default_isr            /* 0x0028  TCA0_CMP0   */
    jmp   default_isr            /* 0x002C  TCA0_CMP1   */
    jmp   default_isr            /* 0x0030  TCA0_CMP2   */
    jmp   dds_isr                /* 0x0034  TCB0_INT    ← DDS sample clock */
    jmp   default_isr            /* 0x0038  TCB1_INT    */
    jmp   default_isr            /* 0x003C  TCD0_OVF    */
    jmp   default_isr            /* 0x0040  TCD0_TRIG   */
    jmp   default_isr            /* 0x0044  AC0_AC      */
    jmp   default_isr            /* 0x0048  AC1_AC      */
    jmp   default_isr            /* 0x004C  AC2_AC      */
    jmp   default_isr            /* 0x0050  ADC0_RESRDY */
    jmp   default_isr            /* 0x0054  ADC0_WCOMP  */
    jmp   default_isr            /* 0x0058  ADC1_RESRDY */
    jmp   default_isr            /* 0x005C  ADC1_WCOMP  */
    jmp   default_isr            /* 0x0060  TWI0_TWIS   */
    jmp   default_isr            /* 0x0064  TWI0_TWIM   */
    jmp   default_isr            /* 0x0068  SPI0_INT    */
    jmp   default_isr            /* 0x006C  USART0_RXC  */
    jmp   default_isr            /* 0x0070  USART0_DRE  */
    jmp   default_isr            /* 0x0074  USART0_TXC  */
    jmp   default_isr            /* 0x0078  NVMCTRL_EE  */

```

### Build

```bash
MCU=attiny3217
avr-gcc -mmcu=${MCU} -nostartfiles -nodefaultlibs \
        -Wl,-Map=dds.map \
        -o dds.elf src/dds.S
avr-objdump -h dds.elf           # check section sizes and load addresses
avr-objdump -d dds.elf           # disassemble to verify ISR body
avr-objcopy -O ihex dds.elf dds.hex
avrdude -p t3217 -c serialupdi -P /dev/ttyUSB0 -U flash:w:dds.hex:i
```

The `-Wl,-Map=dds.map` flag writes a linker map. Inspect it to confirm that
`sine_table` is placed at a 256-byte-aligned flash address (the `.balign 256`
directive will force this, and the map file shows the actual result).

---

## Frequency Accuracy and Phase Truncation

### Two Sources of Frequency Error

A 16-bit DDS implementation on ATtiny3217 has two independent sources of
frequency error:

**1. Sample rate quantisation error.**

The sample clock period must be an integer number of CPU cycles. At
F_CPU = 3,333,333 Hz and target f_s = 8000 Hz, the ideal period is
416.667 cycles, which rounds to 417. The resulting sample rate is:

```
f_s_actual = 3,333,333 / 417 = 7992.4 Hz
```

Every output frequency is scaled by this 0.10% error. For A4 at 440 Hz, that
is a 0.44 Hz shift.

**2. Tuning word quantisation error.**

The tuning word M must be an integer. Rounding introduces an error of at most
±0.5 steps, corresponding to ±Δf/2 = ±0.061 Hz at 7992 Hz and N=16. This
error is independent for each output frequency.

The combined worst-case frequency error is approximately:

```
|error_max| ≈ f_out × 0.001 + 0.061 Hz
```

For A4: ≈ 0.44 + 0.06 = 0.50 Hz. That is 0.11% — well within typical
loudspeaker and hearing tolerance.

### Phase Truncation and Spurious Tones

The phase accumulator has 16 bits of precision, but the waveform table has only
256 entries. Only the top 8 bits of the accumulator are used as the table
index. The bottom 8 bits are discarded — this is called **phase truncation**.

Phase truncation creates a periodic phase-step error. That error manifests in
the output spectrum as spurious tones, sometimes called spurs or phase
truncation spurs (PTS). The amplitude of the worst-case spur is approximately:

```
Spur level ≈ −6.02 × (N − B)    dBc

Where:
  N = accumulator bits = 16
  B = table address bits = 8
  N − B = truncated bits = 8

Spur level ≈ −6.02 × 8 = −48 dBc
```

"dBc" means decibels below the carrier (the wanted output tone). A −48 dBc
spur is about 250 times smaller in amplitude than the carrier. For most audio
and control applications this is inaudible and negligible, but it matters for
communications use where spectral purity is required.

To reduce spurs without enlarging the table, use a wider accumulator (increase
N) or interpolate between adjacent table entries (which is more expensive in
the ISR but suppresses spurs dramatically).

### Worst-Case Spur Frequency

Phase truncation spurs appear at frequencies related to the tuning word and the
accumulator overflow rate. For a tuning word M and sample rate f_s:

```
Spur frequencies ≈ k × (f_s × M / gcd(M, 2^N))    for integer k

where gcd() is the greatest common divisor of M and 2^N.
```

When M is odd, gcd(M, 2^16) = 1, and the only spur within the Nyquist band is
the fundamental itself. When M shares factors of 2 with 2^16, multiple spurs
appear at harmonics of a sub-fundamental. Choosing M to be odd or to share
minimal common factors with 2^N reduces the spur density, though not their
individual amplitude.

---

## Phase and Frequency Modulation

### Phase Modulation

A phase offset can be added to the accumulator at the table lookup step without
changing the accumulator itself:

```asm
/* PM: add 16-bit phase offset from SRAM before the table lookup */
lds   r22, phase_offset          /* low byte of offset  */
lds   r23, phase_offset+1        /* high byte of offset */
add   r18, r22                   /* r18 = accum_lo + offset_lo */
adc   r17, r23                   /* r17 = accum_hi + offset_hi + C */
/* now use r17 as the table index — the accumulator itself is unchanged */
```

The accumulated phase and the modulation offset are kept separate. This means
the carrier oscillates at the frequency set by `phase_step`, and the modulation
shifts the output phase each sample without altering the carrier rate.

A constant `phase_offset` shifts the output phase permanently (useful for
generating a cosine from the same sine table: set offset = 0x4000 = 90°).

A time-varying `phase_offset` produces phase modulation (PM) or, with careful
choice of offset, frequency modulation (FM):

```
FM: update phase_offset each sample by a small audio signal value
    → the carrier frequency swings above and below f_out at the audio rate
```

### Frequency Modulation

The simplest frequency modulation writes a new `phase_step` value each sample.
For a 1 Hz FM deviation, add ±round(1 Hz × 65536 / 7992) = ±8 to `phase_step`.

For a small deviation, update `phase_step` from the ISR itself:

```asm
/* FM via time-varying phase step — add fm_delta each sample */
lds   r20, fm_delta              /* signed FM offset (low byte) */
lds   r21, fm_delta+1            /* signed FM offset (high byte) */

lds   r18, phase_step
lds   r19, phase_step+1
add   r18, r20
adc   r19, r21
sts   phase_step,   r18
sts   phase_step+1, r19
```

`fm_delta` is written by the main loop based on an audio or control input.
This is the pattern used by many simple FM synthesis chips on 8-bit systems.

### Linear Frequency Sweep (Chirp)

A chirp increases or decreases the output frequency linearly over time. The
phase step itself increments by a constant `chirp_rate` each sample:

```asm
/* Chirp: phase_step += chirp_rate each sample */
lds   r22, chirp_rate
lds   r23, chirp_rate+1
add   r18, r22
adc   r19, r23
sts   phase_step,   r18
sts   phase_step+1, r19
```

If `chirp_rate` is positive, the output frequency rises; if negative (unsigned
wrap), it falls. The rate of frequency change is:

```
df/dt = chirp_rate × Δf × f_s
      = chirp_rate × (7992 / 65536) × 7992
      ≈ chirp_rate × 975 Hz/s per tuning-word unit
```

For a chirp rate of 1 (one tuning-word step per sample), the frequency rises
at 975 Hz/s. To cover the range from 200 Hz to 1000 Hz in 2 seconds:

```
total frequency change = 1000 − 200 = 800 Hz
duration = 2 s
chirp_rate = round(800 / (2 × 975)) = round(0.41) → 0 — too slow at 1 step

Use chirp_rate = 1 and a slower duration:
  time = 800 Hz / (1 × 975 Hz/s) = 0.82 s

Or chirp_rate = 4 and set starting M:
  time = 800 / (4 × 975) = 0.205 s
```

The chirp rate is a tuning parameter set before enabling the sweep. The main
loop monitors a tick counter to stop the sweep at the target frequency.

---

## Two-Tone Mixing

A second DDS tone requires a second phase accumulator and a second phase step
in SRAM. At the table lookup, both samples are read and summed:

```asm
/* Second accumulator */
phase_accum2:   .byte 0, 0
phase_step2:    .byte 0, 0
```

ISR extension after computing sample 1 in `r21`:

```asm
/* ── Second oscillator ─────────────────────────────────────────── */
lds   r22, phase_accum2
lds   r23, phase_accum2+1
lds   r24, phase_step2
lds   r25, phase_step2+1
add   r22, r24
adc   r23, r25
sts   phase_accum2,   r22
sts   phase_accum2+1, r23

ldi   ZH, hi8(sine_table)
mov   ZL, r23
lpm   r16, Z               /* r16 = sine sample for oscillator 2 */

/* ── Mix: (sample1 + sample2) / 2 ─────────────────────────────── */
/* Both r21 and r16 are unsigned 0–255 */
/* Sum can reach 510, so use 16-bit add then divide */
add   r21, r16             /* r21 = sample1 + sample2 (low byte)  */
clr   r16
adc   r16, r1              /* r16 = carry from 8-bit overflow     */
lsr   r16
ror   r21                  /* r21:r16 >> 1 → r21 = (sum) / 2     */
```

The result in `r21` is the average of the two samples, range 0–255, suitable
for the 8-bit PWM. Equal-power mixing of two full-scale tones prevents
overflow.

For unequal amplitudes, scale one or both samples before summing. The same
pattern extends to three or four oscillators within the 417-cycle ISR budget,
though the total cycle count must be verified to stay within bounds.

The two-tone ISR costs approximately 52 + 20 = 72 cycles (adding the second
oscillator update and mix), leaving 345 cycles per sample. That is still 17%
CPU utilisation — manageable.

---

## 32-bit Accumulator Variant

When sub-Hz frequency resolution is needed — for example, generating a very
slow periodic waveform for a mechanical actuator, or for tight frequency
locking in a phase-locked loop — extend the accumulator to 32 bits.

### SRAM Layout

```asm
phase_accum32: .byte 0, 0, 0, 0    /* 4 bytes, low to high */
phase_step32:  .byte 0, 0, 0, 0
```

### Tuning Word

For A4 with the 32-bit accumulator:

```
M = round(440 × 2^32 / 7992)
  = round(440 × 4,294,967,296 / 7992)
  = round(236,415,633,536 / 7992)
  = round(29,581,754.8)
  = 29,581,755   (0x01C39BFB)
```

### ISR Accumulator Update

```asm
lds   r16, phase_accum32+0
lds   r17, phase_accum32+1
lds   r18, phase_accum32+2
lds   r19, phase_accum32+3

lds   r20, phase_step32+0
lds   r21, phase_step32+1
lds   r22, phase_step32+2
lds   r23, phase_step32+3

add   r16, r20
adc   r17, r21
adc   r18, r22
adc   r19, r23

sts   phase_accum32+0, r16
sts   phase_accum32+1, r17
sts   phase_accum32+2, r18
sts   phase_accum32+3, r19

/* Table index: top byte = r19 */
ldi   ZH, hi8(sine_table)
mov   ZL, r19
lpm   r21, Z
```

Cycle cost: 4×LDS + 4×LDS + 4×(ADD/ADC) + 4×STS + LDI + MOV + LPM
= 12 + 12 + 4 + 8 + 1 + 1 + 3 = 41 cycles for the accumulator and lookup,
versus 22 cycles for the 16-bit version. The additional 19 cycles are a
reasonable cost for the jump from 0.122 Hz resolution to 1.86 μHz resolution.

---

## Common Pitfalls

### Pitfall 1 — Aliasing Above Nyquist

Setting M above `2^(N-1)` = 32768 causes the output frequency to alias. With a
16-bit accumulator and M = 40000:

```
f_nominal = 7992 × 40000 / 65536 = 4878 Hz   (above Nyquist = 3996 Hz)
f_alias   = f_s − f_nominal = 7992 − 4878 = 3114 Hz
```

The output is not 4878 Hz but 3114 Hz — the mirror image below Nyquist. This
is not an error in the DDS hardware; it is a mathematical property of
discrete-time signals. The fix is to clamp M below `2^(N-1)` before loading it
into `phase_step`.

### Pitfall 2 — Overflow in Tuning Word Calculation

The expression `f_out × 2^N` overflows a 16-bit integer for any frequency above
1 Hz when N=16. Always use 32-bit or wider arithmetic:

```
Wrong (16-bit overflow for any reasonable audio frequency):
  M = (uint16_t)(440 * 65536) / 7992   → garbage

Correct:
  M = (uint32_t)(440) * 65536UL / 7992  → 3610
```

In the assembly source, M is a precomputed constant. The overflow risk is in the
host-side or C-side calculation, not in the ISR itself.

### Pitfall 3 — Unaligned Sine Table

If `.balign 256` is missing or if the linker places the table at a non-aligned
address, the `MOV ZL, r17` approach gives wrong results when `r17` rolls over.
For example, if `sine_table` is at byte address 0x0180 (ZH=0x01, ZL=0x80), and
the accumulator high byte is 0x00, then Z = 0x0100 — pointing before the table.
When ZL wraps past 0xFF, Z increments ZH, pointing one page past the end.

Verify alignment after building:

```bash
avr-objdump -h dds.elf | grep sine_table
```

or inspect the linker map for the `sine_table` address. If the address is not
a multiple of 256, add `.balign 256` immediately before the `.byte` directives
that define the table.

### Pitfall 4 — Forgetting to Clear the TCB0 Interrupt Flag

TCB0 in Periodic Interrupt mode does not clear its interrupt flag automatically.
If `TCB0_INTFLAGS` is not written in the ISR, the interrupt immediately
re-fires after `RETI`, consuming 100% of the CPU in the ISR. Always include:

```asm
ldi   r16, TCB_CAPT_bm
sts   TCB0_INTFLAGS, r16
```

Write 1 to the bit to clear it. Writing 0 has no effect.

### Pitfall 5 — Phase Accumulator Not Zeroed Before Starting

The `.bss` section is zeroed by the C runtime startup code. In a
`-nostartfiles` assembly build it is not — SRAM power-on state is undefined.
The reset handler must zero `phase_accum` and `phase_step` explicitly before
enabling the TCB0 interrupt. A non-zero initial `phase_step` can cause a brief
burst of incorrect frequency output before the main loop loads the intended
tuning word.

### Pitfall 6 — Interrupt Latency Jitter Adds Phase Noise

If the DDS ISR competes with other ISRs for CPU time, the sample clock has
jitter equal to the latency of whichever ISR runs first. Each jitter event
shifts the phase of the output by a random amount, which adds broadband phase
noise. To minimise this:

- Keep all other ISRs shorter than one sample period (417 cycles).
- If another interrupt source cannot be made that short, assign it a lower
  priority. On ATtiny3217, CPUINT supports two priority levels: normal (all
  ISRs by default) and high (one ISR assigned via `CPUINT_LVL1VEC`). Assign
  the DDS ISR to level 1 (high priority) for the best timing stability.

---

## Relationship to CORDIC

Chapter 19 shows that the CORDIC algorithm can generate sine and cosine from a
phase angle with no waveform table at all, at the cost of about 12 shift-add
stages per sample. The two approaches trade differently:

```
Method              Flash (table)    Cycles/sample    Notes
────────────────────────────────────────────────────────────────────
256-byte LUT        256 bytes        ~5 cycles        best speed, one output
CORDIC (12 stages)  ~24 bytes        ~80–120 cycles   sine + cosine, no table
```

For the DDS context, the LUT approach is almost always faster. CORDIC becomes
attractive when flash is scarce, when both sine and cosine are needed from the
same phase (e.g., I/Q generation), or when the phase is already in BAM16 from
some other computation.

The phase accumulator described in this chapter is format-compatible with the
BAM16 angles used by the CORDIC routines in Chapter 19. The high byte of the
16-bit DDS accumulator (0x00–0xFF) maps to angles 0°–360° in 256 steps. The
CORDIC routines expect BAM16 (0x0000–0xFFFF). The relationship is:

```
CORDIC_angle = DDS_accumulator_high_byte × 256
             = DDS_accumulator × (0xFF00 / 0xFFFF) ≈ DDS_accumulator

More precisely: CORDIC_angle_BAM16 = phase_accum (full 16-bit value)
```

The full 16-bit DDS accumulator is already a valid BAM16 angle. To use CORDIC
instead of the LUT in the DDS ISR, replace the LPM table lookup with a call to
`cordic_sincos_bam16`, passing the accumulator as the angle argument. The sine
output is then used as the PWM sample. The cycle cost rises from ~5 to ~80–120
cycles, which still fits within the 417-cycle budget for a single-channel DDS.

---

## Summary

```
DDS core equation:
  f_out = f_s × M / 2^N

Tuning word for a target frequency:
  M = round(f_out × 2^N / f_s)

Resolution: Δf = f_s / 2^N

ATtiny3217 (F_CPU = 3,333,333 Hz) 16-bit DDS parameters:
  Sample rate:    CCMP = 416 → f_s = 7992 Hz (target 8000 Hz, error −0.10%)
  N:              16  (two SRAM bytes, two registers)
  Resolution:     7992 / 65536 = 0.122 Hz per tuning word step
  Nyquist limit:  3996 Hz (M < 32768)
  Phase spurs:    ≈ −48 dBc (8 truncated bits, 256-entry table)

ISR cycle cost:   ~52 cycles of a 417-cycle budget (12.5% CPU)

Table:
  256 unsigned bytes in flash, .balign 256 for aligned-page ZL lookup
  sine_table[i] = round(127.5 + 127.5 × sin(2π × i / 256))

Phase modulation:  add offset to accumulator copy before LPM (non-destructive)
Frequency mod:     update phase_step from main loop or inner ISR
Chirp:             increment phase_step by chirp_rate each sample

Two tones:
  second accumulator + second step → average both samples before PWM write
  total ISR cost ~72 cycles (17% CPU)

32-bit accumulator:
  resolution ≈ 1.86 μHz at 7992 Hz sample rate
  ISR cost ~70 cycles (additional ~19 cycles for the 4-byte add and stores)
```

Microchip source notes:

- ATtiny3216/3217 data sheet, TCB Periodic Interrupt mode: the TCB counter
  reloads from BOTTOM when it matches CCMP and generates a CAPT interrupt.
  CCMP is a buffered 16-bit register; write CCMPL first, CCMPH second.
- ATtiny3216/3217 data sheet, TCA Split Mode: each 8-bit counter has its own
  compare register (`LCMP0`–`LCMP2`, `HCMP0`–`HCMP2`) and corresponding output
  waveform pins. The PWM frequency in split mode is `CLK_PER / (LPER + 1)`.
- AVR Instruction Set Manual, `LPM Rd, Z`: loads the byte at the flash byte
  address in Z into Rd. On AVRxt devices including ATtiny3217, any register
  may be the destination. The Z register is not modified; Z+ post-increment form
  available but not needed here.
- AVR Instruction Set Manual, `ADD Rd, Rr` and `ADC Rd, Rr`: ADD sets carry on
  overflow; ADC adds carry into the result. Chaining one ADD and one or more ADC
  instructions implements arbitrary-width unsigned addition.

---

## Exercises

1. Compute the tuning word M for the note G4 (392.000 Hz) using f_s = 7992 Hz
   and N = 16. What is the actual output frequency? What is the error in cents
   (1 cent = 1/100 of a semitone ≈ 0.058% frequency change)?

2. The CCMP value 416 gives f_s = 7992 Hz. If you increase CCMP to 520 for a
   lower sample rate, what is the new f_s? What is the maximum output frequency?
   What is the tuning word for 220 Hz (A3) at this sample rate?

3. Explain what happens to the output frequency when M is set to exactly 32768
   (2^15). What does the waveform look like? What happens when M = 32769?

4. Modify the DDS ISR to read the phase step from an 8-bit potentiometer
   connected to an ADC input. The ADC result (0–1023) should map linearly to
   output frequencies 100 Hz–4000 Hz. Write the tuning word conversion formula
   and describe where in the system the conversion runs (ISR or main loop).

5. Add a second sine table in flash for a square wave (table values: 0 for
   indices 0–127, 255 for indices 128–255). How many additional flash bytes does
   this cost? What change in the ISR lets the main loop select between the sine
   and square wave tables at run time?

6. Measure the actual output frequency of the dds.S firmware using a frequency
   counter or oscilloscope, and compare it with the calculated f_out = 440.24 Hz
   for M = 3610. What sources of error remain between the measured and predicted
   values?

---

*Next: Chapter 19 — CORDIC on AVR*
