/*
 * control.S — branches, skip instructions, loops, jump tables on ATtiny3217.
 *
 * Build:
 *   avr-as -mmcu=attiny3217 -o control.o control.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o control.elf control.o
 *   avr-objdump -d control.elf
 */

#include <avr/io.h>

/* ── Test data ────────────────────────────────────────────────────────── */
.section .rodata

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

    /* ── if / else ────────────────────────────────────────────────────────
     * C equivalent:
     *   if (r16 > 100) { r16 = 100; } else { r16 += 5; }
     */
    ldi r16, 120
    cpi r16, 101            ; compare r16 with 101 (> 100 means >= 101)
    brlo else_branch        ; if r16 < 101: go to else
    ldi r16, 100            ; then-branch: clamp
    rjmp end_if
else_branch:
    subi r16, -5            ; else-branch: r16 += 5
end_if:

    /* ── while loop ───────────────────────────────────────────────────────
     * C equivalent:
     *   while (r16 != 0) { r16--; }
     * Test at top — loop may execute 0 times.
     */
    ldi r16, 10
while_test:
    tst r16
    breq while_done
    dec r16
    rjmp while_test
while_done:

    /* ── do-while loop ────────────────────────────────────────────────────
     * C equivalent:
     *   do { r16++; } while (r16 != 50);
     * No pre-test: always executes at least once.
     * NOTE: do-while compiles more efficiently — test only at bottom.
     */
    clr r16
do_body:
    inc r16
    cpi r16, 50
    brne do_body            ; loop back if not 50 yet

    /* ── for loop — fixed count ───────────────────────────────────────────
     * C equivalent:
     *   for (r18 = 8; r18 != 0; r18--) { r17 += 3; }
     * Count down to 0: uses BRNE — cheapest test (no CPI needed).
     */
    clr r17
    ldi r18, 8
for_loop:
    subi r17, -3            ; r17 += 3
    dec  r18
    brne for_loop

    /* ── Array sum — worked example ───────────────────────────────────────
     * Sum 8 bytes from flash into 16-bit r25:r24.
     * Use mapped flash (AVRxt): Z = address + MAPPED_PROGMEM_START.
     */
    ldi ZL, lo8(test_array + MAPPED_PROGMEM_START)
    ldi ZH, hi8(test_array + MAPPED_PROGMEM_START)
    clr r24                 ; sum low byte
    clr r25                 ; sum high byte
    ldi r18, ARRAY_LEN

sum_loop:
    ld   r16, Z+            ; load byte, advance pointer
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
     *
     * C: if (flags & 0x01) { do_something(); }
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
     * On ATtiny3217, low I/O (0x00–0x1F) includes GPIOR0-2.
     * Use GPIOR0 as a fast 1-cycle-accessible flag byte.
     *
     * C: if (GPIOR0 & (1<<2)) { action(); }
     */
    ldi r16, (1 << 2)
    out GPIOR0, r16         ; GPIOR0 bit 2 = 1
    sbis GPIOR0, 2          ; skip if bit 2 set — IS set → skip
    rcall action_a          ; skipped
    sbic GPIOR0, 3          ; skip if bit 3 clear — IS clear → skip
    rcall action_b          ; skipped

    /* ── Jump table (switch/case) ─────────────────────────────────────────
     * C equivalent:
     *   switch (r16) {
     *     case 0: case0(); break;
     *     case 1: case1(); break;
     *     case 2: case2(); break;
     *     default: default_handler(); break;
     *   }
     * Strategy: load Z with address of handler, IJMP.
     * Table entries are word addresses (use pm() operator).
     */
    ldi r16, 1              ; test with case = 1

    cpi r16, 3              ; bounds check: case >= 3?
    brsh jtable_default     ; out of range → default

    ; Compute jump table entry address:
    ; Each entry is 2 bytes (one word = one JMP address word)
    ; table_base + (r16 * 2) — but entries are word addresses so:
    ; Z = pm(jtable) + r16  (each pm() entry = 1 word = 2 bytes)
    ldi ZL, lo8(pm(jtable))
    ldi ZH, hi8(pm(jtable))
    add ZL, r16             ; Z += case_index (each entry is 1 word)
    adc ZH, r1              ; carry
    ijmp                    ; jump to address stored in Z (word address)

jtable_default:
    rcall default_handler
    rjmp jtable_done

jtable:
    rjmp case0_handler      ; case 0
    rjmp case1_handler      ; case 1
    rjmp case2_handler      ; case 2

case0_handler: rcall action_a  ; case 0 body
               rjmp jtable_done
case1_handler: rcall action_b  ; case 1 body
               rjmp jtable_done
case2_handler: rcall action_c  ; case 2 body
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
