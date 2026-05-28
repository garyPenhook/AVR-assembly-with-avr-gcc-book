/*
 * signed_arith.S — Signed arithmetic, two's complement, sign extension.
 *                  Companion source for Chapter 5b.
 *
 * Demonstrates:
 *   - Signed addition / subtraction with V-flag overflow detection
 *   - NEG, COM, ASR — and where each goes wrong when misused
 *   - Signed comparisons: BRLT/BRGE vs BRLO/BRSH vs BRMI
 *   - Sign extension: 8-bit signed → 16-bit signed (CLR + SBRC + SER)
 *   - Signed saturating add / subtract
 *   - Absolute value with −128 guard
 *
 * Build:
 *   avr-gcc -x assembler-with-cpp -mmcu=attiny3217 -c signed_arith.S -o signed_arith.o
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o signed_arith.elf signed_arith.o
 *   avr-objdump -d signed_arith.elf
 *
 * Assemble and inspect with:
 *   avr-objdump -d signed_arith.elf | less
 */

#include <avr/io.h>

.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    jmp main

.section .text
.global main

main:
    ldi  r16, lo8(RAMEND)
    out  SPL, r16
    ldi  r16, hi8(RAMEND)
    out  SPH, r16

/* ════════════════════════════════════════════════════════════════════════
 * TWO'S COMPLEMENT BASICS
 * ════════════════════════════════════════════════════════════════════════ */

    /* ── Manual two's complement conversion ──────────────────────────────
     * −10 = ~10 + 1 = ~0x0A + 1 = 0xF5 + 1 = 0xF6
     * Verify: 0x0A + 0xF6 = 0x100 → discard carry → 0x00 = 0 ✓         */
    ldi  r16, 10            ; = +10 = 0x0A
    com  r16                ; r16 = ~10 = 0xF5
    inc  r16                ; r16 = 0xF6 = −10 (one's complement + 1)
    ; This is exactly what NEG does in one instruction:
    ldi  r16, 10
    neg  r16                ; r16 = 0xF6 = −10 directly

    /* ── Verify: 10 + (−10) = 0 ─────────────────────────────────────────*/
    ldi  r17, 10            ; r17 = +10
    ldi  r16, 0xF6          ; r16 = −10
    add  r16, r17           ; 0xF6 + 0x0A = 0x100 → r16 = 0x00, C=1, Z=1
    ; C=1 (unsigned carry), but Z=1 confirms the signed result is zero ✓

/* ════════════════════════════════════════════════════════════════════════
 * SIGNED ADDITION — SAME OPCODE AS UNSIGNED, DIFFERENT FLAGS TO WATCH
 * ════════════════════════════════════════════════════════════════════════ */

    /* ── No overflow: +50 + (−20) = +30 ─────────────────────────────────
     * Opposite-sign operands can never cause signed overflow.            */
    ldi  r16, 50            ; = +50
    ldi  r17, 0xEC          ; = −20 (0x100 − 20 = 0xEC)
    add  r16, r17           ; 0x32 + 0xEC = 0x11E → r16 = 0x1E = +30
                            ; C=1 (unsigned carry out — ignored for signed)
                            ; V=0 (no signed overflow)

    /* ── Signed overflow: +100 + +100 = +200 > +127 ─────────────────────
     * Same-sign operands exceed the range; V=1 signals the error.       */
    ldi  r16, 100           ; = +100 = 0x64
    ldi  r17, 100           ; = +100
    add  r16, r17           ; 0x64 + 0x64 = 0xC8 = −56 signed ← WRONG
                            ; C=0, V=1, N=1, S = N⊕V = 0
    brvs overflow_add_pos   ; V=1 → overflow detected → branch
    rjmp overflow_add_done
overflow_add_pos:
overflow_add_done:

    /* ── Signed overflow: (−100) + (−100) = −200 < −128 ─────────────────
     * Negative + negative overflows upward into positive territory.      */
    ldi  r16, 0x9C          ; = −100 (0x100 − 100 = 0x9C)
    ldi  r17, 0x9C          ; = −100
    add  r16, r17           ; 0x9C + 0x9C = 0x138 → r16 = 0x38 = +56 ← WRONG
                            ; C=1, V=1
    brvs overflow_add_neg

overflow_add_neg:

    /* ── +127 + +1 = +128: just past the boundary ───────────────────────*/
    ldi  r16, 0x7F          ; = +127
    ldi  r17, 0x01
    add  r16, r17           ; r16 = 0x80 = −128 signed ← WRONG
                            ; V=1 (overflow), N=1, S = 1⊕1 = 0

/* ════════════════════════════════════════════════════════════════════════
 * NEG — TWO'S COMPLEMENT NEGATE
 * ════════════════════════════════════════════════════════════════════════ */

    ldi  r16, 10
    neg  r16                ; r16 = −10 = 0xF6, C=1, V=0

    ldi  r16, 0xF6          ; = −10
    neg  r16                ; r16 = +10 = 0x0A, C=1, V=0

    ldi  r16, 0             ; = 0
    neg  r16                ; r16 = 0, C=0, Z=1 (NEG 0 = 0, no borrow)

    /* ── The 0x80 corner case ────────────────────────────────────────────
     * −128 has no positive 8-bit counterpart. Result is unchanged, V=1. */
    ldi  r16, 0x80          ; = −128
    neg  r16                ; r16 = 0x80 (unchanged!), V=1, C=1, N=1
    brvs neg_overflow       ; V=1 → handle the overflow case
    rjmp neg_done
neg_overflow:
    ldi  r16, 127           ; saturate: best we can do is +127
neg_done:

/* ════════════════════════════════════════════════════════════════════════
 * ASR vs LSR: SIGNED VS UNSIGNED RIGHT SHIFT (DIVIDE BY 2)
 * ════════════════════════════════════════════════════════════════════════ */

    /* ── Wrong: LSR on a signed negative value ───────────────────────────
     * LSR inserts a 0 at bit 7, turning negative values positive.       */
    ldi  r16, 0xFE          ; = −2 signed
    lsr  r16                ; r16 = 0x7F = +127 ← WRONG for signed ÷2
    ;                                              (0 was inserted at bit7)

    /* ── Correct: ASR on a signed negative value ─────────────────────────
     * ASR copies bit 7, preserving the sign through the shift.          */
    ldi  r16, 0xFE          ; = −2 signed
    asr  r16                ; r16 = 0xFF = −1 ✓  (−2 / 2 = −1)
    ;                                              (1 was copied to bit7)

    ldi  r16, 0xFC          ; = −4 signed
    asr  r16                ; r16 = 0xFE = −2  (−4 / 2 = −2) ✓
    asr  r16                ; r16 = 0xFF = −1  (−2 / 2 = −1) ✓

    /* ── ASR on positive: same as LSR ────────────────────────────────────*/
    ldi  r16, 0x10          ; = +16
    asr  r16                ; r16 = 0x08 = +8  ✓ (0 copied to bit7)

/* ════════════════════════════════════════════════════════════════════════
 * SIGNED COMPARISONS: BRLT/BRGE VS BRLO/BRSH VS BRMI
 * ════════════════════════════════════════════════════════════════════════ */

    /* ── Basic signed compare ─────────────────────────────────────────────
     * −16 vs +16: signed −16 < +16, but unsigned 240 > 16               */
    ldi  r16, 0xF0          ; = −16 signed = 240 unsigned
    ldi  r17, 0x10          ; = +16 signed = 16 unsigned
    cp   r16, r17           ; 0xF0 − 0x10 = 0xE0; C=0, N=1, V=0, S=1

    brlo unsigned_less      ; C=0 → NOT taken (240 > 16 unsigned — correct)
    rjmp past_brlo
unsigned_less:
past_brlo:

    brlt signed_less        ; S=1 → taken (−16 < +16 signed — correct)
    rjmp past_brlt
signed_less:
past_brlt:

    /* ── Overflow case: BRLT correct, BRMI wrong ─────────────────────────
     * r16 = −128 (0x80), r17 = +1 (0x01): CP computes 0x7F, N=0, V=1, S=1*/
    ldi  r16, 0x80          ; = −128
    ldi  r17, 0x01          ; = +1
    cp   r16, r17           ; 0x80 − 0x01 = 0x7F; N=0, V=1, S=N⊕V=1

    brmi brmi_would_fail    ; N=0 → NOT taken (WRONG: −128 < +1!)
    rjmp past_brmi
brmi_would_fail:
past_brmi:

    brlt brlt_correct       ; S=1 → taken (CORRECT: −128 < +1)
    rjmp past_brlt2
brlt_correct:
past_brlt2:

    /* ── Overflow case: BRLT correct, BRMI wrong (other direction) ───────
     * r16 = +127 (0x7F), r17 = −1 (0xFF): −127>-1 should be >=, not <    */
    ldi  r16, 0x7F          ; = +127
    ldi  r17, 0xFF          ; = −1
    cp   r16, r17           ; 0x7F − 0xFF: with borrow → 0x80; N=1, V=1, S=0

    brmi brmi_fail2         ; N=1 → WOULD branch (WRONG: +127 >= −1!)
    rjmp past_brmi2
brmi_fail2:
past_brmi2:

    brlt brlt_skip          ; S=0 → NOT taken (CORRECT: +127 >= −1)
    rjmp geq_path           ; >= path: correct
brlt_skip:
geq_path:

/* ════════════════════════════════════════════════════════════════════════
 * SIGN EXTENSION: 8-BIT SIGNED → 16-BIT SIGNED
 * ════════════════════════════════════════════════════════════════════════ */

    /* ── Positive value: high byte = 0x00 ───────────────────────────────
     * r16 = +5 (0x05) → r17:r16 = 0x0005                                */
    ldi  r16, 0x05          ; = +5
    clr  r17                ; assume non-negative: r17 = 0x00
    sbrc r16, 7             ; bit 7 of 0x05 = 0 → SKIP ser r17
    ser  r17                ; (not reached for +5)
    ; r17:r16 = 0x0005 = +5 ✓

    /* ── Negative value: high byte = 0xFF ───────────────────────────────
     * r16 = −1 (0xFF) → r17:r16 = 0xFFFF                                */
    ldi  r16, 0xFF          ; = −1
    clr  r17
    sbrc r16, 7             ; bit 7 of 0xFF = 1 → do NOT skip
    ser  r17                ; r17 = 0xFF
    ; r17:r16 = 0xFFFF = −1 ✓

    /* ── Most negative: 0x80 (−128) → 0xFF80 ────────────────────────────*/
    ldi  r16, 0x80          ; = −128
    clr  r17
    sbrc r16, 7             ; bit 7 = 1 → do NOT skip
    ser  r17                ; r17 = 0xFF
    ; r17:r16 = 0xFF80 = −128 ✓

    /* ── Max positive: 0x7F (+127) → 0x007F ─────────────────────────────*/
    ldi  r16, 0x7F          ; = +127
    clr  r17
    sbrc r16, 7             ; bit 7 = 0 → SKIP
    ser  r17
    ; r17:r16 = 0x007F = +127 ✓

    /* ── WRONG — zero extension of signed value (for comparison) ─────────
     * This is the mistake to avoid:                                      */
    ldi  r16, 0xFF          ; = −1
    clr  r17                ; zero-extend ← WRONG for signed
    ; r17:r16 = 0x00FF = +255 ← mathematically incorrect sign-extended value

/* ════════════════════════════════════════════════════════════════════════
 * SIGNED ARITHMETIC AFTER SIGN EXTENSION
 * ════════════════════════════════════════════════════════════════════════ */

    /* ── (−10) + (−20) using 8-bit values sign-extended to 16-bit ────────
     * Expected: r25:r24 = 0xFFE2 = −30                                  */

    ; sign-extend r16 = −10 into r17:r16
    ldi  r16, 0xF6          ; = −10
    clr  r17
    sbrc r16, 7
    ser  r17                ; r17:r16 = 0xFFF6 = −10

    ; sign-extend r18 = −20 into r19:r18
    ldi  r18, 0xEC          ; = −20
    clr  r19
    sbrc r18, 7
    ser  r19                ; r19:r18 = 0xFFEC = −20

    ; 16-bit signed add
    add  r16, r18
    adc  r17, r19           ; r17:r16 = 0xFFF6 + 0xFFEC = 0x1FFE2 → 0xFFE2 = −30 ✓
                            ; C=1 (unsigned carry — ignored), V=0 (no signed overflow)
    movw r24, r16           ; result to r25:r24

/* ════════════════════════════════════════════════════════════════════════
 * SUBROUTINE CALLS — practical examples
 * ════════════════════════════════════════════════════════════════════════ */

    /* ── Saturating signed add: +100 + +50 → should clamp to +127 ───────*/
    ldi  r16, 100
    ldi  r17, 50
    rcall sat8_sadd

    /* ── Saturating signed add: (−100) + (−50) → should clamp to −128 ──*/
    ldi  r16, 0x9C          ; = −100
    ldi  r17, 0xCE          ; = −50
    rcall sat8_sadd

    /* ── Absolute value of −40 → +40 ────────────────────────────────────*/
    ldi  r16, 0xD8          ; = −40
    rcall abs8_safe         ; r16 = +40

    /* ── Absolute value of −128 → saturates to +127 ─────────────────────*/
    ldi  r16, 0x80          ; = −128
    rcall abs8_safe         ; r16 = +127

    /* ── Sign extension into 16-bit accumulator ──────────────────────────
     * Accumulate three signed readings: +50 + (−30) + +20 = +40         */
    clr  r24
    clr  r25                ; r25:r24 = 0 (accumulator)
    ldi  r16, 50
    rcall accum_signed      ; r25:r24 = +50
    ldi  r16, 0xE2          ; = −30
    rcall accum_signed      ; r25:r24 = +20
    ldi  r16, 20
    rcall accum_signed      ; r25:r24 = +40 = 0x0028

halt:
    rjmp halt

/* ════════════════════════════════════════════════════════════════════════
 * SUBROUTINES
 * ════════════════════════════════════════════════════════════════════════ */

/*
 * sat8_sadd — saturating signed 8-bit add
 *   Input:  r16 = a (signed), r17 = b (signed)
 *   Output: r16 = clamp(a + b, −128, +127)
 *   Clobbers: r18
 */
sat8_sadd:
    mov   r18, r17          ; save copy of addend (need its sign after add)
    add   r16, r18
    brvc  sat8_sadd_ok      ; V=0: no overflow, result is correct
    ; V=1: overflow occurred — direction from sign of saved addend
    sbrs  r18, 7            ; if bit 7 of r18 is set (addend was negative): skip
    ldi   r16, 0x7F         ; addend positive → both positive overflowed → clamp +127
    brvc  sat8_sadd_ok      ; (trick: use branch to skip the negative clamp)
    ldi   r16, 0x80         ; addend negative → both negative overflowed → clamp −128
sat8_sadd_ok:
    ret

/*
 * sat8_ssub — saturating signed 8-bit subtract
 *   Input:  r16 = a (signed), r17 = b (signed)
 *   Output: r16 = clamp(a − b, −128, +127)
 *   Clobbers: r18
 */
sat8_ssub:
    mov   r18, r17
    sub   r16, r18
    brvc  sat8_ssub_ok
    sbrs  r18, 7            ; if subtrahend was negative: skip
    ldi   r16, 0x80         ; subtrahend positive: result went below −128
    brvc  sat8_ssub_ok
    ldi   r16, 0x7F         ; subtrahend negative: result went above +127
sat8_ssub_ok:
    ret

/*
 * abs8_safe — signed absolute value with −128 guard
 *   Input:  r16 = signed 8-bit value (−128..+127)
 *   Output: r16 = |r16|, saturated to +127 if input was −128
 */
abs8_safe:
    sbrc  r16, 7            ; bit 7 clear (non-negative) → skip branch
    rjmp  abs8_do_neg
    ret
abs8_do_neg:
    cpi   r16, 0x80         ; is it −128?
    brne  abs8_simple
    ldi   r16, 127          ; −128 has no exact positive form: return 127
    ret
abs8_simple:
    neg   r16
    ret

/*
 * sext8to16 — sign-extend r16 (8-bit signed) into r17:r16 (16-bit signed)
 *   Input:  r16 = 8-bit signed value
 *   Output: r17:r16 = 16-bit signed value with identical mathematical value
 *   Clobbers: r17
 */
sext8to16:
    clr   r17
    sbrc  r16, 7
    ser   r17
    ret

/*
 * accum_signed — sign-extend r16 and add to r25:r24
 *   Input:  r16 = signed 8-bit sample, r25:r24 = running signed 16-bit sum
 *   Output: r25:r24 updated
 *   Clobbers: r16, r17
 *   Note: does not saturate — V=1 after call if 16-bit signed overflow.
 */
accum_signed:
    clr   r17
    sbrc  r16, 7            ; sign-extend r16 into r17:r16
    ser   r17
    add   r24, r16
    adc   r25, r17
    ret

/*
 * cmp_s8 — signed three-way compare
 *   Input:  r16 = a (signed), r17 = b (signed)
 *   Output: r18 = −1 (0xFF) if a < b, 0 if a == b, +1 (0x01) if a > b
 */
cmp_s8:
    cp    r16, r17
    breq  cmp_s8_equal
    brlt  cmp_s8_less
    ldi   r18, 1            ; a > b
    ret
cmp_s8_equal:
    clr   r18               ; a == b
    ret
cmp_s8_less:
    ldi   r18, 0xFF         ; a < b (= −1 signed)
    ret

/*
 * signed_dispatch — branch on sign of r16 (signed 8-bit)
 *   Uses TST to set flags cleanly (V is cleared so BRMI == BRLT after TST)
 *   Caller's r16 is unchanged.
 */
signed_dispatch_example:
    tst   r16               ; sets N and Z; clears V; C unchanged
    breq  disp_zero
    brmi  disp_neg
    ; fall through: positive
    rjmp  disp_pos_done
disp_zero:
    rjmp  disp_done
disp_neg:
    rjmp  disp_done
disp_pos_done:
disp_done:
    ret

/*
 * signed_min — return smaller of two signed 8-bit values
 *   Input:  r16 = a, r17 = b (both signed)
 *   Output: r16 = min(a, b)
 */
signed_min:
    cp    r16, r17
    brlt  smin_done         ; r16 < r17 (signed) → r16 is already the min
    mov   r16, r17          ; r16 >= r17 → r17 is the min
smin_done:
    ret
