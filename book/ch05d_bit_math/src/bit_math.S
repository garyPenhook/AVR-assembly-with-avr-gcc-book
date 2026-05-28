/*
 * bit_math.S — Masks, shifts, rotates, field extraction, packing, and unpacking.
 *              Companion source for Chapter 5d.
 *
 * Covers:
 *   AND / ANDI / OR / ORI / EOR / COM — all bitwise logic
 *   LSL / LSR / ASR / ROL / ROR / SWAP — all shifts and rotates
 *   BST / BLD — T-flag bit copy
 *   SBRC / SBRS — conditional bit test
 *   SBI / CBI — I/O bit set/clear
 *   Field extraction (nibble, arbitrary [hi:lo])
 *   Field insertion
 *   Packing two nibbles into one byte
 *   Unpacking nibbles
 *   Bit reversal (loop and reference for unrolled)
 *   Population count (popcount8)
 *   Multi-byte 32-bit left and right shift
 *   SPI command byte assembly / disassembly
 *
 * Build:
 *   avr-gcc -x assembler-with-cpp -mmcu=attiny3217 -c bit_math.S -o bit_math.o
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o bit_math.elf bit_math.o
 *   avr-objdump -d bit_math.elf
 */

#include <avr/io.h>

/* ── Vector table ─────────────────────────────────────────────────────────── */
.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    jmp main

/* ── Text section ─────────────────────────────────────────────────────────── */
.section .text
.global main

main:
    ldi  r16, lo8(RAMEND)
    out  SPL, r16
    ldi  r16, hi8(RAMEND)
    out  SPH, r16


/* ════════════════════════════════════════════════════════════════════════════
 * BITWISE LOGIC: AND / OR / EOR / COM
 * ════════════════════════════════════════════════════════════════════════════ */
section_logic:
    ldi  r16, 0b10110110    ; r16 = 0xB6

    /* AND: clear lower nibble */
    mov  r17, r16
    andi r17, 0xF0          ; r17 = 0xB0 (upper nibble preserved, lower cleared)

    /* AND: isolate lower nibble */
    mov  r17, r16
    andi r17, 0x0F          ; r17 = 0x06

    /* OR: set bits 1 and 0 */
    mov  r17, r16
    ori  r17, 0x03          ; r17 = 0xB7

    /* EOR: toggle lower nibble */
    mov  r17, r16
    ldi  r18, 0x0F
    eor  r17, r18           ; r17 = 0xB9 (lower nibble toggled 0110 → 1001)

    /* COM: bitwise NOT */
    mov  r17, r16
    com  r17                ; r17 = 0x49 = ~0xB6

    /* CLR (alias for EOR Rd,Rd) */
    clr  r17                ; r17 = 0x00, Z=1, C unchanged

    /* TST (alias for AND Rd,Rd) — sets flags without changing register */
    tst  r16                ; sets N=1 (bit 7 of 0xB6 is set), Z=0


/* ════════════════════════════════════════════════════════════════════════════
 * MASKING: SET, CLEAR, TOGGLE
 * ════════════════════════════════════════════════════════════════════════════ */
section_masking:
    ldi  r16, 0b01010101    ; r16 = 0x55 = alternating bits

    /* Clear bit 4 */
    andi r16, ~(1 << 4)     ; r16 = 0b01000101 = 0x45

    /* Set bit 7 */
    ori  r16, (1 << 7)      ; r16 = 0b11000101 = 0xC5

    /* Toggle bit 2 */
    ldi  r17, (1 << 2)
    eor  r16, r17           ; r16 = 0b11000001 = 0xC1

    /* Read-modify-write: set bit 3, clear bit 1 */
    ori  r16, (1 << 3)      ; set bit 3
    andi r16, ~(1 << 1)     ; clear bit 1


/* ════════════════════════════════════════════════════════════════════════════
 * SHIFTS AND ROTATES
 * ════════════════════════════════════════════════════════════════════════════ */
section_shifts:
    ldi  r16, 0b00101010    ; r16 = 0x2A = 42

    /* LSL: multiply by 2 */
    mov  r17, r16
    lsl  r17                ; r17 = 0x54 = 84 (42 × 2), C=0

    /* LSR: divide by 2 (unsigned) */
    mov  r17, r16
    lsr  r17                ; r17 = 0x15 = 21 (42 ÷ 2), C=0

    /* ASR: divide by 2 (signed) */
    ldi  r17, 0xFE          ; r17 = -2 (signed)
    asr  r17                ; r17 = 0xFF = -1, C=0  (-2 ÷ 2 = -1) ✓

    /* SWAP: exchange nibbles */
    ldi  r17, 0xAB
    swap r17                ; r17 = 0xBA

    /* Shift left by 3 (×8) using LSL ×3 */
    ldi  r16, 0x05          ; r16 = 5
    lsl  r16
    lsl  r16
    lsl  r16                ; r16 = 40 = 5 × 8 ✓

    /* Shift right by 4 using SWAP + mask */
    ldi  r16, 0xB0
    swap r16                ; nibbles exchanged: 0x0B
    andi r16, 0x0F          ; clear upper garbage: r16 = 0x0B = 11 ✓

    /* Shift left by 8: register move */
    ldi  r24, 0x42          ; r25:r24 = 0x0042
    ldi  r25, 0x00
    mov  r25, r24           ; r25 = 0x42 (old low)
    clr  r24                ; r24 = 0x00
    ; r25:r24 = 0x4200 = 16896 ✓


/* ════════════════════════════════════════════════════════════════════════════
 * MULTI-BYTE 32-BIT SHIFT
 * ════════════════════════════════════════════════════════════════════════════ */
section_mb_shift:
    /* 32-bit left shift by 1: r25:r24:r23:r22 <<= 1 */
    ldi  r22, 0xAB
    ldi  r23, 0xCD
    ldi  r24, 0xEF
    ldi  r25, 0x12          ; r25:r24:r23:r22 = 0x12EFCDAB

    lsl  r22
    rol  r23
    rol  r24
    rol  r25
    ; r25:r24:r23:r22 = 0x25DF9B56 (shifted left 1) ✓

    /* 32-bit right shift by 1 (logical): r25:r24:r23:r22 >>= 1 */
    lsr  r25                ; high byte first!
    ror  r24
    ror  r23
    ror  r22
    ; restores original value 0x12EFCDAB ✓


/* ════════════════════════════════════════════════════════════════════════════
 * T-FLAG BIT COPY (BST / BLD)
 * ════════════════════════════════════════════════════════════════════════════ */
section_t_flag:
    ldi  r16, 0b10110000    ; r16 bit 5 = 1
    ldi  r17, 0b00000000    ; r17 bit 2 = 0

    bst  r16, 5             ; T ← bit 5 of r16  (T=1)
    bld  r17, 2             ; bit 2 of r17 ← T

    ; r17 = 0b00000100 = 0x04 (bit 2 set) ✓
    ; r16 unchanged = 0xB0 ✓

    /* Copy bit 0 of r18 to bit 7 of r19 */
    ldi  r18, 0x01          ; bit 0 set
    ldi  r19, 0x00
    bst  r18, 0             ; T = 1
    bld  r19, 7             ; bit 7 of r19 = 1
    ; r19 = 0x80 ✓


/* ════════════════════════════════════════════════════════════════════════════
 * SBRC / SBRS — BIT TEST AND SKIP
 * ════════════════════════════════════════════════════════════════════════════ */
section_skip_bit:
    ldi  r16, 0b00010000    ; bit 4 is set

    /* Test bit 4: should branch to "bit set" path */
    sbrs r16, 4             ; skip next if bit 4 SET → skip rjmp
    rjmp skip_test_clear    ; bit 4 clear: go here
    rjmp skip_test_set      ; bit 4 set: go here (this is the taken path)
skip_test_clear:
    rjmp skip_test_done
skip_test_set:
skip_test_done:

    /* Test bit 3: should take the "clear" path */
    sbrc r16, 3             ; skip next if bit 3 CLEAR → skip rjmp (bit 3 is 0)
    rjmp skip3_set          ; bit 3 set: go here (NOT taken since bit 3 = 0)
    rjmp skip3_clear        ; this rjmp is skipped; execution falls here
skip3_set:
    rjmp skip3_done
skip3_clear:
skip3_done:


/* ════════════════════════════════════════════════════════════════════════════
 * FIELD EXTRACTION
 * ════════════════════════════════════════════════════════════════════════════ */
section_extract:
    ldi  r16, 0b10110100    ; source byte

    /* Extract lower nibble (bits 3:0) */
    mov  r17, r16
    andi r17, 0x0F          ; r17 = 0x04 ✓

    /* Extract upper nibble (bits 7:4) */
    mov  r17, r16
    swap r17
    andi r17, 0x0F          ; r17 = 0x0B ✓

    /* Extract bits 6:4 (3-bit field at offset 4) */
    mov  r17, r16
    andi r17, 0b01110000    ; mask bits 6:4 = 0x70
    lsr  r17
    lsr  r17
    lsr  r17
    lsr  r17                ; r17 = 0b00000011 = 3  ✓ (bits 6,5,4 = 0,1,1 from 0b10110100)

    /* Extract single bit 5 to bit 0 using BST/BLD */
    clr  r17
    bst  r16, 5
    bld  r17, 0             ; r17 = 0 or 1 = bit 5 value of r16
    ; r16 = 0b10110100, bit 5 = 1 → r17 = 1 ✓ (but other bits of r17 still 0 from CLR)


/* ════════════════════════════════════════════════════════════════════════════
 * FIELD INSERTION
 * ════════════════════════════════════════════════════════════════════════════ */
section_insert:
    ldi  r16, 0b11111111    ; destination (all bits set)
    ldi  r17, 0b00000101    ; value to insert: 5 (3-bit field, bits 2:0)

    /* Insert bits 2:0 of r17 into bits 5:3 of r16 */
    andi r17, 0x07          ; ensure 3 bits only
    lsl  r17
    lsl  r17
    lsl  r17                ; r17 = (5 << 3) = 0b00101000 = 0x28

    andi r16, ~0b00111000   ; clear bits 5:3 of destination: r16 = 0b11000111
    or   r16, r17           ; r16 = 0b11101111 = 0xEF ✓
    ; Verify bits 5:3 = 0b101 = 5 ✓


/* ════════════════════════════════════════════════════════════════════════════
 * PACKING TWO NIBBLES
 * ════════════════════════════════════════════════════════════════════════════ */
section_pack:
    ldi  r17, 0x04          ; tens digit = 4 (low nibble)
    ldi  r18, 0x07          ; units digit = 7 (low nibble)

    andi r17, 0x0F
    andi r18, 0x0F
    swap r17                ; tens → upper nibble: r17 = 0x40
    or   r17, r18           ; merge: r17 = 0x47 ✓

    /* Reverse: unpack 0x47 into tens=4, units=7 */
    ldi  r16, 0x47

    mov  r17, r16
    swap r17
    andi r17, 0x0F          ; r17 = 0x04 = tens ✓

    mov  r18, r16
    andi r18, 0x0F          ; r18 = 0x07 = units ✓


/* ════════════════════════════════════════════════════════════════════════════
 * SPI COMMAND BYTE ASSEMBLY AND DISASSEMBLY
 * Format: [7:5]=opcode, [4:2]=address, [1:0]=flags
 * ════════════════════════════════════════════════════════════════════════════ */
section_spi_cmd:
    ldi  r20, 5             ; opcode  = 0b101 = 5
    ldi  r21, 3             ; address = 0b011 = 3
    ldi  r22, 2             ; flags   = 0b10  = 2

    /* Assemble */
    andi r20, 0x07
    lsl  r20
    lsl  r20
    lsl  r20
    lsl  r20
    lsl  r20                ; opcode in bits 7:5 = 0b10100000

    andi r21, 0x07
    lsl  r21
    lsl  r21                ; address in bits 4:2 = 0b00001100

    andi r22, 0x03          ; flags in bits 1:0

    or   r20, r21
    or   r20, r22
    mov  r16, r20           ; r16 = 0b10101110 = 0xAE ✓

    /* Disassemble 0xAE */
    ldi  r16, 0xAE

    mov  r17, r16           ; extract opcode
    andi r17, 0b11100000
    lsr  r17
    lsr  r17
    lsr  r17
    lsr  r17
    lsr  r17                ; r17 = 5 ✓

    mov  r18, r16           ; extract address
    andi r18, 0b00011100
    lsr  r18
    lsr  r18                ; r18 = 3 ✓

    mov  r19, r16           ; extract flags
    andi r19, 0b00000011    ; r19 = 2 ✓


/* ── End of demo — halt ───────────────────────────────────────────────────── */
halt:
    rjmp halt


/* ════════════════════════════════════════════════════════════════════════════
 * SUBROUTINES
 * ════════════════════════════════════════════════════════════════════════════ */

/*
 * bit_reverse8 — reverse all 8 bits of r16
 *   Input:  r16 = byte to reverse
 *   Output: r16 = bit-reversed result
 *   Clobbers: r17, r18
 */
.global bit_reverse8
bit_reverse8:
    ldi  r18, 8
    clr  r17
bit_rev_loop:
    lsl  r17            ; make room (shift accumulator left)
    lsr  r16            ; LSB of source → C
    rol  r17            ; C → bit 0 of accumulator
    dec  r18
    brne bit_rev_loop
    mov  r16, r17
    ret


/*
 * popcount8 — count number of set bits in r16
 *   Input:  r16 = byte to examine
 *   Output: r17 = count of set bits (0–8)
 *   Clobbers: r18
 */
.global popcount8
popcount8:
    clr  r17
    ldi  r18, 8
popcount_loop:
    lsr  r16            ; bit 0 → C
    adc  r17, r1        ; r17 += C  (r1 = 0 per ABI)
    dec  r18
    brne popcount_loop
    ret


/*
 * pack_nibbles — combine low nibbles of r16 and r17 into one byte
 *   Input:  r16 = upper nibble source (low nibble used)
 *           r17 = lower nibble source (low nibble used)
 *   Output: r16 = packed result: {r16[3:0], r17[3:0]}
 *   Clobbers: r17
 */
.global pack_nibbles
pack_nibbles:
    andi r16, 0x0F
    andi r17, 0x0F
    swap r16            ; low nibble of r16 → upper nibble
    or   r16, r17       ; merge
    ret


/*
 * extract_field — extract bits [hi:lo] from r16 into r17
 *   Input:  r16 = source byte
 *           r18 = field mask  (bits [hi:lo] = 1, others = 0)
 *           r19 = lo (number of right-shifts needed = starting bit position)
 *   Output: r17 = extracted field value (right-aligned, bits [width-1:0])
 *   Clobbers: r17, r19
 */
.global extract_field
extract_field:
    mov  r17, r16
    and  r17, r18           ; apply mask
extract_shift_loop:
    tst  r19
    breq extract_done
    lsr  r17
    dec  r19
    rjmp extract_shift_loop
extract_done:
    ret
