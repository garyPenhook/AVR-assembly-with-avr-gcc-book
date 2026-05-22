/*
 * loadstore.S — demonstrates all load/store addressing modes on ATtiny3217.
 *               Copies a flash table to SRAM two ways: LPM and mapped LD.
 *
 * Build:
 *   avr-as -mmcu=attiny3217 -o loadstore.o loadstore.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o loadstore.elf loadstore.o
 *   avr-objdump -d -s loadstore.elf
 */

#include <avr/io.h>

.equ    TABLE_LEN, 8

/* ── Flash table ─────────────────────────────────────────────────────── */
.section .rodata

powers_of_two:
    .byte 1, 2, 4, 8, 16, 32, 64, 128

/* ── SRAM buffers ────────────────────────────────────────────────────── */
.section .bss

buf_lpm:    .skip TABLE_LEN      ; copy via LPM
buf_ld:     .skip TABLE_LEN      ; copy via mapped LD

/* ── Vector table ────────────────────────────────────────────────────── */
.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    jmp     main

/* ── Code ────────────────────────────────────────────────────────────── */
.section .text
.global main

main:
    ldi r16, lo8(RAMEND)
    out SPL, r16
    ldi r16, hi8(RAMEND)
    out SPH, r16

    /* ────────────────────────────────────────────────────────────────────
     * Method 1: LPM — load from flash via program bus.
     * Z = flash BYTE address of source.
     * X = SRAM byte address of destination.
     * LPM Rd, Z+ — load byte at Z into Rd, then Z++.
     * ST  X+, Rd — store Rd to address X, then X++.
     */
    ldi ZL,  lo8(powers_of_two)          ; Z = flash addr of table
    ldi ZH,  hi8(powers_of_two)
    ldi XL,  lo8(buf_lpm)                ; X = SRAM addr of dest
    ldi XH,  hi8(buf_lpm)
    ldi r18, TABLE_LEN

copy_lpm:
    lpm  r16, Z+                          ; r16 = flash[Z], Z++
    st   X+,  r16                         ; sram[X] = r16, X++
    dec  r18
    brne copy_lpm

    /* ────────────────────────────────────────────────────────────────────
     * Method 2: LD with mapped flash address (AVRxt feature).
     * Add MAPPED_PROGMEM_START (0x8000) to the flash address.
     * Z now points into the data address space where flash is mapped.
     * Reads exactly like SRAM — no special instruction needed.
     */
    ldi ZL,  lo8(powers_of_two + MAPPED_PROGMEM_START)
    ldi ZH,  hi8(powers_of_two + MAPPED_PROGMEM_START)
    ldi XL,  lo8(buf_ld)
    ldi XH,  hi8(buf_ld)
    ldi r18, TABLE_LEN

copy_mapped:
    ld   r16, Z+                          ; r16 = flash[Z - 0x8000], Z++
    st   X+,  r16
    dec  r18
    brne copy_mapped

    /* ────────────────────────────────────────────────────────────────────
     * Displacement addressing: LDD / STD with Y or Z pointer.
     * Access a struct-like block of SRAM without moving the pointer.
     * Here: write 0xAA to buf_ld[0], 0xBB to buf_ld[2], 0xCC to buf_ld[7]
     */
    ldi YL, lo8(buf_ld)
    ldi YH, hi8(buf_ld)

    ldi r16, 0xAA
    std Y+0, r16                          ; buf_ld[0] = 0xAA
    ldi r16, 0xBB
    std Y+2, r16                          ; buf_ld[2] = 0xBB
    ldi r16, 0xCC
    std Y+7, r16                          ; buf_ld[7] = 0xCC

    ldd r17, Y+2                          ; r17 = buf_ld[2] = 0xBB (verify)

    /* ────────────────────────────────────────────────────────────────────
     * Pre-decrement: walk an array backwards.
     * X points ONE PAST the end; -X decrements before each load.
     */
    ldi XL, lo8(buf_lpm + TABLE_LEN)     ; X = one past end
    ldi XH, hi8(buf_lpm + TABLE_LEN)
    ldi r18, TABLE_LEN

walk_backward:
    ld   r16, -X                          ; X--, then r16 = sram[X]
    ; r16 now holds buf_lpm[TABLE_LEN-1], buf_lpm[TABLE_LEN-2], ...
    dec  r18
    brne walk_backward

    /* ────────────────────────────────────────────────────────────────────
     * Direct addressing: LDS / STS — for known fixed SRAM addresses.
     * Slower (3 cycles load, 2 cycles store) and 32-bit instructions.
     */
    ldi  r16, 0x42
    sts  buf_lpm,   r16                   ; buf_lpm[0] = 0x42
    lds  r17,       buf_lpm               ; r17 = buf_lpm[0] = 0x42

halt:
    rjmp halt
