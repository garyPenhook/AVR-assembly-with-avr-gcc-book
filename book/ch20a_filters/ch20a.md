# Integer Filters for ADC and Control

The ADC converts a voltage to a number, but that number is rarely clean. The
internal 1.1 V reference has a tolerance of roughly ±2% (rising to about ±5%
over the full temperature and voltage range). The sample-and-hold
capacitor leaks charge during long conversions. Digital switching on the same
supply rail couples noise into the analog circuitry. A sensor with high source
impedance cannot charge the S/H capacitor fully in the default sample time.
Even with a perfect hardware setup, thermal noise and quantisation noise are
always present.

Software filters reduce that noise before the application acts on the result.
They are also the building blocks of feedback control: a proportional-integral-
derivative (PID) controller is three filter operations — a scaled identity, an
integrator, and a differentiated low-pass — combined with a subtractor.

This chapter covers:

1. **Noise sources** on the ATtiny3217 ADC and where each filter type helps.
2. **Exponential Moving Average (EMA)** — the most important tool, with
   16-bit and 24-bit fixed-point implementations.
3. **Box filter** — a running-window average using a circular buffer.
4. **Median filter** — a 3-sample compare-and-swap network for spike removal.
5. **Cascaded EMA** — two stages in series for a steeper low-pass rolloff.
6. **Integer PID structure** — proportional, integral, and derivative terms
   in fixed-point arithmetic, with anti-windup clamping.
7. **Filter selection** — a practical guide to choosing the right tool.
8. **Common pitfalls** — accumulator sizing, initialisation, and windup.

All filters in this chapter operate on 10-bit unsigned ADC results (0–1023)
and use integer arithmetic with no floating-point operations.

---

## Noise Sources and Filter Choices

```
Noise source              Character        Best filter
──────────────────────────────────────────────────────────────────────────────
Thermal / quantisation    Broadband white  EMA or box filter
Supply-coupled switching  Periodic spike   Median filter
Ground bounce             Periodic spike   Median filter
Mechanical bounce         Sustained burst  EMA with large k
High-source-impedance     Slow settling    Add SAMPCTRL time; EMA helps
ADC INL / DNL             Systematic       Cannot be removed by software
```

The first step is always hardware: bypass capacitors, short ground paths, low-
impedance sources, and correct SAMPCTRL settings from Chapter 20. Software
filters cannot fix systematic hardware errors, but they substantially reduce
random noise.

---

## Exponential Moving Average

The exponential moving average (EMA), also called a first-order IIR low-pass
filter, is the single most useful filter for ADC conditioning on a small MCU.
It needs only one extra word of SRAM, runs in under 40 cycles, and has
well-understood frequency-domain behaviour.

### Algorithm

The update rule is:

```
y[n] = y[n-1] + (x[n] - y[n-1]) / 2^k
```

Where:

```
x[n]   new ADC sample (0..1023)
y[n]   filtered output (0..1023)
k      shift parameter: larger k = more smoothing, slower response
```

The term `(x[n] - y[n-1]) / 2^k` is an error-weighted correction. When the
input suddenly changes, the output moves toward it in exponential steps of size
`1/2^k` per sample. Larger k makes the steps smaller and the filter slower.

### Fixed-Point Implementation

The division by `2^k` is an arithmetic right shift, which is exact and free on
AVR. The challenge is representing `y[n]` with enough precision to accumulate
small corrections without truncating them away.

The solution is a **scaled accumulator**: keep the accumulator at `2^k × y[n]`
rather than `y[n]` itself. Each update adds the new sample and subtracts the
shifted accumulator:

```
accum[n] = accum[n-1] - (accum[n-1] >> k) + x[n]

output = accum[n] >> k
```

This is equivalent to the definition because `accum ≈ 2^k × y`, so
`accum >> k ≈ y`, and `accum - (accum >> k) + x = accum × (1 - 1/2^k) + x`.

### Accumulator Width

The scaled accumulator converges to `2^k × x` at steady state. For a 10-bit
ADC input (maximum 1023) and shift parameter k, the maximum accumulator value
is:

```
accum_max = 1023 × 2^k
```

```
k   accum_max   Bits required   Register choice
──────────────────────────────────────────────────────────────────
1   2046         11              16-bit (2 bytes)
2   4092         12              16-bit
3   8184         13              16-bit
4   16368        14              16-bit
5   32736        15              16-bit
6   65472        16              16-bit — maximum for 16-bit accumulator
7   130944       17              24-bit (3 bytes)
8   261888       18              24-bit
10  1047552      20              24-bit
14  16760832     24              24-bit — maximum for 24-bit accumulator
```

A 16-bit accumulator supports k up to 6. A 24-bit accumulator supports k up to
14. For most ADC conditioning, k = 4 (16-bit) or k = 8 (24-bit) are the
practical starting points.

### Cutoff Frequency

The EMA is a first-order low-pass filter. Its −3 dB cutoff frequency is:

```
fc ≈ fs / (2^k × 2π)
```

Where `fs` is the sample rate (how often the filter is updated). At different
sample rates:

```
k    fc at fs=1000 Hz   fc at fs=100 Hz   fc at fs=7992 Hz
──────────────────────────────────────────────────────────────────
1    79.6 Hz            7.96 Hz           636 Hz
2    39.8 Hz            3.98 Hz           318 Hz
3    19.9 Hz            1.99 Hz           159 Hz
4    9.95 Hz            0.995 Hz          79.5 Hz
6    2.49 Hz            0.249 Hz          19.9 Hz
8    0.622 Hz           0.0622 Hz         4.97 Hz
10   0.155 Hz           0.0155 Hz         1.24 Hz
```

Approximate formula derivation: the EMA transfer function is
`H(z) = α / (1 − (1−α) z⁻¹)` where `α = 1/2^k`. For small α, the −3 dB
radian frequency is `ω_c ≈ α`, so `fc ≈ fs × α / (2π) = fs / (2^k × 2π)`.
The approximation is within a few percent for k ≥ 4 (about 6% at k = 3).

### Assembly: 16-bit Accumulator (k = 4)

```asm
.section .bss
ema_accum: .byte 0              /* 16-bit scaled accumulator, low byte          */
           .byte 0              /* high byte — addressed as ema_accum+1         */
```

```asm
/* ema16_k4 — EMA low-pass, alpha = 1/16 (k = 4), 16-bit accumulator
 *
 * fc ≈ fs / 101  (e.g., 9.9 Hz at 1000 Hz sample rate)
 * Valid for 10-bit ADC input — accum_max = 16368 < 65536
 *
 * Entry: R25:R24 = new ADC sample (0..1023, unsigned)
 * Exit:  R25:R24 = filtered output (0..1023, unsigned)
 * Clobbers: R16, R17, R18, R19
 */
ema16_k4:
    /* Load scaled accumulator from SRAM */
    lds   r18, ema_accum         /* accum low byte                               */
    lds   r19, ema_accum+1       /* accum high byte                              */

    /* shift = accum >> 4  (copy, then shift right 4 times) */
    movw  r16, r18               /* r17:r16 = r19:r18 (copy of accum)           */
    lsr   r17
    ror   r16
    lsr   r17
    ror   r16
    lsr   r17
    ror   r16
    lsr   r17
    ror   r16                    /* r17:r16 = accum >> 4                         */

    /* accum = accum - shift + sample */
    sub   r18, r16               /* accum_lo -= shift_lo (may borrow)            */
    sbc   r19, r17               /* accum_hi -= shift_hi - borrow                */
    add   r18, r24               /* accum_lo += sample_lo                        */
    adc   r19, r25               /* accum_hi += sample_hi + carry                */

    /* Store updated accumulator */
    sts   ema_accum,   r18
    sts   ema_accum+1, r19

    /* Output = accum >> 4 */
    movw  r24, r18               /* r25:r24 = r19:r18                            */
    lsr   r25
    ror   r24
    lsr   r25
    ror   r24
    lsr   r25
    ror   r24
    lsr   r25
    ror   r24                    /* r25:r24 = accum >> 4 = filtered output       */
    ret
```

Cycle count: 2 LDS (6) + MOVW (1) + 4×(LSR+ROR) (8) + 2×SUB/SBC + 2×ADD/ADC (4) +
2 STS (4) + MOVW (1) + 4×(LSR+ROR) (8) + RET (4) = **36 cycles** plus 2 for the
RCALL (AVRxt timing).

At 1 kHz sample rate: 38 of the 3333 cycles per sample period = 1.1% CPU.

The shift uses logical right shift (LSR/ROR) because the accumulator is
unsigned. The signed arithmetic right shift (ASR/ROR) is used for signed values;
here the accumulator cannot go negative, so LSR is correct.

### Initialisation

The accumulator must be zeroed before the first sample, or pre-loaded with a
known value. In a `-nostartfiles` build:

```asm
reset_handler:
    ...
    clr   r16
    sts   ema_accum,   r16
    sts   ema_accum+1, r16
```

A zero-initialised accumulator makes the filter converge from 0 toward the true
signal, which can cause a startup transient. For a faster settling, pre-load
with `first_sample × 2^k`:

```asm
/* Pre-load EMA accumulator with first ADC reading × 16 (for k=4) */
rcall adc0_read                  /* returns r25:r24 = 10-bit sample               */
movw  r18, r24                   /* r19:r18 = sample                              */
ldi   r16, 0
ldi   r17, 0
/* multiply r19:r18 by 16 = shift left 4 */
lsl   r18
rol   r19
lsl   r18
rol   r19
lsl   r18
rol   r19
lsl   r18
rol   r19                        /* r19:r18 = sample × 16                         */
sts   ema_accum,   r18
sts   ema_accum+1, r19
```

Pre-loading eliminates the cold-start transient: the filter begins at the correct
output rather than converging from zero.

### Assembly: 24-bit Accumulator (k = 8)

For stronger filtering (k = 8, fc ≈ fs/1608), the accumulator needs 24 bits.

```asm
.section .bss
ema_accum24: .byte 0            /* byte 0: lowest                                */
             .byte 0            /* byte 1: middle                                */
             .byte 0            /* byte 2: highest — ema_accum24+2               */
```

```asm
/* ema24_k8 — EMA low-pass, alpha = 1/256 (k = 8), 24-bit accumulator
 *
 * fc ≈ fs / 1608  (e.g., 0.62 Hz at 1000 Hz sample rate)
 * Valid for 10-bit ADC input — accum_max = 261888, fits in 24 bits (16777216)
 *
 * Entry: R25:R24 = new ADC sample (0..1023)
 * Exit:  R25:R24 = filtered output (0..1023)
 * Clobbers: R16, R17, R18, R19, R20, R21
 */
ema24_k8:
    /* Load 24-bit accumulator (byte 0 = least significant) */
    lds   r19, ema_accum24
    lds   r20, ema_accum24+1
    lds   r21, ema_accum24+2

    /* accum >> 8: byte N shifts down to byte N-1; byte 0 is discarded.
     * Shift value as three bytes: {0, b2, b1} = {0, r21, r20}.
     *
     * accum - (accum >> 8): subtract {0, b2, b1} from {b2, b1, b0}:
     *   byte0: b0 - b1
     *   byte1: b1 - b2 - borrow
     *   byte2: b2 - 0  - borrow
     */
    sub   r19, r20               /* byte0: b0 - b1                               */
    sbc   r20, r21               /* byte1: b1 - b2 - C  (r20 was b1, r21 = b2)  */
    sbc   r21, r1                /* byte2: b2 - 0  - C  (r1 = 0)                */

    /* accum += sample (r25:r24 ≤ 1023, r25 ≤ 3) */
    add   r19, r24
    adc   r20, r25
    adc   r21, r1                /* propagate carry into high byte               */

    /* Store updated accumulator */
    sts   ema_accum24,   r19
    sts   ema_accum24+1, r20
    sts   ema_accum24+2, r21

    /* Output = accum >> 8 = top 16 bits {b2, b1} = {r21, r20}
     * r25:r24 = r21:r20 */
    movw  r24, r20               /* r24 = r20 (mid byte), r25 = r21 (high byte) */
    ret
```

The key insight in `ema24_k8` is that a right-shift by 8 on a 24-bit number
reduces to moving bytes down by one position. There is no bit-level shifting at
all: the shift value is just the middle and high bytes with the low byte
discarded. The `sub r19, r20` / `sbc r20, r21` / `sbc r21, r1` chain performs
the subtraction in one pass without needing a temporary copy.

Cycle count: 3 LDS (9) + 3×(SUB/SBC) (3) + 3×(ADD/ADC) (3) + 3 STS (6) +
MOVW (1) + RET (4) = **26 cycles** plus 2 for the RCALL (AVRxt timing).

The 24-bit version is actually *cheaper* than the 16-bit version because the
shift-by-8 is free (byte movement).

---

## Box Filter (N-Sample Moving Average)

A box filter (also called a sliding window average or rectangular FIR) averages
the last N samples. It has a sharper rolloff than EMA at the cost of N×2 bytes
of SRAM for the sample history.

### Algorithm

```
sum = sum + new_sample - oldest_sample
buf[write_idx] = new_sample
write_idx = (write_idx + 1) mod N

output = sum / N
```

The circular buffer replaces the oldest sample with the new one and adjusts the
running sum by the difference. Division by N is an arithmetic right shift when N
is a power of two.

### Implementation: N = 8 (M = 3 shifts)

For N = 8 and a 10-bit ADC:

```
sum_max = 8 × 1023 = 8184 < 65535 → 16-bit sum
buf:       8 × 2 bytes = 16 bytes of SRAM
idx:       1 byte, range 0..7
```

```asm
.section .bss
box_buf:  .fill 16, 1, 0        /* 8 × 2-byte sample slots                      */
box_sum:  .byte 0               /* running sum, low byte                         */
          .byte 0               /* running sum, high byte                        */
box_idx:  .byte 0               /* circular buffer write index, 0..7             */
```

```asm
/* box8_update — 8-sample box filter (sliding window average)
 *
 * Entry: R25:R24 = new ADC sample (0..1023)
 * Exit:  R25:R24 = filtered output (0..1023)
 * Clobbers: R16, R17, R18, R19, R30, R31 (Z)
 */
box8_update:
    /* Load write index */
    lds   r16, box_idx            /* r16 = idx (0..7)                             */

    /* Point Z at box_buf[idx]: byte offset = idx × 2                            */
    ldi   ZL, lo8(box_buf)
    ldi   ZH, hi8(box_buf)
    mov   r17, r16
    lsl   r17                     /* r17 = idx × 2                               */
    add   ZL, r17
    adc   ZH, r1                  /* Z = &box_buf[idx] (low byte of entry)       */

    /* Load oldest sample from that slot */
    ld    r18, Z+                 /* r18 = old_lo, Z advances to high byte        */
    ld    r19, Z                  /* r19 = old_hi                                */

    /* Store new sample in the same slot */
    st    Z,  r25                 /* write new_hi at high-byte position           */
    st   -Z,  r24                 /* pre-decrement Z; write new_lo at low-byte    */

    /* Load running sum (Z is now free — LDS uses direct addressing, not Z)      */
    lds   r30, box_sum
    lds   r31, box_sum+1

    /* sum += new_sample - old_sample */
    add   r30, r24
    adc   r31, r25
    sub   r30, r18
    sbc   r31, r19

    /* Store updated sum */
    sts   box_sum,   r30
    sts   box_sum+1, r31

    /* Advance index: idx = (idx + 1) & 7 */
    inc   r16
    andi  r16, 0x07
    sts   box_idx, r16

    /* Output = sum >> 3 */
    movw  r24, r30                /* r25:r24 = r31:r30                           */
    lsr   r25
    ror   r24
    lsr   r25
    ror   r24
    lsr   r25
    ror   r24                     /* r25:r24 = sum / 8                            */
    ret
```

The `LD r18, Z+` / `LD r19, Z` pair reads the little-endian 16-bit sample from
the circular buffer without modifying the entry. After both reads, Z points at
the high-byte slot. `ST Z, r25` writes the new high byte; `ST -Z, r24`
pre-decrements Z and writes the new low byte. After those two stores, the entry
in SRAM holds the new sample in the correct little-endian layout.

`LDS` and `STS` use a direct 16-bit address encoded in the instruction word.
They do not use or disturb the Z register. Loading the sum into r30:r31 does not
clobber Z even though r30 and r31 are the Z register components, because after
the buffer access, Z is no longer needed.

### Box Filter Initialisation

Zero the sum, buffer, and index before use:

```asm
box_init:
    clr   r16
    sts   box_sum,   r16
    sts   box_sum+1, r16
    sts   box_idx,   r16
    /* Zero the 16-byte buffer with a loop */
    ldi   ZL, lo8(box_buf)
    ldi   ZH, hi8(box_buf)
    ldi   r17, 16
.Lbox_zero:
    st    Z+, r16
    dec   r17
    brne  .Lbox_zero
    ret
```

Like the EMA, zero initialisation causes a startup transient. Pre-fill the
buffer with the first sample to avoid it.

### Frequency Response

The box filter has a sinc-like frequency response. Its first null is at `fc =
fs / N`. For N = 8 and fs = 1000 Hz: first null at 125 Hz. The filter attenuates
noise broadly up to that frequency, but has significant side lobes above it.

Box filters have poor sidelobe rejection compared to EMA. They are better suited
to removing broadband noise when the sample count can be tuned to place the first
null at the dominant interference frequency.

---

## Median Filter (3-Sample)

A median filter returns the middle value of the last N samples, discarding
outliers entirely. A 3-sample median removes isolated spikes with no smoothing
of the underlying signal: valid consecutive readings pass through unchanged, but
a single anomalous reading (EMI glitch, mechanical event) is removed.

### Algorithm: Sorting Network

Sort three values a, b, c using a 3-swap network. After the network, the middle
value b is the median. The compare-and-swap operation COMPARE_SWAP(x, y) swaps
x and y if x > y, ensuring x ≤ y afterwards:

```
COMPARE_SWAP(a, b)    → a ≤ b
COMPARE_SWAP(b, c)    → b ≤ c
COMPARE_SWAP(a, b)    → a ≤ b
After: a ≤ b ≤ c.  Median = b.
```

Verification with {7, 3, 5}:
1. COMPARE_SWAP(7, 3) → swap → {3, 7, 5}
2. COMPARE_SWAP(7, 5) → swap → {3, 5, 7}
3. COMPARE_SWAP(3, 5) → no swap → {3, 5, 7}
Median = 5. ✓

### SRAM Layout

The 3-sample median needs the two oldest samples in SRAM:

```asm
.section .bss
med_hist: .byte 0, 0, 0, 0     /* two 16-bit samples: oldest at +0, prev at +2  */
```

### Assembly Implementation

```asm
/* med3_update — 3-sample median filter using a compare-and-swap sorting network
 *
 * Entry: R25:R24 = newest ADC sample (0..1023, unsigned)
 * Exit:  R25:R24 = median of last 3 samples (0..1023)
 * Clobbers: R18, R19, R20, R21, R22, R23
 */
med3_update:
    /* Load history: a = oldest (med_hist), b = previous (med_hist+2) */
    lds   r22, med_hist          /* a_lo                                          */
    lds   r23, med_hist+1        /* a_hi                                          */
    lds   r20, med_hist+2        /* b_lo                                          */
    lds   r21, med_hist+3        /* b_hi                                          */

    /* Shift history: oldest = prev, prev = new */
    sts   med_hist,   r20
    sts   med_hist+1, r21        /* oldest ← prev */
    sts   med_hist+2, r24
    sts   med_hist+3, r25        /* prev ← new    */

    /* c = new sample in r25:r24 */

    /* ── Sorting network ────────────────────────────────────────────── */

    /* COMPARE_SWAP(a, b): if a >= b, swap(a, b)
     *
     * CP/CPC: compare a − b.  Carry set (BRLO) iff a < b.
     * We want to skip the swap when a < b; swap otherwise (a >= b).
     * Swapping equal values is harmless and avoids an extra branch.
     */

    /* Step 1: COMPARE_SWAP(a, b) → ensures a ≤ b afterwards */
    cp    r22, r20
    cpc   r23, r21               /* compare a (r23:r22) with b (r21:r20)          */
    brlo  .Lmed3_step2           /* a < b: already ordered, skip swap             */
    movw  r18, r22               /* temp = a                                      */
    movw  r22, r20               /* a = b                                         */
    movw  r20, r18               /* b = temp                                      */

.Lmed3_step2:
    /* Step 2: COMPARE_SWAP(b, c) → ensures b ≤ c afterwards */
    cp    r20, r24
    cpc   r21, r25               /* compare b (r21:r20) with c (r25:r24)          */
    brlo  .Lmed3_step3
    movw  r18, r20               /* temp = b                                      */
    movw  r20, r24               /* b = c                                         */
    movw  r24, r18               /* c = temp  (c not needed after this)           */

.Lmed3_step3:
    /* Step 3: COMPARE_SWAP(a, b) → restores a ≤ b after step 2 may have changed b */
    cp    r22, r20
    cpc   r23, r21
    brlo  .Lmed3_done
    movw  r18, r22               /* temp = a (result discarded)                   */
    movw  r22, r20               /* a = b   (result discarded)                    */
    movw  r20, r18               /* b = old a → median                            */

.Lmed3_done:
    /* Median is in r21:r20 (b after sorting) */
    movw  r24, r20               /* r25:r24 = median output                       */
    ret
```

`MOVW Rd, Rr` requires both `Rd` and `Rr` to be even-numbered registers. All
register pairs used here (r18, r20, r22, r24) satisfy that constraint.

`CP Rd, Rr; CPC Rd, Rr` implements a 16-bit unsigned comparison. After
`CP r22, r20; CPC r23, r21`, the carry flag is set if and only if a < b
(unsigned 16-bit). `BRLO` (branch if lower = branch if carry set) therefore
branches when a < b.

The median filter adds 4 bytes of SRAM. It does not smooth the signal at all:
valid readings pass through with zero delay. Use it as a pre-stage before EMA
when the sensor produces occasional large spikes.

---

## Cascaded EMA (Second-Order Low-Pass)

Running the output of one EMA through a second EMA produces a second-order
low-pass filter with a steeper rolloff: the response falls at approximately
40 dB/decade above the cutoff rather than the 20 dB/decade of a single stage.

### SRAM Layout

Two independent accumulators, one per stage. This example uses k = 5 for each
stage. Cascading two identical single-pole stages puts the combined −3 dB point
at about 0.64× a single stage's cutoff (≈ the cutoff of a single-stage EMA with
k ≈ 5.6), but with a steeper second-order rolloff:

```asm
.section .bss
ema2_accum0: .byte 0, 0          /* Stage 1 accumulator (k=5, 16-bit)            */
ema2_accum1: .byte 0, 0          /* Stage 2 accumulator (k=5, 16-bit)            */
```

### Implementation

```asm
/* ema2_k5_update — two cascaded EMA stages, k=5 each
 *
 * Second-order (40 dB/decade) rolloff; combined -3 dB cutoff ≈ single-stage k≈5.6
 * fc ≈ fs / (2^5 × 2π) per stage; cascaded fc is lower (≈ 0.64× per-stage fc)
 *
 * Entry: R25:R24 = new ADC sample (0..1023)
 * Exit:  R25:R24 = filtered output (0..1023)
 * Clobbers: R16, R17, R18, R19
 */
ema2_k5_update:
    /* ── Stage 1: accum0 ────────────────────────────────────────────── */
    lds   r18, ema2_accum0
    lds   r19, ema2_accum0+1

    movw  r16, r18
    lsr   r17                    /* shift accum0 >> 5 (5 times) */
    ror   r16
    lsr   r17
    ror   r16
    lsr   r17
    ror   r16
    lsr   r17
    ror   r16
    lsr   r17
    ror   r16

    sub   r18, r16
    sbc   r19, r17
    add   r18, r24
    adc   r19, r25

    sts   ema2_accum0,   r18
    sts   ema2_accum0+1, r19

    /* Stage 1 output in r25:r24 = accum0 >> 5 */
    movw  r24, r18
    lsr   r25
    ror   r24
    lsr   r25
    ror   r24
    lsr   r25
    ror   r24
    lsr   r25
    ror   r24
    lsr   r25
    ror   r24                    /* r25:r24 = stage-1 output                     */

    /* ── Stage 2: accum1 ────────────────────────────────────────────── */
    lds   r18, ema2_accum1
    lds   r19, ema2_accum1+1

    movw  r16, r18
    lsr   r17
    ror   r16
    lsr   r17
    ror   r16
    lsr   r17
    ror   r16
    lsr   r17
    ror   r16
    lsr   r17
    ror   r16

    sub   r18, r16
    sbc   r19, r17
    add   r18, r24
    adc   r19, r25

    sts   ema2_accum1,   r18
    sts   ema2_accum1+1, r19

    movw  r24, r18
    lsr   r25
    ror   r24
    lsr   r25
    ror   r24
    lsr   r25
    ror   r24
    lsr   r25
    ror   r24
    lsr   r25
    ror   r24                    /* r25:r24 = final filtered output               */
    ret
```

The cascaded EMA doubles the SRAM cost (4 bytes instead of 2) and roughly
doubles the cycle cost (≈ 72 cycles instead of 36). The reward is a much
steeper roll-off: noise above the cutoff is attenuated more aggressively.

Both stages must be initialised to zero (or pre-filled) before use.

---

## Integer PID Structure

A PID controller computes an output `u` from a setpoint `sp` and measured value
`y`:

```
error = sp - y

P_term = Kp × error
I_term = I_prev + Ki × error        (accumulator — may need anti-windup)
D_term = Kd × (y_prev - y)          (using output, not error, for the D term)

u = P_term + I_term + D_term
```

Using the output rather than the error for the derivative term prevents
**derivative kick**: when the setpoint changes, the error jumps instantly and the
derivative of the error is infinite. The output changes smoothly, so its
derivative is well-behaved.

On AVR, each coefficient is stored as a fixed-point constant (see Chapter 5e
for the multiply mechanics). This chapter uses a simplified representation where
gains are powers of two so that multiplication reduces to a shift. For arbitrary
gains, use the `MUL`/`FMUL` instructions and the Q-format scaling rules from
Chapter 5e.

### Fixed-Point Representation

Use signed 16-bit values throughout. With a 10-bit ADC:

```
error range: −1023 to +1023  (signed, fits in 16 bits)
P_term:      −1023×Kp to +1023×Kp
I_accum:     must hold the running sum of many error samples

Typical gain scales:
  Kp_shift = 0  (Kp = 1): P = error              range ±1023
  Kp_shift = 2  (Kp = 4): P = error << 2         range ±4092
  Ki_shift = k  (Ki = 1/2^k): I += error >> k    integrates slowly
  Kd_shift = 0  (Kd = 1): D = (y_prev - y)       range ±1023
```

### SRAM Layout

```asm
.section .bss
pid_I_accum:  .byte 0, 0, 0, 0  /* 32-bit signed integral accumulator            */
pid_y_prev:   .byte 0, 0        /* previous output sample (for D term)           */
pid_I_min:    .byte 0, 0, 0, 0  /* anti-windup lower clamp (32-bit signed)       */
pid_I_max:    .byte 0, 0, 0, 0  /* anti-windup upper clamp (32-bit signed)       */
pid_out_min:  .byte 0, 0        /* output clamp lower bound (signed 16-bit)      */
pid_out_max:  .byte 0, 0        /* output clamp upper bound (signed 16-bit)      */
```

The integral accumulator is 32-bit because it sums many error samples. At
Ki = 1/16 (Ki_shift = 4) and a sustained error of 512 for 60 seconds at 1 kHz:
total integral = 60000 × 512 / 16 = 1,920,000, which needs 21 bits. A 32-bit
accumulator is safe.

### Proportional Term

```asm
/* P = error << Kp_shift  (signed left shift)
 * Entry:  R25:R24 = error (signed 16-bit, range −1023..+1023)
 * Exit:   R25:R24 = P_term (signed 16-bit, may overflow if Kp too large)
 * Kp_shift = 2 in this example (Kp = 4)
 */
pid_compute_P:
    lsl   r24
    rol   r25
    lsl   r24
    rol   r25                    /* r25:r24 = error × 4 (signed)                  */
    ret
```

`LSL`/`ROL` propagates the sign bit correctly for signed left shift as long as
no overflow occurs. Check that `|error| × Kp < 32767` before choosing Kp_shift.

### Integral Term with Anti-Windup

```asm
/* I_accum += error >> Ki_shift  (signed)
 * Then clamp I_accum to [pid_I_min, pid_I_max].
 *
 * Entry:  R25:R24 = error (signed 16-bit)
 * Exit:   R25:R24 = I_term (low 16 bits of I_accum, scaled for output)
 * Clobbers: R16..R23
 * Ki_shift = 4 in this example (Ki = 1/16)
 */
pid_compute_I:
    /* Sign-extend error to 32 bits: r27:r26:r25:r24 = error */
    movw  r26, r24               /* r27:r26 = r25:r24 (copy error to r27:r26)    */
    clr   r24                    /* r25:r24 = 0 for now                           */
    clr   r25
    sbrc  r27, 7                 /* check sign of original error (in r27 now)    */
    ldi   r25, 0xFF              /* if negative, sign-extend high bytes           */
    mov   r24, r25               /* r25:r24 = 0x0000 or 0xFFFF                   */

    /* Restore signed 32-bit value: r27:r26 was the original error */
    /* r27:r26:r25:r24 layout: byte0=r24(low), byte1=r25, byte2=r26, byte3=r27  */
    /* Rearrange to r23:r22:r21:r20 = 32-bit sign-extended error (low-first)    */
    movw  r20, r26               /* r21:r20 = error_lo word                      */
    movw  r22, r24               /* r23:r22 = sign extension word (0x0000/0xFFFF)*/

    /* Shift right by Ki_shift = 4 (signed: ASR high, ROR lower bytes) */
    asr   r23
    ror   r22
    ror   r21
    ror   r20
    asr   r23
    ror   r22
    ror   r21
    ror   r20
    asr   r23
    ror   r22
    ror   r21
    ror   r20
    asr   r23
    ror   r22
    ror   r21
    ror   r20                    /* r23:r22:r21:r20 = (signed error) >> 4        */

    /* I_accum += error_step (32-bit signed addition) */
    lds   r24, pid_I_accum
    lds   r25, pid_I_accum+1
    lds   r26, pid_I_accum+2
    lds   r27, pid_I_accum+3

    add   r24, r20
    adc   r25, r21
    adc   r26, r22
    adc   r27, r23

    sts   pid_I_accum,   r24
    sts   pid_I_accum+1, r25
    sts   pid_I_accum+2, r26
    sts   pid_I_accum+3, r27

    /* Anti-windup: the caller is responsible for clamping I_accum to
     * [pid_I_min, pid_I_max] and storing the clamped value back.
     * See the anti-windup section below.
     *
     * Return I_term = bytes 1 and 2 of I_accum (I_accum >> 8, low 16 bits).
     * r25 = byte1, r26 = byte2. MOVW requires even source; use two MOVs. */
    mov   r24, r25               /* r24 = accum byte 1                           */
    mov   r25, r26               /* r25 = accum byte 2                           */
    ret
```

### Derivative Term

```asm
/* D = Kd_shift * (y_prev - y)   (using output measurement for smooth D)
 *
 * Entry:  R25:R24 = current measured output y (signed or unsigned 16-bit)
 * Exit:   R25:R24 = D_term
 * Clobbers: R16, R17, R18, R19
 * Kd_shift = 1 (Kd = 2)
 */
pid_compute_D:
    /* Load y_prev */
    lds   r18, pid_y_prev
    lds   r19, pid_y_prev+1

    /* D_raw = y_prev - y (previous minus current = negative rate of change of y) */
    sub   r18, r24
    sbc   r19, r25               /* r19:r18 = y_prev - y                         */

    /* Store current y as new y_prev */
    sts   pid_y_prev,   r24
    sts   pid_y_prev+1, r25

    /* D_term = D_raw × Kd: left shift by Kd_shift = 1 */
    lsl   r18
    rol   r19                    /* r19:r18 = D_raw × 2                          */

    movw  r24, r18               /* return D_term in r25:r24                     */
    ret
```

In a real system, the derivative is usually filtered with an EMA before output
because the discrete first-difference amplifies high-frequency noise. Call
`ema16_k4` (or another suitable filter) on the result of `pid_compute_D` before
adding it to the controller output.

### Anti-Windup

Integral windup occurs when the controller output is saturated (e.g., the
actuator is at its limit) but the integrator continues to accumulate error. When
the error finally reverses, the integrator must "unwind" before the output can
change direction, causing overshoot and slow recovery.

The simplest anti-windup strategy clamps the integral accumulator to a range:

```asm
/* pid_clamp_I — clamp pid_I_accum to [pid_I_min, pid_I_max]
 *
 * All values are 32-bit signed.
 * Clobbers: R16..R23
 */
pid_clamp_I:
    /* Load current accumulator */
    lds   r16, pid_I_accum
    lds   r17, pid_I_accum+1
    lds   r18, pid_I_accum+2
    lds   r19, pid_I_accum+3     /* r19:r18:r17:r16 = I_accum (lo first)         */

    /* Compare with pid_I_min (load and compare signed 32-bit) */
    lds   r20, pid_I_min
    lds   r21, pid_I_min+1
    lds   r22, pid_I_min+2
    lds   r23, pid_I_min+3

    /* Signed comparison: I_accum < I_min? (check sign of I_accum - I_min) */
    cp    r16, r20
    cpc   r17, r21
    cpc   r18, r22
    cpc   r19, r23               /* sets flags for I_accum - I_min               */
    brge  .Lclamp_check_max      /* if I_accum >= I_min: check upper bound        */

    /* I_accum < I_min: clamp to I_min */
    sts   pid_I_accum,   r20
    sts   pid_I_accum+1, r21
    sts   pid_I_accum+2, r22
    sts   pid_I_accum+3, r23
    ret

.Lclamp_check_max:
    /* Compare with pid_I_max */
    lds   r20, pid_I_max
    lds   r21, pid_I_max+1
    lds   r22, pid_I_max+2
    lds   r23, pid_I_max+3

    cp    r16, r20
    cpc   r17, r21
    cpc   r18, r22
    cpc   r19, r23               /* sets flags for I_accum - I_max               */
    brlt  .Lclamp_done           /* if I_accum < I_max: within bounds             */

    /* I_accum >= I_max: clamp to I_max */
    sts   pid_I_accum,   r20
    sts   pid_I_accum+1, r21
    sts   pid_I_accum+2, r22
    sts   pid_I_accum+3, r23

.Lclamp_done:
    ret
```

`BRGE` and `BRLT` are signed comparisons: they branch based on the combination
of the N (negative) and V (overflow) flags after a CP/CPC sequence. The 32-bit
signed comparison CP + CPC + CPC + CPC works correctly because each CPC
propagates the carry and updates the V flag.

The clamp bounds in SRAM (`pid_I_min`, `pid_I_max`, `pid_out_min`,
`pid_out_max`) should be set during initialisation based on the actuator range
and the expected steady-state error. This example clamps the integral to
±16384 and the output to ±1023 (a stand-in for a 10-bit actuator command; pick
values that match your real actuator):

```asm
/* Set I_min/I_max = ∓16384 (0xFFFFC000 / 0x00004000)
 * and out_min/out_max = ∓1023 (0xFC01 / 0x03FF, signed 16-bit) */
pid_init_clamps:
    ldi   r16, 0x00
    ldi   r17, 0xC0
    ldi   r18, 0xFF
    ldi   r19, 0xFF
    sts   pid_I_min,   r16
    sts   pid_I_min+1, r17
    sts   pid_I_min+2, r18
    sts   pid_I_min+3, r19

    ldi   r16, 0x00
    ldi   r17, 0x40
    ldi   r18, 0x00
    ldi   r19, 0x00
    sts   pid_I_max,   r16
    sts   pid_I_max+1, r17
    sts   pid_I_max+2, r18
    sts   pid_I_max+3, r19

    /* out_min = −1023 = 0xFC01 */
    ldi   r16, 0x01
    ldi   r17, 0xFC
    sts   pid_out_min,   r16
    sts   pid_out_min+1, r17

    /* out_max = +1023 = 0x03FF */
    ldi   r16, 0xFF
    ldi   r17, 0x03
    sts   pid_out_max,   r16
    sts   pid_out_max+1, r17
    ret
```

### Assembling the Full PID Output

```asm
/* pid_update — compute full PID output
 *
 * Entry: R25:R24 = setpoint (unsigned 16-bit, same scale as ADC reading)
 *        R23:R22 = measured value y (unsigned 16-bit)
 * Exit:  R25:R24 = controller output u (signed 16-bit)
 * Clobbers: many registers — this is a top-level routine
 */
pid_update:
    /* Compute signed error = setpoint - y.
     * The P, I, and D helper routines between clobber r16..r27, so every value
     * that must survive across them is held on the stack, not in registers.    */
    sub   r24, r22
    sbc   r25, r23               /* r25:r24 = sp − y (signed error)              */
    movw  r18, r24               /* r19:r18 = error (survives pid_compute_P)     */

    push  r22                    /* save current y (for the D term)              */
    push  r23

    /* P term (input: error in r25:r24) */
    rcall pid_compute_P          /* r25:r24 = P_term (clobbers only r24:r25)     */
    push  r24                    /* save P_term on the stack                     */
    push  r25

    /* I term (input: error) */
    movw  r24, r18               /* r25:r24 = error                              */
    rcall pid_compute_I          /* r25:r24 = I_term                             */
    rcall pid_clamp_I            /* clamp accumulator (leaves r25:r24 untouched) */
    push  r24                    /* save I_term on the stack                     */
    push  r25

    /* Recover terms. Stack top→bottom holds: I_term, P_term, y */
    pop   r25                    /* I_term high                                  */
    pop   r24                    /* I_term low  → r25:r24 = I_term               */
    pop   r19                    /* P_term high                                  */
    pop   r18                    /* P_term low  → r19:r18 = P_term               */
    add   r24, r18
    adc   r25, r19               /* r25:r24 = I_term + P_term                     */

    pop   r21                    /* y high                                       */
    pop   r20                    /* y low       → r21:r20 = y                     */

    /* D term (input: current y); preserve the running sum across the call */
    push  r24                    /* save (I+P) low                               */
    push  r25                    /* save (I+P) high                              */
    movw  r24, r20               /* r25:r24 = current y                          */
    rcall pid_compute_D          /* r25:r24 = D_term                             */

    /* For a low-noise D term, filter it before summing, e.g.:                   */
    /* rcall ema16_k4            (optional: smooth the derivative)               */

    pop   r19                    /* (I+P) high                                   */
    pop   r18                    /* (I+P) low   → r19:r18 = I_term + P_term       */
    add   r24, r18
    adc   r25, r19               /* r25:r24 = P + I + D = raw controller output    */

    rcall pid_clamp_out          /* clamp u to the actuator output range          */
    ret
```

### Output Clamping

The integral clamp (`pid_clamp_I`) bounds one term; the *output* clamp bounds
the sum. Real actuators have a finite range — a PWM duty cycle between 0 and
TOP, a DAC code, a current limit — and the controller must never command beyond
it. Clamping the final `u` is what makes the integral clamp meaningful: the two
together implement saturation with anti-windup. Without the output clamp, a
saturated command is silently truncated by the actuator's own limits and the
integrator has no consistent bound to work against.

`pid_clamp_out` clamps the signed 16-bit output to `[pid_out_min, pid_out_max]`.
It is the 16-bit analogue of `pid_clamp_I`: a signed `CP`/`CPC` compare against
each bound, then a conditional `MOVW` to the bound when the output is outside it.

```asm
/* pid_clamp_out — clamp signed 16-bit output u to [pid_out_min, pid_out_max]
 *
 * Entry: R25:R24 = u (raw controller output, signed 16-bit)
 * Exit:  R25:R24 = u clamped to [pid_out_min, pid_out_max]
 * Clobbers: R18, R19
 */
pid_clamp_out:
    /* u < out_min? */
    lds   r18, pid_out_min
    lds   r19, pid_out_min+1
    cp    r24, r18
    cpc   r25, r19               /* flags for u − out_min                        */
    brge  .Lco_check_max         /* u >= out_min: check the upper bound           */
    movw  r24, r18               /* u < out_min: clamp to out_min                 */
    ret

.Lco_check_max:
    /* u > out_max? */
    lds   r18, pid_out_max
    lds   r19, pid_out_max+1
    cp    r24, r18
    cpc   r25, r19               /* flags for u − out_max                        */
    brlt  .Lco_done              /* u < out_max: already within bounds            */
    movw  r24, r18               /* u >= out_max: clamp to out_max                */

.Lco_done:
    ret
```

As with the integral clamp, `BRGE`/`BRLT` make the comparison signed, so a
negative output below `pid_out_min` is detected correctly rather than being
treated as a large unsigned value. `MOVW r24, r18` copies the 16-bit bound into
the output pair in one cycle.

In a real application, the PID structure is called from a timer ISR or a
tick-driven scheduler task once per control sample period. The control period
and gain values must be tuned to the specific plant (motor, heater, valve, etc.).

---

## Filter Selection Guide

```
Requirement                      Recommended filter
──────────────────────────────────────────────────────────────────────────────
Broadband noise, low SRAM        EMA (k=4..6, 16-bit accum)
Broadband noise, strong filter   EMA (k=8, 24-bit accum) or cascaded EMA
Isolated spike removal           Median (3-sample) as pre-stage before EMA
Known noise frequency            Box filter (place null at noise frequency)
Smooth, fast-converging          EMA with large k; pre-load accumulator
Feedback control                 EMA on sensor + PID with anti-windup
Derivative in control loop       First-difference, then EMA on D term
```

### SRAM Cost Summary

```
Filter                SRAM bytes   Notes
──────────────────────────────────────────────────────────────────────────────
EMA, 16-bit accum     2            k ≤ 6
EMA, 24-bit accum     3            k ≤ 14
Box, N=8              19           16-byte buffer + 2-byte sum + 1-byte idx
Box, N=16             35
Median (3-sample)     4            2 × 16-bit history samples
Cascaded EMA ×2       4 or 6       two independent accumulators
PID                   18           I_accum(4) + y_prev(2) + I clamps(8) + out clamps(4)
```

---

## Common Pitfalls

### Pitfall 1 — Using LSR/ROR on a Signed Value

The EMA accumulator is unsigned (all ADC results are non-negative). Use
`LSR`/`ROR` for the right shift, not `ASR`/`ROR`. The `ASR` instruction
preserves the sign bit and is correct only for signed arithmetic right shifts.
The EMA `ema24_k8` example also uses `r1` (the zero register) in `sbc r21, r1`
to propagate borrow without a literal operand. Never modify `r1` from outside
the shift chain.

### Pitfall 2 — Accumulator Overflow

A 16-bit accumulator overflows when `k > 6` for a 10-bit ADC. Symptoms: output
wraps around or jumps suddenly when the input is near the top of range.

Check before using: `k + 10 ≤ accumulator_width_bits` (the input needs about
10 bits, since `log2(1023) ≈ 10`, and the scaling adds k bits).
For k=6: 6 + 10 = 16 → exactly at the limit. ✓ for k ≤ 6; use 24-bit for k=7+.

### Pitfall 3 — Not Initialising the Accumulator

In a `-nostartfiles` build, `.bss` is not zeroed automatically. If the EMA
accumulator starts at a random SRAM value, the filter output will be incorrect
for many samples. Always zero all filter state in `reset_handler`, or pre-load
the accumulator with `first_sample × 2^k` for instant convergence.

### Pitfall 4 — Updating the Filter from Two Places

If both the ISR and the main loop call the filter update, the accumulator can
be read-modify-written non-atomically. Symptom: occasional wrong output
readings. Fix: update the filter in one place only. If the ISR stores the raw
ADC result, let the main loop call the filter update on that stored value.

### Pitfall 5 — Box Filter Zero Not Re-Zeroed After Reset

The box filter has 16 bytes of buffer plus the running sum. If only the sum is
zeroed on reset but the buffer retains stale SRAM values, the running sum
accumulates garbage from the first N updates. Zero the entire buffer and the
sum index before use.

### Pitfall 6 — Integral Windup Without Clamping

Omitting the anti-windup clamp on the integral accumulator causes the integrator
to drift arbitrarily far during saturation. On an 8-bit AVR, 32-bit overflow is
silent and wraps the accumulator. The controller then behaves correctly in the
short term but with a large hidden bias that eventually flips sign and causes
violent instability.

Always set `pid_I_min` and `pid_I_max` to values that correspond to the maximum
useful integral contribution, and call `pid_clamp_I` after every update.

### Pitfall 7 — Derivative Amplifying Noise

A 10-bit ADC with ±1 LSB noise produces first-differences of up to ±2 LSB per
sample. At a 1 kHz sample rate and Kd = 1, that is a D-term noise band of ±2.
At Kd = 16 it is ±32 — roughly 3% of full scale, visible as jitter in the
actuator output.

Always low-pass filter the derivative with a small EMA (k = 2..4) before use.
The low-pass on D limits the noise bandwidth without significantly delaying
response to genuine rate-of-change events.

---

## Summary

```
EMA (exponential moving average) — the primary ADC filter
  accum = accum - (accum >> k) + sample
  output = accum >> k
  fc ≈ fs / (2^k × 2π)
  16-bit accum for k ≤ 6;  24-bit accum for k ≤ 14

Box filter (N-point average) — broadband noise at fixed N
  running sum updated with circular buffer
  N = 2^M for efficient division (M right shifts)
  SRAM: 2N + 3 bytes

Median filter (3-sample) — spike rejection, no smoothing
  3-swap compare-and-swap sorting network
  output = middle value of last 3 samples
  SRAM: 4 bytes

Cascaded EMA — 40 dB/decade roll-off for strong filtering
  apply EMA twice; doubles SRAM and cycle cost

PID structure
  P = error >> p_shift           (or << for gain > 1)
  I += (error >> Ki_shift)       with anti-windup clamp
  D = (y_prev − y) << Kd_shift  then EMA on D
  u = clamp(P + I + D, out_min, out_max)
  Integral accumulator: 32-bit signed; clamp it AND clamp the output u

Initialisaton matters:
  zero all filter state in reset_handler (not done by -nostartfiles)
  pre-load EMA accum with first_sample × 2^k for instant convergence
  set pid_I_min / pid_I_max before enabling the controller

Signed arithmetic:
  LSR/ROR for unsigned accumulator right shifts (EMA, box output)
  ASR/ROR for signed right shifts (PID integral shift, D-term gain)
  BRGE/BRLT for signed 32-bit comparison after CP+CPC+CPC+CPC chain
```

Microchip source notes:

- ATtiny3217 data sheet, ADC result registers: `ADC0_RESL` is the low byte of
  the 10-bit result; `ADC0_RESH` holds bits 9:8. Read RESL first to latch both
  bytes.
- AVR Instruction Set Manual, `LSR Rd`: shifts Rd right by 1, zero into MSB,
  MSB into carry. Use for unsigned right shift.
- AVR Instruction Set Manual, `ASR Rd`: shifts Rd right by 1, MSB preserved
  (sign extension). Use for signed right shift.
- AVR Instruction Set Manual, `CP Rd, Rr` / `CPC Rd, Rr`: signed comparison
  flags are N ⊕ V (negative after borrow ≠ sign bit of result). BRGE/BRLT
  (branch if greater-or-equal / less-than, signed) use this combined flag.
- AVR Instruction Set Manual, `MOVW Rd, Rr`: copies a register pair. Both Rd
  and Rr must be even-numbered registers (R0, R2, ... R30).

---

## Exercises

1. Implement `ema16_k6` (k = 6, alpha = 1/64). What is the maximum safe input
   value for a 16-bit accumulator? Show that 1023 × 64 = 65472 fits in 16 bits.
   What is the cutoff frequency at fs = 1000 Hz?

2. Modify `box8_update` for N = 16. What changes: the buffer size, the sum
   width, the index mask, and the shift count? Does the sum still fit in a
   16-bit register?

3. Trace through `med3_update` for the input sequence 1023, 0, 512 (newest
   first). What is the output? Repeat for 0, 0, 1023. Does the filter behave
   as expected?

4. Implement `ema24_k10`. What are the three LDS addresses? Verify that the
   output `movw` picks up the correct two bytes of the 24-bit accumulator.

5. The `pid_clamp_I` routine uses `BRGE` (branch if greater or equal, signed)
   after a four-instruction `CP/CPC/CPC/CPC` chain. Explain why `BRSH` (branch
   if same or higher, unsigned) would give wrong results for negative accumulator
   values.

6. Connect a potentiometer to PA4 and log the raw and EMA-filtered ADC output
   over USART at 1 kHz. Use different k values (3, 5, 7) and compare the
   settling time and noise level on each setting. What k gives a useful balance
   between noise rejection and response speed for a slow-changing mechanical
   input?

---

*Next: Appendices*
