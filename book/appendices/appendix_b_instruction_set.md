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
