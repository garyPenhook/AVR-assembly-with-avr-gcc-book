/*
 * control.S — branches, skip instructions, loops, jump tables on ATtiny3217.
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c control.S -o control.o
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o control.elf control.o
 *   avr-objdump -d control.elf
 */

#include <avr/io.h>

/* ── Test data in flash ───────────────────────────────────────────────── */
.section .progmem.data, "a", @progbits

test_array:
    .byte 10, 20, 30, 40, 50, 60, 70, 80
.equ ARRAY_LEN, 8

/* ── SRAM ─────────────────────────────────────────────────────────────── */
.section .bss
result16: .skip 2          ; 16-bit sum result

/* ── Vectors ──────────────────────────────────────────────────────────── */
.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    jmp main

/* ── Code ─────────────────────────────────────────────────────────────── */
.section .text
.global main

main:
    ldi r16, lo8(RAMEND)
    out SPL, r16
    ldi r16, hi8(RAMEND)
    out SPH, r16

    /* ── Two-way decision ─────────────────────────────────────────────────
     * If r16 is above 100, clamp it to 100.
     * Otherwise, add 5.
     */
    ldi r16, 120
    cpi r16, 101            ; compare r16 with 101 (> 100 means >= 101)
    brlo else_branch        ; if r16 < 101: go to else
    ldi r16, 100            ; then-branch: clamp
    rjmp end_if
else_branch:
    subi r16, -5            ; else-branch: r16 += 5
end_if:

    /* ── Top-tested loop ──────────────────────────────────────────────────
     * Decrement r16 until it reaches zero.
     * Test at top: loop may execute 0 times.
     */
    ldi r16, 10
top_test:
    tst r16
    breq top_done
    dec r16
    rjmp top_test
top_done:

    /* ── Bottom-tested loop ───────────────────────────────────────────────
     * Increment r16 until it reaches 50.
     * No pre-test: always executes at least once.
     * Test only at bottom, so the branch is also the loop-back.
     */
    clr r16
do_body:
    inc r16
    cpi r16, 50
    brne do_body            ; loop back if not 50 yet

    /* ── Fixed-count loop ─────────────────────────────────────────────────
     * Count down to 0: uses BRNE — cheapest test (no CPI needed).
     */
    clr r17
    ldi r18, 8
count_loop:
    subi r17, -3            ; r17 += 3
    dec  r18
    brne count_loop

    /* ── Array sum — worked example ───────────────────────────────────────
     * Sum 8 bytes from flash into 16-bit r25:r24.
     * Use LPM: Z is the flash byte address of test_array.
     */
    ldi ZL, lo8(test_array)
    ldi ZH, hi8(test_array)
    clr r24                 ; sum low byte
    clr r25                 ; sum high byte
    ldi r18, ARRAY_LEN

sum_loop:
    lpm  r16, Z+            ; load byte from flash, advance pointer
    add  r24, r16           ; add to sum low byte
    adc  r25, r1            ; propagate carry (r1 = 0)
    dec  r18
    brne sum_loop

    sts result16,   r24     ; store result
    sts result16+1, r25

    /* ── Skip instructions: SBRC / SBRS ──────────────────────────────────
     * SBRC Rr, b — Skip if Bit b of Rr is Clear
     * SBRS Rr, b — Skip if Bit b of Rr is Set
     * Skips exactly one instruction (1-word or 2-word).
     */
    ldi r16, 0b00000101     ; flags byte
    sbrc r16, 0             ; skip next if bit 0 clear — bit 0 IS set, no skip
    rcall action_a          ; executed
    sbrc r16, 1             ; skip next if bit 1 clear — bit 1 IS clear, SKIP
    rcall action_b          ; skipped
    sbrs r16, 2             ; skip next if bit 2 set — bit 2 IS set, SKIP
    rcall action_c          ; skipped
    sbrs r16, 3             ; skip next if bit 3 set — bit 3 clear, no skip
    rcall action_d          ; executed

    /* ── SBIC / SBIS — skip on I/O bit ───────────────────────────────────
     * SBIC A, b — Skip if bit b of I/O reg A (addr 0x00–0x1F) is Clear
     * SBIS A, b — Skip if bit b of I/O reg A (addr 0x00–0x1F) is Set
     *
     * On ATtiny3217, low I/O (0x00–0x1F) includes GPIOR0-3.
     * Use GPIOR0 as a fast 1-cycle-accessible flag byte.
     */
    ldi r16, (1 << 2)
    out GPIOR0, r16         ; GPIOR0 bit 2 = 1
    sbis GPIOR0, 2          ; skip if bit 2 set — IS set → skip
    rcall action_a          ; skipped
    sbic GPIOR0, 3          ; skip if bit 3 clear — IS clear → skip
    rcall action_b          ; skipped

    /* ── Jump table ───────────────────────────────────────────────────────
     * Dispatch r16 values 0, 1, or 2 to separate handlers.
     * Other values use the default handler.
     * Strategy: load Z with the selected table entry and IJMP into it.
     * Table entries are executable RJMP instructions, one word each.
     */
    ldi r16, 1              ; selector = 1

    cpi r16, 3              ; bounds check: selector >= 3?
    brsh jtable_default     ; out of range → default

    ; Compute jump table entry address:
    ; Each entry is 1 instruction word (2 bytes).
    ; Z is a program word address, so:
    ; Z = pm(jtable) + r16
    ldi ZL, lo8(pm(jtable))
    ldi ZH, hi8(pm(jtable))
    add ZL, r16             ; Z += selector index (each entry is 1 word)
    adc ZH, r1              ; carry
    ijmp                    ; jump to selected RJMP entry in the table

jtable_default:
    rcall default_handler
    rjmp jtable_done

jtable:
    rjmp entry0_handler     ; selector 0
    rjmp entry1_handler     ; selector 1
    rjmp entry2_handler     ; selector 2

entry0_handler: rcall action_a
               rjmp jtable_done
entry1_handler: rcall action_b
               rjmp jtable_done
entry2_handler: rcall action_c
               rjmp jtable_done

jtable_done:

halt:
    rjmp halt

/* ── Stubs ────────────────────────────────────────────────────────────── */
action_a:       ret
action_b:       ret
action_c:       ret
action_d:       ret
default_handler:ret
