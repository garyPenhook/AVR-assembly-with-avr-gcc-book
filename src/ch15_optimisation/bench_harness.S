/*
 * bench_harness.S — Assembly-only harness for Chapter 15 optimisation examples
 *                   Companion source for Chapter 15: Optimisation Techniques
 *
 * Covers:
 *   Links memcpy_naive.S, memcpy_fast.S, lut_sin.S into one ELF for comparison
 *   avr-nm --size-sort bench.elf — compare symbol sizes (naive vs fast memcpy)
 *   avr-objdump -d bench.elf — inspect unrolled vs loop instruction sequences
 *   Benchmark pattern: call each routine, inspect cycle counts with avr-objdump
 *
 * Build from ch15_optimisation/:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -g3 -Wa,--gdwarf-2 \
 *       -nostartfiles -o bench.elf \
 *       src/bench_harness.S src/memcpy_naive.S src/memcpy_fast.S src/lut_sin.S
 *
 * The harness gives the linker concrete call sites and data symbols so
 * avr-objdump and avr-nm can be used to inspect size and instruction flow.
 */

#include <avr/io.h>

.section .vectors, "ax", @progbits
.global __vectors

__vectors:
    jmp     main
    .rept   30
    jmp     isr_default
    .endr

.section .bss
.global src_data
src_data:
    .zero   16

.global dst_naive
dst_naive:
    .zero   16

.global dst_fast
dst_fast:
    .zero   16

.global sin_sample
sin_sample:
    .zero   1

.section .text

isr_default:
    reti

.global main
.type   main, @function

main:
    ldi     r16, lo8(RAMEND)
    out     SPL, r16
    ldi     r16, hi8(RAMEND)
    out     SPH, r16

    clr     r1                  /* GCC ABI: r1 must be zero; mul clears it here */

    /* ── Fill src_data with known pattern 0x40..0x4F ─────────────────────
     * Gives us predictable data so objdump / GDB can confirm the copies.  */
    ldi     XL, lo8(src_data)
    ldi     XH, hi8(src_data)
    ldi     r18, 16             /* 16 bytes to fill                            */
    ldi     r19, 0x40           /* starting value                              */

fill_src:
    st      X+, r19             /* store byte, advance X                       */
    inc     r19                 /* next value                                  */
    dec     r18
    brne    fill_src

    /* ── Test memcpy_naive: 16 bytes src_data → dst_naive ───────────────
     * AVR/GCC ABI: dst in R25:R24, src in R23:R22, len in R20.           */
    ldi     r24, lo8(dst_naive)
    ldi     r25, hi8(dst_naive)
    ldi     r22, lo8(src_data)
    ldi     r23, hi8(src_data)
    ldi     r20, 16
    rcall   memcpy_naive        /* one byte per loop iteration                 */

    /* ── Test memcpy_fast: 16 bytes src_data → dst_fast ─────────────────
     * Same ABI. Copies 4 bytes per loop iteration; verify dst_fast = dst_naive. */
    ldi     r24, lo8(dst_fast)
    ldi     r25, hi8(dst_fast)
    ldi     r22, lo8(src_data)
    ldi     r23, hi8(src_data)
    ldi     r20, 16
    rcall   memcpy_fast         /* 4-byte unrolled inner loop                  */

    /* ── Test sin8: angle 64 (= 90° × 64/256) → should return ~182 ──────
     * LUT maps 0..255 to 0..360°; entry 64 corresponds to 90°, sin = +1.0
     * scaled to ~255, but the table has 255 at index 63/64.               */
    ldi     r24, 64             /* angle = 0x40                                */
    rcall   sin8                /* r24 = sin_table[64]                         */
    sts     sin_sample, r24     /* store result so objdump/GDB can inspect it  */

/* ── bench_done: inspect memory here in GDB / avr-objdump ───────────────── */
.global bench_done
bench_done:
    nop                         /* "break bench_done" to see all three results */

.global halt
halt:
    rjmp    halt

.size   main, .-main
