/*
 * unsigned_arith.S — Unsigned integer arithmetic on 8-bit and 16-bit registers.
 *                    Companion source for Chapter 5a.
 *
 * Covers:
 *   8-bit:  ADD, SUBI (add via negate), INC, SUB, DEC, saturate, compare
 *   16-bit: ADD+ADC, ADIW, SUBI+SBCI, SUB+SBC, SBIW, CP+CPC, MOVW
 *
 * Build:
 *   avr-gcc -x assembler-with-cpp -mmcu=attiny3217 -c unsigned_arith.S -o unsigned_arith.o
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o unsigned_arith.elf unsigned_arith.o
 *   avr-objdump -d unsigned_arith.elf
 *
 * Run each section through avr-objdump to verify encodings and trace values.
 */

#include <avr/io.h>

.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    jmp main

.section .text
.global main

main:
    /* Stack pointer initialisation */
    ldi  r16, lo8(RAMEND)
    out  SPL, r16
    ldi  r16, hi8(RAMEND)
    out  SPH, r16

/* ════════════════════════════════════════════════════════════════════════
 * 8-BIT UNSIGNED ADDITION
 * ════════════════════════════════════════════════════════════════════════ */

    /* ── Basic ADD ───────────────────────────────────────────────────────
     * 100 + 50 = 150, no overflow                                       */
    ldi  r16, 100
    ldi  r17, 50
    add  r16, r17           ; r16 = 150, C=0, Z=0

    /* ── ADD with unsigned overflow ──────────────────────────────────────
     * 200 + 100 = 300, wraps to 44, C=1                                 */
    ldi  r16, 200
    ldi  r17, 100
    add  r16, r17           ; r16 = 44 (300-256), C=1

    /* ── SUBI to add an immediate (no ADDI instruction exists) ──────────
     * r16 += 10: subtract the two's-complement negation of 10           */
    ldi  r16, 50
    subi r16, -10           ; r16 = 60  (subtract -10 = add 10)

    /* ── INC — note: does NOT update the carry flag ──────────────────────
     * Use INC only for simple counters. Never feed its carry into ADC.  */
    ldi  r16, 0xFF          ; 255
    inc  r16                ; r16 = 0, Z=1, but C is unchanged (not set)

/* ════════════════════════════════════════════════════════════════════════
 * 8-BIT UNSIGNED SUBTRACTION
 * ════════════════════════════════════════════════════════════════════════ */

    /* ── Basic SUB, no borrow ────────────────────────────────────────────
     * 100 - 40 = 60                                                      */
    ldi  r16, 100
    ldi  r17, 40
    sub  r16, r17           ; r16 = 60, C=0

    /* ── SUB with unsigned underflow (borrow) ────────────────────────────
     * 10 - 30 = -20, wraps to 236 (256-20), C=1                         */
    ldi  r16, 10
    ldi  r17, 30
    sub  r16, r17           ; r16 = 236 (0xEC), C=1

    /* ── SUBI — subtract immediate ───────────────────────────────────────
     * r16 -= 25                                                          */
    ldi  r16, 100
    subi r16, 25            ; r16 = 75

    /* ── DEC — also does NOT update carry ───────────────────────────────
     * Good for loop counters checked with BREQ/BRNE (reads Z, not C).  */
    ldi  r20, 5
dec_loop:
    dec  r20
    brne dec_loop           ; Z=1 when r20 reaches 0 → loop exits

/* ════════════════════════════════════════════════════════════════════════
 * SATURATING 8-BIT ARITHMETIC
 * ════════════════════════════════════════════════════════════════════════ */

    /* ── Saturating add: result = min(r16 + r17, 255) ───────────────────
     * Input: r16=200, r17=100 → should clamp to 255                     */
    ldi  r16, 200
    ldi  r17, 100
    add  r16, r17           ; 300 → r16=44, C=1
    brcc sat_add_ok         ; C=0 → no overflow, skip clamp
    ser  r16                ; C=1 → clamp to 0xFF = 255
sat_add_ok:
    ; r16 = 255 (clamped)

    /* ── Saturating subtract: result = max(r16 - r17, 0) ───────────────
     * Input: r16=10, r17=30 → should clamp to 0                         */
    ldi  r16, 10
    ldi  r17, 30
    sub  r16, r17           ; 10-30 → underflow, C=1
    brcc sat_sub_ok         ; C=0 → no borrow, result is valid
    clr  r16                ; C=1 → clamp to 0
sat_sub_ok:
    ; r16 = 0 (clamped)

/* ════════════════════════════════════════════════════════════════════════
 * 8-BIT UNSIGNED COMPARISON AND BRANCHING
 * ════════════════════════════════════════════════════════════════════════ */

    /* ── CP / CPI ────────────────────────────────────────────────────────
     * Compare without storing result. Then branch unsigned.              */
    ldi  r16, 42
    ldi  r17, 100
    cp   r16, r17           ; 42 - 100 → C=1 (borrow: 42 < 100)
    brlo r16_is_less        ; taken: 42 < 100 unsigned
    rjmp compare_done
r16_is_less:
compare_done:

    /* ── CPI — compare with immediate ────────────────────────────────────
     * Is r16 in [30..80]?                                                */
    ldi  r16, 55            ; test value
    cpi  r16, 30
    brlo range_fail         ; r16 < 30 → out of range
    cpi  r16, 81            ; hi+1 = 81
    brsh range_fail         ; r16 >= 81 → out of range
    ; in range [30..80]
    rjmp range_ok
range_fail:
range_ok:

    /* ── CPSE — compare and skip if equal ───────────────────────────────
     * Skip the RJMP when r16 == r17.                                    */
    ldi  r16, 50
    ldi  r17, 50
    cpse r16, r17           ; equal → skip next instruction
    rjmp not_equal_cpse     ; skipped when equal
    ; equal path
    rjmp cpse_done
not_equal_cpse:
cpse_done:

/* ════════════════════════════════════════════════════════════════════════
 * 16-BIT REGISTER PAIRS AND MOVW
 * ════════════════════════════════════════════════════════════════════════ */

    /* ── Load 16-bit constant into r25:r24 ──────────────────────────────
     * r25:r24 = 1000 (0x03E8)                                            */
    ldi  r24, lo8(1000)     ; r24 = 0xE8
    ldi  r25, hi8(1000)     ; r25 = 0x03

    /* ── MOVW — copy pair in one instruction ─────────────────────────────
     * r23:r22 = r25:r24                                                  */
    movw r22, r24           ; r23:r22 = r25:r24 = 1000

/* ════════════════════════════════════════════════════════════════════════
 * 16-BIT UNSIGNED ADDITION
 * ════════════════════════════════════════════════════════════════════════ */

    /* ── ADD + ADC carry chain ───────────────────────────────────────────
     * r25:r24 = 500 + 700 = 1200 (0x04B0)
     * Trace: 0xF4 + 0xBC = 0x1B0 → low=0xB0 C=1
     *        0x01 + 0x02 + 1  = 0x04 → high=0x04 C=0               */
    ldi  r24, lo8(500)      ; r24 = 0xF4
    ldi  r25, hi8(500)      ; r25 = 0x01
    ldi  r22, lo8(700)      ; r22 = 0xBC
    ldi  r23, hi8(700)      ; r23 = 0x02
    add  r24, r22           ; low bytes FIRST — may produce carry
    adc  r25, r23           ; high bytes — includes carry from ADD

    /* ── ADD + ADC with 16-bit overflow ─────────────────────────────────
     * 60000 + 10000 = 70000 > 65535 → wraps, C=1                       */
    ldi  r24, lo8(60000)
    ldi  r25, hi8(60000)
    ldi  r22, lo8(10000)
    ldi  r23, hi8(10000)
    add  r24, r22
    adc  r25, r23           ; C=1 → 16-bit overflow
    brcs overflow_16_add
    rjmp add16_done
overflow_16_add:
add16_done:

    /* ── ADIW — add immediate 0..63 to a supported pair ─────────────────
     * r25:r24 += 16  (2 cycles)                                         */
    ldi  r24, lo8(1000)
    ldi  r25, hi8(1000)
    adiw r24, 16            ; r25:r24 = 1016

    /* ── ADIW on pointer registers ───────────────────────────────────────
     * Advance X pointer by 4                                             */
    ldi  r26, lo8(0x3800)   ; XL
    ldi  r27, hi8(0x3800)   ; XH
    adiw XL, 4              ; X += 4 → X = 0x3804

    /* ── SUBI + SBCI — add large constant to r16-r31 pair ───────────────
     * r25:r24 += 1000   (1000 > 63, can't use ADIW)
     * -1000 in 16-bit = 0xFC18: lo8=0x18, hi8=0xFC                    */
    ldi  r24, lo8(2000)
    ldi  r25, hi8(2000)
    subi r24, lo8(-1000)    ; r24 -= lo8(0xFC18) = subtract 0x18 = add 0xE8
    sbci r25, hi8(-1000)    ; r25 -= hi8(0xFC18) + borrow = add 0x03+carry
    ; r25:r24 = 3000

    /* ── ADD + ADC with zero-extended 8-bit operand ──────────────────────
     * Add small unsigned 8-bit value (r16) to 16-bit pair (r25:r24).
     * Must zero-extend r16 first.                                        */
    ldi  r24, lo8(65000)
    ldi  r25, hi8(65000)
    ldi  r16, 100           ; 8-bit addend
    clr  r17                ; zero-extend: r17:r16 = 0:100
    add  r24, r16
    adc  r25, r17           ; correctly propagates carry

/* ════════════════════════════════════════════════════════════════════════
 * 16-BIT UNSIGNED SUBTRACTION
 * ════════════════════════════════════════════════════════════════════════ */

    /* ── SUB + SBC borrow chain ──────────────────────────────────────────
     * r25:r24 = 1200 - 700 = 500 (0x01F4)
     * Trace: 0xB0 - 0xBC → borrow: r24=0xF4 C=1
     *        0x04 - 0x02 - 1(C) = 0x01 → r25=0x01 C=0              */
    ldi  r24, lo8(1200)     ; r24 = 0xB0
    ldi  r25, hi8(1200)     ; r25 = 0x04
    ldi  r22, lo8(700)      ; r22 = 0xBC
    ldi  r23, hi8(700)      ; r23 = 0x02
    sub  r24, r22           ; low bytes first
    sbc  r25, r23           ; high bytes — includes borrow from SUB

    /* ── SUB + SBC with underflow ────────────────────────────────────────
     * r25:r24 = 300 - 500 → underflow, C=1                              */
    ldi  r24, lo8(300)
    ldi  r25, hi8(300)
    ldi  r22, lo8(500)
    ldi  r23, hi8(500)
    sub  r24, r22
    sbc  r25, r23           ; C=1 → 16-bit underflow
    brcs underflow_16_sub
    rjmp sub16_done
underflow_16_sub:
sub16_done:

    /* ── SBIW — subtract immediate 0..63 ─────────────────────────────────
     * r25:r24 -= 1  (2 cycles)                                          */
    ldi  r24, lo8(1000)
    ldi  r25, hi8(1000)
    sbiw r24, 1             ; r25:r24 = 999

    /* ── SBIW loop: count 100 down to 0 ─────────────────────────────────
     * BRNE reads Z, which SBIW sets correctly for the full 16-bit pair. */
    ldi  r24, lo8(100)
    ldi  r25, hi8(100)
sbiw_loop:
    sbiw r24, 1
    brne sbiw_loop          ; Z=1 when r25:r24 == 0 → exit

    /* ── SUBI + SBCI — subtract large immediate ──────────────────────────
     * r25:r24 -= 300  (lo8(300)=0x2C, hi8(300)=0x01)                  */
    ldi  r24, lo8(1000)
    ldi  r25, hi8(1000)
    subi r24, lo8(300)      ; r24 -= 0x2C
    sbci r25, hi8(300)      ; r25 -= 0x01 + borrow
    ; r25:r24 = 700

/* ════════════════════════════════════════════════════════════════════════
 * 16-BIT UNSIGNED COMPARISON
 * ════════════════════════════════════════════════════════════════════════ */

    /* ── CP + CPC chain ─────────────────────────────────────────────────
     * Compare r25:r24 (500) with r23:r22 (700): 500 < 700 → BRLO taken  */
    ldi  r24, lo8(500)
    ldi  r25, hi8(500)
    ldi  r22, lo8(700)
    ldi  r23, hi8(700)
    cp   r24, r22           ; compare low bytes
    cpc  r25, r23           ; compare high bytes + borrow
    brlo pair_less          ; C=1 → r25:r24 < r23:r22 (unsigned)
    rjmp cmp16_done
pair_less:
cmp16_done:

    /* ── 16-bit range check: is r25:r24 in [100, 5000]? ─────────────────
     * (1500 should pass)                                                 */
    ldi  r24, lo8(1500)
    ldi  r25, hi8(1500)

    ldi  r22, lo8(100)
    ldi  r23, hi8(100)
    cp   r24, r22
    cpc  r25, r23
    brlo out_of_range16     ; r25:r24 < 100

    ldi  r22, lo8(5001)     ; hi+1
    ldi  r23, hi8(5001)
    cp   r24, r22
    cpc  r25, r23
    brsh out_of_range16     ; r25:r24 >= 5001
    ; in range [100, 5000]
    rjmp in_range16
out_of_range16:
in_range16:

/* ════════════════════════════════════════════════════════════════════════
 * PRACTICAL EXAMPLES — subroutine calls
 * ════════════════════════════════════════════════════════════════════════ */

    /* ── Saturating 16-bit add ───────────────────────────────────────────
     * sat16_add(60000, 10000): should clamp to 65535                    */
    ldi  r24, lo8(60000)
    ldi  r25, hi8(60000)
    ldi  r22, lo8(10000)
    ldi  r23, hi8(10000)
    rcall sat16_add         ; r25:r24 = 65535 (0xFFFF)

    /* ── 8-bit counter with rollover detection ───────────────────────────
     * Call count_step 10× and observe that rollover fires at count=0   */
    clr  r16                ; counter = 0
    rcall count_step
    rcall count_step

halt:
    rjmp halt

/* ════════════════════════════════════════════════════════════════════════
 * SUBROUTINES
 * ════════════════════════════════════════════════════════════════════════ */

/*
 * sat16_add — saturating 16-bit unsigned add
 *   Input:  r25:r24 = a, r23:r22 = b
 *   Output: r25:r24 = min(a + b, 65535)
 *   Clobbers: nothing besides r25:r24
 */
sat16_add:
    add  r24, r22
    adc  r25, r23
    brcc sat16_add_done     ; C=0 → result fits in 16 bits
    ser  r24                ; C=1 → clamp: r25:r24 = 0xFFFF
    ser  r25
sat16_add_done:
    ret

/*
 * sat16_sub — saturating 16-bit unsigned subtract
 *   Input:  r25:r24 = a, r23:r22 = b
 *   Output: r25:r24 = max(a - b, 0)
 *   Clobbers: nothing besides r25:r24
 */
sat16_sub:
    sub  r24, r22
    sbc  r25, r23
    brcc sat16_sub_done     ; C=0 → result is non-negative
    clr  r24                ; C=1 → underflow: clamp to 0
    clr  r25
sat16_sub_done:
    ret

/*
 * count_step — advance an 8-bit counter, set Z=1 on rollover (255→0)
 *   Input:  r16 = counter
 *   Output: r16 = counter + 1 (mod 256); SREG Z=1 if rollover occurred
 *   Clobbers: nothing
 */
count_step:
    inc  r16                ; r16++; Z=1 if wrapped 255→0
    ret
    ; Caller checks: breq rollover_handler

/*
 * add8u_sat — saturating 8-bit unsigned add
 *   Input:  r16 = a, r17 = b
 *   Output: r16 = min(a + b, 255)
 */
add8u_sat:
    add  r16, r17
    brcc add8u_sat_done
    ser  r16
add8u_sat_done:
    ret

/*
 * sub8u_sat — saturating 8-bit unsigned subtract
 *   Input:  r16 = a, r17 = b
 *   Output: r16 = max(a - b, 0)
 */
sub8u_sat:
    sub  r16, r17
    brcc sub8u_sat_done
    clr  r16
sub8u_sat_done:
    ret

/*
 * in_range8u — 8-bit unsigned range check [lo, hi]
 *   Input:  r16 = value, r17 = lo, r18 = hi
 *   Output: Z=1 if lo <= value <= hi (unsigned), Z=0 otherwise
 *   Clobbers: r17, r18
 */
in_range8u:
    cp   r16, r17           ; value < lo?
    brlo range8_fail
    cp   r18, r16           ; hi < value? (equivalently: value > hi)
    brlo range8_fail
    ; In range: set Z=1 by comparing a register to itself
    cp   r16, r16           ; Z=1 (always equal)
    ret
range8_fail:
    ; Out of range: clear Z by comparing 0 to 1
    ldi  r17, 1
    cp   r1, r17            ; 0 != 1 → Z=0
    ret

/*
 * zero_extend_add — add 8-bit unsigned r16 to 16-bit r25:r24
 *   Input:  r25:r24 = accumulator, r16 = byte to add
 *   Output: r25:r24 = accumulator + r16 (saturated to 0xFFFF)
 *   Clobbers: r17
 */
zero_extend_add:
    clr  r17                ; zero-extend r16 → r17:r16 = 0:byte
    add  r24, r16
    adc  r25, r17           ; properly propagates carry from low byte
    brcc zero_extend_done
    ser  r24                ; saturate
    ser  r25
zero_extend_done:
    ret
