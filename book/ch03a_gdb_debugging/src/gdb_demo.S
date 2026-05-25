/*
 * gdb_demo.S - Small ATtiny3217 assembly program for GDB practice
 *
 * Build from ch03a_gdb_debugging/:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -g3 -Wa,--gdwarf-2 \
 *       -c -o gdb_demo.o src/gdb_demo.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -g3 \
 *       -o gdb_demo.elf gdb_demo.o
 *
 * Debug:
 *   avr-gdb --nx gdb_demo.elf
 */

#include <avr/io.h>

.section .vectors, "ax", @progbits
.global __vectors

__vectors:
    jmp     main

.section .progmem.data, "a", @progbits
.global table_bytes
table_bytes:
    .byte   0x11, 0x22, 0x33, 0x44

.section .bss
.global sum_result
sum_result:
    .zero   1

.global loop_count
loop_count:
    .zero   1

.section .text
.global main
.type   main, @function

main:
    ldi     r16, lo8(RAMEND)
    out     SPL, r16
    ldi     r16, hi8(RAMEND)
    out     SPH, r16

    ldi     ZL, lo8(table_bytes)
    ldi     ZH, hi8(table_bytes)
    ldi     r18, 4
    clr     r19

.global sum_loop
sum_loop:
    lpm     r20, Z+
    add     r19, r20
    dec     r18
    brne    sum_loop

    sts     sum_result, r19
    sts     loop_count, r18

.global break_here
break_here:
    nop

.global halt
halt:
    rjmp    halt

