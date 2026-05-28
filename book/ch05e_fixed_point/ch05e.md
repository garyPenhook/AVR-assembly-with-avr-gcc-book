# Fixed-Point Arithmetic

Floating-point hardware does not exist on the ATtiny3217. When you need
fractional values — sensor gains, filter coefficients, percentages, scaled
ADC readings — you carry the decimal point in your head and use integer
arithmetic to do the work. This is fixed-point arithmetic.

This chapter covers fixed-point arithmetic from the representation through
every operation you will need in practice:

1. Q-format: how the decimal point is encoded in an integer register.
2. Range and resolution for the formats used most on 8-bit AVR.
3. Addition and subtraction.
4. Multiplication — the hard part, worked out in full.
5. The AVR fractional multiply instructions: FMUL, FMULS, FMULSU.
6. Division and reciprocal multiplication.
7. Conversion between fixed-point and integer.
8. Rounding and truncation.
9. Saturation and overflow detection.
10. Three complete worked examples: ADC gain scaling, a first-order low-pass
    filter, and a PID derivative term.

---

## What Fixed-Point Is

The CPU stores integers. Fixed-point assigns a constant scale factor to those
integers so they represent non-integer values. If you decide that the integer
`256` means `1.0`, then `128` means `0.5` and `384` means `1.5`. You and the
code agree on the scale. The CPU just does integer math.

The formal notation is **Q-format**. A Qm.n number has:

- `m` integer bits above the binary point
- `n` fractional bits below the binary point
- Total width: m + n bits (for unsigned), m + n + 1 bits (for signed, one bit
  for the sign)

The value represented is:

```
value = raw_integer × 2^(−n)
```

Some examples, all unsigned:

```
Format   Width   Range              Resolution    Scale
──────────────────────────────────────────────────────────────
Q0.8      8-bit   0 to 255/256        1/256        raw/256
Q1.7      8-bit   0 to 255/128        1/128        raw/128
Q4.4      8-bit   0 to 15.9375        1/16         raw/16
Q8.8     16-bit   0 to 255.996        1/256        raw/256
Q8.24    32-bit   0 to 255.9999999    1/16777216   raw/2^24
```

Signed Q-format adds a two's-complement sign bit. A signed Q1.7 number has
1 integer bit, 7 fractional bits, and 1 implicit sign bit — total 8 bits,
range −1.0 to +127/128.

The most common formats on 8-bit AVR:

```
Format    Width   Unsigned range      Signed range        Typical use
──────────────────────────────────────────────────────────────────────────
Q0.8       8      [0, 1)              —                   Blend factors, alpha
Q1.7       8      [0, 2)              [−1, +127/128]      Unit fractions, trig
Q4.4       8      [0, 16)             [−8, +7.9375]       Small scaled values
Q8.8      16      [0, 256)            [−128, +127.996]    General purpose
Q8.16     24      [0, 256)            [−128, +127.99999]  High-res sensor data
Q16.16    32      [0, 65536)          [−32768, +32767.99] Extended precision
```

---

## Representation in Registers

A Q8.8 value occupies two registers. By convention in this chapter:

```
Register pair    Contents
────────────────────────────────────────────────
r_H : r_L        integer byte : fractional byte
```

For example, 3.5 in Q8.8:
- 3.5 × 256 = 896 = 0x0380
- r_H = 0x03, r_L = 0x80

There is no special instruction or flag for fixed-point. The CPU treats the
register pair as a plain 16-bit integer. Only your interpretation gives it
meaning.

---

## Addition and Subtraction

Fixed-point addition and subtraction are identical to integer addition and
subtraction. The scales cancel:

```
(a × 2^−n) + (b × 2^−n) = (a + b) × 2^−n
```

Both operands must be in the same Q format. If they are not, align them
first by shifting the lower-resolution operand.

### Q8.8 Addition

```asm
; Add two Q8.8 values.
; A in r17:r16, B in r19:r18 → result in r17:r16.
add  r16, r18       ; fractional bytes
adc  r17, r19       ; integer bytes, carry from fractional
```

Overflow: if the integer byte wraps, the addition overflowed. The V and C
flags from `ADC` signal this, identical to unsigned 16-bit overflow detection
from chapter 5a.

### Q8.8 Subtraction

```asm
; Subtract: A = A − B.
sub  r16, r18       ; fractional bytes
sbc  r17, r19       ; integer bytes, borrow from fractional
```

---

## Multiplication

Multiplication is where fixed-point diverges from plain integer work. When
you multiply two Q8.8 numbers the result has twice as many fractional bits
and needs to be shifted back:

```
(a × 2^−8) × (b × 2^−8) = (a × b) × 2^−16
```

To express the result as Q8.8 (scale 2^−8), divide the raw 32-bit product by
2^8 — that is, discard the lowest 8 bits and keep the next 16:

```
raw 32-bit product:  bits[31:24] bits[23:16] bits[15:8] bits[7:0]
                     overflow    integer     fractional  sub-frac
                                 ──── Q8.8 result ────
```

The AVR has no 16×16 multiply instruction, so you build it from four 8×8
partial products using `MUL`.

### The MUL Family

```
Instruction   Operands           Result         Register constraints
──────────────────────────────────────────────────────────────────────
MUL  Rd, Rr   unsigned × unsigned  R1:R0 = Rd×Rr  Rd, Rr ∈ R0–R31
MULS Rd, Rr   signed   × signed   R1:R0 = Rd×Rr  Rd, Rr ∈ R16–R31
MULSU Rd, Rr  signed   × unsigned R1:R0 = Rd×Rr  Rd, Rr ∈ R16–R23
FMUL  Rd, Rr  unsigned × unsigned R1:R0 = (Rd×Rr)<<1  Rd, Rr ∈ R16–R23
FMULS Rd, Rr  signed   × signed   R1:R0 = (Rd×Rr)<<1  Rd, Rr ∈ R16–R23
FMULSU Rd, Rr signed   × unsigned R1:R0 = (Rd×Rr)<<1  Rd, Rr ∈ R16–R23
```

`MUL` always places the result in R1:R0. **The GCC/avr-libc ABI assumes R1 is
zero at all times except during a multiply.** Clear R1 with `clr r1` after
every `MUL` family instruction before any call, interrupt return, or branch
that may reach code expecting R1 = 0.

### Unsigned Q8.8 Multiplication

Label registers: A_H:A_L = r17:r16, B_H:B_L = r19:r18.
The 32-bit product occupies a four-register accumulator p3:p2:p1:p0.

Partial products:

```
P00 = A_L × B_L → contributes to bits [15:0]
P01 = A_L × B_H → contributes to bits [23:8]
P10 = A_H × B_L → contributes to bits [23:8]
P11 = A_H × B_H → contributes to bits [31:16]
```

Q8.8 result = p2:p1 (integer byte p2, fractional byte p1).
p0 is the sub-fractional byte used for rounding. p3 indicates overflow.

```asm
; mul_q8_8_unsigned — unsigned Q8.8 × Q8.8 → Q8.8
;
; Input:  A in r17:r16 (r17=integer, r16=fractional)
;         B in r19:r18 (r19=integer, r18=fractional)
; Output: result in r22:r21 (r22=integer, r21=fractional)
;         r20 = sub-fractional byte (for rounding)
;         r23 = overflow byte (non-zero = result exceeded Q8.8 range)
; Clobbers: r0, r1 (cleared on exit)

mul_q8_8_unsigned:
    ; P00 = A_L × B_L
    mul     r16, r18        ; R1:R0 = A_L × B_L (unsigned)
    movw    r20, r0         ; p1:p0 = R1:R0
    clr     r22
    clr     r23

    ; P01 = A_L × B_H
    mul     r16, r19        ; R1:R0 = A_L × B_H
    add     r21, r0         ; p1 += low byte
    adc     r22, r1         ; p2 += high byte + carry
    clr     r1
    adc     r23, r1         ; p3 += carry

    ; P10 = A_H × B_L
    mul     r17, r18        ; R1:R0 = A_H × B_L
    add     r21, r0
    adc     r22, r1
    clr     r1
    adc     r23, r1

    ; P11 = A_H × B_H
    mul     r17, r19        ; R1:R0 = A_H × B_H
    add     r22, r0
    adc     r23, r1
    clr     r1              ; restore R1 = 0

    ret
    ; Result: Q8.8 integer byte in r22, fractional byte in r21.
    ; For truncated result use r22:r21 directly.
    ; For rounded result see rounding section below.
```

**Worked trace — 1.5 × 1.5 = 2.25:**

1.5 in Q8.8 = 0x0180 → r17=0x01, r16=0x80
B = same: r19=0x01, r18=0x80

```
P00: 0x80 × 0x80 = 0x4000  → p1:p0 = 0x40:0x00
P01: 0x80 × 0x01 = 0x0080  → p1 += 0x80 → p1=0xC0, p2=0x00
P10: 0x01 × 0x80 = 0x0080  → p1 += 0x80 → p1=0x40 (carry!), p2=0x01
P11: 0x01 × 0x01 = 0x0001  → p2 += 0x01 → p2=0x02

p3:p2:p1:p0 = 0x00:0x02:0x40:0x00
Q8.8 result = p2:p1 = 0x02:0x40 = 2.25 ✓
```

### Signed Q8.8 Multiplication

When the integer bytes are signed (two's complement), the partial products
use mixed-sign multiplies:

```
P00 = A_L × B_L     — unsigned × unsigned  → MUL
P01 = B_H × A_L     — signed   × unsigned  → MULSU  (Rd=B_H signed)
P10 = A_H × B_L     — signed   × unsigned  → MULSU  (Rd=A_H signed)
P11 = A_H × B_H     — signed   × signed    → MULS
```

`MULSU Rd, Rr` treats Rd as signed and Rr as unsigned. Both Rd and Rr must
be in R16–R23. After `MULSU`, the C flag equals bit 15 of R1:R0 (the sign
of the 16-bit partial product). `SBC Rx, Rx` uses that C flag to produce a
sign-extension byte: 0xFF if C=1, 0x00 if C=0. This byte is added into the
top accumulator register to correctly sign-extend the partial product to
32 bits. This is the pattern documented in Microchip Application Note
**AVR201** (Using the AVR Hardware Multiplier).

```asm
; mul_q8_8_signed — signed Q8.8 × Q8.8 → Q8.8
;
; Input:  A in r17:r16 (r17=signed integer, r16=unsigned fractional)
;         B in r19:r18 (r19=signed integer, r18=unsigned fractional)
;         All registers must be in R16–R23 (MULS/MULSU constraint).
; Output: Q8.8 result in r22:r21 (r22=signed integer, r21=fractional)
;         r20 = sub-fractional byte (for rounding)
;         r23 = sign-extended overflow byte
; Clobbers: r0, r1 (cleared on exit)

mul_q8_8_signed:
    ; P00: A_L × B_L (unsigned × unsigned)
    mul     r16, r18
    movw    r20, r0         ; p1:p0 = R1:R0
    clr     r22
    clr     r23

    ; P01: B_H(signed) × A_L(unsigned)
    mulsu   r19, r16        ; MULSU Rd=r19(signed B_H), Rr=r16(unsigned A_L)
                            ; C flag = bit15 of result = sign of partial product
    sbc     r23, r23        ; r23 = 0xFF (negative product) or 0x00 (positive)
    add     r21, r0         ; accumulate low byte
    adc     r22, r1         ; accumulate high byte
    adc     r23, r1         ; r23 += r1 + carry (r1 is high byte of product)
    clr     r1              ; restore R1 = 0

    ; P10: A_H(signed) × B_L(unsigned)
    mulsu   r17, r18        ; MULSU Rd=r17(signed A_H), Rr=r18(unsigned B_L)
    sbc     r23, r23        ; sign-extend partial product
    add     r21, r0
    adc     r22, r1
    adc     r23, r1
    clr     r1

    ; P11: A_H(signed) × B_H(signed)
    muls    r17, r19        ; MULS: both R16–R31 constraint, r17 and r19 qualify
    add     r22, r0
    adc     r23, r1
    clr     r1

    ret
    ; Q8.8 result: signed integer byte in r22, fractional byte in r21.

---

## The FMUL Family: Fractional Multiply

The FMUL instructions are purpose-built for Q1.7 arithmetic. They
multiply and shift the result left by 1 bit in a single instruction cycle:

```
FMUL  Rd, Rr:  R1:R0 = (unsigned Rd × unsigned Rr) << 1
FMULS Rd, Rr:  R1:R0 = (signed Rd   × signed Rr)   << 1
FMULSU Rd, Rr: R1:R0 = (signed Rd   × unsigned Rr) << 1
```

Operands: Rd, Rr ∈ R16–R23.
Flags: C = bit 15 of the unshifted product (i.e. bit 16 of the shifted result,
overflow indicator for Q1.7). Z = result is zero.

### Why the Left Shift?

In Q1.7 format, each value has 1 integer bit and 7 fractional bits. When two
Q1.7 numbers are multiplied, the raw 16-bit product has 2 integer bits and 14
fractional bits (Q2.14). The two integer bits are always a sign-extended copy
of each other for values in [−1, +1). Shifting left by 1 removes the
redundant copy, returning a Q1.15 result in R1:R0 where R1 holds the Q1.7
high byte.

```
Q1.7 × Q1.7 product:  [I][I][f6..f0][f6..f0]  (Q2.14, 16-bit)
After left shift:      [I][f6..f0][f6..f0][0]  (Q1.15, 16-bit)
High byte R1:          [I][f6..f0]              (Q1.7 result)
```

### Q0.8 Multiply with MUL

For unsigned Q0.8 (values 0 to 255/256), use plain `MUL` and keep the high
byte R1:

```asm
; Q0.8 × Q0.8 → Q0.8.
; a in r16, b in r17. Result in r1 (Q0.8). r0 = sub-fractional byte.
mul     r16, r17        ; R1:R0 = a × b (16-bit unsigned product)
; R1 = (a × b) >> 8 = Q0.8 result.
; R0 = sub-fractional (used for rounding).
clr     r1              ; restore R1 = 0
```

Why R1? A Q0.8 value has implicit scale 1/256. The product of two Q0.8
integers `a` and `b` is `(a × b)`, and the Q0.8 result value is
`(a × b) / 256`, which is exactly R1 (the high byte of the 16-bit product).

**Do not use FMUL for Q0.8.** FMUL shifts the product left by 1, yielding
`R1 = (a × b) >> 7`, which is twice the correct value. FMUL is designed
specifically for Q1.7 format (scale 1/128).

### Q1.7 Signed Multiply with FMULS

For signed Q1.7 (values −1.0 to +127/128):

```asm
; Signed Q1.7 × Q1.7 → Q1.7.
; Inputs in r16 (signed), r17 (signed). Result in r1 (signed Q1.7).
fmuls   r16, r17
; R1 = Q1.7 result. C flag set if result would overflow Q1.7.
clr     r1
```

Special case: FMULS(−1.0, −1.0) sets C=1 because +1.0 cannot be represented
in signed Q1.7 (maximum is +127/128). Check C after FMULS when overflow is
possible and saturate if needed.

### Mixed-Sign Fractional Multiply with FMULSU

Used when one operand is a signed coefficient and the other is an unsigned
signal sample (common in filters and control loops):

```asm
; signed Q1.7 coefficient in r16, unsigned Q0.8 sample in r17.
; Result in R1:R0 (signed Q1.15, or take R1 as signed Q1.7).
fmulsu  r16, r17
clr     r1
```

---

## Division

AVR has no divide instruction. Fixed-point division is handled two ways:

### Divide by a Constant: Multiply by Reciprocal

Dividing by a constant `d` is equivalent to multiplying by `1/d`. Pre-compute
the reciprocal as a Q0.16 constant and use a 16-bit multiply:

```
Example: divide Q8.8 value by 3.
1/3 in Q0.16 = round(65536 / 3) = 21845 = 0x5555

; x / 3 using Q0.16 reciprocal
; x in r17:r16 (Q8.8)
ldi     r18, lo8(21845)      ; 0x55
ldi     r19, hi8(21845)      ; 0x55
; 16×16 unsigned multiply, keep bits[31:16] as the result
; (shifting right by 16 after multiply by 1/2^16 reciprocal)
; Full 32-bit product needed; bits [31:16] = x/3 in Q8.8.
```

The 32-bit product of a Q8.8 value by a Q0.16 reciprocal gives a Q8.24
full product; bits [31:16] of that product are the Q8.8 result.

### Divide by a Power of Two: Arithmetic Shift Right

```asm
; Divide Q8.8 value in r17:r16 by 4 (shift right 2).
asr     r17             ; arithmetic shift right of high byte
ror     r16             ; rotate right of low byte (with carry from asr)
asr     r17
ror     r16
```

`ASR` preserves the sign bit. `ROR` passes the carry bit into the MSB,
completing the 16-bit right shift. Two iterations divide by 4.

### Variable Division: Software Routine

For variable divisors, use a software long-division routine or restructure
the algorithm to use only multiplies (often possible in control and signal
processing code).

---

## Type Conversion

### Integer to Fixed-Point

Shift left by n bits (the number of fractional bits):

```asm
; Convert 8-bit unsigned integer in r16 to Q8.8 in r17:r16.
mov     r17, r16        ; integer part
clr     r16             ; fractional part = 0
```

For Q4.4 from a 4-bit integer: shift left 4.

```asm
; 8-bit integer in r16 → Q4.4 in r16 (same byte, fractional bits zeroed).
; Integer value must be in [0,15] to fit.
swap    r16             ; swap nibbles: integer nibble → high nibble
andi    r16, 0xF0       ; zero the low (fractional) nibble
```

### Fixed-Point to Integer (Truncation)

Discard the fractional byte:

```asm
; Q8.8 in r17:r16 → integer in r17 (truncated toward zero).
; r16 (fractional byte) is discarded.
```

For Q4.4: shift right 4.

```asm
swap    r16
andi    r16, 0x0F       ; keep high nibble as integer in low nibble
```

### Fixed-Point to Integer with Rounding

Add 0.5 (half LSB of the integer part) before truncating:

```asm
; Q8.8 in r17:r16 → rounded integer in r17.
ldi     r18, 0x80       ; 0.5 in Q0.8
add     r16, r18        ; add 0.5 to fractional byte
adc     r17, r1         ; carry into integer byte (r1 = 0)
; r17 is now the rounded integer result.
```

### Changing Q Format

To convert from Qm.n to Qm.k (same total width, different split):

- If k > n (more fractional bits): shift left (k − n) bits.
- If k < n (fewer fractional bits): shift right (n − k) bits (truncate or
  round).

---

## Rounding

Truncation is the default (just drop bits). Rounding to nearest adds 0.5 ULP
(unit in the last place of the result) before truncating.

For Q8.8 multiplication, r20 holds the sub-fractional byte. Round by adding
the MSB of r20 as a carry into the result:

```asm
; After mul_q8_8_unsigned, result in r22:r21, sub-frac in r20.
lsl     r20             ; shift sub-frac MSB into carry
adc     r21, r1         ; round fractional byte (r1 = 0)
adc     r22, r1         ; carry into integer byte
; r22:r21 = rounded Q8.8 result.
```

---

## Saturation

When fixed-point addition or multiplication overflows, the result wraps. For
control systems and audio processing, **saturation arithmetic** clamps the
result to the representable maximum or minimum instead.

### Saturating Q8.8 Addition (Unsigned)

```asm
; Saturating add: r17:r16 + r19:r18 → r17:r16, clamped to [0, 255.996].
add     r16, r18
adc     r17, r19
brcc    .no_overflow_add    ; C clear = no overflow
ldi     r16, 0xFF          ; saturate to 0xFF:0xFF (maximum Q8.8)
ldi     r17, 0xFF
.no_overflow_add:
```

### Saturating Q8.8 Addition (Signed)

For signed Q8.8, overflow occurs when two positives produce a negative or
two negatives produce a positive. The V flag signals this:

```asm
; Signed saturating add.
add     r16, r18
adc     r17, r19
brvs    .signed_overflow    ; V set = signed overflow
rjmp    .done_add
.signed_overflow:
    ; If result MSB is 0 after overflow, we went positive→negative (underflow).
    ; Set to 0x8000 (minimum). Otherwise set to 0x7FFF (maximum).
    ldi     r16, 0x00
    ldi     r17, 0x80       ; assume underflow: minimum = −128.0
    sbrs    r17, 7          ; if result MSB was 1 (went negative→positive)
    ldi     r16, 0xFF       ;   maximum = +127.996
    sbrs    r17, 7
    ldi     r17, 0x7F
.done_add:
```

### Overflow Detection After Multiplication

After `mul_q8_8_unsigned`, r23 is non-zero if the result exceeds 255.996:

```asm
tst     r23
brne    .multiply_overflow
```

---

## Practical Examples

### Example 1: ADC Gain Scaling

An ADC returns a 10-bit result (0–1023). You want to convert it to millivolts
given VCC = 3300 mV:

```
mV = adc_result × (3300 / 1024)
   = adc_result × 3.22265625
```

Express the gain 3.22265625 as Q8.8: 3.22265625 × 256 = 825 = 0x0339.
Gain: r_gain_H = 0x03, r_gain_L = 0x39.

The ADC result is a 10-bit integer. Treat it as Q8.8 by storing it as-is
in a 16-bit pair (the value is an integer, so fractional part = 0x00):

```asm
; ADC result in r25:r24 (10-bit integer, max 0x03FF).
; Gain 0x0339 in r21:r20.
; Result (millivolts, Q8.8) in r23:r22:r21:r20 after multiply.

; Load gain
ldi     r20, lo8(825)   ; 0x39
ldi     r21, hi8(825)   ; 0x03

; The ADC integer value treated as Q8.8 (fractional byte = 0):
; A_H:A_L = r25:r24,  B_H:B_L = r21:r20

; P00 = 0 × gain_L = 0 (A_L = 0 since integer)
; P01 = 0 × gain_H = 0
; P10 = adc_L × gain_L
mul     r24, r20        ; R1:R0 = adc_L × gain_L
movw    r22, r0         ; p1:p0

; P11 is split because adc is 16-bit:
; P10' = adc_H × gain_L
mul     r25, r20
add     r23, r0         ; note: result fits in r23 for typical ADC values

; P01' = adc_L × gain_H
mul     r24, r21
add     r23, r0
clr     r1

; P11' = adc_H × gain_H
mul     r25, r21
add     r23, r0         ; overflow lands here (can be checked)
clr     r1

; mV result (Q8.8 integer part) in r23 for typical values.
; For exact result including fractional, r23:r22 is the Q8.8 mV value.
```

For a cleaner implementation, call `mul_q8_8_unsigned` directly with the
ADC result as the Q8.8 value (integer byte = high bits, fractional byte = 0).

### Example 2: First-Order Low-Pass Filter

A single-pole IIR low-pass filter:

```
y[n] = y[n−1] + α × (x[n] − y[n−1])
```

where α ∈ (0, 1) is the smoothing factor in Q0.8. A smaller α gives more
smoothing.

```asm
; Low-pass filter step.
; x (new sample) in r17:r16  (Q8.8)
; y (previous output) in r19:r18  (Q8.8)
; alpha in r20  (Q0.8, e.g. 0x1A ≈ 0.1 for heavy smoothing)
; Result (new y) written back to r19:r18.
;
; Steps:
;   1. err = x − y   (Q8.8 subtraction)
;   2. adj = alpha × err   (Q0.8 × Q8.8 multiply, keep Q8.8 result)
;   3. y  = y + adj

    ; Step 1: err = x − y  (r17:r16 − r19:r18)
    sub     r16, r18        ; fractional
    sbc     r17, r19        ; integer (with borrow)
    ; err in r17:r16

    ; Step 2: adj = alpha × err
    ; This is Q0.8 × Q8.8. The result is Q8.8:
    ; alpha (Q0.8) × err_H (Q8.8 integer) → partial Q8.8
    ; alpha (Q0.8) × err_L (Q8.8 fractional) → partial sub-fractional
    ;
    ; Result = (alpha × err_H) giving integer and fractional parts,
    ;          plus (alpha × err_L) >> 8 as the fractional contribution.

    mul     r20, r16        ; alpha × err_L (unsigned × unsigned)
    mov     r22, r1         ; save high byte (fractional contribution)
    clr     r1

    mul     r20, r17        ; alpha × err_H (unsigned × signed → needs MULSU)
    ; For signed err_H, use MULSU:
    ; mulsu r17, r20  (but r17 may not be in r16-r23 — adjust if needed)
    ; Assuming registers are arranged in R16–R23:
    add     r22, r0         ; add low byte of (alpha × err_H)
    clc
    adc     r23, r1         ; add high byte (integer of result)
    clr     r1
    ; adj in r23:r22 (Q8.8)

    ; Step 3: y = y + adj
    add     r18, r22        ; fractional
    adc     r19, r23        ; integer
    ; Updated y in r19:r18.
```

### Example 3: PID Derivative Term

A PID controller derivative term scaled by a Q8.8 coefficient Kd:

```
D = Kd × (error − prev_error)
```

```asm
; error in r17:r16 (Q8.8, signed)
; prev_error in r19:r18 (Q8.8, signed)
; Kd in r21:r20 (Q8.8, unsigned coefficient)
; Result D in r22:r21 (Q8.8)

    ; delta = error − prev_error
    sub     r16, r18
    sbc     r17, r19
    ; delta in r17:r16

    ; D = Kd × delta (signed Q8.8 multiply)
    ; Use mul_q8_8_signed with r17:r16 and r21:r20.
    ; Call mul_q8_8_signed — result in r22:r21.
    rcall   mul_q8_8_signed
```

---

## Choosing a Format

```
Situation                            Recommended format
──────────────────────────────────────────────────────────────────────────
Blend factor, alpha 0–1               Q0.8 (unsigned)
Unit trig values −1 to +1             Q1.7 (signed) with FMULS
ADC scaling, general fractions        Q8.8
Control coefficients (medium range)   Q8.8 signed
High-resolution sensor accumulator    Q8.16 or Q16.16
Intermediate multiply accumulator     Use 32-bit (four registers)
```

Pick the narrowest format that covers your range with the resolution you need.
Wider formats cost more instructions per operation. Q8.8 is the default
starting point for most general-purpose fixed-point work on 8-bit AVR.

---

## Summary

Fixed-point arithmetic on AVR is integer arithmetic with a documented scale.
The key rules:

- **Same Q format to add/subtract.** The hardware does plain `ADD`/`SUB`.
- **Multiply shifts the binary point:** Q8.8 × Q8.8 = Q16.16 raw; extract
  bits [23:8] to get the Q8.8 result.
- **Four partial products** for 16×16: use `MUL`, `MULS`, `MULSU` according
  to signedness. Follow Microchip AVR201 for the complete signed version.
- **FMUL family** is purpose-built for Q1.7/Q0.8: one instruction multiplies
  and shifts. Operands must be in R16–R23. Clear R1 after every MUL-family
  instruction.
- **Always clear R1** before any code that assumes R1 = 0 (calls, returns,
  interrupts).
- **Saturation prevents wrap-around** for control and audio code.
- **Pre-computed reciprocals** replace division by constants.
