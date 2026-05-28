/*
 * loadstore.S — demonstrates all load/store addressing modes on ATtiny3217.
 *               Copies a flash table to SRAM two ways: LPM and mapped LD.
 *               Companion source for Chapter 5: Load and Store
 *
 * Covers:
 *   Pointer Registers X / Y / Z — r27:r26 / r29:r28 / r31:r30
 *   Indirect Addressing: LD Rd, X+  (post-increment) and LD Rd, -X (pre-decrement)
 *   Displacement Addressing: LDD / STD Rd, Y+q  (struct-style field access)
 *   Reading Flash: LPM Rd, Z+  (program bus, byte address in Z)
 *   Reading Flash: Mapped Access — add MAPPED_PROGMEM_START and use LD (AVRxt only)
 *   Direct Addressing: LDS / STS — 32-bit instruction, 3-cycle load
 *   Pointer Arithmetic: walking an array forward and backward
 *
 * Build:
 *   avr-gcc -x assembler-with-cpp -mmcu=attiny3217 -c loadstore.S -o loadstore.o
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o loadstore.elf loadstore.o
 *   avr-objdump -d -s loadstore.elf
 */

#include <avr/io.h>

.equ    TABLE_LEN, 8

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
     * Reading Flash: LPM (Chapter 5)
     * Z = flash BYTE address (not a data-space address).
     * X = SRAM byte address of destination.
     * LPM Rd, Z+ — load byte at Z into Rd, then Z++ (post-increment).
     * ST  X+, Rd — store Rd to address X, then X++ (post-increment).
     * Timing: LPM is 3 cycles; LD from SRAM is 2 cycles.
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
     * Reading Flash: Mapped Access — AVRxt only (Chapter 5)
     * Add MAPPED_PROGMEM_START (0x8000) to obtain the data-space address.
     * Z now sits in the flash window of the unified data address space.
     * Normal LD instruction works — no special opcode needed.
     * Flash writes are NVMCTRL-controlled; mapped flash is read-only here.
     * Advantage over LPM: code that reads SRAM can read flash unchanged.
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
     * Displacement Addressing: LDD / STD Y+q (Chapter 5)
     * Access struct fields without moving the base pointer.
     * Y is held at the base of buf_ld; fields reached by offset q (0..63).
     * Only Y and Z support displacement; X does not (no LDD/STD X+q).
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
     * Pointer Arithmetic: pre-decrement — walk array backwards (Chapter 5)
     * X points ONE PAST the last element so the first -X lands on it.
     * Contrast with post-increment (Z+): that leaves Z pointing past the end.
     * Pre-decrement idiom is common in stack-style pop sequences.
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
     * Direct Addressing: LDS / STS (Chapter 5)
     * For known fixed SRAM addresses — peripherals, named variables.
     * LDS is a 32-bit (2-word) instruction: 3 cycles load, 2 cycles store.
     * Indirect LD via a pointer register is faster when you have a pointer.
     */
    ldi  r16, 0x42
    sts  buf_lpm,   r16                   ; buf_lpm[0] = 0x42
    lds  r17,       buf_lpm               ; r17 = buf_lpm[0] = 0x42

halt:
    rjmp halt

    /* Keep this table after executable code so it does not occupy interrupt
     * vector slots.  The label is a program-memory byte address for LPM; add
     * MAPPED_PROGMEM_START when reading the same bytes through LD. */
    .balign 2
powers_of_two:
    .byte 1, 2, 4, 8, 16, 32, 64, 128
