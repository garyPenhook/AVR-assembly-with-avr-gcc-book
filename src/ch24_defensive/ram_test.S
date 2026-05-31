/* ============================================================
 * ram_test.S — power-on RAM test (March C-) for defensive firmware
 * Target: ATtiny3217 @ 3.333 MHz (default OSC20M /6)
 * Build:  avr-gcc -mmcu=attiny3217 -nostartfiles ram_test.S -o ram_test.elf
 * ============================================================
 *
 * A RAM test belongs in a power-on self-test: before the firmware trusts its
 * working memory, prove that every cell can hold both a 0 and a 1 and is not
 * coupled to its neighbours. This file implements March C-, the standard
 * industry test, as a reusable routine over an arbitrary SRAM region.
 *
 * March C- runs six elements over the region. "Ascending" walks low->high
 * address, "descending" high->low; w0/w1 write 0x00/0xFF, r0/r1 read and
 * expect 0x00/0xFF:
 *     M0  any   w0            (initialise)
 *     M1  up    r0, w1
 *     M2  up    r1, w0
 *     M3  down  r0, w1
 *     M4  down  r1, w0
 *     M5  any   r0            (final check)
 * Reading the opposite value from each cell in alternating directions catches
 * stuck-at faults and the address-order coupling faults a single pass misses.
 *
 * The test is DESTRUCTIVE — it overwrites the region — and it uses RCALL, so
 * it cannot test the bytes currently holding the stack. Run it at power-on on
 * a region that is not the stack (this demo tests a .bss buffer). A true
 * whole-RAM POST tests memory in halves, or runs stackless before the stack
 * pointer is set up. See the chapter.
 *
 * Result: r24 = 0 if every cell passed, 1 if any fault was detected.
 * On pass the demo lights LED0 (PA3, active-low); the result byte is also
 * stored at ram_result for inspection.
 *
 * Registers: r16 scratch, r18 expected value, r19 write value,
 *            r21:r20 saved region start, r23:r22 saved length,
 *            r25:r24 working counter, X working pointer.
 * ============================================================ */
#include <avr/io.h>

.equ LED_BIT,    3              /* PA3, Curiosity Nano LED0 */
.equ TEST_LEN,   64             /* bytes of the demo buffer to test */

/* ── Vector table ─────────────────────────────────────────────────────── */
.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    jmp  main
    .rept 30
    jmp  isr_default
    .endr

/* ── State ────────────────────────────────────────────────────────────── */
.section .bss
.global ram_result
ram_result:
    .skip 1
test_buf:
    .skip TEST_LEN              /* the region this demo exercises */

/* ── Code ─────────────────────────────────────────────────────────────── */
.section .text

isr_default:
    reti

/*
 * ram_march — March C- over [X, X+len).
 *
 * In:   X (r27:r26) = region start (SRAM),  r25:r24 = length in bytes (> 0)
 * Out:  r24 = 0 pass, 1 fail
 * Clobbers: r16, r18, r19, r20..r25, X
 */
.global ram_march
ram_march:
    movw  r20, r26              /* save start  -> r21:r20 */
    movw  r22, r24              /* save length -> r23:r22 */

    ldi   r19, 0x00             /* M0: write 0 ascending */
    rcall fill_asc

    ldi   r18, 0x00             /* M1: up   r0, w1 */
    ldi   r19, 0xFF
    rcall rmw_asc
    brcs  .Lfail

    ldi   r18, 0xFF             /* M2: up   r1, w0 */
    ldi   r19, 0x00
    rcall rmw_asc
    brcs  .Lfail

    ldi   r18, 0x00             /* M3: down r0, w1 */
    ldi   r19, 0xFF
    rcall rmw_desc
    brcs  .Lfail

    ldi   r18, 0xFF             /* M4: down r1, w0 */
    ldi   r19, 0x00
    rcall rmw_desc
    brcs  .Lfail

    ldi   r18, 0x00             /* M5: read 0 ascending */
    rcall check_asc
    brcs  .Lfail

    ldi   r24, 0               /* every element passed */
    ret
.Lfail:
    ldi   r24, 1
    ret

/* fill_asc — write r19 to the whole region, low->high. */
fill_asc:
    movw  r26, r20             /* X = start          */
    movw  r24, r22             /* counter = length    */
.Lfa:
    st    X+, r19
    sbiw  r24, 1
    brne  .Lfa
    ret

/* rmw_asc — low->high: read, expect r18 (C=1 on mismatch), write r19. */
rmw_asc:
    movw  r26, r20
    movw  r24, r22
.Lra:
    ld    r16, X               /* read current cell   */
    cp    r16, r18
    brne  .Lrw_fail
    st    X+, r19              /* write new, advance  */
    sbiw  r24, 1
    brne  .Lra
    clc
    ret

/* rmw_desc — high->low: read, expect r18, write r19. */
rmw_desc:
    movw  r26, r20
    movw  r24, r22
    add   r26, r24             /* X = start + length  */
    adc   r27, r25
    sbiw  r26, 1               /* X = last byte       */
.Lrd:
    ld    r16, X
    cp    r16, r18
    brne  .Lrw_fail
    st    X, r19               /* rewrite same cell   */
    sbiw  r26, 1               /* X--                 */
    sbiw  r24, 1               /* counter--           */
    brne  .Lrd
    clc
    ret

/* shared mismatch exit for the read/modify/write passes */
.Lrw_fail:
    sec
    ret

/* check_asc — low->high: read and expect r18; C=1 on mismatch. */
check_asc:
    movw  r26, r20
    movw  r24, r22
.Lca:
    ld    r16, X+
    cp    r16, r18
    brne  .Lca_fail
    sbiw  r24, 1
    brne  .Lca
    clc
    ret
.Lca_fail:
    sec
    ret

/* ── Demonstration ────────────────────────────────────────────────────── */
.global main
main:
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    /* Test the .bss buffer (not the stack region near RAMEND). */
    ldi   XL, lo8(test_buf)
    ldi   XH, hi8(test_buf)
    ldi   r24, lo8(TEST_LEN)
    ldi   r25, hi8(TEST_LEN)
    rcall ram_march

    sts   ram_result, r24      /* 0 = pass, 1 = fail */

    /* LED0 (PA3) on if the RAM passed. */
    sbi   VPORTA_DIR, LED_BIT
    sbi   VPORTA_OUT, LED_BIT  /* default off (active-low) */
    tst   r24
    brne  .Lhalt               /* fail: leave LED off */
    cbi   VPORTA_OUT, LED_BIT  /* pass: drive PA3 low -> LED on */

.Lhalt:
    rjmp  .Lhalt
