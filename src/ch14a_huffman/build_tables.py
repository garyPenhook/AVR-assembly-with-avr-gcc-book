#!/usr/bin/env python3
"""build_tables.py - offline Huffman table generator for huffman.S

The MCU only decodes. This script does the part that does not belong on a
2 KB-SRAM part: count symbol frequencies, build the Huffman tree, derive
canonical code lengths, and emit everything the assembly decoders need.

It prints, for a given message:
  * the canonical code table (symbol, length, code);
  * the explicit-tree node table (.Lnodes) for huff_decode_tree;
  * the counts[] and symbols[] tables for huff_decode_canon;
  * the packed, MSB-first bit stream (.Lstream).

Usage:
    python3 build_tables.py "ABRACADABRA"

The defaults reproduce the tables committed in huffman.S.
"""
import sys
import heapq
from collections import Counter

# Pad counts[] to this many lengths so it matches MAXLEN in huffman.S; the
# canonical decoder loops len = 1..MAXLEN and must not read past the table.
MAXLEN = 8


def code_lengths(message):
    """Return {symbol: code_length} from a Huffman tree over message."""
    freq = Counter(message.encode("ascii"))
    if len(freq) == 1:                      # degenerate single-symbol alphabet
        return {next(iter(freq)): 1}
    # Heap entries: (weight, tiebreaker, node). node is a symbol or a pair.
    heap = [(w, i, s) for i, (s, w) in enumerate(sorted(freq.items()))]
    heapq.heapify(heap)
    counter = len(heap)
    while len(heap) > 1:
        w1, _, a = heapq.heappop(heap)
        w2, _, b = heapq.heappop(heap)
        heapq.heappush(heap, (w1 + w2, counter, (a, b)))
        counter += 1
    lengths = {}

    def walk(node, depth):
        if isinstance(node, tuple):
            walk(node[0], depth + 1)
            walk(node[1], depth + 1)
        else:
            lengths[node] = depth
    walk(heap[0][2], 0)
    return lengths


def canonical(lengths):
    """Assign canonical codes. Return ordered [(symbol, length, code)]."""
    order = sorted(lengths, key=lambda s: (lengths[s], s))
    table, code, prev_len = [], 0, 0
    for sym in order:
        length = lengths[sym]
        code <<= (length - prev_len)
        table.append((sym, length, code))
        code += 1
        prev_len = length
    return table


def pack(message, codes):
    """Pack message MSB-first using {symbol: (length, code)}; return bytes."""
    bits = []
    for sym in message.encode("ascii"):
        length, code = codes[sym]
        bits.extend((code >> (length - 1 - i)) & 1 for i in range(length))
    out = bytearray()
    for i in range(0, len(bits), 8):
        chunk = bits[i:i + 8]
        chunk += [0] * (8 - len(chunk))         # pad final byte with zeros
        out.append(int("".join(map(str, chunk)), 2))
    return bytes(out), len(bits)


def build_nodes(codes):
    """Build the explicit node table: list of (child0, child1) bytes.

    Internal child = node index (bit7 = 0); leaf = 0x80 | 7-bit symbol.
    """
    nodes = [[None, None]]                       # node 0 = root

    def insert(sym, length, code):
        node = 0
        for level in range(length):
            bit = (code >> (length - 1 - level)) & 1
            last = level == length - 1
            if last:
                nodes[node][bit] = 0x80 | sym    # leaf marker
            else:
                if nodes[node][bit] is None:
                    nodes.append([None, None])
                    nodes[node][bit] = len(nodes) - 1
                node = nodes[node][bit]
    for sym, length, code in canonical_with_codes(codes):
        insert(sym, length, code)
    return nodes


def canonical_with_codes(codes):
    return [(s, l, c) for s, (l, c) in codes.items()]


def fmt_byte(b):
    return f"0x{b:02X}"


def main():
    message = sys.argv[1] if len(sys.argv) > 1 else "ABRACADABRA"
    lengths = code_lengths(message)
    table = canonical(lengths)
    codes = {s: (l, c) for s, l, c in table}     # symbol -> (length, code)
    maxlen = max(l for _, l, _ in table)

    print(f'message  : "{message}"  ({len(message)} symbols)')
    print(f'max code length: {maxlen}\n')

    print("canonical codes (symbol, length, code):")
    for sym, length, code in table:
        print(f"  '{chr(sym)}'  len {length}  {code:0{length}b}")
    print()

    # counts[len] for len 0..MAXLEN (zero-padded to match the decoder)
    counts = [0] * (MAXLEN + 1)
    for _, length, _ in table:
        counts[length] += 1
    symbols = [sym for sym, _, _ in table]
    print(".Lcounts:  .byte " + ", ".join(str(c) for c in counts))
    print(".Lsymbols: .byte " +
          ", ".join(f"'{chr(s)}'" for s in symbols))
    print()

    nodes = build_nodes(codes)
    print(".Lnodes:")
    for i, (c0, c1) in enumerate(nodes):
        def child(c):
            return f"0x80|'{chr(c & 0x7f)}'" if c & 0x80 else str(c)
        print(f"    .byte {child(c0)}, {child(c1)}    /* node{i} */")
    print()

    stream, nbits = pack(message, codes)
    print(f".Lstream:  .byte " + ", ".join(fmt_byte(b) for b in stream) +
          f"    /* {nbits} bits */")


if __name__ == "__main__":
    main()
