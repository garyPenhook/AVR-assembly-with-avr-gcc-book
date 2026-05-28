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

/* ── SRAM variables (inspect these in GDB after break_here) ──────────────── */
.section .bss
.global sum_result
sum_result:
    .zero   1               /* byte sum of table_bytes (expected 0xAA = 170)   */

.global loop_count
loop_count:
    .zero   1               /* should be 0x00 after the loop finishes          */

.section .text
.global main
.type   main, @function

/*
 * main — set up SP, then sum four flash bytes into sum_result.
 *
 * GDB exercise: set a breakpoint at break_here, then inspect:
 *   (gdb) x/1xb &sum_result   → should show 0xaa
 *   (gdb) x/1xb &loop_count   → should show 0x00
 *
 * Registers used:
 *   Z   (R31:R30) = flash byte address of table_bytes
 *   R18 = countdown counter (starts at 4, ends at 0)
 *   R19 = accumulator (holds running sum)
 *   R20 = current byte loaded from flash
 */
main:
    ldi     r16, lo8(RAMEND)        /* set SP to top of SRAM (0x3FFF)          */
    out     SPL, r16
    ldi     r16, hi8(RAMEND)
    out     SPH, r16

    ldi     ZL, lo8(table_bytes)    /* Z = flash byte address of table         */
    ldi     ZH, hi8(table_bytes)
    ldi     r18, 4                  /* r18 = element count                     */
    clr     r19                     /* r19 = sum accumulator = 0               */

/* ── sum_loop: load each byte from flash and add to r19 ─────────────────── */
.global sum_loop
sum_loop:
    lpm     r20, Z+                 /* r20 = flash[Z], Z++ (post-increment)    */
    add     r19, r20                /* sum += byte                             */
    dec     r18                     /* counter--                               */
    brne    sum_loop                /* loop while counter != 0                 */

    sts     sum_result, r19         /* store final sum to SRAM                 */
    sts     loop_count, r18         /* store final counter value (0)           */

/* ── break_here: GDB breakpoint target ──────────────────────────────────── */
.global break_here
break_here:
    nop                             /* "break break_here" lands here in GDB    */

/* ── halt: spin forever ─────────────────────────────────────────────────── */
.global halt
halt:
    rjmp    halt

/* ── table_bytes: four data bytes summed by the loop ──────────────────────
 * Sum: 0x11 + 0x22 + 0x33 + 0x44 = 0xAA (170 decimal)                     */
.balign 2
.global table_bytes
table_bytes:
    .byte   0x11, 0x22, 0x33, 0x44
