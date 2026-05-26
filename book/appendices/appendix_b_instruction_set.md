# AVR Instruction Set Summary

Complete instruction set for AVR (classic core, enhanced core with MUL).
Columns: **Opcode** — mnemonic and operands; **Operation** — what it does;
**Cycles** — clock cycles (branch cycles shown as taken/not-taken);
**Flags** — SREG bits modified (I T H S V N Z C).

`Rd` = destination register (R0–R31 unless noted).
`Rr` = source register.
`K` = 8-bit constant (0–255).
`k` = relative branch offset (−64..63 for 7-bit, −2048..2047 for 12-bit).
`b` = bit index (0–7).
`A` = I/O address (0–63).
`q` = displacement (0–63) for Y/Z indirect with displacement.

---

## How to Read the AVR Instruction Set Manual

This appendix is a quick reference. The Microchip instruction set manual is the
authoritative source. If you only use the summary table, you can write code.
If you learn to read the manual pages directly, you can answer harder questions:

- Why does this instruction only work on `r16–r31`?
- Why is this branch 1 cycle sometimes and 2 cycles other times?
- Why does `SBIS` skip differently from `BRNE`?
- Why does `OUT` work here but `STS` is required there?
- Why does an instruction update `Z` but not `C`?

The manual is not hard once you know what each field is trying to tell you.
The problem is that it reads like a hardware document, not a tutorial.

### What One Instruction Page Contains

Each instruction in the manual is usually presented in the same structure:

- **Description / operation**: what value changes logically.
- **Syntax**: the assembly form, such as `ADD Rd, Rr`.
- **Operands**: legal ranges, such as `0 <= d <= 31`.
- **Program Counter**: how `PC` changes after execution.
- **Opcode**: the encoded bit pattern.
- **Status Register (SREG) and Boolean Formula**: which flags change and why.
- **Words / Cycles**: code size and execution time, often by AVR core family.

When reading a page, do not read it top to bottom like prose. Read it in this
order instead:

1. **Syntax**: what form the instruction has.
2. **Operands**: which registers or constants are legal.
3. **Operation**: what value is computed.
4. **SREG effects**: which later branches or compares it can support.
5. **Words / Cycles**: whether it is a good fit for tight loops.
6. **Opcode**: only when you want to understand encoding limits or disassembly.

That order matches how you actually use the information while programming.

### Start with Syntax, but Trust the Operand Limits

Beginners often read `LDI Rd, K` as "load any register with any 8-bit
constant". The syntax alone does not tell the whole story. The **Operands**
field does:

```text
LDI Rd, K
Operands: 16 <= d <= 31, 0 <= K <= 255
```

That means `ldi r0, 1` is impossible, not merely discouraged. The reason is in
the opcode encoding: `LDI` only has four bits for the register number, so the
encoded register is really `Rd - 16`.

This pattern appears all over AVR:

- `LDI`, `ANDI`, `ORI`, `SUBI`, `SBCI`, `CPI` only work on `r16–r31`.
- `ADIW` and `SBIW` only work on specific register pairs.
- `MOVW` only uses even-numbered register pairs.
- `SBI`, `CBI`, `SBIC`, `SBIS` only work on low I/O addresses.

If the syntax looks general but the operand range is narrow, believe the range.
The encoding is the real reason.

### Read "Words" Before "Cycles"

AVR documentation uses **words**, not bytes, as the natural unit of program
storage. One word is 16 bits, so:

- **1 word** = 2 bytes
- **2 words** = 4 bytes

This matters because AVR instructions are either one word or two words. That
affects all of these at once:

- code size in flash
- instruction fetch behaviour
- skip-instruction timing
- absolute vs relative addressing choices

Examples:

- `OUT` is one word; `STS` is two words.
- `RJMP` is one word; `JMP` is two words.
- `RCALL` is one word; `CALL` is two words.

So when the manual says an instruction is "Words: 2", translate that
immediately into "this costs 4 bytes and may also affect skip timing".

### Relative Addresses Are Not Absolute Addresses

AVR manuals use several similar-looking operand letters:

- `K` often means an immediate constant.
- `k` often means a relative code offset.
- `q` means a small displacement from `Y` or `Z`.
- `A` means a low I/O address.

Case matters. `K` and `k` are not interchangeable.

For branches and relative calls:

- `RJMP k` means jump relative to the current `PC`
- `RCALL k` means call relative to the current `PC`
- `BRNE k` means branch a short relative distance if `Z = 0`

The manual usually writes this as:

```text
PC <- PC + k + 1
```

That `+ 1` exists because the PC normally advances to the next instruction
word before the relative offset is applied. The important practical result is:

- `RJMP` and `RCALL` do not encode a full absolute address.
- `BRxx` instructions have much shorter range than `RJMP`.
- Disassemblers may show targets as labels, but the hardware stores offsets.

### Read the SREG Section as "What Can I Test Next?"

The **Status Register (SREG)** is not just bookkeeping. It determines what
branches are meaningful after an instruction.

The bits are:

- `I`: global interrupt enable
- `T`: transfer bit for `BST` / `BLD`
- `H`: half-carry, mainly for nibble/BCD-style carries
- `S`: sign bit, defined as `N xor V`
- `V`: signed overflow
- `N`: negative
- `Z`: zero
- `C`: carry / borrow

When reading an instruction page, ask:

- Does this instruction update flags at all?
- Which flags does it update?
- Are those flags enough for unsigned comparison, signed comparison, or both?

Examples:

- `ADD` updates `Z`, `C`, `N`, `V`, `S`, `H`, so it supports later arithmetic
  decisions.
- `INC` does **not** update `C`, so it is not a drop-in replacement for
  `ADD Rd, 1` if carry matters.
- `TST` is really a flag-producing logical test, useful before `BREQ` or
  `BRMI`.
- `CP` changes flags without changing registers, which is why branches usually
  follow it directly.

The fastest way to understand a flag table is to map it to branch usage:

- For **unsigned** comparisons, care mostly about `C` and `Z`.
- For **signed** comparisons, care mostly about `S`, `V`, `N`, and `Z`.
- For equality, care about `Z`.

That is why AVR has both unsigned-style branches (`BRLO`, `BRSH`) and
signed-style branches (`BRLT`, `BRGE`).

### Do Not Panic About the Boolean Formulas

The manual often gives flag equations in Boolean form. Those formulas are
precise, but you usually do not need to derive them by hand while writing
ordinary code.

Use them in three situations:

1. When a flag result surprises you.
2. When writing multi-byte arithmetic where carry/borrow chains matter.
3. When reviewing whether two instructions are truly interchangeable.

For most programming, this simpler interpretation is enough:

- `C`: carry out of bit 7 for addition, borrow behaviour for subtraction
- `Z`: result was zero
- `N`: result bit 7 is 1
- `V`: signed overflow happened
- `S`: signed comparison helper, `N xor V`
- `H`: carry from bit 3 to bit 4

If you are not doing decimal-style arithmetic or bit-exact arithmetic tricks,
`H` is usually less important than `Z`, `C`, and `S`.

### Cycles Are Family-Specific

The instruction set manual often shows cycle counts across multiple AVR core
families. This book targets the ATtiny3217, which is an **AVRxt** device, so
the AVRxt column is the one that matters most here.

Do not assume:

- a timing number from an older ATmega necessarily matches AVRxt
- all loads and stores cost the same on every AVR family
- every manual example was written with your exact core in mind

When timing matters, read the correct family column first, then read any note
attached to it. Notes are where the manual hides the details that break naive
assumptions.

### Skip Instructions Need Extra Attention

`CPSE`, `SBRC`, `SBRS`, `SBIC`, and `SBIS` do not branch. They **skip the next
instruction** if the condition is true.

That sounds simple, but the manual's word count matters here:

- If the next instruction is 1 word, the skip jumps over 2 bytes.
- If the next instruction is 2 words, the skip jumps over 4 bytes.
- That is why skip instructions have multiple cycle counts.

So this is safe:

```asm
sbrc r16, 0
rjmp bit_was_set
```

But this behaves differently from a true branch because the skip is based on
the size of the *next* instruction, not on a stored relative destination.

When reading the manual, any cycle count like `1/2/3` or `2/3/4` should make
you ask: "is this a skip instruction, and is the next instruction one or two
words long?"

### Learn the Address Spaces Separately

AVR documentation is much easier once you stop treating "memory" as one thing.
The manual switches among several address spaces:

- **register file**: `r0–r31`
- **I/O space**: low peripheral addresses used by `IN` / `OUT`
- **data space**: SRAM and memory-mapped locations used by `LD` / `ST` / `LDS`
  / `STS`
- **program memory**: flash, read with `LPM`

Many confusing instruction choices become obvious once you ask which space is
being accessed.

Example:

- `OUT PORTA_DIR, r16` only works if that register is in low I/O space.
- `STS PORTA_DIR, r16` works with a data-space address, but costs more.
- `LPM` is for flash, not SRAM.

If two instructions seem to do the same job, check whether they are really
talking to different address spaces.

### Aliases and Pseudo-Instructions Can Hide the Real Opcode

Assembly source often uses friendly names that are not separate hardware
instructions.

Examples:

- `CLR Rd` is assembled as `EOR Rd, Rd`.
- `SER Rd` is assembled as `LDI Rd, 0xFF`.
- `LSL Rd` is effectively `ADD Rd, Rd`.
- named branches like `BREQ` and `BRNE` are readable aliases for specific
  `BRBS` / `BRBC` conditions.

That matters because the manual may document one spelling while the assembler
accepts another. If something looks inconsistent, check whether you are dealing
with:

- a real opcode
- an alias mnemonic
- a pseudo-instruction expanded by the assembler

### A Good Manual-Reading Workflow

When you meet an unfamiliar instruction, use this checklist:

1. Read the syntax and operand limits.
2. Identify the address space involved: register, I/O, SRAM, or flash.
3. Check whether it is 1 word or 2 words.
4. Check which SREG flags it updates.
5. Check whether the cycle count depends on branch taken/not taken, skip size,
   or AVR core family.
6. Check whether there is a shorter equivalent instruction for your case.

That method is enough to decode most of the manual quickly.

### What This Means for the Rest of the Book

Use Chapter 4 to learn the common instruction patterns, then come back to this
appendix when you need the full table. Use the Microchip manual when a question
depends on one of these details:

- exact flag behaviour
- exact operand limits
- instruction encoding constraints
- family-specific cycle counts
- special notes about program memory, skip timing, or core differences

Once you start reading the manual this way, it stops looking like a wall of
tables and starts looking like a set of answers to very specific questions.

---

## Arithmetic and Logic

```
Opcode          Operation                      Cycles   Flags
──────────────────────────────────────────────────────────────────────────────
ADD  Rd, Rr     Rd ← Rd + Rr                   1        H S V N Z C
ADC  Rd, Rr     Rd ← Rd + Rr + C               1        H S V N Z C
ADIW Rd, K      Rd+1:Rd ← Rd+1:Rd + K (0–63)  2        S V N Z C
SUB  Rd, Rr     Rd ← Rd − Rr                   1        H S V N Z C
SUBI Rd, K      Rd ← Rd − K                    1        H S V N Z C
SBC  Rd, Rr     Rd ← Rd − Rr − C               1        H S V N Z C
SBCI Rd, K      Rd ← Rd − K − C                1        H S V N Z C
SBIW Rd, K      Rd+1:Rd ← Rd+1:Rd − K (0–63)  2        S V N Z C
AND  Rd, Rr     Rd ← Rd AND Rr                 1        S V N Z
ANDI Rd, K      Rd ← Rd AND K  (R16–R31)       1        S V N Z
OR   Rd, Rr     Rd ← Rd OR Rr                  1        S V N Z
ORI  Rd, K      Rd ← Rd OR K   (R16–R31)       1        S V N Z
EOR  Rd, Rr     Rd ← Rd XOR Rr                 1        S V N Z
COM  Rd         Rd ← 0xFF − Rd (bitwise NOT)   1        S V N Z C
NEG  Rd         Rd ← 0x00 − Rd (two's comp)   1        H S V N Z C
INC  Rd         Rd ← Rd + 1                    1        S V N Z
DEC  Rd         Rd ← Rd − 1                    1        S V N Z
MUL  Rd, Rr     R1:R0 ← Rd × Rr (unsigned)    2        Z C
MULS Rd, Rr     R1:R0 ← Rd × Rr (signed)      2        Z C
                  Rd, Rr: R16–R31 only
MULSU Rd, Rr    R1:R0 ← Rd × Rr (sgn × uns)  2        Z C
                  Rd, Rr: R16–R23 only
FMUL  Rd, Rr    R1:R0 ← (Rd × Rr) << 1 (uns) 2        Z C
FMULS Rd, Rr    R1:R0 ← (Rd × Rr) << 1 (sgn) 2        Z C
FMULSU Rd, Rr   R1:R0 ← (Rd × Rr) << 1 (s×u) 2        Z C
```

---

## Shift and Rotate

```
Opcode          Operation                      Cycles   Flags
──────────────────────────────────────────────────────────────────────────────
LSL  Rd         Rd ← Rd << 1; Rd0=0; C←Rd7    1        H S V N Z C
LSR  Rd         Rd ← Rd >> 1; Rd7=0; C←Rd0    1        S V N Z C
ASR  Rd         Rd ← Rd >> 1; Rd7 unchanged   1        S V N Z C
ROL  Rd         Rd ← Rd << 1; Rd0=C; C←Rd7    1        H S V N Z C
ROR  Rd         Rd ← Rd >> 1; Rd7=C; C←Rd0    1        S V N Z C
SWAP Rd         Rd[7:4] ↔ Rd[3:0]             1        —
```

---

## Bit Operations

```
Opcode          Operation                      Cycles   Flags
──────────────────────────────────────────────────────────────────────────────
SBI  A, b       I/O[A][b] ← 1  (A: 0–31)      2        —
CBI  A, b       I/O[A][b] ← 0  (A: 0–31)      2        —
BST  Rd, b      T ← Rd[b]                      1        T
BLD  Rd, b      Rd[b] ← T                      1        —
SEC             C ← 1                          1        C
CLC             C ← 0                          1        C
SEN             N ← 1                          1        N
CLN             N ← 0                          1        N
SEZ             Z ← 1                          1        Z
CLZ             Z ← 0                          1        Z
SEI             I ← 1 (global interrupt on)    1        I
CLI             I ← 0 (global interrupt off)   1        I
SES             S ← 1                          1        S
CLS             S ← 0                          1        S
SEV             V ← 1                          1        V
CLV             V ← 0                          1        V
SET             T ← 1                          1        T
CLT             T ← 0                          1        T
SEH             H ← 1                          1        H
CLH             H ← 0                          1        H
BSET b          SREG[b] ← 1                    1        (b)
BCLR b          SREG[b] ← 0                    1        (b)
```

---

## Compare and Test

```
Opcode          Operation                      Cycles   Flags
──────────────────────────────────────────────────────────────────────────────
CP   Rd, Rr     Rd − Rr (flags only)           1        H S V N Z C
CPC  Rd, Rr     Rd − Rr − C (flags only)       1        H S V N Z C
CPI  Rd, K      Rd − K (flags only, R16–R31)   1        H S V N Z C
TST  Rd         Rd AND Rd (flags only)          1        S V N Z
```

---

## Branch Instructions

```
Opcode          Condition          Cycles   Notes
──────────────────────────────────────────────────────────────────────────────
RJMP k          —                  2        PC ← PC + k + 1; k: −2048..2047
JMP  k          —                  3        PC ← k; 32-bit instruction
IJMP            —                  2        PC ← Z (16-bit)
EIJMP           —                  2        PC ← EIND:Z (>128KB flash)

RCALL k         —                  3        Push PC, PC ← PC + k + 1
CALL  k         —                  4        Push PC, PC ← k; 32-bit
ICALL           —                  3        Push PC, PC ← Z
EICALL          —                  3        Push PC, PC ← EIND:Z
RET             —                  4        Pop PC
RETI            —                  4        Pop PC, I ← 1

BRBS b, k       SREG[b] = 1       1/2      Branch if bit set; 1=not taken, 2=taken
BRBC b, k       SREG[b] = 0       1/2      Branch if bit clear

/* Named branch mnemonics (aliases for BRBS/BRBC) */
BREQ k          Z = 1             1/2      Branch if equal
BRNE k          Z = 0             1/2      Branch if not equal
BRCS k          C = 1             1/2      Branch if carry set
BRCC k          C = 0             1/2      Branch if carry clear
BRSH k          C = 0             1/2      Branch if same or higher (unsigned ≥)
BRLO k          C = 1             1/2      Branch if lower (unsigned <)
BRMI k          N = 1             1/2      Branch if minus
BRPL k          N = 0             1/2      Branch if plus
BRGE k          S = 0             1/2      Branch if greater or equal (signed ≥)
BRLT k          S = 1             1/2      Branch if less than (signed <)
BRHS k          H = 1             1/2      Branch if half-carry set
BRHC k          H = 0             1/2      Branch if half-carry clear
BRTS k          T = 1             1/2      Branch if T set
BRTC k          T = 0             1/2      Branch if T clear
BRVS k          V = 1             1/2      Branch if overflow set
BRVC k          V = 0             1/2      Branch if overflow clear
BRIE k          I = 1             1/2      Branch if interrupt enabled
BRID k          I = 0             1/2      Branch if interrupt disabled
```

### Skip Instructions

```
Opcode          Condition              Cycles      Notes
──────────────────────────────────────────────────────────────────────────────
CPSE Rd, Rr     Rd = Rr → skip next   1/2/3       skip 1 or 2-word instruction
SBRC Rd, b      Rd[b] = 0 → skip      1/2/3
SBRS Rd, b      Rd[b] = 1 → skip      1/2/3
SBIC A, b       I/O[A][b] = 0 → skip  2/3/4       A: 0–31 only
SBIS A, b       I/O[A][b] = 1 → skip  2/3/4       A: 0–31 only
```

Skip cycle counts: 1 = no skip; 2 = skip 1-word instruction; 3 = skip 2-word
instruction (LDS, STS, CALL, JMP). `SBIC`/`SBIS` add 1 due to I/O read.

---

## Load and Store

```
Opcode          Operation                      Cycles   Notes
──────────────────────────────────────────────────────────────────────────────
MOV  Rd, Rr     Rd ← Rr                        1
MOVW Rd, Rr     Rd+1:Rd ← Rr+1:Rr             1        Rd, Rr: even registers
LDI  Rd, K      Rd ← K  (R16–R31 only)         1
LDS  Rd, k      Rd ← SRAM[k]                   2        k: 16-bit address
STS  k, Rr      SRAM[k] ← Rr                   2        k: 16-bit address

/* X register (R27:R26) indirect */
LD   Rd, X      Rd ← SRAM[X]                   2
LD   Rd, X+     Rd ← SRAM[X]; X ← X+1         2
LD   Rd, −X     X ← X−1; Rd ← SRAM[X]         2
ST   X, Rr      SRAM[X] ← Rr                   2
ST   X+, Rr     SRAM[X] ← Rr; X ← X+1         2
ST   −X, Rr     X ← X−1; SRAM[X] ← Rr         2

/* Y register (R29:R28) indirect */
LD   Rd, Y      Rd ← SRAM[Y]                   2
LD   Rd, Y+     Rd ← SRAM[Y]; Y ← Y+1         2
LD   Rd, −Y     Y ← Y−1; Rd ← SRAM[Y]         2
LDD  Rd, Y+q    Rd ← SRAM[Y+q]  q: 0–63       2
ST   Y, Rr      SRAM[Y] ← Rr                   2
ST   Y+, Rr     SRAM[Y] ← Rr; Y ← Y+1         2
ST   −Y, Rr     Y ← Y−1; SRAM[Y] ← Rr         2
STD  Y+q, Rr    SRAM[Y+q] ← Rr  q: 0–63       2

/* Z register (R31:R30) indirect */
LD   Rd, Z      Rd ← SRAM[Z]                   2
LD   Rd, Z+     Rd ← SRAM[Z]; Z ← Z+1         2
LD   Rd, −Z     Z ← Z−1; Rd ← SRAM[Z]         2
LDD  Rd, Z+q    Rd ← SRAM[Z+q]  q: 0–63       2
ST   Z, Rr      SRAM[Z] ← Rr                   2
ST   Z+, Rr     SRAM[Z] ← Rr; Z ← Z+1         2
ST   −Z, Rr     Z ← Z−1; SRAM[Z] ← Rr         2
STD  Z+q, Rr    SRAM[Z+q] ← Rr  q: 0–63       2
```

### Load from Program Memory (Flash)

```
Opcode          Operation                      Cycles   Notes
──────────────────────────────────────────────────────────────────────────────
LPM             R0 ← FLASH[Z]                  3        Z = byte address
LPM  Rd, Z      Rd ← FLASH[Z]                  3
LPM  Rd, Z+     Rd ← FLASH[Z]; Z ← Z+1        3
ELPM            R0 ← FLASH[RAMPZ:Z]            3        >64KB flash devices
ELPM Rd, Z      Rd ← FLASH[RAMPZ:Z]            3
ELPM Rd, Z+     Rd ← FLASH[RAMPZ:Z]; Z++       3
SPM             FLASH[Z] ← R1:R0               varies   Boot section only
```

---

## I/O Instructions

```
Opcode          Operation                      Cycles   Notes
──────────────────────────────────────────────────────────────────────────────
IN   Rd, A      Rd ← I/O[A]                    1        A: 0–63
OUT  A, Rr      I/O[A] ← Rr                    1        A: 0–63
PUSH Rr         SRAM[SP] ← Rr; SP ← SP−1       2
POP  Rd         SP ← SP+1; Rd ← SRAM[SP]       2
```

---

## Miscellaneous

```
Opcode          Operation                      Cycles   Notes
──────────────────────────────────────────────────────────────────────────────
NOP             No operation                   1
SLEEP           Enter sleep mode               1        MCU-defined behaviour
WDR             Reset watchdog timer           1
BREAK           Stop for on-chip debug system  1
```

---

## Instruction Encoding Summary

Most AVR instructions are 16-bit (one word). 32-bit instructions:

```
32-bit instructions (2 words):
  LDS Rd, k    — word 1: opcode+Rd; word 2: 16-bit address k
  STS k, Rr    — word 1: opcode+Rr; word 2: 16-bit address k
  CALL k       — word 1: 0x940E+kH; word 2: kL (22-bit address)
  JMP  k       — word 1: 0x940C+kH; word 2: kL (22-bit address)
```

All other instructions are 16-bit. The assembler handles encoding automatically.

---

## GCC ABI Register Conventions

```
Registers     Role                     Save by
──────────────────────────────────────────────────────────────────────
R0            Temporary, MUL result    Caller (assume destroyed)
R1            Always zero (GCC)        Callee must restore if modified
R2–R17        Call-saved               Callee (push/pop if used)
R18–R27       Call-clobbered           Caller (assume destroyed)
R28–R29 (Y)   Frame pointer            Callee
R30–R31 (Z)   Call-clobbered           Caller

Return values:
  8-bit:  R24
  16-bit: R25:R24
  32-bit: R25:R24:R23:R22 (little-endian: R22=lowest byte)

Arguments (first to last):
  arg1: R25:R24  (or R24 for 8-bit)
  arg2: R23:R22
  arg3: R21:R20
  arg4: R19:R18
  More: pushed on stack (rightmost first)
```

After `MUL`/`MULS`/`MULSU`: always restore `R1 = 0` before returning or
calling any C function. `R0` is implicitly scratch.
