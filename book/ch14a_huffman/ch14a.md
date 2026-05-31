# Huffman Decoding from Flash

Huffman coding gives frequent symbols short bit-codes and rare symbols long
ones, so a message that is mostly a few common bytes packs into fewer bits.
This chapter uses it for one job: unpacking data that was compressed ahead of
time and stored in Flash — canned strings, lookup tables, bitmap fonts.

The chapter is deliberately decode-only. Building an optimal Huffman code means
counting symbol frequencies, repeatedly merging the two least-frequent nodes,
and assigning codes by walking the resulting tree. That is pointer-heavy,
allocation-heavy work that fits a desktop far better than a part with 2 KB of
SRAM. Real firmware almost never builds the tree on the device. It does what
this chapter does:

```
Host side (offline, build time):
  Count frequencies, build the tree, derive a canonical table.
  Emit the table and the packed stream as const data in Flash.

MCU side (this chapter, assembly):
  Walk a bit stream, follow the table, write decoded bytes to SRAM.
  No tree construction. No dynamic memory. Decode only.
```

This chapter covers:

1. What a Huffman code is, and why decode-only suits AVR
2. Prefix codes and the MSB-first bit-stream contract
3. Two table formats: an explicit tree, and a canonical (length) table
4. A tree-walk decoder in assembly
5. A canonical decoder in assembly
6. Reading tables and packed data from Flash on AVRxmega3
7. Validation, edge cases, and when not to reach for Huffman

---

## Huffman in One Picture

Take the message `ABRACADABRA`. The symbols and their frequencies are:

```
Symbol  Count
A       5
B       2
R       2
C       1
D       1
```

A Huffman tree merges the two least-frequent nodes repeatedly until one tree
remains. Reading `0` for a left branch and `1` for a right branch gives each
symbol a code. One optimal tree for this message is:

```
        (root)
        /    \
      0/      \1
      A       (.)
             /    \
           0/      \1
          (.)      (.)
          / \      / \
        0/   \1  0/   \1
        B    C   D    R
```

```
Symbol  Code   Bits
A       0       1
B       100     3
C       101     3
D       110     3
R       111     3
```

The frequent `A` costs one bit; the rare symbols cost three. The whole message
packs into 23 bits instead of 88.

The property that makes decoding possible is that this is a **prefix code**: no
code is a prefix of another. `A` is `0`, and every other code starts with `1`,
so the moment the decoder has read a complete code it knows the symbol ended —
no separators are needed between codes.

When two nodes have equal weight there is a choice of which to merge, so more
than one optimal tree exists. Different tools may produce different code
*shapes* for the same input; all that matters is that the decoder uses the same
table the encoder did. The companion script `build_tables.py` is the source of
truth for the tables in this chapter.

---

## The Bit-Stream Contract

Codes are packed into bytes **most-significant bit first**. The first bit of
the message is bit 7 of the first byte. This matches the AVR shift
instructions: `LSL` moves bit 7 into `SREG.C`, so reading the next bit and
testing it is a single instruction, exactly as in the CRC chapter.

For `ABRACADABRA` the codes concatenate to 23 bits, packed into three bytes
(the final byte padded with zeros):

```
A  B    R    A  C    A  D    A  B    R    A
0  100  111  0  101  0  110  0  100  111  0

bit:  0 1 0 0 1 1 1 0 | 1 0 1 0 1 1 0 0 | 1 0 0 1 1 1 0 (0)
byte:      0x4E       |      0xAC       |      0x9C
```

Two facts the decoder cannot recover from the stream itself:

```
Where the message ends:
  Byte count does not tell you the symbol count (the last byte is padded).
  Store an explicit symbol count, or reserve an end-of-message symbol.

Which table was used:
  The table is not in the stream. The decoder must hold the matching table.
```

The examples here store the symbol count as a build-time constant (`MSG_LEN`)
and decode exactly that many symbols.

---

## Two Ways to Store the Table

The same code can be stored two ways, and the chapter implements both:

```
Format            Flash cost          Decode work     Notes
---------------   -----------------   -------------   --------------------
Explicit tree     2 bytes / node      1 node / bit    easiest to follow
Canonical table   1 byte / symbol     1 pass / symbol smallest; DEFLATE uses it
                  + 1 byte / length
```

The explicit tree is the literal picture above: a node table you walk one bit
at a time. The canonical table stores only how *long* each symbol's code is;
the codes themselves are regenerated from the lengths, because canonical codes
are assigned in a fixed order (by length, then by symbol). That is why a
`.png`-style format or DEFLATE ships code lengths and not codes.

---

## Reading Flash

Both decoders read two things from Flash: the table and the packed stream. As
in the CRC chapter, that means `LPM` with the `Z` pointer. The wrinkle is that
the decoders need two Flash pointers at once — one walking the stream, one
indexing the table — but only `Z` can drive `LPM`.

The fix is to carry the stream pointer in `X` and copy it into `Z` only for the
moment of the fetch, then save the advanced value back:

```asm
movw  r30, r26              /* Z = stream pointer (X)        */
lpm   r20, Z+               /* fetch next byte, advance Z     */
movw  r26, r30              /* save advanced pointer back to X */
```

Between fetches `Z` is free, so each table lookup recomputes `Z` from a base
address held in registers. The tables and stream live in `.text` (Flash) as
plain bytes, and pointers into them are loaded with `lo8`/`hi8`:

```asm
.section .text
.balign 2
.Lnodes:
    .byte 0x80|'A', 0x01        /* node0 */
    .byte 0x02, 0x03            /* node1 */
    .byte 0x80|'B', 0x80|'C'    /* node2 */
    .byte 0x80|'D', 0x80|'R'    /* node3 */
```

(On this AVRxmega3 part the whole Flash is also mapped into the data space at
`0x8000`, so the stream could instead be read with a plain `LD` from
`address + 0x8000`, freeing `Z` entirely. Exercise 7 rewrites the bit reader
that way; the listings here stay with `LPM` for consistency with the rest of
the book.)

---

## A Shared Bit Reader

Both decoders pull bits the same way. A byte is held in a buffer register with
a count of how many bits remain. When the count reaches zero the next stream
byte is fetched (via the `X`-to-`Z` `LPM` dance above). `LSL` delivers the next
bit (MSB first) into carry:

```
if bits_left == 0:
    buffer = next stream byte
    bits_left = 8
shift buffer left      ; old bit 7 -> Carry
bits_left = bits_left - 1
```

`DEC` does not touch the carry flag, so the bit produced by `LSL` survives the
decrement and is still available to the instruction that consumes it.

---

## Decoder 1 — Walking the Tree

The explicit tree is stored two bytes per node: the child to take on a `0`
bit, then the child to take on a `1` bit. Each child byte is either an
**internal node index** (bit 7 clear) or a **leaf** (bit 7 set, with the 7-bit
symbol in the low bits). Seven bits hold any ASCII symbol, which suits text.
The root is node 0.

```
node0:  0 -> leaf 'A'    1 -> node1
node1:  0 -> node2       1 -> node3
node2:  0 -> leaf 'B'    1 -> leaf 'C'
node3:  0 -> leaf 'D'    1 -> leaf 'R'
```

Decoding is a walk from the root: read a bit, step to the named child, and if
that child is a leaf, emit its symbol and return to the root.

```
node = root (0)
loop:
    read next bit
    entry = node_table[node*2 + bit]
    if entry is a leaf:
        emit entry's symbol
        node = root
    else:
        node = entry
    until all symbols decoded
```

The register contract:

```
Input:
  X        packed stream, Flash byte address
  Y        output buffer in SRAM
  r25:r24  node-table base, Flash byte address
  r23      number of symbols to decode

Scratch:
  r0       zero register (carry propagation)
  r17      current child entry
  r20      bit buffer
  r21      bits left in buffer
  r22      current node index
```

The implementation:

```asm
.global huff_decode_tree
huff_decode_tree:
    clr   r0                    /* zero register                       */
    clr   r22                   /* node = root (index 0)               */
    clr   r21                   /* bits left = 0 -> force a reload      */
.Lt_bit:
    tst   r21
    brne  .Lt_have
    movw  r30, r26              /* Z = stream pointer                   */
    lpm   r20, Z+               /* fetch next stream byte, advance       */
    movw  r26, r30              /* save advanced pointer back to X       */
    ldi   r21, 8
.Lt_have:
    movw  r30, r24              /* Z = base + node*2                    */
    add   r30, r22
    adc   r31, r0
    add   r30, r22
    adc   r31, r0
    lsl   r20                   /* next bit (MSB first) -> Carry        */
    dec   r21                   /* DEC preserves Carry                  */
    adc   r30, r0               /* a 1 bit selects the right child (+1) */
    adc   r31, r0
    lpm   r17, Z                /* child entry                          */
    sbrc  r17, 7                /* leaf?                                */
    rjmp  .Lt_leaf
    mov   r22, r17              /* internal node: descend               */
    rjmp  .Lt_bit
.Lt_leaf:
    andi  r17, 0x7f             /* recover the 7-bit symbol             */
    st    Y+, r17
    clr   r22                   /* back to the root                     */
    dec   r23
    brne  .Lt_bit
    ret
```

Worth noting:

- The node address is `base + node*2 + bit`. The two `ADD`/`ADC` pairs double
  the node index; the `ADC r30, r0` after `LSL` folds the data bit in, because
  `r0` is zero and carry holds the bit.
- `SBRC` (skip if bit cleared) tests bit 7 of the child entry in one
  instruction: a leaf skips the `RJMP` and falls into `.Lt_leaf`.
- Cost is one table read per *bit*, so a three-bit symbol costs three reads.
  That is the price of the simplest possible table.

---

## Decoder 2 — Canonical Decode

The canonical decoder stores no tree. It keeps two small tables:

```
counts[len]  number of codes that are exactly len bits long (len 0..MAXLEN)
symbols[]    the symbols, in canonical order: by length, then by symbol
```

For `ABRACADABRA`:

```
counts:   len 0..8 = 0, 1, 0, 4, 0, 0, 0, 0, 0
symbols:  A, B, C, D, R
```

One code of length 1 (`A`), four of length 3 (`B C D R`, in symbol order).
Canonical codes are assigned by counting up within each length and shifting
left when the length increases, so the decoder can regenerate them on the fly.
It folds in one bit per length and asks whether the code so far lands inside
the block of codes of that length:

```
code = first = index = 0
for len = 1 .. MAXLEN:
    code |= next_bit
    count = counts[len]
    if (code - first) < count:
        return symbols[index + (code - first)]
    index += count
    first  = (first + count) << 1
    code <<= 1
```

`first` is the numeric value of the first code of the current length; `index`
is where that length's symbols begin in `symbols[]`. If the accumulated `code`
is within `count` of `first`, the symbol is found and its position follows
directly. Capping `MAXLEN` at 8 keeps every value in a single byte. (DEFLATE
allows code lengths up to 15 and needs 16-bit arithmetic; the structure is
identical.)

The register contract:

```
Input:
  X        packed stream, Flash byte address
  Y        output buffer in SRAM
  r25:r24  counts[] base, Flash byte address
  r3:r2    symbols[] base, Flash byte address
  r16      number of symbols to decode

Scratch:
  r0       zero register
  r4       index        r17  code - first (temp)
  r6       count        r18  len
  r19      symbols left  r20  bit buffer    r21  bits left
  r22      code          r23  first
```

The implementation:

```asm
.equ MAXLEN, 8

.global huff_decode_canon
huff_decode_canon:
    clr   r0
    mov   r19, r16              /* symbols remaining                   */
    clr   r21                   /* bits left = 0 -> force a reload      */
.Lc_sym:
    clr   r22                   /* code  = 0                           */
    clr   r23                   /* first = 0                           */
    clr   r4                    /* index = 0                           */
    ldi   r18, 1                /* len   = 1                           */
.Lc_len:
    tst   r21
    brne  .Lc_have
    movw  r30, r26              /* Z = stream pointer                   */
    lpm   r20, Z+
    movw  r26, r30
    ldi   r21, 8
.Lc_have:
    lsl   r20                   /* next bit (MSB first) -> Carry        */
    dec   r21                   /* preserves Carry                      */
    adc   r22, r0               /* code |= bit (bit 0 was clear)        */
    movw  r30, r24              /* count = counts[len]                  */
    add   r30, r18
    adc   r31, r0
    lpm   r6, Z
    mov   r17, r22              /* r17 = code - first                   */
    sub   r17, r23
    cp    r17, r6               /* (code - first) < count ?             */
    brlo  .Lc_found
    add   r4, r6                /* index += count                       */
    add   r23, r6               /* first += count                       */
    lsl   r23                   /* first <<= 1                          */
    lsl   r22                   /* code  <<= 1                          */
    inc   r18
    cpi   r18, MAXLEN+1
    brlo  .Lc_len
    ret                         /* overran MAXLEN: stream is corrupt    */
.Lc_found:
    add   r4, r17               /* index += (code - first)              */
    movw  r30, r2               /* Z = symbols base                     */
    add   r30, r4
    adc   r31, r0
    lpm   r17, Z                /* the symbol                           */
    st    Y+, r17
    dec   r19
    brne  .Lc_sym
    ret
```

Compared with the tree walk:

- The table is far smaller: one byte per symbol plus a short `counts[]` array,
  with no per-node child pointers.
- The inner work is a subtract and an unsigned compare (`CP` then `BRLO`) per
  length, not a table read per bit.
- `counts[]` is padded out to `MAXLEN` with zeros so the loop, which always
  runs `len = 1..MAXLEN`, never reads past the table even on a malformed
  stream. The `RET` after the `MAXLEN` check is the corrupt-input exit.

---

## Standalone Demo

The full source is [huffman.S](src/huffman.S). It decodes the packed
`ABRACADABRA` stream twice — once with each decoder — into two SRAM buffers,
then transmits the decoded text over USART0 (polled, 9600 8N1) before halting:

```asm
main:
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    /* tree decode into out_tree */
    ldi   XL, lo8(.Lstream)
    ldi   XH, hi8(.Lstream)
    ldi   YL, lo8(out_tree)
    ldi   YH, hi8(out_tree)
    ldi   r24, lo8(.Lnodes)
    ldi   r25, hi8(.Lnodes)
    ldi   r23, MSG_LEN
    rcall huff_decode_tree

    /* canonical decode into out_canon */
    ldi   XL, lo8(.Lstream)
    ldi   XH, hi8(.Lstream)
    ldi   YL, lo8(out_canon)
    ldi   YH, hi8(out_canon)
    ldi   r24, lo8(.Lcounts)
    ldi   r25, hi8(.Lcounts)
    ldi   r18, lo8(.Lsymbols)
    ldi   r19, hi8(.Lsymbols)
    movw  r2, r18               /* r3:r2 = symbols base                */
    ldi   r16, MSG_LEN
    rcall huff_decode_canon

    /* USART0: 9600 8N1, TX only (polled) */
    sbi   VPORTB_OUT, TXD_BIT   /* drive PB2 high before TXEN takes over */
    sbi   VPORTB_DIR, TXD_BIT
    ldi   r16, BAUD_LO
    sts   USART0_BAUDL, r16
    ldi   r16, BAUD_HI
    sts   USART0_BAUDH, r16
    ldi   r16, USART_TXEN_bm
    sts   USART0_CTRLB, r16

    /* transmit out_canon (CRLF afterward; see the full source) */
    ldi   XL, lo8(out_canon)
    ldi   XH, hi8(out_canon)
    ldi   r18, MSG_LEN
.Lsend:
    ld    r16, X+
    rcall usart_tx_byte
    dec   r18
    brne  .Lsend

.Lhalt:
    rjmp  .Lhalt
```

The output path reuses the Curiosity Nano setup from the USART chapter: TXD is
PB2, the byte is pushed to `USART0_TXDATAL` once `USART_DREIF` shows the
transmit buffer is free. Decoding into a buffer first keeps the two SRAM
results inspectable; Exercise 5 wires the transmit into the decode loop so each
symbol goes out as it is produced.

Build it:

```bash
avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o huffman.o src/huffman.S
avr-gcc -mmcu=attiny3217 -nostartfiles -o huffman.elf huffman.o
```

Run it under simavr with a debugger attached and inspect both buffers (break at
`.Lhalt` — find its address with `avr-objdump -d huffman.elf`):

```bash
simavr -m attiny3217 -g huffman.elf &
avr-gdb -batch \
    -ex "target remote :1234" \
    -ex "break *.Lhalt" \
    -ex "continue" \
    -ex "x/11cb &out_tree" \
    -ex "x/11cb &out_canon" \
    huffman.elf
```

Both buffers hold the same eleven bytes, and the same text appears on TXD:

```
41 42 52 41 43 41 44 41 42 52 41   =   A B R A C A D A B R A
```

---

## Regenerating the Tables

The tables and stream in `huffman.S` were produced by
[build_tables.py](src/build_tables.py), which does the offline half of the job:

```bash
python3 src/build_tables.py "ABRACADABRA"
```

It counts frequencies, builds the tree, derives canonical code lengths, and
prints the `.Lnodes`, `.Lcounts`, `.Lsymbols`, and `.Lstream` lines ready to
paste into the assembly source. To compress a different message — a status
string, a font, a table — run the script over it and replace the four data
lines plus `MSG_LEN`. The decoders do not change.

---

## When Not to Use Huffman

Huffman is not free, and on a small MCU it is often the wrong tool:

```
Tiny payloads:
  The table can cost more Flash than it saves. A 20-byte string is not
  worth a tree plus a stream.

High-entropy data:
  Already-compressed or near-random data does not have skewed symbol
  frequencies, so codes do not shrink.

Streaming with no host step:
  If the data is produced on the device and never pre-analysed, there is
  no place to build the table.
```

For runs of repeated bytes — cleared regions, padded records, simple bitmaps —
run-length encoding is simpler and usually wins, with no tree at all. Huffman
earns its place when a fixed, skewed alphabet (text, a known symbol set) is
decoded many times from a table you can prepare once at build time.

A decoder that walks off the end of a valid table only on corrupt input still
needs a guard in production: the canonical decoder's `MAXLEN` check is that
guard, and the tree decoder should be given only streams whose length matches
`MSG_LEN`. The Defensive Firmware chapter covers treating external data as
hostile, which applies directly to anything you decompress at runtime.

---

## Summary

```
Decode-only:
  Build the table on the host; the MCU never builds a tree.

Bit stream:
  MSB first; LSL moves the next bit into SREG.C.
  Store the symbol count or an end-of-message symbol separately.

Tree decoder (huff_decode_tree):
  Node table, 2 bytes/node: child-on-0, child-on-1.
  Leaf = bit7 set + 7-bit symbol; internal = node index.
  One table read per bit.

Canonical decoder (huff_decode_canon):
  counts[len] + symbols[] in canonical order.
  Regenerates codes from lengths; one pass per symbol.
  Smallest table; the format DEFLATE uses.

Flash access:
  LPM via Z reads tables and stream; carry the stream pointer in X
  and MOVW it into Z only to fetch the next byte.
```

---

## Exercises

1. Hand-decode the first byte of the stream, `0x4E`, with the tree table. How
   many symbols does it yield, and how many bits of the second byte are needed
   to finish the symbol that straddles the byte boundary?

2. The tree decoder marks a leaf with bit 7, limiting symbols to 7 bits. Change
   the node format to allow full 8-bit symbols. What extra information does each
   entry now need, and how does the decode loop change?

3. Add an end-of-message symbol to the alphabet and have `huff_decode_tree`
   stop when it emits that symbol, instead of counting `MSG_LEN` symbols.
   Regenerate the tables with `build_tables.py` over a message that includes it.

4. Feed `huff_decode_canon` a deliberately truncated stream and confirm it exits
   through the `MAXLEN` path rather than running away. What does the output
   buffer contain in that case?

5. The demo decodes into a buffer and then transmits it. Move the USART
   transmit inside `huff_decode_tree` so each symbol goes out as it is produced,
   with no output buffer at all. Which register in the decode loop holds the
   byte to send, and what must you preserve across the `usart_tx_byte` call?

6. Compare the total Flash cost of the two table formats for a 16-symbol
   alphabet with a maximum code length of 6. Which is smaller, and by how much?

7. Rewrite the shared bit reader to use the AVRxmega3 Flash mapping: point `X`
   at `.Lstream + 0x8000` and fetch stream bytes with `ld r20, X+` instead of
   the `MOVW`/`LPM`/`MOVW` sequence. What does this free up, and why does it
   work only because the stream lives below the 32 KB Flash boundary?

---

*Next: Optimisation Techniques*
