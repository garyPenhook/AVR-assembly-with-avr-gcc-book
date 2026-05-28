# Signed Arithmetic, Two's Complement, and Sign Extension

The previous chapter treated every byte as a number from 0 to 255. That works
for sensor raw counts, buffer indices, and packet lengths. It does not work for
temperature deltas, motor direction, calibration offsets, or any quantity that
can go below zero.

This chapter covers the other half of AVR integer arithmetic: **signed values**.
The instructions are mostly the same — ADD, SUB, CP — but the representation
changes, new flags become important (V, N, S), the branch instructions change
(BRLT and BRGE instead of BRLO and BRSH), and a new operation, sign extension,
becomes necessary whenever you widen a signed value.

Everything here applies to 8-bit operations. The sign-extension section shows
how to connect an 8-bit signed value to the 16-bit arithmetic in the next
chapter.

---

## Two's Complement from First Principles

Before examining any AVR instruction, it is worth understanding exactly what
two's complement is and why it was chosen as the standard representation for
signed integers.

### The Wrapping Number Line

An 8-bit register can hold 256 distinct bit patterns: 0x00 through 0xFF. In
unsigned interpretation these map 1-to-1 to the integers 0 through 255. In
signed two's complement interpretation the mapping shifts: the upper half of
bit patterns (0x80 through 0xFF) represents negative integers.

The simplest mental model is a clock face, but with 256 positions instead of
12:

```
          0x00 = 0
    0xFF = -1    0x01 = 1
  0xFE = -2        0x02 = 2
 0xFD = -3          0x03 = 3
          ·  ·  ·
0x81 = -127      0x7F = 127
     0x80 = -128
```

Moving clockwise adds 1. Moving counter-clockwise subtracts 1. Incrementing
0x7F (127) clockwise reaches 0x80 (−128). Decrementing 0x00 counter-clockwise
reaches 0xFF (−1). The number line is a ring; it wraps at both ends.

This wrapping view explains why two's complement addition works without any
special-casing: the CPU adds bit patterns modulo 256, and those same patterns
happen to represent the correct signed result, as long as the true answer fits
in the representable range [−128, +127].

### The Full 8-bit Signed Map

```
Bit pattern   Signed value   Unsigned value
───────────   ────────────   ──────────────
0x00          0              0
0x01          +1             1
0x02          +2             2
  ...
0x7E          +126           126
0x7F          +127           127
───  sign boundary ───────────────────────
0x80          −128           128
0x81          −127           129
0x82          −126           130
  ...
0xFE          −2             254
0xFF          −1             255
```

Three facts stand out:

1. **Bit 7 is the sign bit.** Patterns with bit 7 = 0 are non-negative (0 to
   127). Patterns with bit 7 = 1 are negative (−128 to −1). The CPU's N flag
   is simply a copy of bit 7 of the result.

2. **Zero is positive.** The single value 0x00 is the boundary non-negative
   value. There is no −0.

3. **The range is asymmetric.** There are 128 non-negative values (0 to 127)
   and 128 negative values (−128 to −1). The maximum positive value is +127,
   but the minimum negative value is −128, not −127. This asymmetry produces
   the only overflow case that has no correct answer.

### How to Convert a Decimal Negative to Two's Complement

Two steps: take the bit pattern of the absolute value, invert all bits, add 1.

Example: −10 in 8-bit two's complement.

```
  10 in binary:  0b00001010   (= 0x0A)
  Invert bits:   0b11110101   (= 0xF5)
  Add 1:         0b11110110   (= 0xF6)

Result: −10 is represented as 0xF6.
```

Verification: 0x0A + 0xF6 = 0x100. Discard the ninth bit: 0x00. So 10 + (−10) = 0. ✓

This is exactly what the NEG instruction computes. The invert-and-add-1 identity is
also why `COM Rd` followed by `INC Rd` is equivalent to `NEG Rd`.

### Why the Same Addition Works for Both Signed and Unsigned

The single most important property of two's complement: addition is the same
operation for signed and unsigned values.

The 8-bit ADD instruction computes (Rd + Rr) mod 256 — a simple modular sum.
The bit pattern of that sum is the correct two's complement representation of
the signed sum, as long as the true mathematical answer falls in [−128, +127].

```
Example: (−10) + (−20) = −30 in signed 8-bit

As bit patterns:
    0xF6 (= −10) + 0xEA (= −20) = 0x1E0

Discard carry (the ninth bit):
    0xE0 = −32

Wait — that is wrong. Let me recalculate.
    0xF6 + 0xEA:
    F6
  + EA
  ----
   1E0
Discard carry → 0xE0 = 0b11100000

0xE0 as signed: bit 7 = 1, so negative.
Two's complement of 0xE0: invert = 0x1F, +1 = 0x20 = 32. So 0xE0 = −32.

−10 + (−20) = −30, but we got −32. Something is wrong in the example.
Let me redo: −20 in 8-bit two's complement:
  20 = 0x14
  Invert: 0xEB
  Add 1: 0xEC
So −20 = 0xEC.

0xF6 + 0xEC:
    F6
  + EC
  ----
   1E2
Discard carry → 0xE2

0xE2 as signed: invert = 0x1D, +1 = 0x1E = 30 → 0xE2 = −30. ✓

−10 + (−20) = −30. Correct!
```

Example (continued): (−10) + (−20) = −30

```
    0xF6  (= −10) +  0xEC  (= −20)
  = 0x1E2  →  discard carry  →  0xE2  (= −30)  ✓
```

The carry that is discarded is not a sign of an error here — it is expected and
handled by the carry flag (C=1 from the ADD). For signed arithmetic you ignore
C and watch V instead.

---

## The Signed Flags: N, V, and S

For signed arithmetic, three flags matter:

### N — Negative Flag

```
N = bit 7 of the result
```

N=1 means the result's most significant bit is 1, which under signed
interpretation means the result is negative. N=0 means the result is zero or
positive.

N is simply bit 7 of the 8-bit result, copied into SREG. It is fast and cheap:
the CPU reads it directly from the ALU output.

**N alone is not always reliable for signed comparisons.** When overflow
occurs, bit 7 of the result is wrong (the sign flipped incorrectly). That is
why the S flag exists.

### V — Signed Overflow Flag

```
V = 1 when the mathematical result exceeds the range [−128, +127]
```

Overflow happens when two same-sign operands produce a result with the opposite
sign — which is impossible in correct arithmetic and always indicates wrap.

The formal hardware definition for ADD:

```
V_ADD = (Rd7 AND Rr7 AND !R7) OR (!Rd7 AND !Rr7 AND R7)
```

Where `Rd7` is bit 7 of the destination operand before the add, `Rr7` is bit 7
of the source operand, and `R7` is bit 7 of the result. In English:

- **(positive) + (positive) → (negative)**: V=1. Two non-negative values
  cannot produce a negative result in true arithmetic; the sum overflowed +127.
- **(negative) + (negative) → (positive)**: V=1. Two negative values cannot
  produce a zero-or-positive result; the sum underflowed −128.
- **(positive) + (negative) → anything**: V=0. Adding opposite signs always
  shrinks the magnitude; the result is guaranteed to fit.
- **(negative) + (positive) → anything**: V=0. Same reason.

For SUB and CP, the formula adapts to subtraction but the rule is the same:
opposite-sign results from same-sign inputs signal overflow.

**Concrete overflow examples:**

```
+127 + 1  = ?
0x7F + 0x01 = 0x80 = 128 unsigned = −128 signed
V=1 (positive + positive → negative: overflow)

−128 − 1 = ?
0x80 - 0x01 = 0x7F = 127 unsigned = +127 signed
V=1 (negative − positive added extra magnitude: overflow) [sub as add of negated]

+100 + +100 = ?
0x64 + 0x64 = 0xC8 = 200 unsigned = −56 signed
V=1 (positive + positive → negative: overflow)

−100 + −100 = ?
0x9C + 0x9C = 0x138 → discard carry → 0x38 = +56 signed
V=1 (negative + negative → positive: overflow)

+50 + −30 = ?
0x32 + 0xE2 = 0x114 → 0x14 = +20 signed
V=0 (opposite-sign operands never overflow)
```

### S — Sign Flag

```
S = N XOR V
```

The S flag is the "corrected sign bit" for signed comparisons. It accounts for
the case where overflow has flipped the result's sign bit to the wrong value.

The clearest way to understand S is through a concrete failure of N:

```
CP r16, r17  where  r16 = 0x80 (−128),  r17 = 0x01 (+1)

CPU computes: 0x80 - 0x01 = 0x7F = +127

N = 0  (result 0x7F has bit 7 = 0 → looks positive)
V = 1  (overflow: −128 − 1 should be −129, wrapped to +127)
S = N XOR V = 0 XOR 1 = 1

Correct answer: −128 < +1, so r16 < r17. Should produce a "less than" signal.
BRMI: reads N=0 → would NOT branch → WRONG
BRLT: reads S=1 → DOES branch → CORRECT
```

And the reverse case, where a signed subtraction overflows in the other
direction:

```
CP r16, r17  where  r16 = 0x7F (+127),  r17 = 0xFF (−1)

CPU computes: 0x7F - 0xFF = 0x80 (borrow from wrap)
Hmm, more carefully: 0x7F - 0xFF = 0x7F + 0x01 - 0x100 = 0x80 with C=1
N = 1  (result 0x80 has bit 7 = 1 → looks negative)
V = 1  (overflow: +127 − (−1) = +128 exceeds +127)
S = N XOR V = 1 XOR 1 = 0

Correct answer: +127 >= −1, so r16 >= r17. Should NOT branch for less-than.
BRMI: reads N=1 → DOES branch → WRONG
BRLT: reads S=0 → does NOT branch → CORRECT
```

**The rule: use BRLT/BRGE for signed comparisons. Never use BRMI/BRPL for
signed less-than/greater-than decisions.** BRMI tests raw bit 7; BRLT tests S
which is corrected for overflow.

BRMI and BRPL have their own legitimate uses: testing whether a result is
simply negative or non-negative when overflow is known impossible, or testing
the sign bit of a fresh load that did not go through arithmetic.

---

## Signed 8-bit Arithmetic Instructions

### ADD and ADC — Signed Addition

The ADD and ADC instructions are physically identical to unsigned addition. The
same opcodes, the same result bits. Only the flags you check afterward
determine whether you are doing signed or unsigned arithmetic.

```asm
ldi  r16, 0x32      ; = +50 signed
ldi  r17, 0xEC      ; = −20 signed (0xEC = two's complement of 20)
add  r16, r17       ; 0x32 + 0xEC = 0x11E → 0x1E = +30 signed ✓
                    ; C=1 (unsigned carry occurred), V=0 (signed OK)
```

Ignore C. For signed arithmetic, C=1 does not mean error — it just records a
carry out of the top bit that has no signed meaning. Watch V instead.

```asm
; Overflow example
ldi  r16, 0x64      ; = +100 signed
ldi  r17, 0x64      ; = +100 signed
add  r16, r17       ; 0x64 + 0x64 = 0xC8 = −56 signed ← wrong!
                    ; C=0, V=1, N=1, S = N XOR V = 0
brvs signed_overflow ; V=1 → overflow detected
```

### SUB and SUBI — Signed Subtraction

Again, the same instructions as unsigned subtraction. The hardware cannot tell
the difference.

```asm
ldi  r16, 0x0A      ; = +10
ldi  r17, 0x1E      ; = +30
sub  r16, r17       ; 10 − 30 = −20 → 0xEC
                    ; C=1 (unsigned borrow), V=0 (signed OK), N=1, S=1
```

C=1 from a signed subtraction does not necessarily mean overflow. −20 is a
perfectly valid signed result.

```asm
; Signed subtraction overflow: −128 − 1
ldi  r16, 0x80      ; = −128
ldi  r17, 0x01      ; = +1
sub  r16, r17       ; 0x80 − 0x01 = 0x7F = +127 signed ← wrong!
                    ; C=0, V=1, N=0, S = N XOR V = 1
brvs signed_overflow
```

### NEG — Two's Complement Negate

```
NEG Rd              ; Rd ← 0x00 − Rd
```

`NEG` computes the additive inverse: the value that, when added back, produces
zero. It is a single-instruction "change sign."

```
NEG Rd:
  Rd = 0x00 - Rd  (computed as: COM Rd, then INC Rd)

Flags: H, S, V, N, Z, C
  C = 1 if Rd was nonzero; C = 0 if Rd was 0x00
  Z = 1 if result is 0x00
  V = 1 if Rd = 0x80 (the one unrepresentable case)
  N = bit 7 of result
  S = N XOR V
```

**The normal cases:**

```asm
ldi  r16, 10        ; = +10 = 0x0A
neg  r16            ; r16 = 0 - 10 = −10 = 0xF6, C=1, V=0

ldi  r16, 0xF6      ; = −10
neg  r16            ; r16 = 0 - (−10) = +10 = 0x0A, C=1, V=0

ldi  r16, 0         ; = 0
neg  r16            ; r16 = 0 - 0 = 0, C=0, Z=1
```

**The 0x80 corner case:**

```asm
ldi  r16, 0x80      ; = −128 (the most negative 8-bit signed value)
neg  r16            ; 0x00 - 0x80 = 0x80 (result wraps!)
                    ; V=1 (overflow), C=1, N=1
                    ; r16 is still 0x80 — unchanged
```

The true mathematical result of −(−128) is +128. But +128 does not exist in
8-bit signed arithmetic (the maximum is +127). The hardware stores 0x80 and
sets V=1 to record the failure. If your code calls NEG on a value that might
be −128, check V afterward or ensure by design that −128 cannot appear.

### Absolute Value

Using NEG to compute |x|:

```asm
; |r16|  (signed 8-bit input, unsigned 8-bit result — valid for −127..+127)
sbrc  r16, 7        ; if bit 7 clear (non-negative): skip NEG
neg   r16           ; bit 7 set: negate to make positive
; r16 now holds |input|  (undefined for input = −128; see note above)
```

For safety when −128 is possible:

```asm
; |r16|  with −128 guard
cpi   r16, 0x80     ; is it −128?
breq  abs_clamp     ; if so, clamp (or error)
sbrc  r16, 7
neg   r16
rjmp  abs_done
abs_clamp:
ldi   r16, 127      ; saturate |−128| to 127 (the closest representable value)
abs_done:
```

### COM — One's Complement vs NEG

`COM Rd` inverts all bits: `Rd ← 0xFF − Rd`. It is bitwise NOT, not
arithmetic negation. COM and NEG produce different results for all nonzero
values:

```
r16 = 0x05 (= +5):
  COM r16 → 0xFA (= −6 signed)   ← NOT +5
  NEG r16 → 0xFB (= −5 signed)   ← correct negation
```

COM is for bit manipulation and for building multi-byte NEG sequences. NEG is
for signed arithmetic negation. Do not confuse them.

---

## Detecting and Handling Signed Overflow

### Post-operation Overflow Check

After any ADD, ADC, SUB, or SBC that operates on signed values, test V
immediately:

```asm
add  r16, r17
brvs overflow_handler   ; V=1 → signed overflow
; safe path — result is in [−128, +127]
```

```asm
sub  r16, r17
brvs overflow_handler
```

`BRVS` branches if V=1. `BRVC` branches if V=0.

### The Four Overflow Scenarios for 8-bit Signed Addition

For `ADD Rd, Rr`, V=1 only in these two situations — and V=0 always when the
inputs have opposite signs:

```
Rd sign   Rr sign   V=1 when...
────────  ────────  ─────────────────────────────────────
  +         +       result > +127  (positive sum too large)
  −         −       result < −128  (negative sum too small)
  +         −       impossible — V always 0
  −         +       impossible — V always 0
```

Table of the boundary cases:

```
Operation           Decimal      Hex result   V
──────────────────  ──────────   ──────────   ─
+127 + +1           +128         0x80         1  (overflows to −128)
+127 + +127         +254         0xFE         1  (overflows to −2)
−128 + (−1)         −129         0x7F         1  (overflows to +127)
−128 + (−128)       −256         0x00         1  (overflows to 0)
+100 + +50          +150         0x96         1  (overflows to −106)
+100 + (−50)        +50          0x32         0  (opposite signs, safe)
−100 + +50          −50          0xCE         0  (opposite signs, safe)
+64  + +64          +128         0x80         1  (overflows to −128)
```

### Signed Saturating Addition

Clamp the result to [−128, +127] instead of wrapping:

```asm
; Saturating signed add: r16 = clamp(r16 + r17, −128, +127)
add  r16, r17
brvc sat_add_ok         ; V=0: no overflow, result is correct

; Overflow occurred. Determine direction from the sign of one operand.
; If both positive (N=0 in r17 before add), result should be +127.
; If both negative (N=1 in r17 before add), result should be −128.
; Use the sign bit of the source operand to decide.
sbrs r17, 7             ; if r17 was negative (bit 7 set), skip next
ldi  r16, 0x7F          ; both positive → clamp to +127
brvc sat_add_ok         ; skip the negative clamp
ldi  r16, 0x80          ; both negative → clamp to −128
sat_add_ok:
```

A cleaner approach saves r17's sign before the add:

```asm
; Saturating signed add: r16 += r17, clamped to [−128, +127]
; Preserves r17.
sat8_sadd:
    mov   r18, r17      ; save copy of addend
    add   r16, r18
    brvc  sat_ok        ; no overflow
    ; overflow: saturate based on the sign of the saved addend
    tst   r18
    brmi  sat_neg       ; addend was negative → result must clamp to −128
    ldi   r16, 0x7F     ; addend was positive → clamp to +127
    ret
sat_neg:
    ldi   r16, 0x80     ; clamp to −128
sat_ok:
    ret
```

### Signed Saturating Subtraction

```asm
; Saturating signed subtract: r16 = clamp(r16 − r17, −128, +127)
sat8_ssub:
    mov   r18, r17
    sub   r16, r18
    brvc  ssub_ok
    ; overflow during subtraction: direction is opposite of the subtrahend's sign
    tst   r18
    brmi  ssub_pos      ; subtrahend was negative → r16 − (neg) went above +127
    ldi   r16, 0x80     ; subtrahend was positive → r16 − (pos) went below −128
    ret
ssub_pos:
    ldi   r16, 0x7F
ssub_ok:
    ret
```

---

## Signed Comparison and Branches

### The Signed Branch Set

After `CP Rd, Rr` or `CPI Rd, K`, these branches test signed relationships:

```
Instruction   Condition (signed)         Flag tested   Notes
───────────   ──────────────────         ───────────   ────────────────────────
BRLT          Rd < Rr   (signed <)       S = 1         S = N XOR V
BRGE          Rd >= Rr  (signed >=)      S = 0         S = N XOR V
BRMI          result < 0                 N = 1         tests raw bit 7 of result
BRPL          result >= 0                N = 0         tests raw bit 7 of result
BRVS          signed overflow occurred   V = 1
BRVC          no signed overflow         V = 0
BREQ          Rd == Rr                   Z = 1         same for signed and unsigned
BRNE          Rd != Rr                   Z = 0         same for signed and unsigned
```

### BRLT and BRGE in Practice

```asm
; Signed comparison: branch if r16 < r17 (signed)
ldi  r16, 0xF0      ; = −16 signed
ldi  r17, 0x10      ; = +16 signed
cp   r16, r17       ; −16 − (+16) = −32; C=1, N=1, V=0, S=1
brlt r16_less       ; S=1 → taken (correct: −16 < +16)
```

```asm
; Threshold check: if temperature < −10°C, take action
; temperature in r16, signed
ldi  r17, 0xF6      ; = −10 (two's complement)
cp   r16, r17
brlt too_cold       ; signed less-than
```

### Signed Range Check

Is the signed value in r16 within [−40, +85]?

```asm
; Range check: is r16 in [−40, +85] (signed)?
ldi  r17, 0xD8      ; = −40 (0x100 − 40 = 0xD8)
cp   r16, r17
brlt out_of_range_low   ; r16 < −40 (signed)

ldi  r17, 85        ; = +85
cp   r16, r17
brgt_pattern:
    ; No BRGT instruction — need two steps for "strictly greater"
    breq in_range       ; equal to 85 is still in range
    brlt in_range       ; r16 < 85 → in range
    rjmp out_of_range_high  ; r16 > 85

in_range:
    ; ...
    rjmp check_done
out_of_range_low:
out_of_range_high:
check_done:
```

A cleaner form using `BRGE` for the upper bound:

```asm
; Range check: is r16 in [−40, +85] (signed)?
ldi  r17, 0xD8          ; = −40
cp   r16, r17
brlt range_fail_signed  ; r16 < −40

ldi  r17, 86            ; upper + 1 = 86
cp   r16, r17
brge range_fail_signed  ; r16 >= 86

; in range [−40, +85]
rjmp range_pass_signed
range_fail_signed:
range_pass_signed:
```

The upper bound uses 86 (not 85) because `BRGE` tests >=. The check `r16 >= 86`
is equivalent to `r16 > 85`.

### BRMI vs BRLT: When They Differ

`BRMI` tests N (raw bit 7 of result). `BRLT` tests S (N XOR V). They disagree
when overflow occurs:

```
Case 1: r16 = −128 (0x80), r17 = +1 (0x01)
  CP r16, r17 computes 0x80 − 0x01 = 0x7F
  N=0 (result bit 7 is 0, looks positive)
  V=1 (overflow: −128 − 1 should be −129)
  S = 0 XOR 1 = 1

  BRMI checks N=0 → does NOT branch → says "r16 >= r17" → WRONG (−128 < +1)
  BRLT checks S=1 → DOES branch    → says "r16 < r17"  → CORRECT
```

```
Case 2: r16 = +127 (0x7F), r17 = −1 (0xFF)
  CP r16, r17 computes 0x7F − 0xFF
    0x7F − 0xFF: borrow from 0x80 gives 0x80, C=1
  N=1 (result bit 7 is 1, looks negative)
  V=1 (overflow: 127 − (−1) = +128, exceeds +127)
  S = 1 XOR 1 = 0

  BRMI checks N=1 → DOES branch    → says "r16 < r17" → WRONG (+127 > −1)
  BRLT checks S=0 → does NOT branch → says "r16 >= r17" → CORRECT
```

**Practical rule:**
- Use `BRMI`/`BRPL` only to test whether a freshly computed or loaded value is
  negative or non-negative — when no overflow is possible or expected.
- Use `BRLT`/`BRGE` after any `CP`/`CPI`/`SUB` where the operands might have
  extreme signed values that cause overflow.

When in doubt, always use `BRLT`/`BRGE`. They are always correct for signed
comparisons. `BRMI`/`BRPL` are a shortcut valid only in specific circumstances.

---

## Sign Extension

### The Problem: Widening a Signed Value

When you compute with 16-bit values (addresses, timer counts, multi-byte
results), you often need to combine an 8-bit signed value with a 16-bit
quantity. Before doing so, you must **sign-extend** the 8-bit value to 16 bits.

Sign extension preserves the mathematical signed value when increasing the bit
width. The rule: fill the new high bits with copies of the sign bit.

```
 8-bit signed   16-bit sign-extended
 ─────────────  ────────────────────
 0x05  (= +5)   0x0005  (= +5)       high byte = 0x00 (sign bit was 0)
 0x7F  (+127)   0x007F  (+127)       high byte = 0x00
 0xFF  (= −1)   0xFFFF  (= −1)       high byte = 0xFF (sign bit was 1)
 0x80  (−128)   0xFF80  (−128)       high byte = 0xFF
 0xD8  (= −40)  0xFFD8  (= −40)      high byte = 0xFF
```

### Why Zero Extension Fails for Signed Values

A common mistake is zero-extending a signed value — clearing the high byte to
0x00 regardless of the value's sign:

```asm
; WRONG — zero extension applied to signed value:
ldi  r16, 0xFF      ; = −1 signed
clr  r17            ; r17:r16 = 0x00FF = +255 — mathematically wrong!
```

0x00FF as a 16-bit signed value is +255. But −1 as a 16-bit signed value is
0xFFFF. Zero extension changed the mathematical meaning.

```asm
; WRONG again:
ldi  r16, 0xD8      ; = −40 signed
clr  r17            ; r17:r16 = 0x00D8 = +216 — completely wrong!
```

Zero extension is correct only for unsigned values (see Chapter 5a). For signed
values, you must sign-extend.

### The Sign Extension Pattern

```asm
; Sign-extend r16 (8-bit signed) into r17:r16 (16-bit signed)
; After: r17 = 0x00 if r16 was non-negative, 0xFF if r16 was negative
clr   r17           ; assume non-negative: high byte = 0
sbrc  r16, 7        ; if bit 7 is CLEAR (non-negative): skip the SER
ser   r17           ; bit 7 set: value is negative, high byte = 0xFF
; r17:r16 is now the correct 16-bit signed representation
```

`SBRC Rr, b` skips the next instruction if bit b of register Rr is **clear**
(0). So `sbrc r16, 7` skips `ser r17` when bit 7 of r16 is 0 (non-negative).
When bit 7 is 1, SBRC does not skip and SER loads 0xFF into r17.

Three cycles in the non-negative path (CLR + SBRC skip + nothing), three cycles
in the negative path (CLR + SBRC no-skip + SER). Balanced and branchless.

Trace:

```
Input r16 = 0x05 (+5):
  CLR r17   → r17 = 0x00
  SBRC r16, 7: bit 7 of 0x05 = 0 → skip SER
  Result: r17:r16 = 0x0005 = +5 ✓

Input r16 = 0xFF (−1):
  CLR r17   → r17 = 0x00
  SBRC r16, 7: bit 7 of 0xFF = 1 → do NOT skip
  SER r17   → r17 = 0xFF
  Result: r17:r16 = 0xFFFF = −1 ✓

Input r16 = 0x80 (−128):
  CLR r17   → r17 = 0x00
  SBRC r16, 7: bit 7 of 0x80 = 1 → do NOT skip
  SER r17   → r17 = 0xFF
  Result: r17:r16 = 0xFF80 = −128 ✓
```

### Alternative Sign Extension Using SBRS

If you prefer to branch on the set case:

```asm
clr   r17
sbrs  r16, 7        ; if bit 7 SET: execute next instruction (then fall through)
rjmp  sext_done     ; bit 7 clear: jump to done (no sign extension needed)
ser   r17           ; bit 7 set: sign-extend
sext_done:
```

This takes an extra word and one extra cycle in the non-negative path. The
`CLR + SBRC + SER` form is more concise and preferred.

### Sign Extension as a Subroutine

```asm
/*
 * sext8to16 — sign-extend r16 to r17:r16
 *   Input:  r16 = 8-bit signed value
 *   Output: r17:r16 = 16-bit signed value
 *   Clobbers: r17
 *   Cycles: 3 (non-negative), 3 (negative), +4 for rcall/ret
 */
sext8to16:
    clr   r17
    sbrc  r16, 7
    ser   r17
    ret
```

### Sign Extension Before 16-bit Arithmetic

After sign-extending, you can use the 16-bit unsigned arithmetic from Chapter
5a, treating the 16-bit pair as signed. The same ADD+ADC and SUB+SBC chains
work correctly for signed 16-bit arithmetic, with V set appropriately at the
end by the high-byte instruction.

```asm
; signed 8-bit r16 + signed 8-bit r18 → signed 16-bit result in r25:r24

; Sign-extend r16 → r17:r16
    clr   r17
    sbrc  r16, 7
    ser   r17

; Sign-extend r18 → r19:r18
    clr   r19
    sbrc  r18, 7
    ser   r19

; 16-bit signed add (same instructions as unsigned)
    add   r16, r18
    adc   r17, r19      ; V=1 if signed 16-bit overflow occurred

; Copy to return registers
    movw  r24, r16      ; r25:r24 = result
```

The result in r25:r24 is a signed 16-bit value. V=1 if the signed 16-bit result
overflowed; otherwise the mathematical value is exact.

---

## Reading Flags Produced by Signed Operations

### The N Flag After a Load or Move

After `LDS`, `LD`, `MOV`, or other data-transfer instructions that **do not
affect SREG**, N is whatever it was before. These instructions are not
arithmetic — they do not update flags. You cannot test N after a load.

Use `TST` to set flags from a loaded value:

```asm
lds   r16, temperature   ; load signed temperature — flags NOT updated
tst   r16                ; Rd AND Rd → sets N, Z, clears V; Rd unchanged
brmi  is_negative        ; N=1 means r16 < 0 (since TST clears V, S=N)
```

After `TST`, V=0, so S = N XOR 0 = N. This means `BRMI` and `BRLT` behave
identically after `TST`. Using `BRMI` after `TST` is therefore correct.

### The Z Flag and Signed Zero

Z=1 means the result is exactly zero, regardless of signed or unsigned
interpretation. Zero is non-negative in signed arithmetic. After `TST`, Z=1
and N=0 when the value is zero:

```asm
tst  r16
breq is_zero        ; Z=1: r16 == 0
brmi is_negative    ; N=1, Z=0: r16 < 0
; here: r16 > 0 (positive and non-zero)
```

This three-way dispatch (negative / zero / positive) is a common pattern in
signed firmware.

### Flags After Logical Operations

`AND`, `ANDI`, `OR`, `ORI`, `EOR`, `COM`, `TST` all force V=0. This means:

- After any of these, S = N XOR 0 = N.
- `BRLT` and `BRMI` produce identical results after a logical op.
- `BRGE` and `BRPL` produce identical results after a logical op.

This is fine for sign tests on fresh values, but do not run a logical
instruction between a signed arithmetic result and the V-based branch that
depends on it.

---

## Common Pitfalls

### Pitfall 1: Using BRLO Instead of BRLT for Signed Comparisons

```asm
ldi  r16, 0xF0      ; = −16 signed
ldi  r17, 0x10      ; = +16 signed
cp   r16, r17       ; C=0 (no unsigned borrow — 0xF0 > 0x10 unsigned)
brlo wrong_branch   ; C=0 → NOT taken → says "r16 >= r17" → WRONG!
brlt correct_branch ; S=1 → taken → says "r16 < r17" → CORRECT
```

The CPU computed 0xF0 − 0x10 = 0xE0. No borrow occurred, so C=0. To the
unsigned view, 240 > 16. But in signed arithmetic, −16 < +16, which is
captured by S=1.

**Always use BRLT/BRGE for signed comparisons.**

### Pitfall 2: ASR vs LSR for Signed Right Shift

To divide a signed value by 2, use `ASR` (arithmetic shift right), not `LSR`
(logical shift right). ASR copies bit 7 (the sign bit) into the vacated
position. LSR inserts a 0, which incorrectly makes negative values positive:

```asm
ldi  r16, 0xFE      ; = −2 signed
lsr  r16            ; r16 = 0x7F = +127  ← WRONG (unsigned right shift)
                    ; LSR inserts 0 at bit 7 regardless of sign

ldi  r16, 0xFE      ; = −2 signed
asr  r16            ; r16 = 0xFF = −1   ← CORRECT (−2 / 2 = −1)
                    ; ASR copies bit 7 into bit 7 (sign-extended shift)
```

```asm
ldi  r16, 0xFC      ; = −4 signed
asr  r16            ; r16 = 0xFE = −2   (−4 / 2 = −2) ✓
asr  r16            ; r16 = 0xFF = −1   (−2 / 2 = −1) ✓
```

ASR rounds toward negative infinity (floor division). This differs from C's
signed right shift behaviour, which is implementation-defined, but GCC on AVR
generates ASR for its signed divisions by powers of two.

### Pitfall 3: Forgetting NEG 0x80

Code that unconditionally calls NEG on a signed value is subtly broken:

```asm
; BROKEN — returns wrong result for input = −128
abs8:
    sbrc  r16, 7
    neg   r16       ; NEG 0x80 = 0x80, V=1 — still −128!
    ret
```

If your domain guarantees the input is in [−127, +127], this is safe.
If −128 can appear, guard it explicitly (see the absolute value section above).

### Pitfall 4: Using COM as a Negate

`COM` is one's complement (flip all bits). `NEG` is two's complement (flip all
bits and add 1). COM is not a sign change:

```asm
ldi  r16, 0x01      ; = +1
com  r16            ; r16 = 0xFE = −2  ← NOT −1!
neg  r16            ; r16 = 0xFF = −1  ← correct negate of +1
```

### Pitfall 5: Inserting Flag-Altering Instructions Between Arithmetic and Branch

```asm
add  r16, r17
mov  r18, r16       ; safe: MOV does not alter flags
brvs overflow       ; V still valid ✓

add  r16, r17
andi r18, 0x01      ; ANDI clears V! V=0 after this regardless of add result
brvs overflow       ; V is now 0, overflow is never detected ✗
```

Check every instruction between the arithmetic and its branch for flag effects.
The safest approach: keep the branch immediately after the arithmetic, or save
intermediate results to a scratch register without using logical ops.

### Pitfall 6: Sign Extension After Narrowing Operations

If you mask an 8-bit value and then sign-extend, the mask may clear the sign
bit, corrupting the extension:

```asm
; WRONG — mask destroys the sign bit before sign extension
andi  r16, 0x7F     ; clears bit 7 — value is now always non-negative!
clr   r17
sbrc  r16, 7        ; bit 7 is always 0 after ANDI 0x7F → always skips SER
ser   r17           ; never reached
```

Sign-extend first, then mask, or design the mask to preserve bit 7.

---

## Instruction Reference for Signed Arithmetic

```
Instruction     Action                 Flags set/cleared      Notes
─────────────   ────────────────────   ──────────────────     ──────────────────────
ADD Rd, Rr      Rd = Rd + Rr           H,S,V,N,Z,C            V=1 on signed overflow
SUB Rd, Rr      Rd = Rd − Rr           H,S,V,N,Z,C            V=1 on signed overflow
SUBI Rd, K      Rd = Rd − K            H,S,V,N,Z,C            r16-r31 only
ADC Rd, Rr      Rd = Rd + Rr + C       H,S,V,N,Z,C            for multi-byte chains
SBC Rd, Rr      Rd = Rd − Rr − C       H,S,V,N,Z,C            for multi-byte chains
NEG Rd          Rd = 0 − Rd            H,S,V,N,Z,C            V=1 only if Rd=0x80
COM Rd          Rd = 0xFF − Rd         C=1, S,V=0,N,Z         bitwise NOT, not negate
ASR Rd          Rd = Rd >> 1 (signed)  S,V,N,Z,C              sign bit preserved
CP Rd, Rr       flags from Rd − Rr     H,S,V,N,Z,C            no result stored
CPI Rd, K       flags from Rd − K      H,S,V,N,Z,C            r16-r31 only
TST Rd          flags from Rd AND Rd   S,V=0,N,Z              Rd unchanged; C unchanged

Branch        Condition       Flag   Use after
──────────    ─────────────   ────   ─────────────────────────
BRLT          Rd < Rr signed  S=1    CP/CPI for signed less-than
BRGE          Rd >= Rr signed S=0    CP/CPI for signed greater-or-equal
BRMI          result < 0      N=1    TST/arithmetic when overflow impossible
BRPL          result >= 0     N=0    TST/arithmetic when overflow impossible
BRVS          overflow        V=1    after signed ADD/SUB to detect overflow
BRVC          no overflow     V=0    after signed ADD/SUB to confirm safe result
BREQ          equal           Z=1    signed or unsigned
BRNE          not equal       Z=0    signed or unsigned
```

---

## Worked Examples

### Example 1: Signed Temperature Comparison

A sensor returns a signed 8-bit Celsius reading (−40 to +85). Take action if
it exceeds a signed threshold stored in SRAM.

```asm
/*
 * check_temp — compare temperature against threshold
 *   Inputs:  r16 = current temperature (signed 8-bit)
 *            r17 = threshold (signed 8-bit)
 *   Output:  Z=1 if temp == threshold
 *            C=0 and Z=0 if temp > threshold (use brge after call)
 *            C=1 via S flag interpretation: use brlt
 *   Use: rcall check_temp; brlt too_cold; brge warm_enough
 */
check_temp:
    cp   r16, r17   ; signed compare: sets S for BRLT/BRGE
    ret
```

Calling code:

```asm
    lds   r16, temperature  ; signed reading
    ldi   r17, 0xF6         ; threshold: −10°C
    rcall check_temp
    brlt  heater_on         ; temperature < −10 → heat
    rjmp  heater_off
```

### Example 2: Signed Delta Between Two Readings

Compute the difference between two signed readings and take action based on
the magnitude and direction:

```asm
/*
 * signed_delta — r16 = new − old (signed, may overflow for extreme values)
 *   Input:  r16 = new reading, r17 = old reading (both signed 8-bit)
 *   Output: r16 = signed delta (new − old)
 *           V=1 if overflow (new and old differ by more than 127/128)
 */
signed_delta:
    sub   r16, r17      ; r16 = new − old
    ret

; Example use: was the change positive (warming) or negative (cooling)?
    lds   r16, temp_new
    lds   r17, temp_old
    rcall signed_delta
    brvs  delta_overflow    ; readings too far apart to trust the delta
    brmi  cooling           ; delta < 0 → temperature dropped
    breq  stable            ; delta = 0 → no change
    ; here: delta > 0 → temperature rose
warming:
```

### Example 3: Signed Absolute Value

```asm
/*
 * abs8_safe — |r16|, handles −128 by saturating to +127
 *   Input:  r16 = signed 8-bit value (−128..+127)
 *   Output: r16 = |r16| (0..+127, or +127 if input was −128)
 */
abs8_safe:
    sbrc  r16, 7        ; bit 7 clear → non-negative → no action
    rjmp  do_neg
    ret
do_neg:
    cpi   r16, 0x80     ; is it the special −128 case?
    brne  simple_neg
    ldi   r16, 127      ; −128 has no exact positive form: saturate to +127
    ret
simple_neg:
    neg   r16           ; all other negatives: negate normally
    ret
```

### Example 4: Three-Way Signed Dispatch

Test a signed value and dispatch to one of three handlers:

```asm
/*
 * signed_dispatch — branch on sign of r16
 *   Input:  r16 = signed 8-bit value
 *   Effect: branches to negative_handler, zero_handler, or positive_handler
 */
signed_dispatch:
    tst   r16           ; sets N and Z; clears V; C unchanged
    breq  zero_handler  ; Z=1: r16 == 0
    brmi  neg_handler   ; N=1 (V=0 from TST so S=N): r16 < 0
    ; fall through: r16 > 0
    rjmp  pos_handler
```

### Example 5: Sign Extension into a 16-bit Accumulator

Accumulate signed 8-bit ADC readings into a 16-bit signed sum:

```asm
/*
 * accum_signed — add signed 8-bit r16 to 16-bit signed sum in r25:r24
 *   Input:  r16 = signed 8-bit sample, r25:r24 = running sum (16-bit signed)
 *   Output: r25:r24 = updated sum
 *   Does not saturate — caller must check for overflow if needed.
 */
accum_signed:
    clr   r17
    sbrc  r16, 7        ; sign-extend r16 into r17:r16
    ser   r17
    add   r24, r16
    adc   r25, r17      ; V=1 if 16-bit signed overflow occurred
    ret
```

---

## Summary

```
Two's complement:
  8-bit signed range: −128 (0x80) to +127 (0x7F).
  Bit 7 = sign bit; 0 = non-negative, 1 = negative.
  Convert negative N: invert all bits of |N|, then add 1.
  NEG 0x80 = 0x80 (only value that cannot be negated — V=1 to record this).

Flags for signed arithmetic:
  N = bit 7 of result (raw sign bit — unreliable when overflow occurred).
  V = signed overflow (result left [−128, +127]). Set only when same-sign
      operands produce opposite-sign result.
  S = N XOR V (corrected sign — reliable for all signed comparisons).

Signed instructions:
  ADD, SUB, ADC, SBC, SUBI, SBCI — same opcodes as unsigned, V flag differs.
  NEG — two's complement negate; handle 0x80 corner case explicitly.
  ASR — arithmetic right shift; preserves sign bit (signed ÷2).
  COM — bitwise NOT; NOT a sign change. Always sets C=1.

Signed branches (after CP/CPI/SUB):
  BRLT: Rd < Rr signed   (reads S=N⊕V)  — always correct
  BRGE: Rd >= Rr signed  (reads S=N⊕V)  — always correct
  BRMI: result bit 7 = 1 (reads N)       — correct only when V=0 (no overflow)
  BRPL: result bit 7 = 0 (reads N)       — correct only when V=0 (no overflow)
  BRVS/BRVC: overflow detection after arithmetic
  BREQ/BRNE: equal/not-equal (same for signed and unsigned)

  Rule: use BRLT/BRGE for signed less-than/greater-than comparisons.
        use BRMI/BRPL only after TST or when overflow is guaranteed absent.

Sign extension (8-bit signed → 16-bit signed):
  clr  Rh
  sbrc Rl, 7      ; skip SER if bit 7 is clear (non-negative)
  ser  Rh         ; bit 7 set: fill high byte with 0xFF

Common pitfalls:
  BRLO/BRSH are unsigned — never use them for signed comparisons.
  LSR is unsigned right shift — use ASR for signed ÷2.
  COM is bitwise NOT — use NEG for arithmetic sign change.
  Zero extension is wrong for signed widening — always sign-extend.
  Logical ops (AND, OR, EOR) force V=0 — do not insert them before BRVS.
  NEG 0x80 = 0x80 with V=1 — guard this case when input range includes −128.
```

---

## Exercises

1. Predict the result, V, N, and S flags after each operation. Do this before
   assembling, then verify:
   - `ldi r16, 0x60; ldi r17, 0x60; add r16, r17` (= +96 + +96)
   - `ldi r16, 0x90; ldi r17, 0x90; add r16, r17` (= −112 + −112)
   - `ldi r16, 0x7F; ldi r17, 0x80; add r16, r17` (= +127 + −128)
   - `ldi r16, 0x80; subi r16, 1` (= −128 − 1)

2. Write a signed comparison subroutine `cmp_s8(r16, r17)` that returns:
   - r18 = 0xFF (−1) if r16 < r17 signed
   - r18 = 0x00 (0) if r16 == r17
   - r18 = 0x01 (+1) if r16 > r17 signed

3. Implement a signed 8-bit division by 4 using ASR. Verify:
   - 100 / 4 = 25
   - −100 / 4 = −25
   - −1 / 4 = 0 (floor toward −∞)
   - −4 / 4 = −1
   Why does ASR give floor division rather than truncation toward zero?

4. Sign-extend the four values 0x00, 0x7F, 0x80, and 0xFF from 8-bit to
   16-bit using the `CLR + SBRC + SER` pattern. Write out the expected r17:r16
   for each case before running the code.

5. The following code tries to check whether a signed value is in [−50, +50]
   but contains a bug. Find and fix it:
   ```asm
   cpi  r16, 0xCE    ; −50 in two's complement
   brlo too_small    ; WRONG: this is an unsigned branch
   cpi  r16, 51
   brsh too_large    ; WRONG
   ```

6. Implement `accum_signed` (from Worked Example 5) with 16-bit signed
   saturation: clamp the sum to [−32768, +32767] instead of wrapping. What
   flags do you check and what values do you load for each clamp direction?

7. Explain why `BRLT` uses S = N XOR V rather than N alone. Construct a
   concrete example (specific register values and a CP instruction) where BRLT
   gives the correct answer but BRMI gives the wrong one.

8. Write a subroutine `signed_min(r16, r17) → r16` that returns the smaller
   of two signed 8-bit values. Use `CP` and one conditional move pattern
   (you will need to copy r17 conditionally — there is no CMOV on AVR, so use
   a `BRGE` + `MOV` combination).

---

*Next: Chapter 5c — Multi-byte Addition, Subtraction, Comparison, and Negation*
