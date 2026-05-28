/*
 * syntax_demo.S — demonstrates GAS directives, labels, sections, and
 *                 flash data access on ATtiny3217.
 *                 Companion source for Chapter 3: AVR-AS Syntax and Directives
 *
 * Covers:
 *   Constant directives: .equ (see "Constant Directives" section)
 *   Section layout: .rodata, .bss, .data, .vectors, .text (see "Sections")
 *   Data directives: .byte, .asciz, .skip, .word (see "Data Directives")
 *   Flash data on AVRxt: .rodata mapped at MAPPED_PROGMEM_START (see "Flash Data on AVRxt")
 *   Numeric local labels: 1: 2: 3: used with 1b / 2f / 3f (see "Labels")
 *   .global and .section flags "ax"/@progbits (see "Sections")
 *   Delay subroutine: uses .Llocal labels (file-scoped, not exported)
 *
 * Build:
 *   avr-gcc -x assembler-with-cpp -mmcu=attiny3217 -c syntax_demo.S -o syntax_demo.o
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o syntax_demo.elf syntax_demo.o
 *   avr-objdump -s -d syntax_demo.elf   ; inspect all sections + disasm
 */

#include <avr/io.h>

/* ── Constants (Chapter 3: Constant Directives) ────────────────────────── */
/* .equ defines an assembler-time symbol.  No code or data is emitted.
 * Anywhere LED_MASK appears, the assembler substitutes (1<<3) = 0x08.    */
.equ    LED_PIN,    3           ; PA3, LED0 on Curiosity Nano
.equ    LED_MASK,   (1 << LED_PIN)
.equ    DELAY_MS,   500         ; target delay in ms (used in comment only)

/* ── Flash data: lookup table (Chapter 3: Flash Data on AVRxt) ─────────
 * On AVRxt (ATtiny3217) flash is mapped at 0x8000 in the data address
 * space. Data placed in .rodata is linked into flash and can be read
 * with LD once you add MAPPED_PROGMEM_START to the address.
 *
 * The linker places .rodata after .text in flash.  The symbol address
 * reported in the ELF is the flash byte address (< 0x8000). To read
 * it via the data bus, add MAPPED_PROGMEM_START (= 0x8000).
 */
.section .rodata

morse_dit:
    .byte 1, 0          ; 1 = LED on, 0 = LED off (one element = one unit)
morse_dah:
    .byte 1, 1, 1, 0    ; three units on, one off
end_of_table:
    .byte 0xFF          ; sentinel

greeting:
    .asciz "Hello AVR"  ; null-terminated string (9 chars + null = 10 bytes)

/* ── Uninitialised data (Chapter 3: Sections — .bss) ───────────────────
 * .bss occupies SRAM but no flash space. Normally the avr-libc C runtime
 * (crt) zeroes it before main; this file is linked with -nostartfiles
 * so neither variable is initialised — they hold whatever was in SRAM at
 * reset. The labels exist here purely to demonstrate the section.       */
.section .bss

counter:    .skip 1     ; reserve 1 byte in SRAM (uninitialised here)
buf:        .skip 8     ; reserve 8 bytes (uninitialised here)

/* ── Initialised data (Chapter 3: Sections — .data) ────────────────────
 * The initial bytes live in flash; the avr-libc C runtime normally copies
 * them into SRAM before main. With -nostartfiles (this build) no copy
 * happens, so reading these in SRAM would give garbage. They exist here
 * only to demonstrate the directive layout.                              */
.section .data

tick:       .byte 0x00  ; initial image only — not copied with -nostartfiles
mode:       .word 0x1234 ; 16-bit, little-endian in flash image

/* ── Vector table ───────────────────────────────────────────────────── */
.section .vectors, "ax", @progbits
.global __vectors

__vectors:
    jmp     main

/* ── Code ───────────────────────────────────────────────────────────── */
.section .text
.global main

main:
    /* Stack pointer init */
    ldi     r16, lo8(RAMEND)
    out     SPL, r16
    ldi     r16, hi8(RAMEND)
    out     SPH, r16

    /* PA3 → output */
    ldi     r16, LED_MASK           ; use .equ constant
    sts     PORTA_DIRSET, r16

    /* Load address of morse_dit table into Z, adjusted for mapped flash */
    ldi     ZL, lo8(morse_dit + MAPPED_PROGMEM_START)
    ldi     ZH, hi8(morse_dit + MAPPED_PROGMEM_START)

    /* Walk the table: flash byte 0xFF is sentinel
     * Chapter 3: Labels — numeric local labels (1: 2: 3:) avoid naming
     * short-lived loops.  "1b" = most recent preceding "1:" label,
     * "2f" = next following "2:" label.  Safe to reuse across the file.  */
1:
    ld      r16, Z+                 ; load byte, increment Z
    cpi     r16, 0xFF               ; sentinel?
    breq    done

    /* LED on (1) or off (0) based on table value */
    tst     r16
    breq    2f                      ; 2f = next forward label "2:"
    ldi     r17, LED_MASK
    sts     PORTA_OUTCLR, r17       ; LED on (active-low)
    rjmp    3f                      ; 3f = next forward label "3:"
2:
    ldi     r17, LED_MASK
    sts     PORTA_OUTSET, r17       ; LED off
3:
    rcall   delay_unit
    rjmp    1b                      ; 1b = most recent backward label "1:"

done:
    rjmp    done                    ; halt

/* ── delay_unit: ~400 ms at 3.33 MHz ─────────────────────────────────
 * r25:r24 starts at 0, so SBIW underflows and the inner loop runs
 * 65,536 iterations × 4 cycles ≈ 262 k cycles per outer pass.
 * 5 outer passes × 262 k ≈ 1.31 M cycles ÷ 3.33 MHz ≈ 0.4 s.
 */
delay_unit:
    push    r19                 ; only r19 needs preserving (call-saved);
                                ; r24/r25 are call-clobbered per GCC ABI
    ldi     r19, 5
.Ldelay_outer:
    ldi     r25, 0
    ldi     r24, 0
.Ldelay_inner:
    sbiw    r24, 1
    brne    .Ldelay_inner
    dec     r19
    brne    .Ldelay_outer
    pop     r19
    ret
