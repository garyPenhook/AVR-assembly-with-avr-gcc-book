/*
 * huffman.S — standalone Huffman decode-only demonstration
 *             Companion source for Chapter: Huffman Decoding from Flash
 *
 * Covers:
 *   Decode-only Huffman: the table is built offline on the host and frozen
 *   into Flash; the MCU never builds a tree and never allocates memory.
 *   Two decoders share one MSB-first bit reader:
 *     1. huff_decode_tree  — walk an explicit binary tree, one node per bit.
 *     2. huff_decode_canon — canonical (code-length) decode, one symbol per
 *        outer pass, using counts[] + symbols[] tables.
 *   Both tables and the packed stream live in Flash and are read with LPM via
 *   the Z pointer, the same idiom as the CRC chapter. The stream pointer is
 *   carried in X and copied into Z (MOVW) only to fetch the next byte, so Z
 *   stays free for table indexing in between.
 *   The decoded text is then transmitted over USART0 (polled) at 9600 8N1,
 *   reusing the Curiosity Nano setup from the USART chapter.
 *
 * Target: ATtiny3217 @ 3.333 MHz internal oscillator (default after reset)
 *
 * Worked example message: "ABRACADABRA" (11 symbols)
 *   Frequencies: A:5  B:2  R:2  C:1  D:1
 *   Canonical codes:  A=0  B=100  C=101  D=110  R=111
 *   Packed stream (MSB first, 23 bits): 0x4E 0xAC 0x9C
 *
 * Both decoders write 11 bytes to SRAM (out_tree, out_canon). After the
 * program halts, each buffer should read: 41 42 52 41 43 41 44 41 42 52 41
 * ("ABRACADABRA"), and the same text is sent out TXD (PB2).
 *
 * Regenerate all tables and the packed stream with build_tables.py.
 */

#include <avr/io.h>

.equ MSG_LEN,     11            /* symbols to decode                   */
.equ MAXLEN,      8             /* longest code length the canonical   */
                                /* decoder supports (8-bit arithmetic) */

/* Baud rate register for 9600 bps at 3.333 MHz (see the USART chapter):
 * USART0_BAUD = (f_cpu × 64) / (16 × baud) = 1389 = 0x056D */
.equ BAUD_LO,     0x6D
.equ BAUD_HI,     0x05
.equ TXD_BIT,     2             /* PB2 = USART0 TXD on the Curiosity Nano */

/* -- Vector table ------------------------------------------------------- */
.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    jmp   main
    .rept 30
    jmp   isr_default
    .endr

/* -- Flash-resident tables and packed data ------------------------------ */
.section .text

/*
 * Explicit tree, 2 bytes per node: [child-on-0, child-on-1].
 * Each child byte is either an internal node index (bit7 = 0) or a leaf
 * marked by bit7 = 1 with the 7-bit symbol in the low bits. ASCII symbols
 * fit in 7 bits, so this layout suits text. Root is node 0.
 *
 *   node0:  0 -> leaf 'A'    1 -> node1
 *   node1:  0 -> node2       1 -> node3
 *   node2:  0 -> leaf 'B'    1 -> leaf 'C'
 *   node3:  0 -> leaf 'D'    1 -> leaf 'R'
 */
.balign 2
.Lnodes:
    .byte 0x80|'A', 0x01        /* node0 */
    .byte 0x02, 0x03            /* node1 */
    .byte 0x80|'B', 0x80|'C'    /* node2 */
    .byte 0x80|'D', 0x80|'R'    /* node3 */

/*
 * Canonical tables.
 *   counts[len] = number of codes of length len, for len = 0..MAXLEN.
 *   symbols[]   = symbols in canonical order (by length, then symbol).
 */
.Lcounts:
    .byte 0, 1, 0, 4, 0, 0, 0, 0, 0     /* len 0..8 */
.Lsymbols:
    .byte 'A', 'B', 'C', 'D', 'R'

/* Packed bit stream, MSB first. */
.Lstream:
    .byte 0x4E, 0xAC, 0x9C
.balign 2

/* -- SRAM output buffers ------------------------------------------------ */
.section .bss
.global out_tree
out_tree:
    .skip MSG_LEN
.global out_canon
out_canon:
    .skip MSG_LEN

/* -- Code --------------------------------------------------------------- */
.section .text

isr_default:
    reti

/*
 * huff_decode_tree — decode by walking the explicit node table.
 *
 * For each output symbol, start at the root and consume one bit per level:
 * bit 0 takes the left child, bit 1 the right child. A child with bit7 set
 * is a leaf; emit its symbol and return to the root.
 *
 * In:
 *   X   (r27:r26) = packed stream, Flash byte address
 *   Y   (r29:r28) = output buffer in SRAM
 *   r25:r24       = node-table base, Flash byte address
 *   r23           = number of symbols to decode (> 0)
 *
 * Clobbers: r0, r17, r20, r21, r22, Z, X, Y, r23
 */
.global huff_decode_tree
huff_decode_tree:
    clr   r0                    /* zero register for carry propagation */
    clr   r22                   /* node = root (index 0)               */
    clr   r21                   /* bits left in buffer = 0 -> reload    */
.Lt_bit:
    tst   r21
    brne  .Lt_have
    movw  r30, r26              /* Z = stream pointer                   */
    lpm   r20, Z+               /* fetch next stream byte, advance       */
    movw  r26, r30              /* save advanced stream pointer back to X */
    ldi   r21, 8
.Lt_have:
    /* Z = base + node*2 (two child bytes per node) */
    movw  r30, r24
    add   r30, r22
    adc   r31, r0
    add   r30, r22
    adc   r31, r0
    /* next bit (MSB first); a 1 selects the right child (+1) */
    lsl   r20                   /* bit7 -> Carry                        */
    dec   r21                   /* DEC preserves Carry                  */
    adc   r30, r0               /* +bit                                 */
    adc   r31, r0
    lpm   r17, Z                /* child entry                          */
    sbrc  r17, 7                /* leaf?                                */
    rjmp  .Lt_leaf
    mov   r22, r17              /* internal node: descend               */
    rjmp  .Lt_bit
.Lt_leaf:
    andi  r17, 0x7f             /* recover 7-bit symbol                 */
    st    Y+, r17
    clr   r22                   /* back to the root                     */
    dec   r23
    brne  .Lt_bit
    ret

/*
 * huff_decode_canon — canonical (code-length) decode.
 *
 * Walks lengths 1..MAXLEN. At each length it folds in one more bit, then
 * checks whether the accumulated code falls inside the block of codes of
 * that length. If so, the symbol index is index + (code - first).
 *
 *   code = first = index = 0
 *   for len = 1..MAXLEN:
 *       code |= next_bit
 *       count = counts[len]
 *       if (code - first) < count:
 *           return symbols[index + (code - first)]
 *       index += count
 *       first  = (first + count) << 1
 *       code <<= 1
 *
 * In:
 *   X   (r27:r26) = packed stream, Flash byte address
 *   Y   (r29:r28) = output buffer in SRAM
 *   r25:r24       = counts[] base, Flash byte address (counts[0..MAXLEN])
 *   r3:r2         = symbols[] base, Flash byte address
 *   r16           = number of symbols to decode (> 0)
 *
 * Clobbers: r0, r4, r6, r17, r18, r19, r20, r21, r22, r23, Z, X, Y
 */
.global huff_decode_canon
huff_decode_canon:
    clr   r0
    mov   r19, r16              /* symbols remaining                    */
    clr   r21                   /* bits left in buffer = 0 -> reload    */
.Lc_sym:
    clr   r22                   /* code  = 0                            */
    clr   r23                   /* first = 0                            */
    clr   r4                    /* index = 0                            */
    ldi   r18, 1                /* len   = 1                            */
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
    adc   r22, r0               /* code |= bit (bit0 was clear)         */
    /* count = counts[len] */
    movw  r30, r24
    add   r30, r18
    adc   r31, r0
    lpm   r6, Z
    /* r17 = code - first */
    mov   r17, r22
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
    lpm   r17, Z                /* symbol                               */
    st    Y+, r17
    dec   r19
    brne  .Lc_sym
    ret

/*
 * usart_tx_byte — transmit one byte over USART0 by polling (from Ch. USART).
 * In:  r16 = byte to send.  Clobbers: r17 (pushed/popped).
 */
usart_tx_byte:
    push  r17
.Lwait_dreif:
    lds   r17, USART0_STATUS
    sbrs  r17, USART_DREIF_bp        /* skip when DREIF = 1 (ready)          */
    rjmp  .Lwait_dreif
    sts   USART0_TXDATAL, r16        /* write byte -> clears DREIF            */
    pop   r17
    ret

/* -- Demonstration ------------------------------------------------------ */
.global main
main:
    /* Stack pointer */
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    /* --- Tree decode into out_tree --- */
    ldi   XL, lo8(.Lstream)
    ldi   XH, hi8(.Lstream)
    ldi   YL, lo8(out_tree)
    ldi   YH, hi8(out_tree)
    ldi   r24, lo8(.Lnodes)
    ldi   r25, hi8(.Lnodes)
    ldi   r23, MSG_LEN
    rcall huff_decode_tree

    /* --- Canonical decode into out_canon --- */
    ldi   XL, lo8(.Lstream)
    ldi   XH, hi8(.Lstream)
    ldi   YL, lo8(out_canon)
    ldi   YH, hi8(out_canon)
    ldi   r24, lo8(.Lcounts)
    ldi   r25, hi8(.Lcounts)
    ldi   r18, lo8(.Lsymbols)
    ldi   r19, hi8(.Lsymbols)
    movw  r2, r18               /* r3:r2 = symbols base                 */
    ldi   r16, MSG_LEN
    rcall huff_decode_canon

    /* --- USART0 setup: 9600 8N1, TX only (polled) --- */
    sbi   VPORTB_OUT, TXD_BIT   /* drive PB2 high before TXEN takes over */
    sbi   VPORTB_DIR, TXD_BIT
    ldi   r16, BAUD_LO
    sts   USART0_BAUDL, r16
    ldi   r16, BAUD_HI
    sts   USART0_BAUDH, r16
    ldi   r16, USART_TXEN_bm    /* CTRLC default 8N1; enable TX          */
    sts   USART0_CTRLB, r16

    /* --- Transmit the decoded text + CRLF --- */
    ldi   XL, lo8(out_canon)
    ldi   XH, hi8(out_canon)
    ldi   r18, MSG_LEN
.Lsend:
    ld    r16, X+               /* read decoded byte from SRAM           */
    rcall usart_tx_byte
    dec   r18
    brne  .Lsend
    ldi   r16, '\r'
    rcall usart_tx_byte
    ldi   r16, '\n'
    rcall usart_tx_byte

.Lhalt:
    rjmp  .Lhalt
