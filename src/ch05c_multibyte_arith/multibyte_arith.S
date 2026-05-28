/*
 * multibyte_arith.S — Multi-byte arithmetic on 24-bit, 32-bit, and wider values.
 *                     Companion source for Chapter 5c.
 *
 * Covers:
 *   24-bit: ADD+ADC+ADC, SUB+SBC+SBC, CP+CPC+CPC
 *   32-bit: ADD+ADC chain, SUB+SBC chain, CP+CPC chain
 *   Multi-byte negation: COM all + ADD chain (Method 1)
 *   Zero test: OR chain
 *   32-bit counter ISR (simulated inline here)
 *   32-bit saturating add
 *   32-bit elapsed time
 *
 * Build:
 *   avr-gcc -x assembler-with-cpp -mmcu=attiny3217 -c multibyte_arith.S -o multibyte_arith.o
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o multibyte_arith.elf multibyte_arith.o
 *   avr-objdump -d multibyte_arith.elf
 *
 * Simulate via avr-gdb + simavr, or trace by hand from the objdump listing.
 */

#include <avr/io.h>

/* ── Vector table ─────────────────────────────────────────────────────────── */
.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    jmp main

/* ── Data section ─────────────────────────────────────────────────────────── */
.section .data

counter32:
    .long 0             ; 32-bit uptime counter (little-endian, 4 bytes)

result32:
    .long 0             ; scratch 32-bit result storage

/* ── Text section ─────────────────────────────────────────────────────────── */
.section .text
.global main

main:
    /* ── Stack pointer initialisation ─────────────────────────────────────── */
    ldi  r16, lo8(RAMEND)
    out  SPL, r16
    ldi  r16, hi8(RAMEND)
    out  SPH, r16


/* ════════════════════════════════════════════════════════════════════════════
 * 24-BIT ADDITION
 * r26:r25:r24 = r26:r25:r24 + r22:r21:r20
 * Trace: 0x00FFA0 + 0x000160 = 0x010100
 * ════════════════════════════════════════════════════════════════════════════ */
section_24bit_add:
    ldi  r24, 0xA0          ; r26:r25:r24 = 0x00FFA0
    ldi  r25, 0xFF
    ldi  r26, 0x00
    ldi  r20, 0x60          ; r22:r21:r20 = 0x000160
    ldi  r21, 0x01
    ldi  r22, 0x00

    add  r24, r20           ; low:  0xA0 + 0x60 = 0x100 → r24=0x00, C=1
    adc  r25, r21           ; mid:  0xFF + 0x01 + 1 = 0x101 → r25=0x01, C=1
    adc  r26, r22           ; high: 0x00 + 0x00 + 1 = 0x01 → r26=0x01, C=0
    ; r26:r25:r24 = 0x01:0x01:0x00 = 0x010100 = 65792 ✓


/* ════════════════════════════════════════════════════════════════════════════
 * 24-BIT SUBTRACTION
 * r26:r25:r24 = r26:r25:r24 - r22:r21:r20
 * Trace: 0x010000 - 0x000001 = 0x00FFFF
 * ════════════════════════════════════════════════════════════════════════════ */
section_24bit_sub:
    ldi  r24, 0x00          ; r26:r25:r24 = 0x010000
    ldi  r25, 0x00
    ldi  r26, 0x01
    ldi  r20, 0x01          ; r22:r21:r20 = 0x000001
    ldi  r21, 0x00
    ldi  r22, 0x00

    sub  r24, r20           ; low:  0x00 - 0x01 → borrow → r24=0xFF, C=1
    sbc  r25, r21           ; mid:  0x00 - 0x00 - 1 → borrow → r25=0xFF, C=1
    sbc  r26, r22           ; high: 0x01 - 0x00 - 1 = 0x00 → r26=0x00, C=0
    ; r26:r25:r24 = 0x00FFFF = 65535 ✓


/* ════════════════════════════════════════════════════════════════════════════
 * 24-BIT UNSIGNED COMPARISON
 * Test: 0x010000 >= 0x00FFFF → expect BRSH taken
 * ════════════════════════════════════════════════════════════════════════════ */
section_24bit_cmp:
    ldi  r24, 0x00          ; r26:r25:r24 = 0x010000
    ldi  r25, 0x00
    ldi  r26, 0x01
    ldi  r20, 0xFF          ; r22:r21:r20 = 0x00FFFF
    ldi  r21, 0xFF
    ldi  r22, 0x00

    cp   r24, r20           ; low bytes
    cpc  r25, r21           ; mid bytes + borrow
    cpc  r26, r22           ; high bytes + borrow → C=0 (0x010000 > 0x00FFFF)
    brsh cmp24_ge           ; C=0 → r26:r25:r24 >= r22:r21:r20 → taken
    rjmp cmp24_done
cmp24_ge:
cmp24_done:


/* ════════════════════════════════════════════════════════════════════════════
 * 32-BIT ADDITION
 * r25:r24:r23:r22 += r19:r18:r17:r16
 * Trace: 0x00FFFFFF + 0x00000001 = 0x01000000
 * ════════════════════════════════════════════════════════════════════════════ */
section_32bit_add:
    ldi  r22, 0xFF          ; r25:r24:r23:r22 = 0x00FFFFFF
    ldi  r23, 0xFF
    ldi  r24, 0xFF
    ldi  r25, 0x00
    ldi  r16, 0x01          ; r19:r18:r17:r16 = 0x00000001
    ldi  r17, 0x00
    ldi  r18, 0x00
    ldi  r19, 0x00

    add  r22, r16           ; byte 0: 0xFF + 0x01 = 0x100 → r22=0x00, C=1
    adc  r23, r17           ; byte 1: 0xFF + 0x00 + 1 = 0x100 → r23=0x00, C=1
    adc  r24, r18           ; byte 2: 0xFF + 0x00 + 1 = 0x100 → r24=0x00, C=1
    adc  r25, r19           ; byte 3: 0x00 + 0x00 + 1 = 0x01 → r25=0x01, C=0
    ; r25:r24:r23:r22 = 0x01000000 ✓


/* ════════════════════════════════════════════════════════════════════════════
 * 32-BIT SUBTRACTION
 * r25:r24:r23:r22 -= r19:r18:r17:r16
 * Trace: 0x01000000 - 0x00000001 = 0x00FFFFFF
 * ════════════════════════════════════════════════════════════════════════════ */
section_32bit_sub:
    ldi  r22, 0x00          ; r25:r24:r23:r22 = 0x01000000
    ldi  r23, 0x00
    ldi  r24, 0x00
    ldi  r25, 0x01
    ldi  r16, 0x01          ; r19:r18:r17:r16 = 0x00000001
    ldi  r17, 0x00
    ldi  r18, 0x00
    ldi  r19, 0x00

    sub  r22, r16           ; byte 0: 0x00 - 0x01 → borrow → r22=0xFF, C=1
    sbc  r23, r17           ; byte 1: 0x00 - 0x00 - 1 → borrow → r23=0xFF, C=1
    sbc  r24, r18           ; byte 2: 0x00 - 0x00 - 1 → borrow → r24=0xFF, C=1
    sbc  r25, r19           ; byte 3: 0x01 - 0x00 - 1 = 0x00 → r25=0x00, C=0
    ; r25:r24:r23:r22 = 0x00FFFFFF ✓


/* ════════════════════════════════════════════════════════════════════════════
 * 32-BIT COMPARISON (UNSIGNED)
 * Compare 0x00FFFFFF vs 0x00FFFFFF → expect BREQ taken
 * Then compare 0x01000000 vs 0x00FFFFFF → expect BRSH taken
 * ════════════════════════════════════════════════════════════════════════════ */
section_32bit_cmp_eq:
    ldi  r22, 0xFF          ; r25:r24:r23:r22 = 0x00FFFFFF
    ldi  r23, 0xFF
    ldi  r24, 0xFF
    ldi  r25, 0x00
    ldi  r16, 0xFF          ; r19:r18:r17:r16 = 0x00FFFFFF
    ldi  r17, 0xFF
    ldi  r18, 0xFF
    ldi  r19, 0x00

    cp   r22, r16
    cpc  r23, r17
    cpc  r24, r18
    cpc  r25, r19           ; Z=1 (all bytes equal), C=0
    breq cmp32_equal        ; Z=1 → taken ✓
    rjmp cmp32_eq_done
cmp32_equal:
cmp32_eq_done:

section_32bit_cmp_gt:
    ldi  r22, 0x00          ; r25:r24:r23:r22 = 0x01000000
    ldi  r23, 0x00
    ldi  r24, 0x00
    ldi  r25, 0x01
    ldi  r16, 0xFF          ; r19:r18:r17:r16 = 0x00FFFFFF
    ldi  r17, 0xFF
    ldi  r18, 0xFF
    ldi  r19, 0x00

    cp   r22, r16
    cpc  r23, r17
    cpc  r24, r18
    cpc  r25, r19           ; C=0, Z=0 → a > b
    brsh cmp32_ge           ; C=0 → taken ✓
    rjmp cmp32_gt_done
cmp32_ge:
cmp32_gt_done:


/* ════════════════════════════════════════════════════════════════════════════
 * 32-BIT ZERO TEST (via OR chain)
 * r25:r24:r23:r22 = 0: Z=1
 * r25:r24:r23:r22 = 0x00000001: Z=0
 * ════════════════════════════════════════════════════════════════════════════ */
section_32bit_zero_test:
    ; Test zero value
    ldi  r22, 0x00
    ldi  r23, 0x00
    ldi  r24, 0x00
    ldi  r25, 0x00

    mov  r0, r22
    or   r0, r23
    or   r0, r24
    or   r0, r25            ; r0 = 0x00, Z=1 → all bytes were zero ✓
    breq zero_test_pass1
    rjmp zero_test1_done
zero_test_pass1:
zero_test1_done:

    ; Test non-zero value
    ldi  r22, 0x01          ; r25:r24:r23:r22 = 0x00000001
    ldi  r23, 0x00
    ldi  r24, 0x00
    ldi  r25, 0x00

    mov  r0, r22
    or   r0, r23
    or   r0, r24
    or   r0, r25            ; r0 = 0x01, Z=0 → at least one byte was non-zero ✓
    brne zero_test_pass2    ; Z=0 → taken ✓
    rjmp zero_test2_done
zero_test_pass2:
zero_test2_done:


/* ════════════════════════════════════════════════════════════════════════════
 * 32-BIT NEGATION (Method 1: COM all bytes, then add 1)
 * Trace: negate 0x00000001 → expect 0xFFFFFFFF
 * ════════════════════════════════════════════════════════════════════════════ */
section_32bit_neg:
    ldi  r22, 0x01          ; r25:r24:r23:r22 = 0x00000001
    ldi  r23, 0x00
    ldi  r24, 0x00
    ldi  r25, 0x00

    com  r22                ; ~0x01 = 0xFE
    com  r23                ; ~0x00 = 0xFF
    com  r24                ; ~0x00 = 0xFF
    com  r25                ; ~0x00 = 0xFF
    ; r25:r24:r23:r22 = 0xFF:0xFF:0xFF:0xFE

    ldi  r16, 1
    ldi  r17, 0
    add  r22, r16           ; 0xFE + 0x01 = 0xFF, C=0
    adc  r23, r17           ; 0xFF + 0x00 + 0 = 0xFF, C=0
    adc  r24, r17           ; 0xFF + 0x00 + 0 = 0xFF, C=0
    adc  r25, r17           ; 0xFF + 0x00 + 0 = 0xFF, C=0
    ; r25:r24:r23:r22 = 0xFFFFFFFF = -1 (signed) ✓

    ; Trace: negate 0xFFFFFFFF → expect 0x00000001
    ldi  r22, 0xFF
    ldi  r23, 0xFF
    ldi  r24, 0xFF
    ldi  r25, 0xFF

    com  r22                ; 0x00
    com  r23                ; 0x00
    com  r24                ; 0x00
    com  r25                ; 0x00
    add  r22, r16           ; 0x00 + 0x01 = 0x01, C=0
    adc  r23, r17
    adc  r24, r17
    adc  r25, r17
    ; r25:r24:r23:r22 = 0x00000001 ✓

    ; Trace: negate 0x00000000 → expect 0x00000000 (C=1 after chain, V=0)
    ldi  r22, 0x00
    ldi  r23, 0x00
    ldi  r24, 0x00
    ldi  r25, 0x00

    com  r22
    com  r23
    com  r24
    com  r25                ; all 0xFF
    add  r22, r16           ; 0xFF + 1 = 0x100 → r22=0x00, C=1
    adc  r23, r17           ; 0xFF + 0 + 1 = 0x100 → r23=0x00, C=1
    adc  r24, r17
    adc  r25, r17           ; C=1 at end (expected wrap-around of negating zero)
    ; r25:r24:r23:r22 = 0x00000000 ✓


/* ════════════════════════════════════════════════════════════════════════════
 * 32-BIT SATURATING ADD (add r16 zero-extended, clamp at 0xFFFFFFFF)
 * Trace: 0xFFFFFFF0 + 0x20 → overflow → clamped to 0xFFFFFFFF
 * ════════════════════════════════════════════════════════════════════════════ */
section_sat_add:
    ldi  r22, 0xF0          ; r25:r24:r23:r22 = 0xFFFFFFF0
    ldi  r23, 0xFF
    ldi  r24, 0xFF
    ldi  r25, 0xFF
    ldi  r16, 0x20          ; addend = 0x20

    clr  r17
    add  r22, r16
    adc  r23, r17
    adc  r24, r17
    adc  r25, r17
    brcc sat_add32_done     ; C=0: no overflow
    ser  r22                ; C=1: clamp all bytes to 0xFF
    ser  r23
    ser  r24
    ser  r25
sat_add32_done:
    ; r25:r24:r23:r22 = 0xFFFFFFFF ✓


/* ════════════════════════════════════════════════════════════════════════════
 * 32-BIT ELAPSED TIME (modulo 2^32)
 * current_time - start_time; correct across one rollover
 * Trace: current=0x00000010, start=0xFFFFFFF0 → elapsed=0x00000020
 * ════════════════════════════════════════════════════════════════════════════ */
section_elapsed:
    ldi  r22, 0x10          ; r25:r24:r23:r22 = current = 0x00000010
    ldi  r23, 0x00
    ldi  r24, 0x00
    ldi  r25, 0x00
    ldi  r16, 0xF0          ; r19:r18:r17:r16 = start = 0xFFFFFFF0
    ldi  r17, 0xFF
    ldi  r18, 0xFF
    ldi  r19, 0xFF

    sub  r22, r16           ; 0x10 - 0xF0 → borrow → r22=0x20, C=1
    sbc  r23, r17           ; 0x00 - 0xFF - 1 → borrow → r23=0x00, C=1
    sbc  r24, r18           ; 0x00 - 0xFF - 1 → borrow → r24=0x00, C=1
    sbc  r25, r19           ; 0x00 - 0xFF - 1 → borrow → r25=0x00, C=1
    ; r25:r24:r23:r22 = 0x00000020 = 32 milliseconds elapsed ✓
    ; (Counter rolled over from 0xFFFFFFF0 through 0 to 0x00000010)


/* ════════════════════════════════════════════════════════════════════════════
 * 32-BIT COUNTER IN SRAM — SIMULATE INCREMENT
 * Demonstrates load-modify-store pattern for a 32-bit counter.
 * ════════════════════════════════════════════════════════════════════════════ */
section_counter_incr:
    lds  r22, counter32+0
    lds  r23, counter32+1
    lds  r24, counter32+2
    lds  r25, counter32+3

    ldi  r16, 1
    ldi  r17, 0
    add  r22, r16
    adc  r23, r17
    adc  r24, r17
    adc  r25, r17

    sts  counter32+0, r22
    sts  counter32+1, r23
    sts  counter32+2, r24
    sts  counter32+3, r25


/* ════════════════════════════════════════════════════════════════════════════
 * SIGNED 32-BIT COMPARISON
 * Compare -1 (0xFFFFFFFF) vs +1 (0x00000001)
 * Expect BRLT taken (−1 < +1)
 * ════════════════════════════════════════════════════════════════════════════ */
section_signed_cmp32:
    ldi  r22, 0xFF          ; r25:r24:r23:r22 = 0xFFFFFFFF = -1 (signed 32-bit)
    ldi  r23, 0xFF
    ldi  r24, 0xFF
    ldi  r25, 0xFF
    ldi  r16, 0x01          ; r19:r18:r17:r16 = 0x00000001 = +1
    ldi  r17, 0x00
    ldi  r18, 0x00
    ldi  r19, 0x00

    cp   r22, r16
    cpc  r23, r17
    cpc  r24, r18
    cpc  r25, r19           ; S=1 (−1 < +1 signed): N XOR V
    brlt signed_less        ; BRLT reads S=1 → taken ✓
    rjmp signed_cmp32_done
signed_less:
signed_cmp32_done:


/* ── End of demo — halt ───────────────────────────────────────────────────── */
halt:
    rjmp halt
