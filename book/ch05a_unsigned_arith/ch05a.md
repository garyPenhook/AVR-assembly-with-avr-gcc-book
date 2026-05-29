# Unsigned Integer Arithmetic: 8-bit and 16-bit

Previous chapters introduced the AVR register file, the load/store model, and
the instruction set at a survey level. This chapter narrows to a single topic
and goes deep: **unsigned integer arithmetic** on 8-bit registers and 16-bit
register pairs.

Unsigned arithmetic is where most embedded programs start. Sensor readings,
buffer indices, byte counters, millisecond timestamps, and ADC results are all
unsigned. Getting this layer of arithmetic right — including overflow detection,
borrow tracking, and 16-bit carry chains — is the foundation that every later
chapter builds upon.

The chapter covers the complete unsigned integer toolkit: all relevant
instructions, the flag semantics specific to unsigned operations, two-byte
carry chains, comparisons, and a set of practical worked examples with traced
execution.

---

## What "Unsigned" Means to the CPU

The AVR CPU operates on bytes. Every register holds 8 bits, and every 8-bit
arithmetic instruction produces an 8-bit result. The CPU does not inherently
know whether a register represents a temperature reading, a packet sequence
number, or a raw index. The bits are just bits.

**Unsigned interpretation** means you choose to read those 8 bits as a value
in the range 0 to 255:

```
bit pattern   unsigned value
──────────    ──────────────
0b00000000       0
0b00000001       1
0b01111111     127
0b10000000     128
0b10101010     170
0b11111111     255
```

There is no sign bit. No two's complement. All 256 bit patterns map directly
to distinct non-negative integers. The key consequence: arithmetic that exceeds
255 wraps back to 0, and arithmetic that goes below 0 wraps to 255. The carry
flag records that a wrap happened.

For 16-bit values built from two registers, the range is 0 to 65535. The same
wrapping principle applies, now spanning two bytes connected by the carry chain.

The CPU itself is neutral. The same ADD instruction produces the same bit
result regardless of interpretation. What changes is which flags you check
and which branch instructions you use afterward. Unsigned code uses C and Z;
signed code uses S, V, and N. The moment you choose `BRLO` instead of `BRLT`,
you are telling the CPU to apply unsigned interpretation.

---

## The Status Register (SREG) and Unsigned Flags

Every arithmetic instruction updates the Status Register (SREG). For unsigned
arithmetic, the relevant flags are:

```
Bit  Name   Unsigned meaning
───  ─────  ─────────────────────────────────────────────────────────────────
 0   C      Carry (addition) or Borrow (subtraction).
            ADD/ADC:  C=1 means result exceeded 255 (or 65535 for 16-bit).
            SUB/SBC:  C=1 means result went below 0 (borrow occurred).
            Compare:  C=1 means Rd < Rr (unsigned less-than).
 1   Z      Zero. Z=1 when the result is exactly 0x00 (or 0x0000 for 16-bit).
 5   H      Half-carry. Carry out of bit 3 into bit 4. Mostly used for BCD.
            For pure unsigned arithmetic, you rarely consult H directly.
```

The signed flags (V, N, S) are still computed by the hardware after unsigned
operations, but you ignore them when working with unsigned data.

A critical point about flag timing: **flags reflect the last instruction that
updated them**. Any instruction between your arithmetic and your branch can
change the flags. A `MOV`, `CLR`, `AND`, or even some pseudo-instructions all
touch flags. Develop the habit of keeping compare/arithmetic results adjacent
to the branch that reads them.

### Flag behavior for INC and DEC

`INC` and `DEC` are the exception to the rule. They update S, V, N, Z but
**do not change the carry flag (C)**. This is by design — they are designed
for simple counters, not for feeding carry into a multi-byte chain. More on
this in the section on 16-bit arithmetic.

---

## 8-bit Unsigned Arithmetic

### Addition: ADD

```
ADD Rd, Rr          ; Rd ← Rd + Rr   (any r0–r31)
```

1 cycle. Flags: H, S, V, N, Z, C.

The fundamental unsigned addition. Both operands are any register; the result
replaces Rd.

```asm
ldi  r16, 100       ; r16 = 100
ldi  r17, 50        ; r17 = 50
add  r16, r17       ; r16 = 150, C=0, Z=0
```

No carry means the result is exact. With larger values:

```asm
ldi  r16, 200       ; r16 = 200
ldi  r17, 100       ; r17 = 100
add  r16, r17       ; 200+100=300, wrapped: r16 = 44, C=1
```

The mathematical result 300 does not fit in 8 bits. The CPU stores 300 mod 256
= 44 in r16 and sets C=1 to record that the result overflowed the 8-bit range.

**C=1 after ADD means unsigned overflow.** The stored 8-bit result is modulo
256 of the true answer.

### Immediate Addition: No ADDI — Use SUBI with Negated Constant

AVR has no `ADDI` instruction. To add a compile-time constant to a register,
subtract its two's-complement negation using `SUBI`:

```
SUBI Rd, K          ; Rd ← Rd - K   (r16–r31 only, K = 0..255)
```

```asm
; r16 += 10   — there is no ADDI, so:
subi r16, -10       ; subtract -10 is the same as add 10
                    ; assembler encodes -10 as 0xF6 and computes 8-bit sub
```

The assembler accepts negative literals and encodes them modulo 256. The
instruction performs `Rd - 0xF6`, which is numerically identical to `Rd + 10`
for the unsigned result bits. C is set if the result would have wrapped, which
for adding 10 is the same carry as adding 10 directly.

This idiom is common and correct. If it feels odd, convince yourself:
subtracting -10 wraps exactly the same as adding 10 in two's-complement
modular arithmetic.

For adding values already in registers, use ADD. `SUBI` is for compile-time
constants only.

### Adding a Constant to r0–r15

`SUBI` only works on r16–r31. For lower registers, load the constant into a
scratch register and use ADD:

```asm
; r5 += 42  (r5 is in lower half, cannot use SUBI)
ldi  r16, 42        ; scratch register
add  r5, r16        ; r5 = r5 + 42
```

### Increment: INC

```
INC Rd              ; Rd ← Rd + 1   (any r0–r31)
```

1 cycle. Flags: S, V, N, Z — **not C**.

`INC` is a convenient shorthand for adding 1, but the missing carry flag is a
critical restriction. Use it only when you do not need the carry afterward:

```asm
ldi  r16, 0
loop:
    ; ... do work ...
    inc  r16            ; advance counter
    cpi  r16, 10
    brne loop           ; repeat while r16 != 10
```

The loop counter never overflows into multi-byte territory, so the absent
carry is irrelevant. This is the intended use case.

```asm
; WRONG: trying to detect overflow via C
ldi  r16, 255
inc  r16            ; r16 = 0 (wraps), but C is NOT set
brcs overflow       ; never branches — C wasn't updated by INC
```

When you need carry-aware addition of 1, use `ADD Rd, some_one_register` with a
register holding 1, or use `ADIW` for 16-bit pairs.

### Subtract: SUB

```
SUB Rd, Rr          ; Rd ← Rd - Rr   (any r0–r31)
```

1 cycle. Flags: H, S, V, N, Z, C.

```asm
ldi  r16, 100
ldi  r17, 40
sub  r16, r17       ; r16 = 60, C=0
```

C=0 means no borrow: the result is non-negative and exact.

```asm
ldi  r16, 10
ldi  r17, 30
sub  r16, r17       ; 10-30 = -20, wrapped: r16 = 236 (0xEC), C=1
```

**C=1 after SUB means unsigned underflow (borrow).** The stored result is
the two's complement of the "deficit," equivalently 256 + (10 - 30) = 236.

For most unsigned code, a borrow means the subtraction went wrong or you should
take a different branch. The pattern is:

```asm
cp   r16, r17       ; compare without changing r16
brlo too_small      ; branch if r16 < r17 unsigned (C=1)
sub  r16, r17       ; only subtract when r16 >= r17
```

### Immediate Subtraction: SUBI

```
SUBI Rd, K          ; Rd ← Rd - K   (r16–r31 only, K = 0..255)
```

1 cycle.

```asm
ldi  r16, 100
subi r16, 25        ; r16 = 75
subi r16, 100       ; 75 - 100 = -25, wrapped: r16 = 231, C=1
```

### Decrement: DEC

```
DEC Rd              ; Rd ← Rd - 1   (any r0–r31)
```

1 cycle. Flags: S, V, N, Z — **not C**.

Same restriction as INC. Use it for simple counters where the carry is not
needed:

```asm
ldi  r20, 8         ; loop 8 times
countdown:
    ; ... do work ...
    dec  r20
    brne countdown  ; BRNE reads Z, not C — safe with DEC
```

`BRNE` tests Z, which DEC does update correctly. This is the reliable pattern
for DEC-based loops.

### Arithmetic vs Logic: ADD vs OR / EOR

A common beginner mistake is using OR to combine two numbers and expecting
addition. OR performs bitwise union, not addition:

```asm
ldi  r16, 0b00001111   ; = 15
ldi  r17, 0b00001111   ; = 15
or   r16, r17          ; r16 = 0b00001111 = 15  ← no carry possible
add  r16, r17          ; r16 = 0b00011110 = 30  ← correct addition
```

OR is for bit manipulation. ADD is for numeric addition.

---

## Unsigned Overflow, Wraparound, and Saturation

### Wraparound (Modular) Arithmetic

When C=1 after ADD, the result has wrapped. Wraparound is useful when you
deliberately want modular arithmetic — for example, a repeating 8-bit phase
counter that cycles 0→255→0→255:

```asm
loop:
    lds  r16, phase
    add  r16, step      ; advance phase — wraps naturally at 255→0
    sts  phase, r16
    rjmp loop
```

No carry check needed; the wrap is the desired behavior.

### Detecting Overflow

When you need to detect that a wrap happened, test C immediately after ADD or
use a pre-check:

```asm
; Post-check: detect overflow after ADD
add  r16, r17
brcs overflow_handler   ; C=1 → result wrapped

; Pre-check: verify headroom before adding
ldi  r17, 10
cpi  r16, 246           ; is r16 > 245? (256 - 10 - 1 = 245)
brsh overflow_handler   ; unsigned >=246 + 10 would exceed 255
add  r16, r17           ; safe to add
```

### Saturating Addition — Clamp to 255

For UI values, brightness levels, and sensor readings, wraparound is wrong:
255 + 1 should stay at 255, not jump to 0. This is called *saturating*
arithmetic:

```asm
; Saturating 8-bit add: result = min(r16 + r17, 255)
add  r16, r17
brcc no_clamp       ; C=0: no overflow, result is correct
ser  r16            ; C=1: clamp to 0xFF = 255
no_clamp:
```

`SER Rd` is an alias for `LDI Rd, 0xFF` and loads 255 into Rd. After the
clamp, r16 holds the saturated result.

### Saturating Subtraction — Clamp to 0

```asm
; Saturating 8-bit subtract: result = max(r16 - r17, 0)
sub  r16, r17
brcc no_underflow   ; C=0: no borrow, result is correct
clr  r16            ; C=1: clamp to 0
no_underflow:
```

These two patterns appear constantly in embedded firmware wherever user-facing
quantities have natural upper or lower bounds.

---

## 8-bit Unsigned Comparisons and Branches

Compare instructions perform a subtraction and set flags without storing the
result. They are always paired with a conditional branch.

### CP — Compare Two Registers

```
CP Rd, Rr           ; Rd - Rr → flags only, Rd and Rr unchanged
```

```asm
ldi  r16, 42
ldi  r17, 100
cp   r16, r17       ; flags set as if 42 - 100 → C=1 (borrow), Z=0
brlo r16_smaller    ; C=1 → r16 < r17 unsigned → branch taken
```

### CPI — Compare with Immediate

```
CPI Rd, K           ; Rd - K → flags only   (r16–r31 only)
```

```asm
cpi  r16, 200
brlo r16_below_200  ; r16 < 200 unsigned → branch
brsh r16_at_or_above; r16 >= 200 unsigned → branch
```

### CPSE — Compare and Skip if Equal

```
CPSE Rd, Rr         ; if Rd == Rr: skip next instruction
```

A 1–2 cycle conditional skip, useful for simple equality without an explicit
branch target:

```asm
cpse r16, r17       ; if r16 == r17: skip the rjmp
rjmp not_equal
; equal path continues here
```

### Unsigned Branch Instructions

These are the branches to use after unsigned comparisons:

| Instruction | Condition | Flag tested | Meaning |
|-------------|-----------|-------------|---------|
| `BREQ` | `Rd == Rr` | Z=1 | Equal |
| `BRNE` | `Rd != Rr` | Z=0 | Not equal |
| `BRLO` | `Rd < Rr` (unsigned) | C=1 | Below (same as `BRCS`) |
| `BRSH` | `Rd >= Rr` (unsigned) | C=0 | Same or higher (same as `BRCC`) |
| `BRCS` | carry set | C=1 | Alias for `BRLO` |
| `BRCC` | carry clear | C=0 | Alias for `BRSH` |

There are no `BRGT` or `BRLE` instructions for unsigned comparisons. These
cases require two tests:

```asm
; Branch if r16 > r17 unsigned (strictly greater)
cp   r16, r17
breq equal          ; r16 == r17: not greater
brsh greater_than   ; r16 >= r17 and not equal → r16 > r17

; Branch if r16 <= r17 unsigned
cp   r16, r17
brlo less_than      ; C=1 → r16 < r17
breq equal          ; Z=1 → r16 == r17
; if neither: r16 > r17
```

### The Unsigned Branching Mental Model

Unsigned branches decode cleanly from the subtraction model:

```
CP Rd, Rr computes: Rd - Rr

If Rd >= Rr (unsigned): subtraction succeeds with no borrow → C=0
If Rd <  Rr (unsigned): subtraction borrows → C=1

Therefore:
    BRLO ≡ branch if C=1 after CP ≡ Rd < Rr unsigned
    BRSH ≡ branch if C=0 after CP ≡ Rd >= Rr unsigned
```

This maps directly to `BRCS`/`BRCC`. The names `BRLO` and `BRSH` just make the
unsigned comparison intent explicit in source code.

### Unsigned Range Check

A common embedded task: check whether a byte is inside a range [lo, hi]:

```asm
; Is r16 in the range [30, 80]?
cpi  r16, 30
brlo out_of_range       ; r16 < 30 unsigned → too low
cpi  r16, 81            ; hi + 1
brsh out_of_range       ; r16 >= 81 unsigned → too high
; here: 30 <= r16 <= 80
```

The upper bound check uses `hi+1` because `BRSH` tests `>=`. If `hi` is 255,
use a separate `CPI r16, 255` + `BRNE` rather than risking the 256 that does
not fit in the immediate.

---

## Moving to 16-bit: Register Pairs

Eight bits holds values up to 255. Many real quantities require more:
millisecond uptime counters, distances in millimetres, raw 10-bit ADC readings,
buffer byte counts for USART frames. These need 16-bit unsigned arithmetic.

AVR registers are 8 bits wide. 16-bit values are held in **register pairs**:
two adjacent registers used together.

### Register Pair Convention

The notation `Rh:Rl` means the high byte is in `Rh` and the low byte is in
`Rl`. The numeric value is:

```
value = (Rh × 256) + Rl
```

Any adjacent pair of registers can hold a 16-bit value, but three specific
pairs are also hardware pointer registers with dedicated addressing instructions:

| Pair name | High register | Low register | Notes |
|-----------|--------------|-------------|-------|
| X | `r27` (XH) | `r26` (XL) | Indirect load/store pointer |
| Y | `r29` (YH) | `r28` (YL) | Indirect load/store; frame pointer in GCC ABI |
| Z | `r31` (ZH) | `r30` (ZL) | Indirect load/store; flash read pointer |

For arithmetic (not pointers), any even-register pair works. By GCC convention,
function results are returned in `r25:r24`. General 16-bit temporaries commonly
use `r25:r24`, `r23:r22`, `r21:r20`, and so on downward in pairs.

### Loading a 16-bit Constant

```asm
; r25:r24 = 1000 (0x03E8)
ldi  r24, lo8(1000)     ; r24 = 0xE8 (low byte)
ldi  r25, hi8(1000)     ; r25 = 0x03 (high byte)
```

`lo8()` and `hi8()` are assembler expressions that extract the low or high byte
of a 16-bit constant. The assembler evaluates these at assembly time.

```asm
; Named constant example
.equ MAX_SAMPLES, 512

ldi  r24, lo8(MAX_SAMPLES)   ; r24 = 0x00
ldi  r25, hi8(MAX_SAMPLES)   ; r25 = 0x02
; r25:r24 = 512
```

### Copying a 16-bit Value: MOVW

```
MOVW Rd, Rr         ; Rd+1:Rd ← Rr+1:Rr   (Rd, Rr must be even)
```

1 cycle. Copies two registers in one instruction. Assembler allows either
the low register or the named alias:

```asm
movw r24, r22       ; r25:r24 ← r23:r22
movw r28, r26       ; Y ← X
movw r30, r24       ; Z ← r25:r24
```

This is faster and clearer than two separate `MOV` instructions, and it reads
naturally as a 16-bit register copy.

### Loading a 16-bit Value from SRAM

```asm
; Load 16-bit variable from SRAM (little-endian: low byte at lower address)
lds  r24, var_lo        ; load low byte
lds  r25, var_hi        ; load high byte

; Using X pointer (after loading address into X)
ld   r24, X+            ; load low byte, X advances
ld   r25, X             ; load high byte
```

AVR stores multi-byte values in **little-endian** order: low byte at the lower
address. The GCC toolchain follows this convention for all variables. When
reading 16-bit values from SRAM, always load the low byte from the lower
address.

---

## 16-bit Unsigned Addition

### The Carry Chain: ADD + ADC

There is no 16-bit ADD instruction. You build 16-bit addition from two 8-bit
operations by using the carry flag as a bridge between bytes.

```
ADD  Rd, Rr         ; low bytes — may produce carry
ADC  Rh, Rsh        ; high bytes — includes carry from previous ADD
```

The mnemonic `ADC` stands for **Add with Carry**: `Rh ← Rh + Rsh + C`.

**The order is mandatory:** always process the low byte first. The carry from
the low byte must be in C when the ADC executes. Processing high before low
produces wrong results.

```asm
; 16-bit add: r25:r24 = r25:r24 + r23:r22
add  r24, r22       ; low bytes: r24 = r24 + r22, may set C
adc  r25, r23       ; high bytes: r25 = r25 + r23 + C
```

Example trace: 500 (0x01F4) + 700 (0x02BC) = 1200 (0x04B0):

```
r24 = 0xF4 (low 500),   r25 = 0x01 (high 500)
r22 = 0xBC (low 700),   r23 = 0x02 (high 700)

ADD r24, r22:  0xF4 + 0xBC = 0x1B0 → r24 = 0xB0, C=1
ADC r25, r23:  0x01 + 0x02 + 1(C) = 0x04 → r25 = 0x04, C=0

Result: r25:r24 = 0x04B0 = 1200  ✓
```

After the chain:
- C=0: exact result
- C=1: unsigned overflow — result exceeded 65535 and wrapped to `(true_result mod 65536)`

```asm
; Detecting 16-bit unsigned overflow
add  r24, r22
adc  r25, r23
brcs overflow_16    ; C=1 after ADC → overflow
```

### ADIW — Add Immediate to Word

```
ADIW Rd, K          ; Rd+1:Rd ← Rd+1:Rd + K   (K = 0..63)
```

2 cycles. Works only on the four special pairs:

| Low-register operand | Pair |
|----------------------|------|
| `r24` | `r25:r24` |
| `r26` / `XL` | `r27:r26` = X |
| `r28` / `YL` | `r29:r28` = Y |
| `r30` / `ZL` | `r31:r30` = Z |

```asm
adiw r24, 1         ; r25:r24 += 1   — 2 cycles
adiw XL, 4         ; X pointer += 4
adiw ZL, 16        ; Z += 16
```

`ADIW` is the preferred way to increment a 16-bit pair when the step fits in
0–63. Two cycles instead of two separate instructions, and the carry semantics
are correct.

Flags: C, Z, N, V, S. Does not update H.

When K is 0, `ADIW Rd, 0` still updates Z and N — useful to test whether a
16-bit pair is zero without modifying it (though `TST` on each byte is more
commonly used for that purpose).

### Adding a Larger Immediate Constant (SUBI + SBCI)

For constants larger than 63 or not on the ADIW-supported pairs, use
`SUBI`+`SBCI` with negated values — the same pattern as 8-bit immediate add,
extended to two bytes:

```asm
; r25:r24 += 1000   (1000 = 0x03E8, larger than 63)
subi r24, lo8(-1000)    ; r24 -= lo8(-1000) = subtract -(0x18) = add 0xE8
sbci r25, hi8(-1000)    ; r25 -= hi8(-1000) + borrow
```

The GNU assembler computes `lo8(-1000)` and `hi8(-1000)` at assembly time.
`-1000` in 16-bit two's complement is `0xFC18`. So `lo8(-1000)` = `0x18` and
`hi8(-1000)` = `0xFC`. The CPU computes `r24 - 0x18` (subtract −low of 1000 =
add low of 1000) and `r25 - 0xFC - C` (which adds the high byte of 1000
corrected by carry).

Both registers must be in r16–r31 for `SUBI`/`SBCI`.

### General Case: ADD + ADC with a Loaded Constant

When neither ADIW nor SUBI/SBCI applies (wrong register range, constant too
large), load the constant into a temporary pair and use ADD+ADC:

```asm
; r25:r24 += 5000   (r25:r24 is the only free pair in r16-r31)
ldi  r22, lo8(5000)
ldi  r23, hi8(5000)
add  r24, r22
adc  r25, r23
```

This is the general case. Two LDI loads, two arithmetic instructions. Use it
when ADIW and SUBI+SBCI don't apply.

---

## 16-bit Unsigned Subtraction

### The Borrow Chain: SUB + SBC

```asm
; 16-bit subtract: r25:r24 = r25:r24 - r23:r22
sub  r24, r22       ; low bytes: r24 = r24 - r22, may set C (borrow)
sbc  r25, r23       ; high bytes: r25 = r25 - r23 - C
```

`SBC` stands for **Subtract with Carry (borrow)**: `Rh ← Rh - Rsh - C`.

The pattern mirrors the addition chain. Low byte first. The borrow from the
low byte is in C when SBC executes on the high byte.

Example trace: 300 (0x012C) − 500 (0x01F4) → underflow:

```
r24 = 0x2C (low 300),  r25 = 0x01 (high 300)
r22 = 0xF4 (low 500),  r23 = 0x01 (high 500)

SUB r24, r22:  0x2C - 0xF4 = -0xC8, borrow → r24 = 0x38, C=1
SBC r25, r23:  0x01 - 0x01 - 1(C) = -1, borrow → r25 = 0xFF, C=1

Result: r25:r24 = 0xFF38 = 65336 (unsigned wrap of 300-500)
Final C=1 → unsigned underflow occurred
```

```asm
; Detecting 16-bit underflow
sub  r24, r22
sbc  r25, r23
brcs underflow_16   ; C=1 after SBC → result wrapped
```

**Note on SBC and the Z flag:** the AVR instruction set defines a special rule:
`SBC` only clears Z when the byte result is nonzero; it does not set Z when
the byte result is zero. This means Z=1 after the complete chain only if
**all bytes** in the chain computed to zero. Do not read Z after only the first
SBC in a multi-byte chain and expect it to mean "the 16-bit result is zero."
Read Z only after the final (most-significant-byte) SBC.

### SBIW — Subtract Immediate from Word

```
SBIW Rd, K          ; Rd+1:Rd ← Rd+1:Rd - K   (K = 0..63)
```

Same register restrictions as `ADIW` (r24, X, Y, Z). 2 cycles.

```asm
sbiw r24, 1         ; r25:r24 -= 1
sbiw ZL, 8         ; Z -= 8
```

`SBIW` is commonly used in countdown loops:

```asm
ldi  r24, lo8(1000)
ldi  r25, hi8(1000)
loop:
    ; ... do work for one step ...
    sbiw r24, 1
    brne loop           ; Z=1 when r25:r24 == 0
```

`BRNE` reads Z, which `SBIW` updates correctly for the full 16-bit value. This
loop runs exactly 1000 times.

### Subtracting a Larger Constant: SUBI + SBCI

```asm
; r25:r24 -= 300  (r25:r24 in r16-r31)
subi r24, lo8(300)
sbci r25, hi8(300)
```

Unlike addition, this is straightforward: no negation needed. `lo8(300)` =
`0x2C`, `hi8(300)` = `0x01`. The CPU subtracts these from the pair with the
borrow propagated through SBCI.

---

## 16-bit Unsigned Comparisons

### CP + CPC — Compare Bytes Then Compare with Carry

To compare two 16-bit unsigned values, chain CP with CPC:

```asm
; Compare r25:r24 with r23:r22 (16-bit unsigned)
cp   r24, r22       ; compare low bytes: (r24 - r22), sets C, Z
cpc  r25, r23       ; compare high bytes including borrow: (r25 - r23 - C)
brlo r24r25_less    ; BRLO: branch if r25:r24 < r23:r22 unsigned
```

After the chain, C and Z reflect the comparison of the full 16-bit value:
- Z=1: the pairs are equal
- C=1: r25:r24 < r23:r22 unsigned (unsigned less-than)
- C=0 and Z=0: r25:r24 > r23:r22

The same Z-flag rule applies to CPC as to SBC: CPC only clears Z, never sets
it for one byte in isolation. Z=1 after the full chain only if both bytes were
equal.

```asm
; 16-bit: is count >= threshold?
;   r25:r24 = count, r23:r22 = threshold
cp   r24, r22
cpc  r25, r23
brlo below_threshold    ; count < threshold → branch
; here: count >= threshold
```

### Comparing with a 16-bit Immediate

There is no 16-bit CPI. Use CPI for the low byte and SBCI for the high byte
comparison (after zeroing a scratch register for the carry):

```asm
; r25:r24 == 1000?
cpi  r24, lo8(1000)     ; compare low byte
ldi  r16, hi8(1000)
cpc  r25, r16           ; compare high byte with borrow
breq equal_to_1000
```

---

## Incrementing and Decrementing 16-bit Values

### Why INC and DEC Fail for 16-bit

`INC Rl` increments the low register but does not set C, so the high register
has no way to learn that a carry happened:

```asm
; WRONG 16-bit increment:
ldi  r24, 0xFF
ldi  r25, 0x00
inc  r24            ; r24 wraps to 0x00, but C is NOT updated
                    ; r25 stays 0x00 — r25:r24 is now 0x0000 instead of 0x0100!
```

Always use ADIW, ADD+ADC, or SUBI+SBCI for 16-bit increments.

### The Correct Patterns

For ±1 to ±63 on a supported pair:

```asm
adiw r24, 1         ; r25:r24 += 1 — correct
sbiw r24, 1         ; r25:r24 -= 1 — correct
```

For ±1 on any pair in r16–r31:

```asm
; r21:r20 += 1
subi r20, lo8(-1)   ; r20 -= -1 = r20 += 1
sbci r21, hi8(-1)   ; r21 -= 0xFF - C = r21 += 0 + C (propagates carry)
```

Wait — `hi8(-1)` is `0xFF`. So this would compute `r21 - 0xFF - C`, which is
not what we want. The correct form for `+1` on a non-ADIW pair in r16-r31:

```asm
; r21:r20 += 1   (both in r16-r31)
ldi  r16, 1
ldi  r17, 0
add  r20, r16
adc  r21, r17
```

Or more efficiently, keep a zero register available and use:

```asm
; r21:r20 += 1
inc  r20            ; low byte
brne no_carry       ; if r20 didn't wrap to 0, no carry needed
inc  r21            ; carry: high byte needs increment
no_carry:
```

This trick works because when INC wraps 0xFF to 0x00, Z is set (the result is
zero). Testing Z lets you determine whether carry needs to propagate. This is
the one sanctioned use of INC in a multi-byte context: you test Z, not C.

For a decrement equivalent:

```asm
; r21:r20 -= 1
tst  r20            ; test r20 without modifying it
breq borrow         ; r20 == 0 → decrement would wrap, need to borrow
dec  r20            ; r20 > 0 → simple decrement, no borrow
rjmp dec_done
borrow:
dec  r20            ; r20 wraps 0x00 to 0xFF (correct for 2's complement)
dec  r21            ; propagate borrow to high byte
dec_done:
```

For most 16-bit decrement needs, `SBIW` is cleaner:

```asm
sbiw r24, 1         ; r25:r24 -= 1 — the right tool when on a valid pair
```

---

## Practical Patterns

### Pattern 1: 8-bit Counter with Rollover Detection

Count events from 0 to 255, then detect each complete rollover:

```asm
; r16 = event counter (0-255, unsigned)
on_event:
    inc  r16
    brne still_counting     ; Z=0: didn't wrap to 0, no rollover
    ; Z=1: counter wrapped 255→0, handle rollover
    rcall on_rollover
still_counting:
    ret
```

INC is appropriate here: we test Z (which INC does update), not C.

### Pattern 2: 16-bit Odometer

Accumulate a 16-bit distance counter (in millimetres, for example):

```asm
; r25:r24 = total_mm (16-bit accumulator)
; r22 = step_mm (8-bit step per tick, always small)
;
; We need 8-bit + 16-bit: zero-extend r22 first

add_distance:
    clr  r23            ; zero-extend r22 to 16-bit: r23:r22 = 0:step_mm
    add  r24, r22
    adc  r25, r23
    brcc distance_ok    ; C=0: no overflow, done
    ser  r24            ; overflow: saturate to 0xFFFF
    ser  r25
distance_ok:
    ret
```

This accumulates distance with saturating overflow at 65535 mm ≈ 65.5 m.

### Pattern 3: 16-bit Elapsed Time Check

Compare an 8-bit timestamp snapshot against a 16-bit running timer:

```asm
; r25:r24 = current_time (16-bit, incremented in interrupt)
; r22:r21 = deadline (16-bit, set when timer was started)
;
; Is current_time >= deadline?

check_deadline:
    cp   r21, r22       ; wait — wrong order! must compare pair to pair
    ; Correct:
    cp   r24, r22       ; low bytes of current vs deadline
    cpc  r25, r23       ; high bytes (deadline high in r23)
    brsh deadline_reached   ; current_time >= deadline
    ret
deadline_reached:
    ; ... handle timeout ...
    ret
```

### Pattern 4: Saturating 16-bit Addition

Add two 16-bit unsigned values, clamping at 65535:

```asm
; r25:r24 = sat16_add(r25:r24, r23:r22)
; Result in r25:r24; saturated to 0xFFFF on overflow
sat16_add:
    add  r24, r22
    adc  r25, r23
    brcc sat16_done     ; C=0: no overflow
    ser  r24            ; C=1: clamp to 0xFFFF
    ser  r25
sat16_done:
    ret
```

### Pattern 5: Unsigned Range Check on 16-bit Value

Is a 16-bit value in the range [lo16, hi16]?

```asm
; Is r25:r24 in [100, 5000]?
; lo16=100 (0x0064), hi16=5000 (0x1388)
;
; Check r25:r24 >= 100
    ldi  r22, lo8(100)
    ldi  r23, hi8(100)
    cp   r24, r22
    cpc  r25, r23
    brlo out_of_range       ; r25:r24 < 100

; Check r25:r24 <= 5000 (equivalently: r25:r24 < 5001)
    ldi  r22, lo8(5001)
    ldi  r23, hi8(5001)
    cp   r24, r22
    cpc  r25, r23
    brsh out_of_range       ; r25:r24 >= 5001

; In range [100, 5000]
    ; ...
    rjmp done
out_of_range:
    ; ...
done:
```

---

## Instruction Reference Table

The following table collects every unsigned arithmetic and comparison
instruction with its operand constraints, cycle count, and which flags it
updates. The flag column uses `✓` for updated, `✗` for not touched, and
`–` for forced-clear.

```
Instruction     Operands          Cycles  H  C  Z  N  S  V
─────────────   ────────────────  ──────  ─  ─  ─  ─  ─  ─
ADD Rd, Rr      r0-r31, r0-r31   1       ✓  ✓  ✓  ✓  ✓  ✓
ADC Rd, Rr      r0-r31, r0-r31   1       ✓  ✓  ✓  ✓  ✓  ✓
SUB Rd, Rr      r0-r31, r0-r31   1       ✓  ✓  ✓  ✓  ✓  ✓
SBC Rd, Rr      r0-r31, r0-r31   1       ✓  ✓  *  ✓  ✓  ✓
SUBI Rd, K      r16-r31          1       ✓  ✓  ✓  ✓  ✓  ✓
SBCI Rd, K      r16-r31          1       ✓  ✓  *  ✓  ✓  ✓
ADIW Rd, K      r24/XL/YL/ZL    2       ✗  ✓  ✓  ✓  ✓  ✓
SBIW Rd, K      r24/XL/YL/ZL    2       ✗  ✓  ✓  ✓  ✓  ✓
INC Rd          r0-r31           1       ✗  ✗  ✓  ✓  ✓  ✓
DEC Rd          r0-r31           1       ✗  ✗  ✓  ✓  ✓  ✓
NEG Rd          r0-r31           1       ✓  ✓  ✓  ✓  ✓  ✓
CP Rd, Rr       r0-r31, r0-r31   1       ✓  ✓  ✓  ✓  ✓  ✓
CPC Rd, Rr      r0-r31, r0-r31   1       ✓  ✓  *  ✓  ✓  ✓
CPI Rd, K       r16-r31          1       ✓  ✓  ✓  ✓  ✓  ✓
CPSE Rd, Rr     r0-r31, r0-r31   1/2     ✗  ✗  ✗  ✗  ✗  ✗
MOV Rd, Rr      r0-r31, r0-r31   1       ✗  ✗  ✗  ✗  ✗  ✗
MOVW Rd, Rr     even, even       1       ✗  ✗  ✗  ✗  ✗  ✗
LDI Rd, K       r16-r31          1       ✗  ✗  ✗  ✗  ✗  ✗

* SBC/SBCI/CPC: only clears Z, never sets it — Z stays 1 if the previous
  byte was also zero. Read Z only after the last instruction in a chain.
```

---

## Common Pitfalls

### Pitfall 1: Using INC/DEC in a Multi-byte Carry Chain

As stressed above: INC and DEC do not update C. Mixing them into an ADD+ADC
or SUB+SBC chain silently corrupts the carry.

```asm
; WRONG:
add  r24, r22
inc  r25            ; r25 += 1 regardless of carry — broken!

; CORRECT:
add  r24, r22
adc  r25, r23       ; r23 must be zero if you only want to propagate carry
```

If you genuinely want to add just 1 to the high byte only when carry is set:

```asm
ldi  r23, 0
add  r24, r22
adc  r25, r23       ; r25 += 0 + C — propagates carry only
```

### Pitfall 2: High Byte Before Low Byte

```asm
; WRONG — processes high byte first, carry is 0 at that point:
add  r25, r23
adc  r24, r22       ; r24 now adds a carry from the wrong byte

; CORRECT — always low byte first:
add  r24, r22
adc  r25, r23
```

The carry produced by ADC on the low byte has nowhere to go. The mathematical
result is wrong for any input where the low byte overflows.

### Pitfall 3: SUBI Negation Confusion

The immediate value for SUBI when you want to add is negated:

```asm
; To add 10 to r16:
subi r16, -10       ; correct — subtract -10 = add 10
subi r16, 10        ; WRONG — this subtracts 10
```

Using a comment documenting the intent helps:

```asm
subi r16, -10       ; r16 += 10 (no ADDI exists)
```

### Pitfall 4: Reading Z After SBC on the Wrong Byte

Z after a multi-byte SBC/CPC chain is only meaningful after the last
(most-significant) instruction in the chain:

```asm
cp   r24, r22       ; low byte
cpc  r25, r23       ; high byte
; Z is now valid for the 16-bit comparison — read it here
breq equal
; DO NOT read Z from the cp alone
```

### Pitfall 5: ADIW Supported Pairs Only

```asm
adiw r20, 1         ; WRONG — r20 is not in the supported set
adiw r24, 1         ; CORRECT — r24 is one of r24, XL, YL, ZL
```

If the pair is not r24, XL, YL, or ZL, use ADD+ADC or SUBI+SBCI instead.

### Pitfall 6: Forgetting SBCI When Using SUBI for 16-bit Constant Add

```asm
; r25:r24 += 300:
subi r24, lo8(-300)
; MISSING sbci r25, hi8(-300)  ← the high byte is never updated!
```

Every `SUBI` on the low byte of a 16-bit operation must be paired with
`SBCI` on the high byte.

---

## Summary

```
8-bit unsigned:
  ADD  Rd, Rr         — add, C=1 on overflow
  SUBI Rd, -K         — add immediate K (no ADDI); r16–r31 only
  INC  Rd             — add 1, but C NOT updated
  SUB  Rd, Rr         — subtract, C=1 on borrow/underflow
  SUBI Rd, K          — subtract immediate; r16–r31 only
  DEC  Rd             — subtract 1, but C NOT updated
  Overflow:  C=1 after ADD means result > 255 (wrapped)
  Underflow: C=1 after SUB means result < 0 (wrapped)
  Saturate:  BRCC/SER for clamp-at-255; BRCC/CLR for clamp-at-0

8-bit unsigned compare and branch:
  CP Rd, Rr / CPI Rd, K   — compare without storing result
  BRLO ≡ BRCS             — branch if Rd < Rr (C=1)
  BRSH ≡ BRCC             — branch if Rd >= Rr (C=0)
  BREQ / BRNE             — branch if equal / not equal (Z)

16-bit register pairs:
  Any two adjacent registers; write high:low (e.g. r25:r24)
  LDI r24, lo8(K) / LDI r25, hi8(K) — load 16-bit constant
  MOVW Rd, Rr — copy pair in 1 cycle (even register numbers)

16-bit unsigned add:
  ADD  r24, r22 / ADC r25, r23  — low byte FIRST, then high byte + carry
  ADIW Rd, K                    — +=0..63, 2 cycles, r24/XL/YL/ZL only
  SUBI r24, lo8(-K) / SBCI r25, hi8(-K)  — add immediate to r16-r31 pair

16-bit unsigned subtract:
  SUB  r24, r22 / SBC r25, r23  — low byte first
  SBIW Rd, K                    — -=0..63, 2 cycles, r24/XL/YL/ZL only
  SUBI r24, lo8(K) / SBCI r25, hi8(K)   — subtract immediate

16-bit unsigned compare:
  CP r24, r22 / CPC r25, r23   — then BRLO / BRSH / BREQ
  Z is valid only after the final instruction in the chain.

Key rules:
  1. Always process low byte first in multi-byte chains.
  2. INC/DEC do not update C — never use them in a carry chain.
  3. SBC/CPC only clear Z, never set it in the middle of a chain.
  4. ADIW/SBIW: four pairs only (r24, X, Y, Z); K = 0..63.
  5. SUBI Rd, -K to add K (no ADDI exists).
```

---

## Exercises

1. Write a subroutine `add8_saturate(r16, r17) → r16` that returns
   `min(r16 + r17, 255)`. Verify with inputs (200, 100) and (100, 50).

2. Write a subroutine `sub8_saturate(r16, r17) → r16` that returns
   `max(r16 - r17, 0)`. Verify with inputs (10, 30) and (100, 40).

3. Implement an 8-bit modular counter that counts 0→9 then wraps to 0.
   On each call to `count_step`, increment the counter and set Z=1 in SREG
   if the counter just wrapped. (Hint: compare with 10 after incrementing.)

4. Write a 16-bit accumulator that sums values arriving one at a time in r16
   (zero-extended to 16-bit). Accumulate into r25:r24. Saturate at 65535.
   How many additions of 255 fit before saturation?

5. Given two 16-bit timestamps `start` (r23:r22) and `now` (r25:r24), compute
   `elapsed = now - start`. What happens if `now` has wrapped past 65535 since
   `start` was recorded? Under what condition does the subtraction still give
   the correct elapsed time modulo 65536?

6. Write a 16-bit unsigned range check: return (via Z) whether `r25:r24` falls
   in the range [200, 3000] inclusive. Use CP+CPC chains. Test with values
   199, 200, 1500, 3000, and 3001.

7. Implement `mul8_scale(r16, r17) → r16`: multiply r16 by the fraction r17
   where r17 represents 0/255 to 255/255. Return the scaled result in r16.
   (Hint: use MUL and take the high byte of the 16-bit product.) This is the
   8-bit fraction scaling trick introduced in Chapter 13.

8. Write a subroutine that counts the number of consecutive zero-bytes in an
   SRAM buffer starting at address in X (r27:r26), up to a maximum of 255.
   Return the count in r16. Use a 16-bit loop counter for the maximum even
   if the count return is 8-bit.

---

*Next: Chapter 9 — Signed Arithmetic, Two's Complement, and Sign Extension*
