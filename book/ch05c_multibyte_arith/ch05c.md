# Multi-byte Addition, Subtraction, Comparison, and Negation

Chapters 5a and 5b established the rules for 8-bit and 16-bit arithmetic. This
chapter takes the same carry-chain principle and pushes it to 24 bits, 32 bits,
and arbitrary width. The operations — addition, subtraction, comparison, and
negation — stay the same. What changes is understanding exactly how the carry
flag threads across three or more bytes, how the zero flag behaves in long
chains, and how to negate multi-byte two's complement values correctly.

The chapter covers unsigned and signed interpretations throughout, addresses the
SRAM storage conventions that govern multi-byte variable layout, and closes with
practical subroutines for 32-bit counters, accumulators, and comparisons.

---

## The Carry Chain Principle

Chapter 5a introduced the two-byte carry chain for 16-bit arithmetic:

```asm
add  r24, r22       ; low bytes: r24 = r24 + r22, C updated
adc  r25, r23       ; high bytes: r25 = r25 + r23 + C
```

The principle behind this is universal: a binary addition or subtraction of any
width is a sequence of 8-bit operations, each feeding its carry or borrow into
the next byte via the C flag.

The invariant is simple:

```
First byte:  ADD or SUB  — consumes no carry, produces a carry
Middle bytes: ADC or SBC — consumes carry from the byte below, produces a carry
Last byte:   ADC or SBC  — consumes carry from the byte below; C/V after this
                           instruction reflect the entire operation
```

The CPU does not need to know how many bytes you intend to chain. It computes
the 8-bit result and sets C. The next `ADC` or `SBC` reads that C. You decide
when to stop. That is the entire mechanism.

**Three rules that never change:**

1. Always start at the least-significant byte.
2. The first byte uses ADD or SUB. Every subsequent byte uses ADC or SBC.
3. Read C and V only after the final instruction in the chain.

---

## 24-bit Unsigned Arithmetic

### Register Layout for 24-bit Values

A 24-bit value occupies three registers. By convention the notation is:

```
Rh:Rm:Rl  — high : middle : low
```

The numeric value is:
```
value = (Rh × 65536) + (Rm × 256) + Rl
```

A 24-bit unsigned value spans 0 to 16,777,215 (0xFFFFFF). Common uses:
a 24-bit timer tick counter, a cumulative distance in micrometres, or
a signed audio sample expressed in 24-bit linear PCM.

No single-register constraint applies: any three registers can hold a 24-bit
value. A common arrangement in GCC-generated code is `r22:r21:r20` or
`r24:r23:r22`.

### 24-bit Addition: ADD + ADC + ADC

```asm
; 24-bit unsigned add: r26:r25:r24 = r26:r25:r24 + r22:r21:r20
add  r24, r20       ; byte 0 (low):    r24 = r24 + r20,         C updated
adc  r25, r21       ; byte 1 (mid):    r25 = r25 + r21 + C,     C updated
adc  r26, r22       ; byte 2 (high):   r26 = r26 + r22 + C,     C final
```

Three instructions. The first is ADD; the rest are ADC. The order is fixed: low
byte first, high byte last.

**Worked trace:** 0x00FFA0 + 0x000160 = 0x010100

```
r26:r25:r24 = 0x00 : 0xFF : 0xA0
r22:r21:r20 = 0x00 : 0x01 : 0x60

ADD r24, r20:  0xA0 + 0x60 = 0x100  →  r24 = 0x00, C = 1
ADC r25, r21:  0xFF + 0x01 + 1(C)   = 0x101  →  r25 = 0x01, C = 1
ADC r26, r22:  0x00 + 0x00 + 1(C)   = 0x01   →  r26 = 0x01, C = 0

Result: r26:r25:r24 = 0x01:0x01:0x00 = 0x010100 = 65792  ✓
```

After the chain:
- C = 0: result fits in 24 bits
- C = 1: unsigned overflow — result exceeded 0xFFFFFF and wrapped

### 24-bit Subtraction: SUB + SBC + SBC

```asm
; 24-bit unsigned subtract: r26:r25:r24 = r26:r25:r24 - r22:r21:r20
sub  r24, r20       ; byte 0 (low):    r24 = r24 - r20,         C=borrow
sbc  r25, r21       ; byte 1 (mid):    r25 = r25 - r21 - C
sbc  r26, r22       ; byte 2 (high):   r26 = r26 - r22 - C,     C final
```

**Worked trace:** 0x010000 − 0x000001 = 0x00FFFF (no overflow)

```
r26:r25:r24 = 0x01 : 0x00 : 0x00
r22:r21:r20 = 0x00 : 0x00 : 0x01

SUB r24, r20:  0x00 - 0x01  →  borrow  →  r24 = 0xFF, C = 1
SBC r25, r21:  0x00 - 0x00 - 1(C)  →  borrow  →  r25 = 0xFF, C = 1
SBC r26, r22:  0x01 - 0x00 - 1(C)  →  0x00    →  r26 = 0x00, C = 0

Result: r26:r25:r24 = 0x00:0xFF:0xFF = 0x00FFFF = 65535  ✓
```

After the chain:
- C = 0: result is non-negative (no borrow)
- C = 1: unsigned underflow — result went below 0 and wrapped

### Unsigned Overflow and Underflow Detection

```asm
; After 24-bit add:
add  r24, r20
adc  r25, r21
adc  r26, r22
brcs overflow_24    ; C=1 after final ADC → result > 0xFFFFFF

; After 24-bit subtract:
sub  r24, r20
sbc  r25, r21
sbc  r26, r22
brcs underflow_24   ; C=1 after final SBC → result < 0
```

---

## 32-bit Unsigned Arithmetic

32-bit values appear constantly in embedded firmware: millisecond uptime
counters, cumulative pulse counts from motor encoders, 32-bit CRC accumulators,
and Unix timestamps. At a 1 ms tick rate, a 16-bit counter rolls over in 65
seconds; a 32-bit counter rolls over in 49 days.

### Register Layout for 32-bit Values

Four registers. Notation: `Rhh:Rhl:Rlh:Rll` (highest byte to lowest byte):

```
value = (Rhh × 16777216) + (Rhl × 65536) + (Rlh × 256) + Rll
```

GCC returns 32-bit results in `r25:r24:r23:r22` (most significant in r25).
General temporaries often use `r19:r18:r17:r16`.

### 32-bit Addition: ADD + ADC + ADC + ADC

```asm
; 32-bit unsigned add: r25:r24:r23:r22 += r19:r18:r17:r16
add  r22, r16       ; byte 0 (lowest):
adc  r23, r17       ; byte 1
adc  r24, r18       ; byte 2
adc  r25, r19       ; byte 3 (highest): C=1 on unsigned overflow
```

The pattern is uniform: one ADD followed by N−1 ADCs, lowest byte first.

**Worked trace:** 0x00FFFFFF + 0x00000001 = 0x01000000

```
r25:r24:r23:r22 = 0x00 : 0xFF : 0xFF : 0xFF
r19:r18:r17:r16 = 0x00 : 0x00 : 0x00 : 0x01

ADD r22, r16:  0xFF + 0x01 = 0x100  →  r22 = 0x00, C = 1
ADC r23, r17:  0xFF + 0x00 + 1 = 0x100  →  r23 = 0x00, C = 1
ADC r24, r18:  0xFF + 0x00 + 1 = 0x100  →  r24 = 0x00, C = 1
ADC r25, r19:  0x00 + 0x00 + 1 = 0x01   →  r25 = 0x01, C = 0

Result: r25:r24:r23:r22 = 0x01000000  ✓
```

### 32-bit Subtraction: SUB + SBC + SBC + SBC

```asm
; 32-bit unsigned subtract: r25:r24:r23:r22 -= r19:r18:r17:r16
sub  r22, r16       ; byte 0 (lowest)
sbc  r23, r17       ; byte 1
sbc  r24, r18       ; byte 2
sbc  r25, r19       ; byte 3 (highest): C=1 on unsigned underflow
```

### 32-bit Signed Overflow

After a 32-bit chain, the final ADC or SBC instruction sets V for signed
overflow. V=1 means the signed mathematical result fell outside
[−2,147,483,648, +2,147,483,647].

```asm
; Signed overflow detection after 32-bit add:
add  r22, r16
adc  r23, r17
adc  r24, r18
adc  r25, r19
brvs signed_overflow_32   ; V=1 → result left signed 32-bit range
```

---

## Extending to N Bytes

The pattern generalises linearly. For an N-byte add:

```asm
add  R_byte0, R_other_byte0   ; first byte: ADD
adc  R_byte1, R_other_byte1   ; all subsequent bytes: ADC
adc  R_byte2, R_other_byte2
; ... repeat for each byte ...
adc  R_byteN-1, R_other_byteN-1   ; last byte: ADC, C final here
```

For an N-byte subtract, replace ADD with SUB and all ADC with SBC.

### 8-byte (64-bit) Addition

A 64-bit counter fits eight registers. The pattern extends straightforwardly:

```asm
; 64-bit add: r7:r6:r5:r4:r3:r2:r1_lo:r0_lo += r15:r14:r13:r12:r11:r10:r9:r8
; (using r0–r7 for accumulator, r8–r15 for addend)
; Note: r1 must be zero per GCC ABI — use r0 if standalone assembly only
add  r0, r8
adc  r1, r9
adc  r2, r10
adc  r3, r11
adc  r4, r12
adc  r5, r13
adc  r6, r14
adc  r7, r15
```

AVR has 32 general-purpose 8-bit registers. A 64-bit counter needs 8 of them.
A 32-bit counter is far more common in practice, but the mechanism is the same.

### Adding a Constant to an N-byte Value

For small constants (0–63) on a supported register pair, `ADIW` handles two
bytes in one instruction. For wider constants or unsupported pairs, load the
constant and use `ADD`+`ADC`:

```asm
; 32-bit: r25:r24:r23:r22 += 1 (increment)
; Option 1: INC chain (only for +1, uses Z not C — see pitfalls)
; Option 2: add via zero registers
clr  r16            ; r16 = 0
ldi  r17, 1         ; r17 = 1
add  r22, r17       ; low byte += 1
adc  r23, r16       ; middle bytes += 0 + carry
adc  r24, r16
adc  r25, r16
```

For the common `+= 1` case on a 32-bit value where the low word is in a
supported ADIW pair, a faster approach avoids loading a constant:

```asm
; 32-bit increment: r25:r24:r23:r22 += 1
; r23:r22 is not an ADIW pair, but r25:r24 is — must use ADD+ADC approach
ldi  r16, 1
ldi  r17, 0
add  r22, r16
adc  r23, r17
adc  r24, r17
adc  r25, r17
```

For adding a 32-bit constant to a 32-bit value in r16–r31 registers, load the
constant into a temporary quad and use `ADD`+`ADC`:

```asm
; r25:r24:r23:r22 += 86400  (seconds per day, for timestamp arithmetic)
; 86400 = 0x00015180
ldi  r16, lo8(86400)         ; r16 = 0x80
ldi  r17, byte2(86400)       ; r17 = 0x51
ldi  r18, byte3(86400)       ; r18 = 0x01
ldi  r19, byte4(86400)       ; r19 = 0x00
add  r22, r16
adc  r23, r17
adc  r24, r18
adc  r25, r19
```

The assembler expression `byte2(K)` extracts bits 15:8, `byte3(K)` extracts
bits 23:16, and `byte4(K)` extracts bits 31:24 of a 32-bit constant K.

---

## The Zero Flag in Multi-byte Chains

### The SBC and CPC Zero-Flag Rule

The SBC (Subtract with Carry) and CPC (Compare with Carry) instructions follow
a special rule for the Z flag that is different from every other instruction:

> **SBC and CPC only clear Z. They never set Z.**

This means: if Z was already 0 (previous byte was nonzero), Z stays 0 after
SBC. If Z was already 1 (previous byte was zero), SBC leaves Z=1 only if the
current byte also produces a zero result.

The hardware rationale: Z can be used as a "still all zeros so far" accumulator
across a multi-byte chain. After the final SBC or CPC, Z=1 means every byte in
the chain computed to zero — the entire multi-byte value is zero.

Compare this to ADC, which sets Z normally based on its own byte result alone.
For equality testing across a subtraction chain, SBC's special Z behaviour is
exactly right. For addition, you need a different approach (see below).

### Reading Z After a Chain

```asm
; 32-bit subtraction with equality check:
sub  r22, r16
sbc  r23, r17
sbc  r24, r18
sbc  r25, r19
; Now: Z=1 iff all four bytes computed to zero iff r25:r24:r23:r22 == r19:r18:r17:r16
breq values_equal
```

Do not read Z after only some of the SBC instructions and expect it to reflect
the whole value:

```asm
sub  r22, r16
sbc  r23, r17       ; ← Z is NOT yet valid for the 32-bit result; never read Z here
sbc  r24, r18
sbc  r25, r19       ; ← only here is Z valid for the full 32-bit result
```

### Testing Whether a Multi-byte Value Is Zero (Without Subtraction)

For checking whether a register group is zero without performing a subtraction,
OR all bytes together and test Z:

```asm
; Is r25:r24:r23:r22 == 0?
mov  r0, r22
or   r0, r23
or   r0, r24
or   r0, r25
breq is_zero        ; Z=1: all four bytes were zero
```

OR only sets Z if the result byte is zero, which happens only when all four
sources had zero bits in every position — i.e. all were 0x00.

Alternatively, OR the upper bytes into a scratch and use TST:

```asm
; Inline 32-bit zero test (clobbers r0):
mov  r0, r22
or   r0, r23
or   r0, r24
or   r0, r25        ; r0 = bitwise OR of all four bytes
; Z=1: all four were 0x00 → r25:r24:r23:r22 == 0
breq all_zero
```

### Why ADC Does Not Have the Same Z Semantics

ADC sets and clears Z normally — it does not preserve a running "still zero"
state. This means you cannot use BREQ after an ADD+ADC chain to test whether
two multi-byte values are equal. Use SUB+SBC instead when you need equality
as a side effect.

---

## Multi-byte Comparison

### Comparing Two 24-bit Values: CP + CPC + CPC

To compare two 24-bit values without changing either, use CP for the low byte
and CPC for each subsequent byte. CPC ("Compare with Carry") is to comparison
what SBC is to subtraction.

```asm
; Compare r26:r25:r24 with r22:r21:r20 (24-bit unsigned)
cp   r24, r20       ; low bytes: sets C, Z  (no carry in)
cpc  r25, r21       ; mid bytes: subtracts borrow from CP
cpc  r26, r22       ; high bytes: subtracts borrow from CPC
; After the chain:
;   Z=1: r26:r25:r24 == r22:r21:r20
;   C=0, Z=0: r26:r25:r24 > r22:r21:r20 (unsigned)
;   C=1: r26:r25:r24 < r22:r21:r20 (unsigned)
brlo a_less_than_b  ; unsigned less-than
brsh a_ge_b         ; unsigned >=
breq a_equal_b      ; exactly equal
```

CPC carries the same special Z semantics as SBC: it only clears Z, never sets
it. Z=1 after the final CPC means the entire multi-byte value matched.

**Full 24-bit comparison example:**

```asm
; Is counter (r26:r25:r24) >= limit (r22:r21:r20)?
cp   r24, r20
cpc  r25, r21
cpc  r26, r22
brsh counter_reached_limit   ; C=0 → counter >= limit
```

### Comparing Two 32-bit Values: CP + CPC + CPC + CPC

```asm
; Compare r25:r24:r23:r22 with r19:r18:r17:r16 (32-bit unsigned)
cp   r22, r16       ; byte 0 (lowest)
cpc  r23, r17       ; byte 1
cpc  r24, r18       ; byte 2
cpc  r25, r19       ; byte 3 (highest): flags final here
brlo a32_lt_b32     ; r25:r24:r23:r22 < r19:r18:r17:r16 (unsigned)
breq a32_eq_b32
; else: r25:r24:r23:r22 > r19:r18:r17:r16
```

### Signed 32-bit Comparison

For signed 32-bit comparison, use BRLT and BRGE after the CPC chain. The V and
S flags produced by the final CPC instruction reflect signed overflow and the
corrected sign — exactly as for 8-bit and 16-bit signed comparisons.

```asm
; Signed 32-bit compare: r25:r24:r23:r22 vs r19:r18:r17:r16
cp   r22, r16
cpc  r23, r17
cpc  r24, r18
cpc  r25, r19
brlt signed_a_lt_b  ; S=1 → a < b (signed)
brge signed_a_ge_b  ; S=0 → a >= b (signed)
breq a_eq_b
```

The rule is identical to ch05b: BRLT reads S (= N XOR V), which handles
overflow correctly. Never use BRLO for signed comparisons.

### Comparing a Multi-byte Value with a Constant

There is no multi-byte CPI. For the low byte use CPI; for higher bytes use
CPC against a register loaded with the constant byte:

```asm
; Is r25:r24:r23:r22 == 86400? (86400 = 0x00015180)
cpi  r22, lo8(86400)         ; compare low byte
ldi  r0,  byte2(86400)
cpc  r23, r0
ldi  r0,  byte3(86400)
cpc  r24, r0
ldi  r0,  byte4(86400)       ; r0 = 0x00 for byte 4 of 86400
cpc  r25, r0
breq equals_86400
```

Note: r0 is clobbered by this sequence. If r0 must be preserved, use a
different scratch register in r16–r31.

For a 32-bit value in r16–r31, use CPI for the low byte and load into a
scratch register for each subsequent CPC:

```asm
; Is r25:r24:r23:r22 >= 0x00800000? (unsigned greater-or-equal to 8388608)
cpi  r22, 0x00                   ; lo8
ldi  r16, 0x00
cpc  r23, r16                    ; byte2
ldi  r16, 0x80
cpc  r24, r16                    ; byte3
ldi  r16, 0x00
cpc  r25, r16                    ; byte4 (hi8)
brsh value_ge_8M
```

---

## Multi-byte Negation

Negation in two's complement means computing `0 - value`. For a single byte,
`NEG Rd` does this directly. For multi-byte values, there is no multi-byte NEG
instruction. You must construct the operation yourself.

### The Two Equivalent Methods

There are two standard ways to negate an N-byte two's complement value:

**Method 1: COM all bytes, then add 1.**

This is the textbook two's complement definition: flip all bits (COM), then
increment (add 1). For a multi-byte value:

```asm
; Negate r25:r24:r23:r22 (32-bit, in-place)
; Method 1: COM each byte, then add 1
com  r22
com  r23
com  r24
com  r25
; Now r25:r24:r23:r22 = bitwise NOT of original value
; Add 1 to complete the two's complement negate:
ldi  r16, 1
ldi  r17, 0
add  r22, r16
adc  r23, r17
adc  r24, r17
adc  r25, r17
```

**Method 2: NEG the low byte, SBC each higher byte from zero.**

```asm
; Negate r25:r24:r23:r22 (32-bit, in-place)
; Method 2: NEG low byte, propagate borrow through SBC
neg  r22            ; r22 = 0 - r22; C=1 if r22 was nonzero, C=0 if zero
; For each subsequent byte: subtract from 0, minus the borrow
; COM+INC equivalent: (0 - byte - borrow) = (~byte + 1 - borrow) when borrow=1
; Use a zero register to do: 0 - Rn - C
clr  r0             ; r0 = 0  (scratch; clobbers r0)
sbc  r0,  r0        ; This is WRONG — we want 0 - r23 - C, not r0 - r0 - C
```

Wait — `SBC r0, r0` computes `r0 - r0 - C = -C`, not `0 - r23 - C`. The
correct form requires the source register to hold the byte we want to negate:

```asm
; Negate r25:r24:r23:r22 (32-bit, in-place) — Method 2 (correct)
neg  r22            ; r22 = 0 - r22, C=1 if r22≠0
; For each subsequent byte: COM then propagate borrow
; SBC Rd, Rr computes Rd = Rd - Rr - C
; We want: Rn = ~Rn - C + 1  (which equals 0 - Rn - C when the original NEG gave C=1)
; Actually: Method 2 is more cleanly expressed as:
; Rn = ~Rn - borrow (complement and subtract borrow from higher NEG/SBC steps)
; This equals: Rn = NOT(Rn) - C = 0xFF - Rn - C = -(Rn + C)
; The identity: 0 - Rn - C = ~Rn + 1 - C  (when C=1 from the previous stage)
; A clean implementation:
com  r23            ; ~r23
sbc  r23, r1        ; r23 = ~r23 - 0 - C  (r1 = 0)
; Actually this gives ~r23 - C, not 0 - r23 - C.
```

The arithmetic identity:

```
0 - Rn - C  =  ~Rn + 1 - C
            =  ~Rn + (1 - C)
```

When the previous byte produced C=1 (borrow), `1 - C = 0`, so the byte
becomes `~Rn`. When the previous byte produced C=0 (no borrow, only happens
if all lower bytes were zero), `1 - C = 1`, so the byte becomes `~Rn + 1`.

The `COM + SBC from zero` pattern using `r1 = 0`:

```asm
; Correct Method 2 for 32-bit negate using COM + SBC with r1=0:
neg  r22            ; r22 = 0 - r22, sets C correctly
com  r23            ; r23 = ~r23
sbci r23, 0         ; r23 = ~r23 - 0 - C = ~r23 - C
                    ; which equals 0 - orig_r23 - (C from prev)  ✓
com  r24
sbci r24, 0
com  r25
sbci r25, 0
```

**Method 1 (COM all + ADD chain) is simpler and less error-prone. Prefer it.**

### 16-bit Negation (Recap)

```asm
; Negate r25:r24 (16-bit)
; Method 1: COM + add 1
com  r24
com  r25
adiw r24, 1         ; adiw is faster than add+adc for +1 on a supported pair
```

Or using `NEG + SBC`:

```asm
; Negate r25:r24 (16-bit, alternate)
neg  r24            ; r24 = 0 - r24, C=1 unless r24 was 0
neg  r25            ; r25 = 0 - r25
sbc  r25, r1        ; r25 -= 0 + C(from neg r24) → r25 = -(r25) - C  ✓
```

Wait — this does NOT give the right result because the second NEG already
computed `0 - r25`, and then subtracts the carry. Let's verify:

```
Original: r25:r24 = 0xAB:0xCD
Negate:   should give  0xFF:0xFF - 0xAB:0xCD + 1 = 0x5433

Step 1: NEG r24:  0 - 0xCD = 0x33, C=1 (0xCD ≠ 0)
Step 2: NEG r25:  0 - 0xAB = 0x55
Step 3: SBC r25, r1:  0x55 - 0 - 1(C) = 0x54

Result: r25:r24 = 0x54:0x33 = 0x5433  ✓
```

The `NEG + NEG + SBC` form works for 16-bit.

For 24-bit and 32-bit, **Method 1 (COM all bytes + add 1) is clearer**:

### 24-bit Negation (Method 1)

```asm
; Negate r26:r25:r24 (24-bit, in-place)
com  r24
com  r25
com  r26
; Add 1 to the bitwise complement:
ldi  r16, 1
ldi  r17, 0
add  r24, r16
adc  r25, r17
adc  r26, r17
```

### 32-bit Negation (Method 1)

```asm
; Negate r25:r24:r23:r22 (32-bit, in-place)
com  r22
com  r23
com  r24
com  r25
ldi  r16, 1
ldi  r17, 0
add  r22, r16
adc  r23, r17
adc  r24, r17
adc  r25, r17
```

**Trace: negate 0x00000001 → should give 0xFFFFFFFF**

```
After COM chain: r25:r24:r23:r22 = 0xFF:0xFF:0xFF:0xFE
ADD r22, r16:  0xFE + 0x01 = 0xFF, C=0
ADC r23, r17:  0xFF + 0x00 + 0 = 0xFF, C=0
ADC r24, r17:  0xFF + 0x00 + 0 = 0xFF, C=0
ADC r25, r17:  0xFF + 0x00 + 0 = 0xFF, C=0
Result: 0xFFFFFFFF = -1 (signed 32-bit)  ✓
```

**Trace: negate 0xFFFFFFFF → should give 0x00000001**

```
After COM chain: r25:r24:r23:r22 = 0x00:0x00:0x00:0x00
ADD r22, r16:  0x00 + 0x01 = 0x01, C=0
ADC r23-r25: all 0+0+0 = 0, C=0
Result: 0x00000001  ✓
```

**Trace: negate 0x00000000 → should give 0x00000000**

```
After COM chain: 0xFF:0xFF:0xFF:0xFF
ADD r22: 0xFF + 1 = 0x100 → r22=0x00, C=1
ADC r23: 0xFF + 0 + 1 = 0x100 → r23=0x00, C=1
ADC r24: 0xFF + 0 + 1 = 0x100 → r24=0x00, C=1
ADC r25: 0xFF + 0 + 1 = 0x100 → r25=0x00, C=1
Result: 0x00000000, C=1  ✓
(C=1 is the expected carry-out for negating zero in two's complement)
```

### Signed Overflow on Multi-byte Negation

For any two's complement value, negating is well-defined for every value except
the most-negative representable integer. Negating `0x80000000` (−2,147,483,648
for 32-bit signed) yields 2,147,483,648, which exceeds +2,147,483,647 and
wraps back to 0x80000000.

After Method 1 negation, test for this case:

```asm
; 32-bit negate with overflow check
com  r22
com  r23
com  r24
com  r25
ldi  r16, 1
ldi  r17, 0
add  r22, r16
adc  r23, r17
adc  r24, r17
adc  r25, r17
; V=1 after the final ADC iff signed overflow occurred
brvs neg32_overflow     ; result is 0x80000000, same as input
```

---

## Loading and Storing Multi-byte Values from SRAM

### Little-Endian Storage

AVR stores multi-byte values in **little-endian** order: the byte with the
lowest address is the least-significant byte. This matches how the C compiler
lays out `uint32_t` variables.

For a 32-bit variable at SRAM address `var32`:

```
Address:    var32+0   var32+1   var32+2   var32+3
Content:    byte 0    byte 1    byte 2    byte 3
            (low)                         (high)
```

### Loading with LDS (Direct Addressing)

```asm
; Load 32-bit value from SRAM into r25:r24:r23:r22
lds  r22, var32+0       ; low byte
lds  r23, var32+1
lds  r24, var32+2
lds  r25, var32+3       ; high byte
```

Each `LDS` is a 3-cycle, 2-word instruction on the ATtiny3217 (AVRxt). Four
LDS instructions = 12 cycles, 8 words of flash.

### Loading with a Pointer Register (More Efficient)

Using the X, Y, or Z pointer with post-increment:

```asm
; Load 32-bit value at address in X into r25:r24:r23:r22
ld   r22, X+        ; low byte, X advances to +1
ld   r23, X+        ; byte 1, X advances to +2
ld   r24, X+        ; byte 2, X advances to +3
ld   r25, X         ; high byte, X points at last byte (not past it)
```

Or using `X+` throughout if X should point past the last byte afterward:

```asm
ld   r22, X+
ld   r23, X+
ld   r24, X+
ld   r25, X+        ; X now points one past the end of the 32-bit value
```

`LD Rd, X+` is 2 cycles on AVRxt. Four loads = 8 cycles, half the flash of
four LDS instructions (one word each instead of two) and four cycles faster.

### Storing with STS

```asm
; Store r25:r24:r23:r22 to SRAM at var32
sts  var32+0, r22
sts  var32+1, r23
sts  var32+2, r24
sts  var32+3, r25
```

### Storing with a Pointer Register

```asm
; Store r25:r24:r23:r22 at address in Y
st   Y+, r22
st   Y+, r23
st   Y+, r24
st   Y,  r25        ; final byte: no post-increment if Y should stay at last byte
```

### Atomicity Warning

Loading or storing a multi-byte variable that is written by an interrupt service
routine is not atomic. If an interrupt fires between the first and last `LD`
instruction, the loaded value may be inconsistent (half from the old value, half
from the new).

The standard fix: disable interrupts around the load/store:

```asm
cli                 ; disable interrupts
lds  r22, counter+0
lds  r23, counter+1
lds  r24, counter+2
lds  r25, counter+3
sei                 ; re-enable interrupts
```

For an 8-byte value, this means holding interrupts off for 8 LDS instructions =
24 cycles on AVRxt. Keep the critical section as short as possible.

---

## Practical Patterns

### Pattern 1: 32-bit Millisecond Uptime Counter

A 32-bit tick counter incremented in a timer interrupt, read safely from
main code:

```asm
.section .data
tick_count: .space 4        ; 32-bit, little-endian, initialized to zero

.section .text

; In the timer ISR (interrupt service routine):
timer_isr:
    push r24            ; save clobbered registers
    push r25
    push r22
    push r23
    push r16
    in   r16, SREG
    push r16

    lds  r22, tick_count+0
    lds  r23, tick_count+1
    lds  r24, tick_count+2
    lds  r25, tick_count+3

    ldi  r16, 1
    ldi  r17, 0
    add  r22, r16
    adc  r23, r17
    adc  r24, r17
    adc  r25, r17

    sts  tick_count+0, r22
    sts  tick_count+1, r23
    sts  tick_count+2, r24
    sts  tick_count+3, r25

    pop  r16
    out  SREG, r16
    pop  r23
    pop  r22
    pop  r25
    pop  r24
    reti

; In main code: atomic read of tick_count into r25:r24:r23:r22
read_ticks:
    cli
    lds  r22, tick_count+0
    lds  r23, tick_count+1
    lds  r24, tick_count+2
    lds  r25, tick_count+3
    sei
    ret
```

### Pattern 2: 32-bit Saturating Accumulator

Accumulate 8-bit unsigned samples into a 32-bit unsigned sum, clamping at
0xFFFFFFFF rather than wrapping:

```asm
/*
 * add32_sat8 — add unsigned 8-bit r16 to 32-bit accumulator r25:r24:r23:r22
 * Saturates at 0xFFFFFFFF. Clobbers r17.
 */
add32_sat8:
    clr  r17
    add  r22, r16       ; zero-extend r16 to 32-bit and add
    adc  r23, r17
    adc  r24, r17
    adc  r25, r17
    brcc sat8_done      ; C=0: no overflow
    ser  r22            ; C=1: saturate to 0xFFFFFFFF
    ser  r23
    ser  r24
    ser  r25
sat8_done:
    ret
```

### Pattern 3: 32-bit Elapsed Time

Given a 32-bit start time and current time (both in milliseconds), compute
the elapsed milliseconds. This works correctly even if the counter has rolled
over past 0xFFFFFFFF back toward zero (one rollover only):

```asm
/*
 * elapsed32 — compute elapsed time
 *   Input:  r25:r24:r23:r22 = start_time, r19:r18:r17:r16 = current_time
 *   Output: r25:r24:r23:r22 = elapsed = current_time - start_time
 *   (Result is correct modulo 2^32 — handles one counter rollover)
 */
elapsed32:
    sub  r22, r16
    sbc  r23, r17
    sbc  r24, r18
    sbc  r25, r19
    ret
```

Unsigned subtraction modulo 2^32 gives the correct elapsed time regardless of
rollover, because `current - start` in 32-bit modular arithmetic gives the
right answer as long as at most one rollover occurred between the two times.

### Pattern 4: 32-bit Range Check

Is a 32-bit unsigned value in the range [lo32, hi32]?

```asm
/*
 * in_range32 — check if r25:r24:r23:r22 is in [lo32, hi32]
 *   Input:  r25:r24:r23:r22 = value to test
 *           lo32 and hi32 = 32-bit constants defined in .equ or .word
 *   Output: Z=1 if in range, Z=0 if out of range
 *   Clobbers: r19:r18:r17:r16
 */
in_range32:
    ; Check value >= lo32
    ldi  r16, lo8(lo32)
    ldi  r17, byte2(lo32)
    ldi  r18, byte3(lo32)
    ldi  r19, byte4(lo32)
    cp   r22, r16
    cpc  r23, r17
    cpc  r24, r18
    cpc  r25, r19
    brlo out_of_range32     ; value < lo32

    ; Check value <= hi32  (equivalently: value < hi32 + 1)
    ldi  r16, lo8(hi32 + 1)
    ldi  r17, byte2(hi32 + 1)
    ldi  r18, byte3(hi32 + 1)
    ldi  r19, byte4(hi32 + 1)
    cp   r22, r16
    cpc  r23, r17
    cpc  r24, r18
    cpc  r25, r19
    brsh out_of_range32     ; value >= hi32 + 1, i.e. value > hi32

    ; In range — signal via Z flag
    ; (Both CP chains consumed Z; now signal "in range" by setting Z explicitly)
    clr  r16
    tst  r16                ; Z=1 (r16 is 0 after CLR)
    ret
out_of_range32:
    ldi  r16, 1
    tst  r16                ; Z=0 (r16 is 1)
    ret
```

In practice, firmware usually branches directly to handlers rather than
returning a flag; the above shows the comparison structure.

### Pattern 5: Signed 32-bit Addition with Overflow Detection

```asm
/*
 * sadd32 — signed 32-bit add with overflow check
 *   Input:  r25:r24:r23:r22 = a, r19:r18:r17:r16 = b
 *   Output: r25:r24:r23:r22 = a + b
 *           V=1 if signed overflow (result outside [-2^31, 2^31 - 1])
 */
sadd32:
    add  r22, r16
    adc  r23, r17
    adc  r24, r18
    adc  r25, r19       ; V=1 here iff signed 32-bit overflow occurred
    ret
```

Calling code that handles overflow:

```asm
    rcall sadd32
    brvs  handle_s32_overflow
```

---

## Instruction Reference

The following table covers the instructions used in multi-byte arithmetic
chains. All cycle counts are for the ATtiny3217.

```
Instruction     Operands            Cycles  Flags updated        Notes
─────────────── ─────────────────── ──────  ──────────────────── ──────────────────────
ADD  Rd, Rr     r0–r31, r0–r31         1   H, S, V, N, Z, C     First byte in chain
ADC  Rd, Rr     r0–r31, r0–r31         1   H, S, V, N, Z, C     Subsequent bytes; adds C
SUB  Rd, Rr     r0–r31, r0–r31         1   H, S, V, N, Z, C     First byte in chain
SBC  Rd, Rr     r0–r31, r0–r31         1   H, S, V, N, Z, *C    Subsequent bytes; Z only cleared
CP   Rd, Rr     r0–r31, r0–r31         1   H, S, V, N, Z, C     Compare first byte (no write)
CPC  Rd, Rr     r0–r31, r0–r31         1   H, S, V, N, Z, *C    Compare subsequent bytes; Z only cleared
NEG  Rd         r0–r31                 1   H, S, V, N, Z, C     Negate single byte; use in multi-byte via COM+chain
COM  Rd         r0–r31                 1   C=1, S, V=0, N, Z    Bitwise NOT; building block for multi-byte NEG
ADIW Rd, K     r24/XL/YL/ZL; K=0-63   2   S, V, N, Z, C; no H  16-bit += constant; use for +1 on 16-bit pairs
SBIW Rd, K     r24/XL/YL/ZL; K=0-63   2   S, V, N, Z, C; no H  16-bit -= constant
LDS  Rd, k      r0–r31                 3   none                  Load byte from SRAM (direct)
STS  k, Rr      r0–r31                 2   none                  Store byte to SRAM (direct)
LD   Rd, X/Y/Z  r0–r31                 2   none                  Load byte (pointer; +/- variants same cycle count)
ST   X/Y/Z, Rr  r0–r31                 1   none                  Store byte (pointer; +/- variants same cycle count)

*SBC, SBCI, CPC: only CLEAR Z (never set Z); Z=1 iff all bytes in the chain produced zero.
```

---

## Common Pitfalls

### Pitfall 1: Using INC to Increment the High Byte of a Multi-byte Value

`INC` does not set the carry flag (C). If you use INC to propagate a carry
from a lower byte to a higher byte, the increment will happen unconditionally
rather than only when carry is set:

```asm
; WRONG — INC is not carry-conditional
add  r22, r16
adc  r23, r17
adc  r24, r18
inc  r25            ; INC runs regardless of carry from ADC — broken!

; CORRECT
add  r22, r16
adc  r23, r17
adc  r24, r18
adc  r25, r19       ; r19 must be 0 if you only want carry propagation
```

When you want to propagate carry into a high byte that has no corresponding
source operand (e.g., zero-extending a smaller value into a larger one), keep a
zero register available and use ADC:

```asm
clr  r17            ; zero register for carry propagation
add  r22, r16       ; low byte: r16 is the actual operand
adc  r23, r17       ; r23 += 0 + C  (propagates carry only)
adc  r24, r17       ; same
adc  r25, r17
```

### Pitfall 2: Processing High Byte Before Low Byte

The carry produced by ADD flows into the first ADC. If you process high before
low, the carry from the wrong byte contaminates the result:

```asm
; WRONG — high byte first
adc  r25, r19       ; C here is from some previous instruction, not from r22's ADD
add  r22, r16

; CORRECT — low byte always first
add  r22, r16
adc  r23, r17
adc  r24, r18
adc  r25, r19
```

### Pitfall 3: Reading Z Before the Final Instruction in an SBC Chain

Z is accumulated across SBC and CPC instructions. Reading it mid-chain gives
the result for only the bytes processed so far:

```asm
sub  r22, r16
sbc  r23, r17      ; Z here: only valid for r23:r22 vs r17:r16 — NOT the 32-bit result
sbc  r24, r18
sbc  r25, r19      ; Z here: valid for full 32-bit comparison
breq equal_32
```

### Pitfall 4: Using BRLO for Signed Multi-byte Comparison

After CP+CPC+...+CPC, use BRLT/BRGE for signed and BRLO/BRSH for unsigned.
The V and S flags produced by the final CPC correctly reflect signed overflow.

```asm
; WRONG for signed comparison:
cp   r22, r16
cpc  r23, r17
cpc  r24, r18
cpc  r25, r19
brlo signed_less    ; WRONG: BRLO reads C, which is unsigned less-than

; CORRECT for signed comparison:
cp   r22, r16
cpc  r23, r17
cpc  r24, r18
cpc  r25, r19
brlt signed_less    ; CORRECT: BRLT reads S = N XOR V
```

### Pitfall 5: COM Is Not NEG

For multi-byte negation, COM is not the whole story. `COM Rd` computes
`~Rd`, which is one less than the negation. After COM-ing all bytes you must
add 1 to complete the two's complement:

```asm
; WRONG — COM alone is not a negate
com r22
com r23
com r24
com r25             ; r25:r24:r23:r22 = ~original, NOT -original

; CORRECT — COM then add 1
com r22
com r23
com r24
com r25
ldi r16, 1
ldi r17, 0
add r22, r16
adc r23, r17        ; these complete the two's complement negate
adc r24, r17
adc r25, r17
```

### Pitfall 6: Multi-byte Compare with Immediate — Forgetting to Load Higher Bytes

`CPI` only works on r16–r31 and compares one byte. Higher bytes of a constant
must be loaded into a scratch register before CPC:

```asm
; WRONG — CPC reads r16 each time, but r16 doesn't change
cpi  r22, lo8(K)
cpc  r23, r16       ; r16 still has lo8(K), not byte2(K)!
cpc  r24, r16
cpc  r25, r16

; CORRECT — load each byte of the constant separately
cpi  r22, lo8(K)
ldi  r16, byte2(K)
cpc  r23, r16
ldi  r16, byte3(K)
cpc  r24, r16
ldi  r16, byte4(K)
cpc  r25, r16
```

### Pitfall 7: Interrupt-Unsafe Multi-byte Reads

Any multi-byte variable modified by an ISR and read by main code must be read
atomically. A multi-byte read is not atomic by default — an interrupt can fire
between two `LDS` instructions:

```asm
; WRONG — susceptible to torn read if ISR modifies counter32
lds  r22, counter32+0
; ← ISR fires here, counter32 rolls over
lds  r23, counter32+1   ; now mismatched with r22!

; CORRECT — atomic read
cli
lds  r22, counter32+0
lds  r23, counter32+1
lds  r24, counter32+2
lds  r25, counter32+3
sei
```

---

## Summary

```
The carry chain principle:
  Any-width ADD:  first byte = ADD, subsequent bytes = ADC (low byte FIRST)
  Any-width SUB:  first byte = SUB, subsequent bytes = SBC (low byte FIRST)
  Any-width CMP:  first byte = CP,  subsequent bytes = CPC
  Final flags (C, V, Z, N, S) are valid only after the LAST instruction in the chain.

24-bit add:   ADD r24,r20 / ADC r25,r21 / ADC r26,r22
24-bit sub:   SUB r24,r20 / SBC r25,r21 / SBC r26,r22
24-bit cmp:   CP r24,r20  / CPC r25,r21 / CPC r26,r22

32-bit add:   ADD r22,r16 / ADC r23,r17 / ADC r24,r18 / ADC r25,r19
32-bit sub:   SUB r22,r16 / SBC r23,r17 / SBC r24,r18 / SBC r25,r19
32-bit cmp:   CP r22,r16  / CPC r23,r17 / CPC r24,r18 / CPC r25,r19

Unsigned overflow/underflow: C=1 after final ADC/SBC
Signed overflow: V=1 after final ADC/SBC; V=1 after final CPC for signed compare

Zero flag in SBC/CPC chains:
  SBC and CPC only CLEAR Z. They never set it.
  Z=1 after the chain iff EVERY byte produced a zero result.
  Read Z only after the LAST instruction in the chain.

Multi-byte zero test without subtraction:
  OR all bytes together into a scratch; Z=1 iff all bytes were 0x00.

Signed multi-byte compare: use BRLT/BRGE (reads S = N XOR V)
Unsigned multi-byte compare: use BRLO/BRSH (reads C)

Multi-byte negation (any width):
  COM all bytes, then add 1 via ADD+ADC chain (Method 1 — prefer this)
  NEG low byte, then COM + SBCI/SBC each higher byte (Method 2 — error-prone)
  Signed overflow iff the value was the most-negative representable integer.

SRAM multi-byte layout: little-endian (lowest address = lowest byte)
  Load/store: LDS/STS (direct) or LD/ST with X/Y/Z pointer (shorter, faster)
  Interrupt safety: CLI + load/store all bytes + SEI for ISR-shared variables

INC/DEC pitfall: these do NOT update C — never use them inside a carry chain.
```

---

## Exercises

1. Write a 24-bit unsigned adder subroutine:
   `add24(r26:r25:r24, r22:r21:r20) → r26:r25:r24`.
   Detect overflow via C after the chain and saturate to 0xFFFFFF if overflow
   occurs. Trace the inputs (0xFFFFF0, 0x000020) and (0x0000FF, 0x000001).

2. Implement a 32-bit two's complement negation subroutine using Method 1
   (COM + add 1). Test with inputs 0x00000001, 0x7FFFFFFF, 0x80000000, and
   0x00000000. For which input does signed overflow occur? What does V indicate?

3. Write a 32-bit comparison subroutine that returns (via Z flag and the SREG S
   flag) whether two 32-bit signed values are less-than, equal, or
   greater-than. Call it from a small main that tests all three outcomes.

4. A 32-bit millisecond counter rolls over every ~49.7 days. Given a start
   timestamp `start32` and a current timestamp `now32`, write a function
   `has_elapsed(now32, start32, delay32) → bool` that returns true if
   `now32 - start32 >= delay32` using only unsigned 32-bit subtraction and
   comparison. Explain why this works even across a rollover.

5. Write a 32-bit saturating subtract subroutine: `r25:r24:r23:r22 -= r19:r18:r17:r16`,
   clamped to 0x00000000 on underflow. Verify with
   inputs (0x00000010, 0x00000020) → should give 0.

6. Given a 24-bit signed value in `r26:r25:r24` (two's complement), sign-extend
   it to 32 bits in `r25:r24:r23:r22`. Describe the pattern (extend r26's sign
   bit across a new fourth byte) and implement it using SBRC + SER / CLR.

7. An SRAM buffer at address `buf` holds three consecutive 32-bit unsigned
   values (little-endian). Write a code sequence that loads all three into
   register quads `r25:r24:r23:r22`, `r19:r18:r17:r16`, and `r11:r10:r9:r8`
   using a single Y-pointer with post-increment. How many flash words does
   this consume compared to twelve separate LDS instructions?

8. Modify the 32-bit uptime counter ISR from the Practical Patterns section to
   also maintain a 32-bit rollover counter that increments each time the uptime
   counter wraps from 0xFFFFFFFF back to 0x00000000. What flag do you test
   after the increment, and where in the ISR does the test go?

---

*Next: Chapter 5d — Bit Math: Masks, Shifts, Rotates, Packing, and Field Extraction*
