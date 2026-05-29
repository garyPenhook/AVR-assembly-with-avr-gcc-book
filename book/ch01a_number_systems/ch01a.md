# Number Systems: Binary, Hexadecimal, Decimal, and BCD

Assembly programming is arithmetic all the way down. Every register holds a
number, every address is a number, every instruction is a number stored in
flash. Before writing a single instruction you need to be comfortable reading
and writing values in all three bases the toolchain uses: decimal (the human
default), binary (the hardware's native form), and hexadecimal (the programmer's
shorthand for binary). Binary Coded Decimal (BCD) rounds out the chapter as a
representation that bridges numeric computation and human-readable output.

This chapter builds each number system from first principles, shows the
conversions between them, and then explains where each one appears in AVR
assembly source and in real hardware like RTCs and display drivers.

---

## Decimal: The System You Already Know

Decimal is base 10: ten distinct symbols (0 through 9) and positional notation
where each position to the left is worth ten times more than the position to
its right.

```
 1  3  7  4
 │  │  │  └── ones     = 4 × 10⁰ = 4 × 1        =     4
 │  │  └───── tens     = 7 × 10¹ = 7 × 10       =    70
 │  └───────── hundreds = 3 × 10² = 3 × 100      =   300
 └────────────  thousands = 1 × 10³ = 1 × 1000   =  1000

Total: 1374
```

The base-10 system is natural for humans because we have ten fingers. It is not
natural for computers. Electronic logic has two stable states (on and off, high
and low, charged and uncharged), which maps cleanly to base 2, not base 10.
Everything a computer stores or computes is ultimately binary; decimal is a
presentation layer applied at the user interface.

---

## Binary: The CPU's Native Language

Binary is base 2. Only two symbols exist: 0 and 1. Each position is worth
twice the position to its right.

```
 1  0  1  1  0  1  1  0
 │  │  │  │  │  │  │  └── 2⁰ = 1    × 0 =   0
 │  │  │  │  │  │  └───── 2¹ = 2    × 1 =   2
 │  │  │  │  │  └───────── 2² = 4    × 1 =   4
 │  │  │  │  └──────────── 2³ = 8    × 0 =   0
 │  │  │  └─────────────── 2⁴ = 16   × 1 =  16
 │  │  └──────────────────  2⁵ = 32   × 1 =  32
 │  └──────────────────────  2⁶ = 64   × 0 =   0
 └─────────────────────────  2⁷ = 128  × 1 = 128

Total: 128 + 32 + 16 + 4 + 2 = 182
```

The bit pattern `10110110` equals 182 in decimal.

### Counting in Binary

Counting up in binary follows the same carry rule as decimal — when a digit
reaches its maximum (1 in binary, 9 in decimal) it rolls back to 0 and
carries 1 into the next position:

```
Decimal   Binary
───────   ──────────
    0     0000 0000
    1     0000 0001
    2     0000 0010
    3     0000 0011
    4     0000 0100
    5     0000 0101
    6     0000 0110
    7     0000 0111
    8     0000 1000
    9     0000 1001
   10     0000 1010
   11     0000 1011
   12     0000 1100
   ...
  127     0111 1111
  128     1000 0000
  ...
  254     1111 1110
  255     1111 1111
```

255 is the largest value in 8 bits; all bits are 1. The next count would be
256, which requires 9 bits: `1 0000 0000`. In an 8-bit register, adding 1 to
255 wraps back to 0; an `ADD`, `ADC`, `ADIW`, or `SUBI` that does this also
sets the carry flag. (The dedicated `INC` instruction wraps 255→0 too, but on
AVR it does *not* affect the carry flag — only the Z, N, V, and S flags.)

### Bit Terminology

Individual binary digits have specific names:

```
Term      Size        Values         Notes
────────  ──────────  ─────────────  ─────────────────────────────────────
Bit       1 bit       0 or 1         The atomic unit of binary storage
Nibble    4 bits      0–15           Half a byte; maps to one hex digit
Byte      8 bits      0–255          The basic unit of AVR register storage
Word      2 bytes     0–65535        16-bit; used for addresses, counters
Long      4 bytes     0–4294967295   32-bit; used for timestamps, CRCs
```

Within a byte, bits are numbered from 0 (the rightmost, least-significant) to
7 (the leftmost, most-significant):

```
Bit positions in a byte:
  ┌────┬────┬────┬────┬────┬────┬────┬────┐
  │ b7 │ b6 │ b5 │ b4 │ b3 │ b2 │ b1 │ b0 │
  └────┴────┴────┴────┴────┴────┴────┴────┘
     MSB                               LSB

MSB = Most Significant Bit  (bit 7 in an 8-bit byte)
LSB = Least Significant Bit (bit 0 in an 8-bit byte)
```

Bit 7 is the **sign bit** under signed (two's complement) interpretation:
if bit 7 is 1, the value is negative. This is explored in depth in Chapter 8
(Signed Arithmetic).

### Converting Binary to Decimal

Sum the place values wherever a 1 appears:

```
Binary:    1 1 0 1 0 0 1 1
           │ │ │ │ │ │ │ └ 2⁰ =   1
           │ │ │ │ │ │ └── 2¹ =   2
           │ │ │ │ │ └──── (0)
           │ │ │ │ └────── (0)
           │ │ │ └──────── 2⁴ =  16
           │ │ └────────── (0)
           │ └──────────── 2⁶ =  64
           └────────────── 2⁷ = 128

Sum: 128 + 64 + 16 + 2 + 1 = 211
```

### Converting Decimal to Binary (Repeated Division)

Divide repeatedly by 2, collecting remainders from bottom to top:

```
Convert 211 to binary:

211 ÷ 2 = 105  remainder 1   ← LSB (bit 0)
105 ÷ 2 =  52  remainder 1
 52 ÷ 2 =  26  remainder 0
 26 ÷ 2 =  13  remainder 0
 13 ÷ 2 =   6  remainder 1
  6 ÷ 2 =   3  remainder 0
  3 ÷ 2 =   1  remainder 1
  1 ÷ 2 =   0  remainder 1   ← MSB (bit 7)

Read remainders from bottom to top: 1 1 0 1 0 0 1 1 = 0b11010011 = 211  ✓
```

### Powers of Two You Must Know

These values appear constantly in AVR programming:

```
2⁰  =      1       2⁸  =    256
2¹  =      2       2⁹  =    512
2²  =      4       2¹⁰ =  1,024   (1 K)
2³  =      8       2¹¹ =  2,048   (2 K)
2⁴  =     16       2¹² =  4,096   (4 K)
2⁵  =     32       2¹³ =  8,192   (8 K)
2⁶  =     64       2¹⁴ = 16,384  (16 K)
2⁷  =    128       2¹⁵ = 32,768  (32 K)
```

The ATtiny3217 has 32 KB = 32,768 bytes of flash (= 2¹⁵), 2 KB = 2,048 bytes
of SRAM (= 2¹¹), and 256 bytes of EEPROM (= 2⁸). These sizes map directly to
bit widths: a 15-bit index spans all of flash, and an 11-bit index spans all of
SRAM. (The *absolute* data-space addresses are larger — SRAM is mapped at
0x3800–0x3FFF, so a real SRAM address needs 14 bits — but the size of each
region is set by these powers of two.)

### Binary Notation in GAS Source

The GNU Assembler accepts a `0b` prefix for binary literals:

```asm
ldi  r16, 0b10110110    ; r16 = 182 (same as ldi r16, 182 or ldi r16, 0xB6)
ldi  r17, 0b00001111    ; r17 = 15 — lower nibble set, upper nibble clear
ldi  r18, 0b11110000    ; r18 = 240 — upper nibble set, lower nibble clear
```

Binary literals are most useful when the bit pattern itself is the point:
configuring peripheral registers where individual bits have named meanings,
setting up masks, or building values for bitwise operations.

---

## Hexadecimal: Compact Binary Notation

Hexadecimal (base 16) is not a different way of thinking about numbers — it is
a compact shorthand for binary. Each hex digit represents exactly four binary
bits (one nibble). Two hex digits represent one byte. This one-to-one
correspondence between hex digits and nibbles is why programmers use hex
constantly and decimal rarely when dealing with binary hardware.

### Hexadecimal Digits

Base 16 needs 16 distinct symbols. The digits 0–9 provide ten, and the letters
A–F (or a–f) provide six more:

```
Hex digit    Decimal    Binary
─────────    ───────    ──────
    0            0      0000
    1            1      0001
    2            2      0010
    3            3      0011
    4            4      0100
    5            5      0101
    6            6      0110
    7            7      0111
    8            8      1000
    9            9      1001
    A           10      1010
    B           11      1011
    C           12      1100
    D           13      1101
    E           14      1110
    F           15      1111
```

This table is worth memorising. After a few weeks of assembly programming you
will read hex digits as their 4-bit patterns automatically.

### Converting Hex ↔ Binary (The Fundamental Operation)

Split the byte into two nibbles and convert each nibble independently:

```
0xB6 → B = 1011,  6 = 0110 → 0b10110110

0xA0 → A = 1010,  0 = 0000 → 0b10100000

0x3F → 3 = 0011,  F = 1111 → 0b00111111
```

The reverse:

```
0b11001010 → split: 1100 | 1010 → C | A → 0xCA

0b00010111 → split: 0001 | 0111 → 1 | 7 → 0x17

0b11111111 → split: 1111 | 1111 → F | F → 0xFF
```

This conversion is instantaneous once you know the 16-entry table. No
arithmetic required. This is why embedded programmers write register values
in hex instead of decimal: `0b10110010` and `0xB2` convey the same information,
but `0xB2` is faster to write and the nibble structure is immediately visible.

### Converting Hex ↔ Decimal

For a two-digit hex value `0xHiLo`:

```
decimal value = (Hi × 16) + Lo
```

Examples:

```
0xB6:  (11 × 16) + 6  = 176 + 6  = 182
0x3F:  ( 3 × 16) + 15 =  48 + 15 =  63
0xFF:  (15 × 16) + 15 = 240 + 15 = 255
0x80:  ( 8 × 16) + 0  = 128 + 0  = 128
0x10:  ( 1 × 16) + 0  =  16 + 0  =   16
0x01:  ( 0 × 16) + 1  =   0 + 1  =    1
```

For a four-digit hex value `0xB3B2B1B0`:

```
decimal = (B3 × 16³) + (B2 × 16²) + (B1 × 16) + B0
        = (B3 × 4096) + (B2 × 256) + (B1 × 16) + B0
```

In practice you rarely convert large hex values to decimal by hand — you use a
calculator or let the assembler do it. What matters is the hex↔binary
correspondence.

### Converting Decimal to Hex (Repeated Division by 16)

```
Convert 211 to hex:

211 ÷ 16 = 13  remainder 3   ← low digit (0x_3)
 13 ÷ 16 =  0  remainder 13  ← high digit (0xD_)

Result: 0xD3

Verify: (13 × 16) + 3 = 208 + 3 = 211  ✓
```

Or convert binary to hex as the two-step shortcut: binary → hex is simpler
than binary → decimal because the nibble grouping aligns perfectly.

### Hex Notation in AVR Assembly and C

GAS and avr-gcc both accept `0x` prefix:

```asm
ldi  r16, 0xFF          ; r16 = 255 (all bits set)
ldi  r17, 0x80          ; r17 = 128 (bit 7 set, all others clear)
ldi  r18, 0x0F          ; r18 = 15  (lower nibble set)
ldi  r19, 0xF0          ; r19 = 240 (upper nibble set)
```

In AVR register and peripheral documentation, values are always given in hex.
The SRAM address space starts at `0x3800` on the ATtiny3217; the stack pointer
register SPL is at I/O address `0x3D`; the PORTB output register is at
`0x0424` (PORTB base `0x0420` plus the `OUT` offset `0x04`). These addresses
only make visual sense in hex.

---

## The Complete 8-bit Map

The following table shows decimal, hexadecimal, and binary side by side for
every value from 0 to 255. Scan it a few times; the patterns become clear.

```
Dec   Hex   Binary      Dec   Hex   Binary      Dec   Hex   Binary
───   ───   ────────    ───   ───   ────────    ───   ───   ────────
  0   00    0000 0000    86   56    0101 0110   171   AB    1010 1011
  1   01    0000 0001    87   57    0101 0111   172   AC    1010 1100
  2   02    0000 0010    88   58    0101 1000   173   AD    1010 1101
  3   03    0000 0011    89   59    0101 1001   174   AE    1010 1110
  4   04    0000 0100    90   5A    0101 1010   175   AF    1010 1111
  5   05    0000 0101    91   5B    0101 1011   176   B0    1011 0000
  6   06    0000 0110    92   5C    0101 1100   177   B1    1011 0001
  7   07    0000 0111    93   5D    0101 1101   178   B2    1011 0010
  8   08    0000 1000    94   5E    0101 1110   179   B3    1011 0011
  9   09    0000 1001    95   5F    0101 1111   180   B4    1011 0100
 10   0A    0000 1010    96   60    0110 0000   181   B5    1011 0101
 11   0B    0000 1011    97   61    0110 0001   182   B6    1011 0110
 12   0C    0000 1100    98   62    0110 0010   183   B7    1011 0111
 13   0D    0000 1101    99   63    0110 0011   184   B8    1011 1000
 14   0E    0000 1110   100   64    0110 0100   185   B9    1011 1001
 15   0F    0000 1111   101   65    0110 0101   186   BA    1011 1010
 16   10    0001 0000   102   66    0110 0110   187   BB    1011 1011
 17   11    0001 0001   103   67    0110 0111   188   BC    1011 1100
 18   12    0001 0010   104   68    0110 1000   189   BD    1011 1101
 19   13    0001 0011   105   69    0110 1001   190   BE    1011 1110
 20   14    0001 0100   106   6A    0110 1010   191   BF    1011 1111
 21   15    0001 0101   107   6B    0110 1011   192   C0    1100 0000
 22   16    0001 0110   108   6C    0110 1100   193   C1    1100 0001
 23   17    0001 0111   109   6D    0110 1101   194   C2    1100 0010
 24   18    0001 1000   110   6E    0110 1110   195   C3    1100 0011
 25   19    0001 1001   111   6F    0110 1111   196   C4    1100 0100
 26   1A    0001 1010   112   70    0111 0000   197   C5    1100 0101
 27   1B    0001 1011   113   71    0111 0001   198   C6    1100 0110
 28   1C    0001 1100   114   72    0111 0010   199   C7    1100 0111
 29   1D    0001 1101   115   73    0111 0011   200   C8    1100 1000
 30   1E    0001 1110   116   74    0111 0100   201   C9    1100 1001
 31   1F    0001 1111   117   75    0111 0101   202   CA    1100 1010
 32   20    0010 0000   118   76    0111 0110   203   CB    1100 1011
 33   21    0010 0001   119   77    0111 0111   204   CC    1100 1100
 34   22    0010 0010   120   78    0111 1000   205   CD    1100 1101
 35   23    0010 0011   121   79    0111 1001   206   CE    1100 1110
 36   24    0010 0100   122   7A    0111 1010   207   CF    1100 1111
 37   25    0010 0101   123   7B    0111 1011   208   D0    1101 0000
 38   26    0010 0110   124   7C    0111 1100   209   D1    1101 0001
 39   27    0010 0111   125   7D    0111 1101   210   D2    1101 0010
 40   28    0010 1000   126   7E    0111 1110   211   D3    1101 0011
 41   29    0010 1001   127   7F    0111 1111   212   D4    1101 0100
 42   2A    0010 1010   128   80    1000 0000   213   D5    1101 0101
 43   2B    0010 1011   129   81    1000 0001   214   D6    1101 0110
 44   2C    0010 1100   130   82    1000 0010   215   D7    1101 0111
 45   2D    0010 1101   131   83    1000 0011   216   D8    1101 1000
 46   2E    0010 1110   132   84    1000 0100   217   D9    1101 1001
 47   2F    0010 1111   133   85    1000 0101   218   DA    1101 1010
 48   30    0011 0000   134   86    1000 0110   219   DB    1101 1011
 49   31    0011 0001   135   87    1000 0111   220   DC    1101 1100
 50   32    0011 0010   136   88    1000 1000   221   DD    1101 1101
 51   33    0011 0011   137   89    1000 1001   222   DE    1101 1110
 52   34    0011 0100   138   8A    1000 1010   223   DF    1101 1111
 53   35    0011 0101   139   8B    1000 1011   224   E0    1110 0000
 54   36    0011 0110   140   8C    1000 1100   225   E1    1110 0001
 55   37    0011 0111   141   8D    1000 1101   226   E2    1110 0010
 56   38    0011 1000   142   8E    1000 1110   227   E3    1110 0011
 57   39    0011 1001   143   8F    1000 1111   228   E4    1110 0100
 58   3A    0011 1010   144   90    1001 0000   229   E5    1110 0101
 59   3B    0011 1011   145   91    1001 0001   230   E6    1110 0110
 60   3C    0011 1100   146   92    1001 0010   231   E7    1110 0111
 61   3D    0011 1101   147   93    1001 0011   232   E8    1110 1000
 62   3E    0011 1110   148   94    1001 0100   233   E9    1110 1001
 63   3F    0011 1111   149   95    1001 0101   234   EA    1110 1010
 64   40    0100 0000   150   96    1001 0110   235   EB    1110 1011
 65   41    0100 0001   151   97    1001 0111   236   EC    1110 1100
 66   42    0100 0010   152   98    1001 1000   237   ED    1110 1101
 67   43    0100 0011   153   99    1001 1001   238   EE    1110 1110
 68   44    0100 0100   154   9A    1001 1010   239   EF    1110 1111
 69   45    0100 0101   155   9B    1001 1011   240   F0    1111 0000
 70   46    0100 0110   156   9C    1001 1100   241   F1    1111 0001
 71   47    0100 0111   157   9D    1001 1101   242   F2    1111 0010
 72   48    0100 1000   158   9E    1001 1110   243   F3    1111 0011
 73   49    0100 1001   159   9F    1001 1111   244   F4    1111 0100
 74   4A    0100 1010   160   A0    1010 0000   245   F5    1111 0101
 75   4B    0100 1011   161   A1    1010 0001   246   F6    1111 0110
 76   4C    0100 1100   162   A2    1010 0010   247   F7    1111 0111
 77   4D    0100 1101   163   A3    1010 0011   248   F8    1111 1000
 78   4E    0100 1110   164   A4    1010 0100   249   F9    1111 1001
 79   4F    0100 1111   165   A5    1010 0101   250   FA    1111 1010
 80   50    0101 0000   166   A6    1010 0110   251   FB    1111 1011
 81   51    0101 0001   167   A7    1010 0111   252   FC    1111 1100
 82   52    0101 0010   168   A8    1010 1000   253   FD    1111 1101
 83   53    0101 0011   169   A9    1010 1001   254   FE    1111 1110
 84   54    0101 0100   170   AA    1010 1010   255   FF    1111 1111
 85   55    0101 0101
```

A few patterns worth noting:

- **0x80 = 128 = 1000 0000**: the boundary between signed-negative and
  signed-non-negative. Bit 7 is the only bit set.
- **0xFF = 255 = 1111 1111**: all bits set. `SER Rd` loads this value.
- **0x0F = 15  = 0000 1111**: lower nibble mask.
- **0xF0 = 240 = 1111 0000**: upper nibble mask.
- **0xAA = 170 = 1010 1010** and **0x55 = 85 = 0101 0101**: alternating
  bit patterns used for hardware stress tests.

---

## Little-Endian Byte Order

When a value wider than 8 bits lives in AVR SRAM, the bytes are stored in
**little-endian** order: the byte at the lowest address holds the
least-significant byte (low byte), and each successive address holds the next
more significant byte.

For the 16-bit value 0x1A2B stored at address 0x0200:

```
Address    Content
0x0200     0x2B   (low byte, least significant)
0x0201     0x1A   (high byte, most significant)
```

For the 32-bit value 0xDEADBEEF stored at address 0x0200:

```
Address    Content
0x0200     0xEF   (byte 0 — least significant)
0x0201     0xBE   (byte 1)
0x0202     0xAD   (byte 2)
0x0203     0xDE   (byte 3 — most significant)
```

Little-endian means "the little end (least significant byte) goes first
(at the lowest address)." The GCC AVR compiler, the assembler's `.word` and
`.long` directives, and the `LDS`/`STS` load-store instructions all follow
this convention. Register pairs in assembly code are written high:low
(e.g., `r25:r24`), but in memory the low register lives at the lower address.

---

## Number Representation in GAS Assembly Source

GAS accepts the same number in any of the three bases. These three lines are
identical:

```asm
ldi  r16, 182           ; decimal
ldi  r16, 0b10110110    ; binary
ldi  r16, 0xB6          ; hex
```

GAS also accepts character literals using single quotes:

```asm
ldi  r16, 'A'           ; r16 = 65 (ASCII code for 'A')
ldi  r17, '\n'          ; r17 = 10 (ASCII newline)
ldi  r18, '0'           ; r18 = 48 (ASCII digit zero)
```

Character literals are especially useful when building USART output code and
working with ASCII display buffers.

### Assembler Arithmetic

GAS evaluates constant expressions at assembly time, including mixed-base
expressions:

```asm
ldi  r16, (0xFF & ~0x0F)    ; r16 = 0xF0 = 240 (upper nibble mask)
ldi  r17, (1 << 5)          ; r17 = 0x20 = 32  (bit 5 set)
ldi  r18, (0x0F | 0x30)     ; r18 = 0x3F = 63
```

Using expressions like `(1 << 5)` instead of a raw constant makes the intent
clear: "bit 5 should be set."

### Data Directives and Byte Order

```asm
.section .data

byte_val:    .byte  0xAB              ; 1 byte: 0xAB
word_val:    .word  0x1234            ; 2 bytes at consecutive addresses:
                                      ;   [addr+0] = 0x34, [addr+1] = 0x12 (little-endian)
long_val:    .long  0xDEADBEEF        ; 4 bytes:
                                      ;   [addr+0]=0xEF, [+1]=0xBE, [+2]=0xAD, [+3]=0xDE
```

The `.word` and `.long` directives store values in little-endian order,
matching the `LDS`/`STS` byte order the CPU expects.

---

## BCD: Binary Coded Decimal

BCD is a representation system that bridges the gap between binary hardware
and decimal human output. Instead of storing a number in pure binary (using all
possible bit patterns), BCD reserves exactly 4 bits for each decimal digit.
Each nibble encodes one decimal digit from 0 to 9. The values 0xA through 0xF
(10–15 in a nibble) are unused — they are illegal BCD digits.

BCD exists because some applications need decimal arithmetic directly: clocks
and calendars (where hours are 00–23, minutes 00–59), postal codes, currency
amounts, and any case where numbers must be displayed without a binary-to-decimal
conversion step.

### Packed BCD

Packed BCD stores two decimal digits in one byte: the high nibble holds the
tens digit, the low nibble holds the units digit.

```
Decimal   Packed BCD   Binary
───────   ──────────   ─────────
  0         0x00       0000 0000
  1         0x01       0000 0001
  9         0x09       0000 1001
 10         0x10       0001 0000
 15         0x15       0001 0101
 42         0x42       0100 0010
 59         0x59       0101 1001
 99         0x99       1001 1001
```

The range of valid packed BCD values in one byte is 0x00–0x99, representing
decimal 0–99. This uses 100 of the 256 possible bit patterns — 156 patterns
are wasted. The advantage is that converting to a decimal display requires only
extracting nibbles, not dividing by 10.

**Packed BCD is the format used by virtually all hardware real-time clocks**,
including the DS1307 and PCF8523 that appear in many AVR designs. Hours,
minutes, and seconds are each stored as packed BCD bytes.

Reading a DS1307:

```
Register value: 0x47
High nibble: 4 → tens digit = 4
Low nibble:  7 → units digit = 7
Decoded:     47 minutes
```

### Unpacked BCD

Unpacked BCD stores one decimal digit per byte in the low nibble (high nibble
is zero):

```
Decimal digit   Unpacked BCD
─────────────   ────────────
      0             0x00
      1             0x01
      5             0x05
      9             0x09
```

Unpacked BCD is less memory-efficient but simpler to manipulate. It is also
closely related to **ASCII digit encoding**: the ASCII codes for '0' through
'9' are 0x30 through 0x39. ASCII digit = unpacked BCD digit + 0x30. This
makes ASCII digit output trivial:

```asm
; Convert a single decimal digit (0–9) in r16 to its ASCII character
ldi  r17, '0'           ; r17 = 0x30
add  r16, r17           ; r16 = 0x30 + digit  (ASCII '0'–'9')
```

And the reverse:

```asm
; Convert ASCII '0'–'9' in r16 to the digit value 0–9
subi r16, '0'           ; r16 -= 0x30  (subtract ASCII '0')
; r16 is now 0–9
```

### BCD Addition on AVR

Adding two packed BCD values with a standard `ADD` instruction produces a
binary sum, which may not be a valid BCD value:

```
  0x29 (= 29 BCD)
+ 0x38 (= 38 BCD)
──────
  0x61 (= 97 decimal in binary)

But 29 + 38 = 67, not 97. The binary add gave 0x61 = 0110 0001, but the
correct BCD result is 0x67 = 0110 0111.
```

The binary add is wrong whenever a nibble sum exceeds 9, because a decimal
digit cannot exceed 9. When a nibble overflows past 9, it enters the illegal
BCD range 0xA–0xF, and the tens carry does not propagate to the next nibble.

The fix is to add 6 to any nibble whose binary sum exceeded 9 or generated a
carry. This is called **BCD correction** or **decimal adjustment**.

Many processor families (x86, Z80, 6502) have a hardware `DAA` (Decimal Adjust
Accumulation) instruction that performs this correction automatically. **The
AVR does not have a DAA instruction.** BCD correction must be done in software.

The correction rules, applied after an `ADD` or `ADC`:

```
For the LOW nibble (units digit):
  If (low nibble of result > 9) OR (H flag = 1):
    add 0x06 to the result

For the HIGH nibble (tens digit):
  If (high nibble of result > 9) OR (C flag = 1):
    add 0x60 to the result
```

The H flag (half-carry, carry out of bit 3 into bit 4) records whether the
low nibble overflowed during the binary add — exactly the condition that
requires a low-nibble correction.

#### BCD Addition Subroutine

```asm
/*
 * bcd_add — add two packed BCD bytes
 *   Input:  r16 = BCD addend A (0x00–0x99)
 *           r17 = BCD addend B (0x00–0x99)
 *   Output: r16 = BCD sum (0x00–0x99)
 *           C=1 if sum >= 100 (decimal carry out of tens digit)
 *   Clobbers: r18, r19
 *
 * The binary add's carry and half-carry drive the corrections, but the
 * low-nibble fix would clobber them — so we snapshot the carry into r19
 * straight away, read H (still valid) for the low-nibble test, and use real
 * ADDs for the corrections so their carry-out stays meaningful.
 */
bcd_add:
    add  r16, r17           ; binary add: result may not be valid BCD
    clr  r19                ; r19 = pending tens carry-out (0 or 1)
    brcc bcd_add_lowchk     ; did the binary add overflow the byte?
    inc  r19                ;   yes → carry out of the tens digit
bcd_add_lowchk:
    ; ── Low nibble correction: +6 if H=1 (half-carry) or low nibble > 9 ──
    brhs bcd_add_lowfix     ; H=1: low nibble carried out of bit 3
    mov  r18, r16
    andi r18, 0x0F          ; isolate low nibble
    cpi  r18, 0x0A
    brlo bcd_add_lowok      ; low nibble <= 9: no correction needed
bcd_add_lowfix:
    ldi  r18, 0x06
    add  r16, r18           ; r16 += 6 via real ADD → C is a true byte carry
    brcc bcd_add_lowok
    ldi  r19, 1             ; the +6 overflowed the byte → tens carry-out
bcd_add_lowok:
    ; ── High nibble correction: +0x60 if a carry is pending or high > 9 ──
    tst  r19
    brne bcd_add_highfix    ; carry pending → tens digit must wrap
    mov  r18, r16
    andi r18, 0xF0          ; isolate high nibble
    cpi  r18, 0xA0          ; high nibble > 9? (0xA0 = 10 in high-nibble position)
    brlo bcd_add_done
bcd_add_highfix:
    ldi  r18, 0x60
    add  r16, r18           ; r16 += 0x60
    ldi  r19, 1             ; sum >= 100 → decimal carry out
bcd_add_done:
    lsr  r19                ; move tens carry-out (bit 0) into the C flag
    ret
```

**Worked trace: 0x29 + 0x38**

```
ADD r16(0x29), r17(0x38):
  0x29 + 0x38 = 0x61
  Low nibble: 9 + 8 = 17 = 0x11 → bit 3 carry → H=1
  High nibble: 2 + 3 + 1(H) = 6, no carry → C=0

Low nibble correction: H=1 → add 6
  0x61 + 0x06 = 0x67
  Low nibble: 1 + 6 = 7 → 0x67 (valid BCD: '7')
  No carry generated from low correction

High nibble correction: C=0; high nibble of 0x67 = 0x60 = 6 → 6 <= 9: no correction

Result: 0x67 = BCD 67 = decimal 67  ✓  (29 + 38 = 67)
```

**Worked trace: 0x75 + 0x48 (= 75 + 48 = 123, BCD overflow)**

```
ADD r16(0x75), r17(0x48):
  0x75 + 0x48 = 0xBD
  Low nibble: 5 + 8 = 13 = 0xD → no carry out of bit 3, so H=0 (13 < 16)
  High nibble: 7 + 4 = 11 = 0xB → C=0 (no overflow out of the byte)

Low correction: H=0, but low nibble 0xD > 9 → add 6
  0xBD + 0x06 = 0xC3
  (no carry out of the byte from the +6; the tens carry stays 0)

High correction: no carry pending, but high nibble 0xC > 9 → add 0x60
  0xC3 + 0x60 = 0x123 → byte portion = 0x23, C=1

Result: 0x23 with C=1
Decoded: BCD 23 with decimal carry → 123  ✓  (75 + 48 = 123)
```

### BCD Subtraction on AVR

BCD subtraction requires the same type of correction in the opposite direction.
After a binary `SUB`, correct any nibble whose result required a borrow by
subtracting 6:

```asm
/*
 * bcd_sub — subtract packed BCD (r16 - r17)
 *   Input:  r16 = minuend (0x00–0x99)
 *           r17 = subtrahend (0x00–0x99)
 *   Output: r16 = BCD difference (0x00–0x99)
 *           C=1 if borrow (r16 < r17); the result is then the ten's-complement
 *           BCD form, i.e. 100 - (r17 - r16)
 *   Clobbers: r18, r19
 *
 * As with bcd_add, the binary subtract's borrow (C) is needed for the
 * tens-digit correction but would be clobbered by the low-nibble fix, so we
 * snapshot it into r19 first and use a real SUB for the correction.
 */
bcd_sub:
    sub  r16, r17           ; binary subtract; H = half-borrow, C = byte borrow
    clr  r19                ; r19 = pending borrow-out (0 or 1)
    brcc bcd_sub_lowchk     ; did the subtract borrow out of the byte?
    inc  r19                ;   yes → result is negative
bcd_sub_lowchk:
    ; Low nibble correction: if H=1 (half-borrow), subtract 6
    brhc bcd_sub_lowok      ; H=0: low nibble did not borrow
    ldi  r18, 0x06
    sub  r16, r18           ; r16 -= 6 via real SUB → C is a true byte borrow
    brcc bcd_sub_lowok
    ldi  r19, 1             ; the -6 borrowed past the byte
bcd_sub_lowok:
    ; High nibble correction: if a borrow is pending, subtract 0x60
    tst  r19
    breq bcd_sub_done
    ldi  r18, 0x60
    sub  r16, r18           ; r16 -= 0x60 (forms the ten's-complement BCD)
bcd_sub_done:
    lsr  r19                ; move borrow-out (bit 0) into the C flag
    ret
```

**Worked trace: 0x73 − 0x28 (= 73 − 28 = 45)**

```
SUB r16(0x73), r17(0x28):
  0x73 - 0x28 = 0x4B
  Low nibble: 3 - 8 = -5 → borrow from high → H=1, low result = 3 - 8 + 16 = 11 = 0xB
  High nibble: 7 - 2 - 1(borrow) = 4 → C=0

Low correction: H=1 → subtract 6
  0x4B - 0x06 = 0x45

High correction: no borrow pending → no correction

Result: 0x45 = BCD 45  ✓  (73 - 28 = 45)
```

### Converting Binary to Packed BCD

A binary value in the range 0–255 encodes as at most three BCD digits.
The standard algorithm is **double-dabble** (also called shift-add-3): it
processes the binary input one bit at a time and adjusts the BCD accumulator
after each shift.

The rule: before shifting each binary bit into the BCD accumulator, add 3 to
any BCD nibble that is >= 5. (This pre-compensates for the value-6 adjustment
that would be needed after the shift overflows a nibble past 9.)

```
Double-dabble for 8-bit input → up to 3 BCD digits (packed into 12 bits):

Registers:
  r18 = hundreds digit (bits 11:8 of BCD accumulator — only low nibble used)
  r17 = tens and units digits (high nibble = tens, low nibble = units)
  r16 = binary input (shifted out MSB first)
```

```asm
/*
 * bin8_to_bcd — convert 8-bit binary to 3 packed BCD digits
 *   Input:  r16 = binary value (0–255)
 *   Output: r18 = hundreds digit (0–2, in low nibble)
 *           r17 = packed BCD: high nibble = tens, low nibble = units
 *   Clobbers: r19, r20
 */
bin8_to_bcd:
    clr  r17                ; clear BCD accumulator (tens:units)
    clr  r18                ; clear hundreds digit

    ldi  r20, 8             ; process 8 bits

bin_bcd_loop:
    ; ── add-3 if any nibble >= 5 (pre-shift correction) ────────────────
    ; Check units nibble
    mov  r19, r17
    andi r19, 0x0F
    cpi  r19, 5
    brlo bin_bcd_skip_units
    subi r17, -3            ; units nibble += 3
bin_bcd_skip_units:

    ; Check tens nibble
    mov  r19, r17
    andi r19, 0xF0
    cpi  r19, 0x50          ; tens >= 5 → high nibble >= 5
    brlo bin_bcd_skip_tens
    subi r17, -0x30         ; tens nibble += 3
bin_bcd_skip_tens:

    ; Check hundreds nibble (in r18, low nibble)
    mov  r19, r18
    andi r19, 0x0F
    cpi  r19, 5
    brlo bin_bcd_skip_hunds
    subi r18, -3            ; hundreds nibble += 3
bin_bcd_skip_hunds:

    ; ── shift MSB of r16 into LSB of BCD accumulator ────────────────────
    lsl  r16                ; MSB of r16 → C
    rol  r17                ; C → LSB of r17 (units nibble ← MSB of binary)
    rol  r18                ; carry from r17 → r18

    dec  r20
    brne bin_bcd_loop

    ret
```

**Trace: binary 137 (0x89) → should give hundreds=1, tens=3, units=7 → 0x37 in r17, 0x01 in r18**

Each iteration does two things, in order:

1. **Add-3 correction** — for any BCD nibble (units, tens, hundreds) that
   is currently ≥ 5, add 3 to that nibble.
2. **Shift left by one** — the MSB of `r16` shifts out into C; `r17` and
   then `r18` shift left, with C feeding into the LSB of `r17`.

Starting state: `r16 = 0x89 = 1000 1001`, `r17 = 0x00`, `r18 = 0x00`.

| Iter | r16 before shift | Nibbles ≥ 5 → add-3 | r17 after add-3 | C from MSB | r17 after shift | r18 after shift |
|------|------------------|---------------------|-----------------|------------|-----------------|-----------------|
| 1 | `1000 1001` | none (all 0)                  | `0x00` | 1 | `0x01` | `0x00` |
| 2 | `0001 0010` | none (units=1, tens=0)        | `0x01` | 0 | `0x02` | `0x00` |
| 3 | `0010 0100` | none (units=2)                | `0x02` | 0 | `0x04` | `0x00` |
| 4 | `0100 1000` | none (units=4)                | `0x04` | 0 | `0x08` | `0x00` |
| 5 | `1001 0000` | units=8 → +3                  | `0x0B` | 1 | `0x17` | `0x00` |
| 6 | `0010 0000` | units=7 → +3                  | `0x1A` | 0 | `0x34` | `0x00` |
| 7 | `0100 0000` | none (units=4, tens=3)        | `0x34` | 0 | `0x68` | `0x00` |
| 8 | `1000 0000` | units=8 → +3, tens=6 → +0x30  | `0x9B` | 1 | `0x37` | `0x01` |

Two iterations are worth checking by hand:

- **Iteration 5.** Pre-shift `r17 = 0x08`. Units nibble = 8 ≥ 5, so add 3:
  `0x08 + 0x03 = 0x0B`. Now shift: the MSB of `r16 = 1001 0000` is 1, so
  `C = 1`; `ROL r17` gives `(0x0B << 1) | 1 = 0001 0111 = 0x17`.

- **Iteration 8.** Pre-shift `r17 = 0x68`. Units nibble = 8 ≥ 5, add 3 →
  `0x6B`. Tens nibble = 6 ≥ 5, add `0x30` → `0x9B`. Shift: MSB of
  `r16 = 1000 0000` is 1, so `C = 1`; `ROL r17` on `0x9B = 1001 1011`
  gives `0011 0111 = 0x37` with carry-out 1, which `ROL r18` then catches
  as `0x01`.

Final: `r18 = 0x01` (hundreds = 1), `r17 = 0x37` (tens = 3, units = 7) → 137 ✓

### Converting Packed BCD to Binary

The reverse: extract the digits and compute `(hundreds × 100) + (tens × 10) + units`.
For 8-bit values (0–99), only tens and units apply:

```asm
/*
 * bcd2_to_bin — convert 2-digit packed BCD to binary (0–99)
 *   Input:  r16 = packed BCD (0x00–0x99)
 *   Output: r16 = binary value (0–99)
 *   Clobbers: r17, r18
 */
bcd2_to_bin:
    mov  r17, r16
    andi r17, 0xF0          ; isolate high nibble (tens)
    swap r17                ; move to low nibble: r17 = tens digit (0–9)
    mov  r18, r17           ; r18 = tens
    lsl  r17                ; tens × 2
    lsl  r17                ; tens × 4
    add  r17, r18           ; tens × 5
    lsl  r17                ; tens × 10
    andi r16, 0x0F          ; isolate units nibble
    add  r16, r17           ; binary = (tens × 10) + units
    ret
```

The multiply-by-10 uses the shift-and-add trick: `N × 10 = (N << 3) + (N << 1)`.
In the code above: `(N × 4 + N) × 2 = N × 10`.

**Trace: 0x47 (BCD 47) → should give 47**

```
r17 = 0x47 & 0xF0 = 0x40 → swap → 0x04 (tens = 4)
r18 = 4
r17: 4 × 2 = 8, 8 × 2 = 16... wait, let's trace the shifts:
  r17 = 0x04
  lsl r17: 0x08 (= 4 × 2 = 8)
  lsl r17: 0x10 (= 8 × 2 = 16 = 4 × 4)
  add r17, r18: 0x10 + 0x04 = 0x14 (= 4 × 5 = 20)
  lsl r17: 0x28 (= 20 × 2 = 40 = 4 × 10)

r16 = 0x47 & 0x0F = 0x07 (units = 7)
add r16, r17: 0x07 + 0x28 = 0x2F = 47  ✓
```

For three-digit values (0–255), incorporate hundreds:

```asm
/* bcd3_to_bin — 3-digit packed BCD to binary
 *   Input:  r18 = hundreds digit (0–2, low nibble)
 *           r17 = packed tens:units (0x00–0x99)
 *   Output: r16 = binary (0–255)
 *   Clobbers: r19, r20
 */
bcd3_to_bin:
    ; Convert r17 (tens:units) to binary subtotal in r16
    mov  r20, r17
    andi r20, 0xF0
    swap r20                ; tens digit
    mov  r19, r20
    lsl  r20
    lsl  r20
    add  r20, r19           ; tens × 5
    lsl  r20                ; tens × 10

    andi r17, 0x0F          ; units digit
    add  r17, r20           ; (tens × 10) + units

    ; Add hundreds × 100
    andi r18, 0x0F          ; hundreds digit (0, 1, or 2)
    mov  r16, r18
    ldi  r19, 100
    ; multiply r16 × 100 (result fits in 8 bits since hundreds ≤ 2 → max 200)
    ; Use repeated add: r16 × 100 = r16 × 64 + r16 × 32 + r16 × 4
    mov  r20, r16
    lsl  r20                ; × 2
    lsl  r20                ; × 4
    mov  r16, r20
    lsl  r20                ; × 8
    lsl  r20                ; × 16
    lsl  r20                ; × 32
    add  r16, r20           ; × 36
    lsl  r20                ; × 64
    add  r16, r20           ; × 100

    add  r16, r17           ; add tens+units subtotal
    ret
```

### BCD and the Half-Carry Flag

The AVR's H (half-carry) flag is specifically designed to support BCD
arithmetic. It records whether a carry occurred from bit 3 to bit 4 during an
ADD, ADC, or SUB operation — in other words, whether the low nibble overflowed.
Since the low nibble holds the units digit in packed BCD, H=1 is precisely the
signal that the units digit overflowed and needs correction.

```
ADD r16, r17 where r16 = 0x08 (BCD 8), r17 = 0x08 (BCD 8):

Binary: 0x08 + 0x08 = 0x10
          the addition column by column:
          
          0000 1000
        + 0000 1000
          ─────────
          0001 0000 = 0x10
          
          Bit 3: 1 + 1 = 10 → a carry leaves bit 3 and enters bit 4,
          so the half-carry flag is set → H=1

H=1 signals: the units nibble overflowed (8 + 8 = 16). Note the low nibble of
the result is 0 — so the "low nibble > 9" test alone would miss this; the H
flag is what catches it.
→ Add 6 to correct: 0x10 + 0x06 = 0x16 = BCD 16  ✓  (8 + 8 = 16)
```

This is why H exists in the AVR status register even though most arithmetic
ignores it. Chapters that use only binary arithmetic can safely ignore H.
BCD arithmetic cannot.

---

## Choosing the Right Representation

```
Representation   When to use
───────────────  ────────────────────────────────────────────────────────────────
Decimal literal  Source code: human-facing constants, loop counts, sensor limits.
                 Use when the numeric quantity is what matters: ldi r16, 100

Binary literal   Source code: bit patterns for peripheral config, masks.
                 Use when individual bits matter: ldi r16, 0b00101101

Hex literal      Source code: addresses, register values, large constants.
                 Use when the nibble structure matters: ldi r16, 0xFF

Pure binary      CPU registers, SRAM, flash. All values are ultimately binary.

Packed BCD       RTC registers (hours, minutes, seconds), display output,
                 numeric entry keyboards, any decimal-digit computation.

Unpacked BCD     ASCII string construction, digit-by-digit output over USART.
                 Digit = ASCII - 0x30; ASCII = digit + 0x30.
```

---

## Summary

```
Decimal (base 10):
  Digits 0–9.  Place values: 1, 10, 100, 1000, ...
  Used in source code for human-legible quantities.

Binary (base 2):
  Digits 0 and 1.  Place values: 1, 2, 4, 8, 16, 32, 64, 128, ...
  Native CPU representation.  Prefix: 0b.
  Bit 0 = LSB.  Bit 7 = MSB / sign bit for 8-bit signed values.
  8-bit range: 0–255 unsigned; -128 to +127 signed (two's complement).

Hexadecimal (base 16):
  Digits 0–9 and A–F.  One hex digit = one nibble = 4 bits.
  Two hex digits = one byte.  Prefix: 0x.
  0b1010 1111 ↔ 0xAF (split at nibble boundary, look up each nibble).

Byte order (AVR SRAM):
  Little-endian: lowest address holds the least-significant byte.
  Multi-byte variables: low byte at var, high byte at var+1.

BCD — Binary Coded Decimal:
  Packed BCD: two decimal digits per byte.  High nibble = tens, low = units.
  Valid range per byte: 0x00–0x99 (decimal 0–99).
  Used in RTCs (DS1307, PCF8523), 7-segment drivers, display output.

  Unpacked BCD: one digit per byte (low nibble only).
  ASCII digit = unpacked BCD digit + 0x30.

  AVR has no DAA instruction.  BCD correction is manual:
    After ADD/ADC: if low nibble > 9 or H=1: result += 6 (units correction)
                   if high nibble > 9 or C=1: result += 0x60 (tens correction)
    After SUB: if H=1: result -= 6
               if C=1: result -= 0x60

  H flag: carry out of bit 3; signals units-digit overflow for BCD code.

Binary ↔ BCD:
  Binary → packed BCD: double-dabble (shift-add-3) algorithm.
  Packed BCD → binary: extract digits, compute (tens × 10) + units.
  For display: use unpacked BCD → add 0x30 → ASCII character per digit.
```

---

## Exercises

1. Convert the following decimal values to 8-bit binary and hexadecimal
   without using a calculator:
   - 43, 128, 200, 255, 0
   Check your work using the full 8-bit map in this chapter.

2. Convert the following hex values to binary and decimal:
   - `0x1F`, `0xC8`, `0x7F`, `0xA5`, `0x80`
   For each, identify whether the value would be positive or negative if
   interpreted as a signed 8-bit two's complement number.

3. A hardware real-time clock returns the following packed BCD register values:
   - Hours register: `0x09`
   - Minutes register: `0x47`
   - Seconds register: `0x31`
   What time does this represent? Write three lines of AVR assembly (using
   `ANDI` and `SWAP`) that extract the tens digit and units digit of the
   minutes value into separate registers.

4. The PORTB output data register is at SRAM address `0x0424` (PORTB base
   `0x0420` plus the `OUT` register offset `0x04`). Write this address in
   binary. How many address bits are needed to reach `0x0424`?
   (Hint: what is the smallest power of two greater than `0x0424`?)

5. Add the packed BCD values `0x57` and `0x46` using the `bcd_add` subroutine.
   Trace every step: binary add result, H and C flags, each correction applied,
   and the final result. Verify the result makes sense (57 + 46 = ?).

6. Subtract the packed BCD values `0x83` − `0x57` using the `bcd_sub` routine.
   Trace the steps. Verify (83 − 57 = 26).

7. A sensor returns a binary value of 197. Convert it to packed BCD using the
   double-dabble algorithm by hand (trace each of the 8 iterations of the loop,
   showing the shift and the nibble check/correction at each step).

8. In a USART output routine, you want to print a two-digit decimal number in
   r16 (range 0–99) as two ASCII characters. Write the assembly sequence that:
   a. Extracts the tens digit (hint: divide by 10, or use packed BCD from the
      `bin8_to_bcd` routine and extract the high nibble)
   b. Converts each digit to its ASCII code
   c. Leaves the tens ASCII character in r17 and units ASCII in r16

9. A 16-bit address `0x1A3F` is stored in SRAM at addresses `0x0200` and
   `0x0201`. Which byte (which value) is at `0x0200`? Which is at `0x0201`?
   If you later load this address with `LD r24, Y+` followed by `LD r25, Y`
   (Y = 0x0200), what values end up in r25:r24?

10. Explain why the AVR H (half-carry) flag is not needed for pure unsigned or
    signed binary arithmetic, but is required for BCD arithmetic. At what point
    in the ADD instruction does the half-carry get generated, and which nibble
    does it serve?

---

*Next: Chapter 3 — AVR Architecture Overview*
