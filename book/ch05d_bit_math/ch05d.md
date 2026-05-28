# Bit Math: Masks, Shifts, Rotates, Packing, and Field Extraction

Arithmetic adds and subtracts numbers. Bit math operates on individual bits and
groups of bits regardless of numeric value. It is how you configure peripheral
registers, isolate sensor channels, assemble protocol frames, move data through
hardware shift registers, and pack two small values into one byte. Every
embedded program uses these techniques constantly.

This chapter covers the complete AVR bitwise toolkit: the logical instructions
(AND, OR, EOR, COM), the shift and rotate family, single-bit test and
manipulation instructions, and the patterns built from them — masking, field
extraction, field insertion, packing, and unpacking.

Shifts and rotates used for arithmetic (multiplying or dividing by powers of
two) are revisited in Chapter 6. This chapter treats them as bit-movement
tools.

---

## The Bitwise Logic Instructions

The four bitwise logic instructions compute their results one bit at a time. Bit
N of the result depends only on bit N of each operand — never on any other bit
position. There are no carries, no overflow, no numeric interpretation.

### AND — Bitwise AND

```
AND Rd, Rr      ; Rd ← Rd AND Rr    (any r0–r31)
ANDI Rd, K      ; Rd ← Rd AND K     (r16–r31 only, K = 0..255)
```

1 cycle. Flags: S, V=0, N, Z. C unchanged.

The AND truth table for each bit pair:

```
A   B   A AND B
─   ─   ───────
0   0      0
0   1      0
1   0      0
1   1      1
```

AND produces 1 only when both inputs are 1. Every other combination gives 0.

The primary use of AND is **masking**: the mask register controls which bits of
the source are preserved (mask bit = 1) and which are forced to zero (mask
bit = 0):

```asm
ldi  r16, 0b10110110    ; source: r16 = 0xB6
ldi  r17, 0b00001111    ; mask:   keep only lower nibble

and  r16, r17
; r16 = 0b00000110 = 0x06
;            ^^^^  — only the lower 4 bits survived
```

AND forces bits to 0. It cannot force bits to 1. To force bits to 1, use OR.

**Flags:** AND always clears V. The N flag reflects bit 7 of the result. Z=1
if the result is 0x00. Because V is forced clear, S = N XOR V = N, which means
BRMI and BRLT behave identically after AND.

### OR — Bitwise OR

```
OR  Rd, Rr      ; Rd ← Rd OR Rr     (any r0–r31)
ORI Rd, K       ; Rd ← Rd OR K      (r16–r31 only)
```

1 cycle. Flags: S, V=0, N, Z. C unchanged.

OR truth table:

```
A   B   A OR B
─   ─   ──────
0   0     0
0   1     1
1   0     1
1   1     1
```

OR produces 1 when either input is 1. It forces bits to 1 wherever the mask
has a 1, and leaves bits unchanged wherever the mask has a 0:

```asm
ldi  r16, 0b00000110    ; r16 = 0x06
ldi  r17, 0b11000000    ; mask: set bits 7 and 6

or   r16, r17
; r16 = 0b11000110 = 0xC6
; ^^               — bits 7 and 6 forced to 1; all others unchanged
```

OR forces bits to 1. It cannot force bits to 0. The combination of AND (force
to 0) and OR (force to 1) is how read-modify-write operations on peripheral
registers work.

### EOR — Bitwise Exclusive OR (XOR)

```
EOR Rd, Rr      ; Rd ← Rd EOR Rr    (any r0–r31)
```

1 cycle. Flags: S, V=0, N, Z. C unchanged. No immediate form — use a scratch
register if a constant mask is needed.

EOR truth table:

```
A   B   A EOR B
─   ─   ───────
0   0      0
0   1      1
1   0      1
1   1      0
```

EOR produces 1 when the inputs differ. It **toggles** bits wherever the mask
has a 1, and leaves bits unchanged wherever the mask has a 0:

```asm
ldi  r16, 0b10110110    ; r16 = 0xB6
ldi  r17, 0b00001111    ; mask: toggle lower nibble

eor  r16, r17
; r16 = 0b10111001 = 0xB9
;            ^^^^  — lower nibble toggled: 0110 → 1001
```

EOR has two special cases worth knowing:

```asm
eor  r16, r16       ; r16 = 0x00  (register XOR itself = clear to zero)
                    ; This is the preferred way to clear r0–r31. Aliases: CLR Rd.
                    ; 1 cycle, sets Z=1, does NOT affect C.

eor  r16, r17       ; Also used for: test if r16 == r17 without storing result
                    ; (result is 0 iff they were equal, setting Z=1)
```

`CLR Rd` is the assembler alias for `EOR Rd, Rd`. Always use `CLR` in source
for clarity.

### COM — Bitwise Complement (One's Complement)

```
COM Rd          ; Rd ← 0xFF − Rd = ~Rd    (any r0–r31)
```

1 cycle. Flags: C=1 (always), S, V=0, N, Z.

COM inverts every bit. It is bitwise NOT:

```asm
ldi  r16, 0b10110110    ; r16 = 0xB6
com  r16
; r16 = 0b01001001 = 0x49
```

Primary uses:
- Building inverted masks at runtime when the positive mask is already computed
- First step of two's complement negation (COM then INC — same as NEG)
- Multi-byte negation (COM all bytes, then add 1 — see Chapter 5c)

COM is **not** arithmetic negation. `COM r16` gives `~r16`; `NEG r16` gives
`-r16 = ~r16 + 1`. For single-byte negate, use NEG. For multi-byte negate,
use COM on every byte then add 1.

### Flag Behaviour Summary for Logic Instructions

All four logic instructions (AND, OR, EOR, COM) clear V to zero and set N and
Z based on the result byte. C is unchanged by AND, OR, and EOR; COM sets C=1.

Because V=0 after a logic instruction, S = N XOR V = N, so:
- `BRMI` and `BRLT` are equivalent after a logic instruction
- `BRPL` and `BRGE` are equivalent after a logic instruction

This matters when you use AND or EOR to test a value and then branch on the
sign.

---

## Masking: Isolating, Clearing, Setting, and Toggling Bits

A **mask** is a byte (or word) used as the second operand of a logic
instruction to select which bits of the first operand are affected. The mask
is the tool; AND, OR, and EOR are the operations.

### Clearing Specific Bits (AND)

To clear bits n and m of a register, AND with a mask that has 0 in positions
n and m and 1 everywhere else:

```asm
; Clear bits 3 and 1 of r16
andi r16, 0b11110101    ; mask: ~(BIT(3) | BIT(1)) = 0xF5
; Bits 3 and 1 are now 0; all other bits unchanged
```

The mask for "clear bit N" is `0xFF ^ (1 << N)` or equivalently `~(1 << N)`,
computed at assembly time:

```asm
andi r16, ~(1 << 3)     ; clear bit 3  (assembler evaluates ~(1<<3) = 0xF7)
andi r16, ~(1 << 5)     ; clear bit 5
```

Mnemonic: AND with 0 clears; AND with 1 preserves.

### Setting Specific Bits (OR)

To set bits n and m, OR with a mask that has 1 in those positions:

```asm
; Set bits 5 and 2 of r16
ori  r16, (1 << 5) | (1 << 2)    ; mask = 0b00100100 = 0x24
; Bits 5 and 2 are now 1; all other bits unchanged
```

Mnemonic: OR with 1 sets; OR with 0 preserves.

### Toggling Specific Bits (EOR)

To flip bits without knowing their current state, EOR with a mask that has 1
in those positions:

```asm
; Toggle bits 7 and 0 of r16
ldi  r17, (1 << 7) | (1 << 0)    ; mask = 0b10000001 = 0x81
eor  r16, r17
; Bits 7 and 0 are inverted; all other bits unchanged
```

### Isolating a Single Bit (AND, Result in-place)

Test whether a specific bit is set by AND-ing with a single-bit mask:

```asm
; Is bit 4 of r16 set?
mov  r17, r16
andi r17, (1 << 4)      ; r17 = 0 if bit 4 was 0; r17 = 0x10 if bit 4 was 1
breq bit4_clear         ; Z=1: bit 4 was 0
; here: bit 4 was 1
```

The result is nonzero (but not necessarily 1) when the bit is set — it equals
the mask value. Use BREQ/BRNE to branch on the result; do not compare with 1.

### Combining Set and Clear: Read-Modify-Write

Peripheral register configuration is almost always read-modify-write: read the
current register value, change only the relevant bits, write back. This
preserves other bits that other code may have set.

```asm
; Configure PORTB: set bit 5 (output high), clear bit 3 (output low)
lds  r16, VPORTB_OUT        ; read current output register
ori  r16, (1 << 5)          ; set bit 5
andi r16, ~(1 << 3)         ; clear bit 3
sts  VPORTB_OUT, r16        ; write back
```

The order — read, modify, write — is the universal peripheral control pattern.

### Common Mask Constants

```
Mask         Binary       Purpose
─────────    ──────────   ─────────────────────────────────────────────────
0x0F         0000 1111    Isolate lower nibble (units digit, low 4 bits)
0xF0         1111 0000    Isolate upper nibble (tens digit, high 4 bits)
0x7F         0111 1111    Clear bit 7 (sign bit in signed, MSB mask)
0x80         1000 0000    Isolate bit 7 (sign bit test)
0x01         0000 0001    Isolate bit 0 (odd/even test, LSB)
(1 << N)     varies       Single-bit mask for bit N (N = 0..7)
~(1 << N)    varies       Clear-bit mask for bit N
```

---

## Shift Instructions

Shifts move all bits left or right by one position. The bit that falls off the
end goes into the carry flag; the vacated position is filled according to the
shift type.

All shift instructions operate on a single register in 1 cycle.

```
LSL Rd — Logical Shift Left
    C ← [7][6][5][4][3][2][1][0] ← 0
    Bit 7 → C. Bit 0 filled with 0. Equivalent to ADD Rd, Rd.
    Effect: Rd × 2 (unsigned). Overflows into C when result > 255.
    Flags: H, C, Z, N, V, S  (H and V are set; V = N XOR C after shift)

LSR Rd — Logical Shift Right
    0 → [7][6][5][4][3][2][1][0] → C
    Bit 0 → C. Bit 7 filled with 0.
    Effect: Rd ÷ 2 (unsigned). Remainder (0 or 1) in C.
    Flags: C, Z, N=0, V=N_before XOR C, S

ASR Rd — Arithmetic Shift Right
    b7 → [7][6][5][4][3][2][1][0] → C
    Bit 0 → C. Bit 7 preserved (copied from its current value).
    Effect: Rd ÷ 2 (signed, rounds toward −∞). Remainder in C.
    Flags: C, Z, N, V=N XOR C, S
```

### Shifts as Bit Movement

Shifts are not just arithmetic: they physically move bits to a new position.
This is how you position a field for insertion or extraction.

Move bit 3 into bit 0 (extract bit 3 to the LSB):

```asm
ldi  r16, 0b00101000    ; r16 bit 3 is set
lsr  r16                ; bit 3 → bit 2, bit 0 → C
lsr  r16                ; bit 2 → bit 1
lsr  r16                ; bit 1 → bit 0
; r16 = 0b00000101  (bit 3 is now in bit 0, though bit 2 is also set from the original bit 5)
; Better: use the ANDI-before-shift pattern for clean extraction (see Field Extraction)
```

A cleaner pattern: mask first, then shift:

```asm
ldi  r16, 0b00101000    ; source
andi r16, (1 << 3)      ; isolate bit 3: r16 = 0b00001000
lsr  r16                ; → 0b00000100
lsr  r16                ; → 0b00000010
lsr  r16                ; → 0b00000001  (bit 3 value is now in bit 0)
```

Alternatively, test the bit directly with SBRC/SBRS (see below) and build the
result bit-by-bit.

### SWAP — Swap Nibbles

```
SWAP Rd         ; bits 7:4 ↔ bits 3:0
```

1 cycle. No flags affected.

SWAP exchanges the upper and lower nibbles of a register:

```asm
ldi  r16, 0xAB
swap r16            ; r16 = 0xBA
```

SWAP is a one-cycle substitute for four LSR (or LSL) instructions when working
with nibble-aligned fields. It is the tool for moving the upper nibble to the
lower position for extraction:

```asm
; Extract the upper nibble of r16 into the lower nibble of r17
mov  r17, r16
swap r17            ; upper nibble → lower nibble (garbage in upper nibble)
andi r17, 0x0F      ; clear the garbage upper nibble
; r17 = upper nibble of r16 as a 4-bit value (0–15)
```

And the reverse — move a low nibble to the upper nibble:

```asm
; Move lower nibble of r16 into upper nibble
andi r16, 0x0F      ; clear upper nibble first
swap r16            ; lower nibble → upper nibble (0s in lower nibble)
```

---

## Rotate Instructions

Rotates shift bits through the carry flag. The carry flag acts as a 9th bit
in the rotation ring.

```
ROL Rd — Rotate Left through Carry
    C ← [7][6][5][4][3][2][1][0] ← (old C)
    Bit 7 → C. Bit 0 gets the old value of C.
    Flags: H, C, Z, N, V, S

ROR Rd — Rotate Right through Carry
    (old C) → [7][6][5][4][3][2][1][0] → C
    Bit 0 → C. Bit 7 gets the old value of C.
    Flags: C, Z, N, V, S
```

### Rotates vs Shifts

A shift discards the outgoing bit (it goes into C but the vacated position is
filled with 0 regardless of C). A rotate feeds C back in on the vacated side.

This distinction is critical for multi-byte operations: when chaining shifts
across multiple registers, rotates are the correct tool because they carry bits
from one register into the next.

### Multi-byte Shift Left (LSL + ROL chain)

```asm
; 16-bit logical shift left: r25:r24 <<= 1
lsl  r24        ; low byte: bit 7 → C, 0 fills bit 0
rol  r25        ; high byte: old C → bit 0, bit 7 → C (new C = overflow)

; 32-bit logical shift left: r25:r24:r23:r22 <<= 1
lsl  r22
rol  r23
rol  r24
rol  r25
```

Each additional byte just adds another `ROL`. The carry from the previous
register flows into the LSB of the next.

### Multi-byte Shift Right (LSR + ROR chain)

```asm
; 16-bit logical shift right: r25:r24 >>= 1
lsr  r25        ; high byte first: bit 0 → C, 0 fills bit 7
ror  r24        ; low byte: old C → bit 7, bit 0 → C

; 32-bit logical shift right
lsr  r25
ror  r24
ror  r23
ror  r22
```

Multi-byte right shift processes high byte first (unlike addition, which
processes low byte first). The carry flows from the high byte down into the
low byte.

### Multi-byte Arithmetic Shift Right (ASR + ROR chain)

```asm
; 16-bit arithmetic shift right (signed ÷2): r25:r24 >>= 1
asr  r25        ; high byte: sign bit preserved, bit 0 → C
ror  r24        ; low byte: C → bit 7, bit 0 → C
```

Use ASR only on the most-significant byte. Every lower byte uses ROR, which
propagates the carry without forcing anything.

### Shifting by N Bits

AVR has no multi-bit shift instruction. Repeat the pair for each bit:

```asm
; 16-bit: r25:r24 >>= 3 (logical)
lsr  r25
ror  r24
lsr  r25
ror  r24
lsr  r25
ror  r24
```

For large shifts (N = 4), SWAP + ANDI/ORI is often faster on 8-bit registers.
For shifts by 8 (full byte), simply move registers:

```asm
; r25:r24 >>= 8  (shift right by one full byte)
mov  r24, r25   ; what was the high byte becomes the low byte
clr  r25        ; high byte is now 0
```

```asm
; r25:r24 <<= 8  (shift left by one full byte)
mov  r25, r24   ; what was the low byte becomes the high byte
clr  r24        ; low byte is now 0
```

---

## Bit Test and Skip Instructions

These instructions test a single bit and conditionally skip the next
instruction. They avoid the need to mask, compare, and branch.

### SBRC / SBRS — Skip if Bit in Register Clear/Set

```
SBRC Rr, b      ; skip next instruction if bit b of Rr is 0 (Clear)
SBRS Rr, b      ; skip next instruction if bit b of Rr is 1 (Set)
```

1 cycle if not skipping; 2 cycles if skipping (3 if the skipped instruction is
2 words). b = 0..7. Operand Rr = any r0–r31. No flags affected.

These are the cleanest way to act on a single bit:

```asm
; Execute handler if bit 4 of r16 is set
sbrs r16, 4         ; skip next if bit 4 SET
rjmp skip_handler   ; bit 4 clear: skip handler
rcall handle_bit4   ; bit 4 set: handle it
skip_handler:

; Conditional assignment: if bit 2 of r16 set, r17 = 0xFF, else r17 = 0x00
clr  r17
sbrs r16, 2         ; skip CLR/SER sequence if bit 2 set
rjmp bit2_clear
ser  r17            ; bit 2 set: r17 = 0xFF
bit2_clear:
```

SBRC and SBRS are the preferred way to branch on a single bit. They are more
readable and often faster than `ANDI + BREQ/BRNE`.

### SBIC / SBIS — Skip if I/O Bit Clear/Set

```
SBIC A, b       ; skip next if bit b of I/O register A is 0
SBIS A, b       ; skip next if bit b of I/O register A is 1
```

A = I/O address 0..31 (the lower I/O space, accessible without IN/OUT). b = 0..7.
No flags affected.

These operate directly on peripheral registers without loading them into a
general-purpose register:

```asm
; Wait until USART transmit data register is empty (UDRE bit in status)
wait_udre:
    sbis UCSR0A, UDRE0  ; skip next if UDRE bit SET (register ready)
    rjmp wait_udre       ; UDRE clear: not ready, loop
    ; here: UDRE is set — safe to write
```

SBIC and SBIS only reach the bottom 32 I/O addresses (0x00–0x1F). Peripheral
registers above that range must use `IN` + SBRC/SBRS.

### SBI / CBI — Set/Clear Bit in I/O Register

```
SBI A, b        ; set bit b in I/O register A
CBI A, b        ; clear bit b in I/O register A
```

2 cycles. A = I/O address 0..31. b = 0..7. No flags affected.

These are atomic single-bit operations on I/O space — no read-modify-write
cycle in software is needed:

```asm
sbi  VPORTB_DIR, 5      ; set PORTB pin 5 as output
cbi  VPORTB_OUT, 5      ; drive PORTB pin 5 low
sbi  VPORTB_OUT, 5      ; drive PORTB pin 5 high
```

SBI and CBI are faster than the ANDI/ORI read-modify-write pattern for the I/O
registers they can reach.

---

## The T Flag: Single-Bit Transfer

The T flag in SREG is a general-purpose bit storage cell. It is not set by
arithmetic; it only changes via BST and BLD.

```
BST Rr, b       ; T ← bit b of Rr  (Bit STore into T)
BLD Rd, b       ; bit b of Rd ← T  (Bit LoaD from T)
```

1 cycle each. Only T is affected by BST; only bit b of Rd is affected by BLD.

The T flag lets you copy an individual bit from one register to any bit
position in another register without clobbering either register:

```asm
; Copy bit 5 of r16 into bit 2 of r17
bst  r16, 5     ; T ← bit 5 of r16
bld  r17, 2     ; bit 2 of r17 ← T
; r16 and r17 are otherwise unchanged
```

Compare with the AND/OR approach that requires scratch registers and clobbers
more of the destination:

```asm
; Same operation without T flag (more cumbersome):
mov  r18, r16
lsr  r18            ; move bit 5 toward bit 0 (need 5 shifts)
lsr  r18
lsr  r18
lsr  r18
lsr  r18            ; r18 bit 0 = original r16 bit 5
andi r18, 0x01      ; isolate
lsl  r18
lsl  r18            ; move to bit 2
andi r17, ~(1 << 2) ; clear bit 2 in destination
or   r17, r18       ; insert
```

The BST/BLD pair is the right tool whenever you need to copy a single bit
between non-corresponding positions.

---

## Field Extraction: Getting Bits n:m from a Register

A **field** is a contiguous run of bits at a known position within a byte.
Extracting a field means isolating those bits and shifting them down to bit 0
so the result is a plain integer (0 to 2^width − 1).

### Single-Bit Extraction to Bit 0

```asm
; Extract bit 5 of r16 into bit 0 of r17 (result: 0 or 1)
mov  r17, r16
andi r17, (1 << 5)      ; isolate bit 5: r17 = 0 or 0x20
lsr  r17                ; 0x20 → 0x10
lsr  r17                ; 0x10 → 0x08
lsr  r17                ; 0x08 → 0x04
lsr  r17                ; 0x04 → 0x02
lsr  r17                ; 0x02 → 0x01
; r17 = 0 (bit was 0) or 1 (bit was 1)
```

With BST, this is two instructions:

```asm
; Extract bit 5 of r16 into bit 0 of r17 using T flag
bst  r16, 5
bld  r17, 0         ; r17 bit 0 = old r16 bit 5; other bits of r17 unchanged
```

If you want a clean 0-or-1 result with other bits zeroed:

```asm
clr  r17
bst  r16, 5
bld  r17, 0         ; r17 = 0 or 1
```

### Multi-bit Field Extraction (General Case)

To extract bits [hi:lo] from a register (a field of width `hi-lo+1` starting
at bit `lo`):

1. Mask to isolate the field
2. Shift right by `lo` positions to bring it to bit 0

```asm
; Extract bits 6:4 (3-bit field at offset 4) from r16 into r17
; Example: r16 = 0b10110100, field bits 6:4 = 0b011 = 3

mov  r17, r16
andi r17, 0b01110000    ; mask = 0x70 = bits 6, 5, 4
lsr  r17                ; bits 6:4 → bits 5:3
lsr  r17                ; bits 5:3 → bits 4:2
lsr  r17                ; bits 4:2 → bits 3:1
lsr  r17                ; bits 3:1 → bits 2:0
; r17 = field value (0–7)
```

The number of shifts equals the field's starting bit position (lo).

For fields at nibble boundaries, SWAP eliminates four shifts:

```asm
; Extract upper nibble (bits 7:4) of r16 into lower nibble of r17
mov  r17, r16
swap r17                ; upper nibble → lower nibble
andi r17, 0x0F          ; clear upper nibble (which now holds old lower nibble)
; r17 = upper nibble value (0–15)
```

### Extracting the Lower Nibble (bits 3:0)

```asm
mov  r17, r16
andi r17, 0x0F          ; r17 = bits 3:0 (lower nibble), 0–15
```

One instruction. No shift needed because the field is already at bit 0.

### Extracting Specific Byte from a Multi-byte Value

When a 16-bit value is in `r25:r24`, extracting the high byte is just a MOV:

```asm
mov  r16, r25           ; r16 = high byte of r25:r24
mov  r16, r24           ; r16 = low byte of r25:r24
```

No shift, no mask. The byte boundary aligns with the register boundary.

---

## Field Insertion: Putting a Value into a Specific Bit Position

Inserting a field is the reverse of extraction: shift the value up to its
target position, mask off any overflow, clear the target bits in the
destination, then OR the shifted value in.

### Single-Bit Insertion

```asm
; Set or clear bit 5 of r16 based on whether r17 bit 0 is set
andi r17, 0x01          ; isolate the source bit (0 or 1)
lsl  r17                ; bit 0 → bit 1
lsl  r17                ; bit 1 → bit 2
lsl  r17                ; bit 2 → bit 3
lsl  r17                ; bit 3 → bit 4
lsl  r17                ; bit 4 → bit 5  (r17 = 0 or 0x20)
andi r16, ~(1 << 5)     ; clear bit 5 in destination
or   r16, r17           ; insert the bit
```

Again, BST/BLD is cleaner for single-bit work:

```asm
; Copy bit 0 of r17 into bit 5 of r16
bst  r17, 0
bld  r16, 5
```

### Multi-bit Field Insertion (General Case)

Insert a w-bit value in r17 (bits [w-1:0]) into bits [hi:lo] of r16, where
lo = start position and w = hi − lo + 1:

1. Mask r17 to exactly w bits (prevent overflow into adjacent fields)
2. Shift r17 left by lo positions
3. AND r16 with the inverted field mask to clear the target bits
4. OR the shifted value into r16

```asm
; Insert bits 2:0 of r17 into bits 6:4 of r16 (3-bit field at offset 4)
; Field mask: bits 6:4 = 0b01110000 = 0x70

andi r17, 0x07          ; step 1: keep only 3 bits (0–7)
lsl  r17                ; step 2: shift up 4 positions (field offset = 4)
lsl  r17
lsl  r17
lsl  r17                ; r17 = (value & 0x07) << 4 = value in bits 6:4

andi r16, ~0x70         ; step 3: clear bits 6:4 in destination (mask = 0x8F)
or   r16, r17           ; step 4: insert the field
```

### Inserting a Lower Nibble into the Upper Nibble (SWAP idiom)

```asm
; Insert lower nibble of r17 into upper nibble of r16
; (Leaves lower nibble of r16 unchanged)
andi r17, 0x0F          ; ensure upper nibble of r17 is clear
swap r17                ; lower nibble → upper nibble
andi r16, 0x0F          ; clear upper nibble of destination
or   r16, r17           ; merge
```

---

## Packing: Combining Two Values into One Byte

Packing puts two separate values into the two halves (nibbles) of a single
byte. This is common for:
- Sending packed sensor data over a 1-byte protocol field
- Storing two 4-bit values in one SRAM byte to save space
- Building BCD digits from separate tens and units values

### Pack Two Nibbles into One Byte

```asm
; r16 = packed byte from low nibble of r17 (tens) and low nibble of r18 (units)
; r17 = tens digit (0–9, stored in low nibble)
; r18 = units digit (0–9, stored in low nibble)

andi r17, 0x0F          ; ensure only low nibble (defensive)
andi r18, 0x0F          ; same
swap r17                ; move tens to high nibble position
or   r17, r18           ; merge units into low nibble
mov  r16, r17           ; r16 = packed result
```

**Trace: tens=4 (r17=0x04), units=7 (r18=0x07)**

```
andi r17, 0x0F:  r17 = 0x04
andi r18, 0x0F:  r18 = 0x07
swap r17:        r17 = 0x40  (4 in upper nibble)
or   r17, r18:   r17 = 0x47  (packed BCD 47)  ✓
```

### Pack Eight Signal Lines into One Byte

When reading a parallel bus where each signal is in a different register, pack
them into a single byte using BST/BLD:

```asm
; Build a byte from 8 individual signal bits:
; bit 7 = MOSI (bit 0 of r20)
; bit 6 = MISO (bit 0 of r21)
; ... etc.
; Result in r16.

clr  r16
bst  r20, 0  ;  MOSI
bld  r16, 7
bst  r21, 0  ;  MISO
bld  r16, 6
; ... (repeat for remaining bits) ...
```

### Pack a Boolean Array into a Byte

Eight boolean values (one per register, non-zero = true) into one flag byte:

```asm
; r8..r15 each hold 0 or nonzero (boolean)
; Pack: r16 bit N = 1 iff r(8+N) is nonzero

clr  r16
ldi  r17, 8
ldi  r30, lo8(r8_array)     ; point Z at r8 using indirect addressing workaround
; (In practice, use SRAM-backed booleans and load via LD)
; For registers: use CPSE + SBI per bit or BST approach
```

A direct approach when the source values are already in known registers:

```asm
; Compact: bit 0 = nonzero(r8), bit 1 = nonzero(r9), ...
clr   r16
tst   r8
breq  pack_b0_done
ori   r16, (1 << 0)
pack_b0_done:
tst   r9
breq  pack_b1_done
ori   r16, (1 << 1)
pack_b1_done:
; ... (repeat for each bit) ...
```

---

## Unpacking: Splitting a Byte into its Fields

Unpacking reads a packed byte and distributes its fields into separate
registers for processing.

### Unpack Two Nibbles from One Byte

```asm
; r16 = packed byte (e.g., BCD 0x47)
; Extract high nibble → r17, low nibble → r18

mov  r17, r16
swap r17                ; upper nibble → lower nibble
andi r17, 0x0F          ; r17 = upper nibble value (4 in this example)

mov  r18, r16
andi r18, 0x0F          ; r18 = lower nibble value (7 in this example)
```

### Unpack a Byte into Individual Bits

Distribute 8 bits from r16 into individual boolean registers r8–r15 (one bit
per register):

```asm
; Unpack r16: each bit → separate register (0 or 1)
bst  r16, 0  ;  bit 0
bld  r8, 0
clr  r8
bst  r16, 0
bld  r8, 0   ; r8 bit 0 = source bit 0; but other bits of r8 are 0 from CLR
```

A cleaner idiom using LSR + carry:

```asm
; Unpack r16 bit-by-bit into r8..r15 using shifts
; After each LSR, carry holds the outgoing bit

lsr  r16        ; bit 0 → C
clr  r8
adc  r8, r8     ; r8 = C (0 or 1)

lsr  r16        ; original bit 1 → C
clr  r9
adc  r9, r9     ; r9 = C

; ... (repeat for r10–r15) ...
```

`ADC Rd, Rd` computes `Rd + Rd + C`. With `CLR r8` first: `0 + 0 + C = C`.
So `clr + adc Rd, Rd` loads C into bit 0 of Rd in one step.

---

## Practical Patterns

### Pattern 1: Read a GPIO Port and Extract a Pin State

```asm
; Read PORTB input and test whether pin 3 is high
lds  r16, VPORTB_IN         ; read PORTB input register
sbrs r16, 3                 ; skip next if pin 3 is HIGH
rjmp pin3_low
; pin3_high:
rjmp pin3_done
pin3_low:
pin3_done:
```

### Pattern 2: Write a Specific Field of a Peripheral Register

```asm
; Set the clock prescaler field (bits 2:0) of a config register to 0b101
; without disturbing other bits

lds  r16, CLK_CONFIG_REG        ; read current config
andi r16, 0b11111000            ; clear bits 2:0
ori  r16, 0b00000101            ; set bits 2:0 to 0b101
sts  CLK_CONFIG_REG, r16        ; write back
```

### Pattern 3: Reverse the Bits of a Byte

Reverse all 8 bits (bit 0 ↔ bit 7, bit 1 ↔ bit 6, etc.) — used for LSB-first
to MSB-first conversion in bit-banged protocols:

```asm
/*
 * bit_reverse8 — reverse all 8 bits of r16
 *   Input:  r16 = byte to reverse
 *   Output: r16 = bit-reversed byte
 *   Clobbers: r17, r18
 */
bit_reverse8:
    ldi  r18, 8         ; 8 bits to process
    clr  r17            ; result accumulator
bit_rev_loop:
    lsl  r17            ; make room for next bit
    lsr  r16            ; LSB of r16 → C
    rol  r17            ; C → bit 0 of r17 (via rotate)
    dec  r18
    brne bit_rev_loop
    mov  r16, r17
    ret
```

**Trace: r16 = 0b10110001**

```
Iteration 1: lsl r17(0)→0, lsr r16→01011000 C=1, rol r17→0b00000001
Iteration 2: lsl r17→0b00000010, lsr r16→00101100 C=0, rol r17→0b00000010
...continuing...
Final: r16 = 0b10001101 (bits reversed) ✓
```

### Pattern 4: Count Set Bits (Population Count / Hamming Weight)

Count the number of 1 bits in a byte:

```asm
/*
 * popcount8 — count set bits in r16
 *   Input:  r16 = byte to examine
 *   Output: r17 = number of set bits (0–8)
 *   Clobbers: r18
 */
popcount8:
    clr  r17            ; count = 0
    ldi  r18, 8         ; 8 iterations

popcount_loop:
    lsr  r16            ; bit 0 → C
    adc  r17, r1        ; r17 += C  (r1 = 0 per ABI)
    dec  r18
    brne popcount_loop
    ret
```

`ADC r17, r1` computes `r17 + 0 + C = r17 + C`. Since r1 = 0 (GCC ABI
invariant), this adds 1 to the count only when a 1 bit was shifted out.

### Pattern 5: Extract a 3-bit SPI Device Address from a Protocol Frame

A SPI command byte has the format: `[7:5] = opcode, [4:2] = device address, [1:0] = flags`.

```asm
; r16 = incoming command byte
; Extract device address (bits 4:2) into r17

mov  r17, r16
andi r17, 0b00011100    ; mask bits 4:2 (= 0x1C)
lsr  r17                ; bit 2 offset: shift right twice
lsr  r17
; r17 = device address (0–7)

; Also extract opcode (bits 7:5) into r18
mov  r18, r16
andi r18, 0b11100000    ; mask bits 7:5 (= 0xE0)
lsr  r18
lsr  r18
lsr  r18
lsr  r18
lsr  r18
; r18 = opcode (0–7)

; Extract flags (bits 1:0) into r19
mov  r19, r16
andi r19, 0b00000011    ; mask bits 1:0 (= 0x03)
; r19 = flags (0–3) — already at bit 0, no shift needed
```

### Pattern 6: Build a SPI Command Byte from Fields

Reverse of the above — assemble a command byte from opcode, address, and flags:

```asm
; r20 = opcode (0–7), r21 = device address (0–7), r22 = flags (0–3)
; Build command byte in r16

andi r20, 0x07          ; ensure 3 bits
lsl  r20
lsl  r20
lsl  r20
lsl  r20
lsl  r20                ; opcode in bits 7:5

andi r21, 0x07          ; ensure 3 bits
lsl  r21
lsl  r21                ; address in bits 4:2

andi r22, 0x03          ; ensure 2 bits (already at bits 1:0)

or   r20, r21
or   r20, r22
mov  r16, r20           ; r16 = assembled command byte
```

**Trace: opcode=5 (0b101), address=3 (0b011), flags=2 (0b10)**

```
opcode: 0b00000101 → <<5 → 0b10100000
address: 0b00000011 → <<2 → 0b00001100
flags: 0b00000010 (no shift)

OR: 0b10100000 | 0b00001100 | 0b00000010 = 0b10101110 = 0xAE ✓
Decode: bits 7:5 = 101 = 5 ✓, bits 4:2 = 011 = 3 ✓, bits 1:0 = 10 = 2 ✓
```

### Pattern 7: Rotate a 32-bit Value Through a Peripheral (Shift Register Output)

Output a 32-bit value MSB-first via a GPIO pin by shifting bit by bit:

```asm
/*
 * shift_out32 — output r25:r24:r23:r22 MSB-first on DATA pin
 *   Assumes DATA = PORTB pin 1, CLK = PORTB pin 0
 *   32 clock pulses are generated. No return value.
 */
shift_out32:
    ldi  r20, 32                ; 32 bits to send

shift_out_loop:
    ; Output MSB of r25 on DATA pin
    sbrs r25, 7                 ; skip next if bit 7 is set
    cbi  VPORTB_OUT, 1          ; bit 7 = 0: DATA low
    sbrc r25, 7                 ; skip next if bit 7 is clear
    sbi  VPORTB_OUT, 1          ; bit 7 = 1: DATA high

    ; Pulse clock
    sbi  VPORTB_OUT, 0          ; CLK high
    cbi  VPORTB_OUT, 0          ; CLK low

    ; Shift left: next MSB moves into bit 7 of r25
    lsl  r22
    rol  r23
    rol  r24
    rol  r25

    dec  r20
    brne shift_out_loop
    ret
```

---

## Instruction Reference

```
Instruction     Operands            Cyc  Flags              Notes
──────────────  ──────────────────  ───  ─────────────────  ─────────────────────────────
AND  Rd, Rr     r0–r31, r0–r31       1   S,V=0,N,Z; C unch  Bitwise AND
ANDI Rd, K      r16–r31; K=0–255     1   S,V=0,N,Z; C unch  AND with immediate
OR   Rd, Rr     r0–r31, r0–r31       1   S,V=0,N,Z; C unch  Bitwise OR
ORI  Rd, K      r16–r31; K=0–255     1   S,V=0,N,Z; C unch  OR with immediate
EOR  Rd, Rr     r0–r31, r0–r31       1   S,V=0,N,Z; C unch  Bitwise XOR; CLR Rd = EOR Rd,Rd
COM  Rd         r0–r31               1   C=1,S,V=0,N,Z      Bitwise NOT (~Rd)
LSL  Rd         r0–r31               1   H,C,Z,N,V,S        Shift left; bit 7→C; 0→bit 0
LSR  Rd         r0–r31               1   C,Z,N=0,V,S        Shift right; 0→bit 7; bit 0→C
ASR  Rd         r0–r31               1   C,Z,N,V,S          Arith shift right; b7 preserved
ROL  Rd         r0–r31               1   H,C,Z,N,V,S        Rotate left through C
ROR  Rd         r0–r31               1   C,Z,N,V,S          Rotate right through C
SWAP Rd         r0–r31               1   none               Swap nibbles; no flags
BST  Rr, b      r0–r31; b=0–7        1   T only             T ← bit b of Rr
BLD  Rd, b      r0–r31; b=0–7        1   none               bit b of Rd ← T
SBRC Rr, b      r0–r31; b=0–7       1/2  none               Skip if bit b of Rr = 0
SBRS Rr, b      r0–r31; b=0–7       1/2  none               Skip if bit b of Rr = 1
SBIC A, b       A=0–31; b=0–7       1/2  none               Skip if I/O bit clear; low I/O only
SBIS A, b       A=0–31; b=0–7       1/2  none               Skip if I/O bit set; low I/O only
SBI  A, b       A=0–31; b=0–7        2   none               Set I/O bit (atomic)
CBI  A, b       A=0–31; b=0–7        2   none               Clear I/O bit (atomic)
CLR  Rd         r0–r31               1   Z=1,N=0,V=0,S=0    Alias for EOR Rd,Rd; C unchanged
SER  Rd         r16–r31              1   none               Alias for LDI Rd,0xFF
TST  Rd         r0–r31               1   Z,N,V=0,S          Alias for AND Rd,Rd; Rd unchanged
```

---

## Common Pitfalls

### Pitfall 1: Using OR to Add Numbers

OR is bitwise union, not addition. When the same bit is set in both operands,
OR produces 1 (it does not carry):

```asm
ldi  r16, 0b00001111   ; = 15
ldi  r17, 0b00001111   ; = 15
or   r16, r17          ; r16 = 0b00001111 = 15  ← not 30!
add  r16, r17          ; r16 = 0b00011110 = 30  ← correct
```

Use ADD for numeric addition. Use OR for bit setting.

### Pitfall 2: EOR Does Not Use an Immediate Operand

There is no `EORI` instruction. To XOR with a constant, load the constant into
a scratch register first:

```asm
; Toggle bits 3 and 0 of r16
; WRONG — no EORI instruction:
; eori r16, 0x09

; CORRECT:
ldi  r17, 0x09
eor  r16, r17
```

### Pitfall 3: COM Is Not NEG

COM computes `~Rd` (flip all bits). NEG computes `-Rd` (two's complement
negation = `~Rd + 1`). They differ by 1 for all nonzero inputs:

```asm
ldi  r16, 0x01      ; +1
com  r16            ; r16 = 0xFE = -2  ← NOT -1
neg  r16            ; r16 = 0xFF = -1  ← correct negate
```

### Pitfall 4: Logic Instructions Do Not Preserve C

AND, OR, and EOR leave C unchanged. If you plan to use C after a masking
operation, the logic instruction will not corrupt it — but if you intended
C to reflect the logic result, it does not.

```asm
add  r16, r17       ; C=1 (carry occurred)
andi r16, 0xF0      ; C is still 1 from the ADD — ANDI did not change it
brcs still_from_add ; this branch uses the carry from the ADD, not the ANDI
```

Keep arithmetic and bit-manipulation flag reading clearly separated.

### Pitfall 5: SBRC/SBRS Skip Only One Instruction

SBRC and SBRS skip exactly one instruction — not a block of code. If the
skipped instruction is itself a branch (RJMP, BREQ, etc.), that one instruction
is skipped:

```asm
; Execute a block if bit 3 is set
sbrs r16, 3         ; skip next instruction if bit 3 SET
rjmp block_done     ; skipped when bit 3 set → fall through to block
; block executes here (when bit 3 is set)
block:
    ; ...
    rjmp block_done
block_done:
```

The skip + `rjmp` pattern is the standard idiom for conditional block execution
with SBRC/SBRS.

### Pitfall 6: Field Mask Must Match the Shift Count

When inserting a field, the number of shift positions must exactly equal the
field's starting bit number, and the field mask must cover exactly those bits:

```asm
; Insert 3-bit value (bits 2:0 of r17) into bits 5:3 of r16
; Correct: shift by 3, mask = 0b00111000 = 0x38
andi r17, 0x07          ; 3 bits of value
lsl  r17
lsl  r17
lsl  r17                ; shifted up by 3 (bits 5:3 position)
andi r16, ~0x38         ; clear bits 5:3 in destination
or   r16, r17           ; insert

; WRONG: shift by 4 (misaligned):
; lsl r17 × 4  → value in bits 6:4, not 5:3 — off by one
```

### Pitfall 7: SBI/CBI Only Reach the Low 32 I/O Addresses

SBI, CBI, SBIC, and SBIS can only address I/O registers at addresses 0x00–0x1F
in the I/O space (which corresponds to 0x20–0x3F in the data space). Higher
peripheral registers require `IN` + `ANDI`/`ORI` + `OUT` or
`LDS`/`ANDI`/`ORI`/`STS`.

On the ATtiny3217, most peripherals use the VPORT mechanism: each port's virtual
registers (at 0x00–0x1F I/O space) are accessible with SBI/CBI.

---

## Summary

```
Bitwise logic:
  AND  Rd, Rr / ANDI Rd, K   — force bits to 0 (mask to clear)
  OR   Rd, Rr / ORI  Rd, K   — force bits to 1 (mask to set)
  EOR  Rd, Rr                — toggle bits (no immediate form)
  COM  Rd                    — invert all bits (~Rd); C=1 always; NOT the same as NEG
  All: V=0 after; S = N; C unchanged (except COM sets C=1).

Masking idioms:
  Clear bits N:  ANDI Rd, ~(1<<N)           — mask has 0 at N, 1 elsewhere
  Set bit N:     ORI  Rd,  (1<<N)           — mask has 1 at N, 0 elsewhere
  Toggle bit N:  load mask, EOR             — no EORI instruction
  Test bit N:    ANDI Rd, (1<<N) + BREQ/BRNE,  or  SBRC/SBRS (preferred)
  Read-modify-write: LDS/IN → ANDI → ORI → STS/OUT

Shifts (1 cycle each):
  LSL — left, 0 fills bit 0, bit 7 → C  (unsigned ×2)
  LSR — right, 0 fills bit 7, bit 0 → C  (unsigned ÷2)
  ASR — right, sign bit preserved  (signed ÷2, rounds toward −∞)
  ROL — rotate left through C  (chain for multi-byte left shift: LSL + ROL...)
  ROR — rotate right through C  (chain for multi-byte right shift: LSR high, ROR low...)
  SWAP — swap nibbles, no flags  (shortcut for 4-position shift)

Multi-byte shifts: left = LSL low, ROL high; right = LSR high, ROR low.
Shift by N: repeat the pair N times, or use register-move for byte shifts.

Single-bit operations:
  SBRC/SBRS Rr, b  — skip next if bit b of Rr is 0/1 (preferred for branches)
  BST/BLD          — copy bit to/from T flag (copy between non-aligned positions)
  SBI/CBI  A, b    — set/clear I/O bit atomically (I/O 0x00–0x1F only)
  SBIC/SBIS A, b   — skip if I/O bit clear/set (same range)

Field extraction:
  Lower nibble: ANDI Rd, 0x0F
  Upper nibble: MOV + SWAP + ANDI 0x0F
  Arbitrary [hi:lo]: ANDI with field mask, then LSR × lo

Field insertion (value into bits [hi:lo] of destination):
  1. ANDI value with width mask  (prevent overflow)
  2. LSL value by lo positions   (align to target)
  3. ANDI dest with ~field mask  (clear target bits)
  4. OR dest, value              (insert)

Packing two nibbles: ANDI + SWAP one, ANDI the other, OR together.
Unpacking nibbles:   MOV + SWAP + ANDI 0x0F for high; ANDI 0x0F for low.
Bit reversal:        8-iteration loop: LSR source → C → ROL accumulator.
Population count:    8-iteration loop: LSR source → C → ADC count, r1.
```

---

## Exercises

1. A peripheral status register contains these fields:
   `[7:6] = mode (2 bits)`, `[5:3] = channel (3 bits)`, `[2:1] = rate (2 bits)`,
   `[0] = enable (1 bit)`.
   Write the assembly sequence to:
   a. Extract the channel field into r17 (result in bits 2:0 of r17, 0–7)
   b. Set the enable bit without affecting any other field
   c. Write mode=2, channel=5, rate=1, enable=1 as a single assembled byte

2. A bitfield byte in r16 encodes eight boolean flags. Write a subroutine
   `get_flag(r16, r17) → r18` where r17 is the bit number (0–7) and r18
   returns 0 or 1. Hint: use a shift loop or look up whether there's a
   single-instruction approach using BST.

3. Implement `bit_reverse8` without a loop: unroll all 8 iterations using
   LSR + ROL pairs and verify the result for input 0b10110001. How many
   instruction words does the unrolled version use compared to the loop?

4. A 16-bit value in `r25:r24` needs to be shifted right by 3 bits
   (logical). Write the 6-instruction sequence (LSR + ROR × 5). Then
   write a version that shifts by 8 bits using only register moves — how
   many instructions?

5. Write a subroutine `pack_nybbles(r16, r17) → r16` that takes the low
   nibble of r16 as the upper nibble and the low nibble of r17 as the lower
   nibble of the result. Verify with inputs r16=0x04, r17=0x09 → 0x49.

6. The GPIO input register holds a byte where bits 7, 5, 3, and 1 are
   connected to four buttons (bit = 1 when pressed). Write a sequence that
   compacts these four button states into bits 3:0 of r17, discarding the
   gaps. (Hint: extract each bit with BST/BLD or with shifts and OR.)

7. Implement `popcount8` without a loop by using the parallel bit-count
   technique: first count pairs, then nibbles, then the full byte using only
   AND, ADD, and shift operations. (Hint: for two-bit groups,
   `count = (x & 0x55) + ((x >> 1) & 0x55)`.) How does cycle count compare
   to the loop version?

8. Write a read-modify-write sequence that atomically (with respect to the
   rest of the main-loop code — not interrupt-safe) configures bits 5:3 of
   a peripheral control register `PERIPH_CTRL` to the value 0b110 (6),
   without disturbing any other bits. Write it twice: once for a register
   reachable by SBI/CBI, and once for a register that requires LDS/STS.

9. A 32-bit shift register protocol requires data MSB-first. Rewrite
   `shift_out32` from the Practical Patterns section to also capture 32
   incoming MISO bits into `r7:r6:r5:r4` using `ROR` on the captured byte
   after each clock pulse.

10. Using only logic instructions (no ADD, no SUB), compute:
    a. `r16 AND (r16 - 1)` — what does this value represent about r16?
       (Hint: think about what the subtraction does to the lowest set bit.)
    b. `r16 OR (r16 - 1)` — similarly, what does this represent?
    Implement both using registers (you may use SUBI for the −1 step) and
    test with r16 = 0b00101000.

---

*Next: Chapter 6 — Shifts, Multiply, and Division*
