/*
 * syntax_demo.S — demonstrates GAS directives, labels, sections, and
 *                 flash data access on ATtiny3217.
 *
 * Build:
 *   avr-as -mmcu=attiny3217 -o syntax_demo.o syntax_demo.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o syntax_demo.elf syntax_demo.o
 *   avr-objdump -s -d syntax_demo.elf   ; inspect all sections + disasm
 */

#include <avr/io.h>

/* ── Constants ─────────────────────────────────────────────────────────── */
.equ    LED_PIN,    3           ; PA3, LED0 on Curiosity Nano
.equ    LED_MASK,   (1 << LED_PIN)
.equ    DELAY_MS,   500         ; target delay in ms (used in comment only)

/* ── Flash data: lookup table ───────────────────────────────────────────
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

/* ── Uninitialised data (SRAM, zeroed by startup) ───────────────────── */
.section .bss

counter:    .skip 1     ; reserve 1 byte in SRAM, initialised to 0
buf:        .skip 8     ; reserve 8 bytes

/* ── Initialised data (SRAM, copied from flash at startup) ──────────── */
.section .data

tick:       .byte 0x00  ; will be 0x00 in SRAM after startup copy
mode:       .word 0x1234 ; 16-bit value, little-endian in SRAM

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

    /* Walk the table: flash byte 0xFF is sentinel */
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

/* ── delay_unit: ~100 ms at 3.33 MHz ───────────────────────────────── */
delay_unit:
    push    r18
    push    r19
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
    pop     r18
    ret
