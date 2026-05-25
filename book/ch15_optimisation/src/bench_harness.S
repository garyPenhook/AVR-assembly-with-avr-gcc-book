/*
 * bench_harness.S - Assembly-only harness for Chapter 15 optimisation examples
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
.global main
.type   main, @function

main:
    ldi     r16, lo8(RAMEND)
    out     SPL, r16
    ldi     r16, hi8(RAMEND)
    out     SPH, r16

    clr     r1

    ldi     XL, lo8(src_data)
    ldi     XH, hi8(src_data)
    ldi     r18, 16
    ldi     r19, 0x40

fill_src:
    st      X+, r19
    inc     r19
    dec     r18
    brne    fill_src

    ldi     r24, lo8(dst_naive)
    ldi     r25, hi8(dst_naive)
    ldi     r22, lo8(src_data)
    ldi     r23, hi8(src_data)
    ldi     r20, 16
    rcall   memcpy_naive

    ldi     r24, lo8(dst_fast)
    ldi     r25, hi8(dst_fast)
    ldi     r22, lo8(src_data)
    ldi     r23, hi8(src_data)
    ldi     r20, 16
    rcall   memcpy_fast

    ldi     r24, 64
    rcall   sin8
    sts     sin_sample, r24

.global bench_done
bench_done:
    nop

.global halt
halt:
    rjmp    halt

.size   main, .-main
