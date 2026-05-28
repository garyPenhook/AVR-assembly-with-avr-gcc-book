/* filters.S — Integer filter library for AVR assembly (ATtiny3217)
 *              Companion source for Chapter 20A: Integer Filters for ADC and Control
 *
 * Each routine maps directly to a section in the chapter:
 *   ema16_k4 / ema24_k8  — "EMA Low-Pass Filter": acc += (new - acc) >> k
 *   box8_update          — "Box (Moving Average) Filter": circular buffer + sum
 *   med3_update          — "Median Filter": 3-element compare-and-swap network
 *   ema2_k5_update       — "Cascaded EMA": two EMA stages for steeper roll-off
 *   pid_compute_P/I/D    — "PID Control": proportional, integral, derivative terms
 *   pid_clamp_I          — "Anti-Windup": clamp integral accumulator to prevent saturation
 *
 * Fixed-point convention: all filter values are Q8.8 or Q16.8 unless noted.
 *
 * Contains buildable implementations of:
 *   ema16_k4      EMA low-pass, 16-bit accumulator, alpha = 1/16
 *   ema24_k8      EMA low-pass, 24-bit accumulator, alpha = 1/256
 *   box8_update   8-sample box filter with circular buffer
 *   med3_update   3-sample median filter (compare-and-swap network)
 *   ema2_k5_update  Two cascaded EMA stages, k=5 each
 *   pid_compute_P   PID proportional term
 *   pid_compute_I   PID integral term (32-bit accumulator)
 *   pid_compute_D   PID derivative term (first-difference)
 *   pid_clamp_I     Anti-windup clamp on integral accumulator
 *
 * This file builds to an inspection ELF only — it is not a complete firmware
 * image and must not be flashed directly (no reset vector or stack init).
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -nodefaultlibs \
 *           -Wl,-r -o filters.elf src/filters.S
 *   avr-objdump -d filters.elf
 */

#include <avr/io.h>

/* ── SRAM Variables ──────────────────────────────────────────────────────── */
.section .bss

/* EMA 16-bit (k=4) */
ema_accum:      .byte 0, 0

/* EMA 24-bit (k=8) */
ema_accum24:    .byte 0, 0, 0

/* Box filter N=8 */
box_buf:        .fill 16, 1, 0   /* 8 × 2-byte entries                           */
box_sum:        .byte 0, 0
box_idx:        .byte 0

/* Median filter (3-sample) */
med_hist:       .byte 0, 0, 0, 0 /* two 16-bit samples: oldest at +0, prev at +2 */

/* Cascaded EMA (two stages, k=5 each) */
ema2_accum0:    .byte 0, 0
ema2_accum1:    .byte 0, 0

/* PID state */
pid_I_accum:    .byte 0, 0, 0, 0 /* 32-bit signed integral accumulator           */
pid_y_prev:     .byte 0, 0       /* previous output sample for D term            */
pid_I_min:      .byte 0, 0, 0, 0 /* anti-windup lower clamp                      */
pid_I_max:      .byte 0, 0, 0, 0 /* anti-windup upper clamp                      */

/* ── Code ────────────────────────────────────────────────────────────────── */
.section .text

/* ── ema16_k4 ────────────────────────────────────────────────────────────── */
/*
 * EMA low-pass, alpha = 1/16 (k=4), 16-bit accumulator
 *
 * fc ≈ fs / 101  (e.g., 9.9 Hz at 1000 Hz sample rate)
 * Valid for 10-bit ADC: accum_max = 1023 × 16 = 16368 < 65536
 *
 * Entry: R25:R24 = new sample (unsigned, 0..1023)
 * Exit:  R25:R24 = filtered output (unsigned, 0..1023)
 * Clobbers: R16, R17, R18, R19
 */
ema16_k4:
    lds   r18, ema_accum
    lds   r19, ema_accum+1

    /* shift = accum >> 4 */
    movw  r16, r18
    lsr   r17
    ror   r16
    lsr   r17
    ror   r16
    lsr   r17
    ror   r16
    lsr   r17
    ror   r16                    /* r17:r16 = accum >> 4                         */

    /* accum = accum - shift + sample */
    sub   r18, r16
    sbc   r19, r17
    add   r18, r24
    adc   r19, r25

    sts   ema_accum,   r18
    sts   ema_accum+1, r19

    /* output = accum >> 4 */
    movw  r24, r18
    lsr   r25
    ror   r24
    lsr   r25
    ror   r24
    lsr   r25
    ror   r24
    lsr   r25
    ror   r24
    ret

/* ── ema24_k8 ────────────────────────────────────────────────────────────── */
/*
 * EMA low-pass, alpha = 1/256 (k=8), 24-bit accumulator
 *
 * fc ≈ fs / 1608  (e.g., 0.62 Hz at 1000 Hz sample rate)
 * Valid for 10-bit ADC: accum_max = 1023 × 256 = 261888 < 16777216
 *
 * Shift by 8 is a byte-move, so no bit-level shifting is needed.
 *
 * Entry: R25:R24 = new sample (unsigned, 0..1023)
 * Exit:  R25:R24 = filtered output (unsigned, 0..1023)
 * Clobbers: R19, R20, R21
 */
ema24_k8:
    lds   r19, ema_accum24       /* b0 (low)    */
    lds   r20, ema_accum24+1     /* b1 (mid)    */
    lds   r21, ema_accum24+2     /* b2 (high)   */

    /* accum - (accum >> 8):
     * accum >> 8 has bytes {0, b2, b1}.
     * Subtract: b0-b1, b1-b2-C, b2-0-C                                         */
    sub   r19, r20
    sbc   r20, r21
    sbc   r21, r1                /* r1 = 0 (zero register)                       */

    /* accum += sample */
    add   r19, r24
    adc   r20, r25
    adc   r21, r1

    sts   ema_accum24,   r19
    sts   ema_accum24+1, r20
    sts   ema_accum24+2, r21

    /* output = accum >> 8 = {b2, b1} = {r21, r20} in r25:r24 */
    movw  r24, r20               /* r24 = r20 (mid), r25 = r21 (high)            */
    ret

/* ── box8_update ─────────────────────────────────────────────────────────── */
/*
 * 8-sample box filter (sliding window average, N=8)
 *
 * Entry: R25:R24 = new sample (unsigned, 0..1023)
 * Exit:  R25:R24 = average of 8 most recent samples (unsigned, 0..1023)
 * Clobbers: R16, R17, R18, R19, R30, R31 (Z)
 */
box8_update:
    lds   r16, box_idx           /* current write index (0..7)                   */

    /* Z = &box_buf[idx]: byte offset = idx × 2 */
    ldi   ZL, lo8(box_buf)
    ldi   ZH, hi8(box_buf)
    mov   r17, r16
    lsl   r17                    /* r17 = idx × 2                               */
    add   ZL, r17
    adc   ZH, r1

    /* Read old sample */
    ld    r18, Z+                /* r18 = old_lo; Z advances to high byte        */
    ld    r19, Z                 /* r19 = old_hi                                 */

    /* Write new sample */
    st    Z,  r25                /* new_hi at high-byte slot                     */
    st   -Z,  r24                /* pre-decrement; new_lo at low-byte slot       */

    /* Update running sum */
    lds   r30, box_sum
    lds   r31, box_sum+1
    add   r30, r24
    adc   r31, r25
    sub   r30, r18
    sbc   r31, r19
    sts   box_sum,   r30
    sts   box_sum+1, r31

    /* Advance and wrap index */
    inc   r16
    andi  r16, 0x07
    sts   box_idx, r16

    /* Output = sum >> 3 */
    movw  r24, r30
    lsr   r25
    ror   r24
    lsr   r25
    ror   r24
    lsr   r25
    ror   r24
    ret

/* ── med3_update ─────────────────────────────────────────────────────────── */
/*
 * 3-sample median filter using a compare-and-swap sorting network.
 *
 * Isolates spike-like noise without smoothing the underlying signal.
 * The 3-swap network guarantees a ≤ b ≤ c; median = b.
 *
 * Entry: R25:R24 = newest sample (unsigned, 0..1023)
 * Exit:  R25:R24 = median of last 3 samples
 * Clobbers: R18, R19, R20, R21, R22, R23
 */
med3_update:
    /* Load history */
    lds   r22, med_hist          /* a_lo (oldest)                                */
    lds   r23, med_hist+1        /* a_hi                                         */
    lds   r20, med_hist+2        /* b_lo (one before newest)                     */
    lds   r21, med_hist+3        /* b_hi                                         */

    /* Shift history forward */
    sts   med_hist,   r20
    sts   med_hist+1, r21        /* oldest ← previous                            */
    sts   med_hist+2, r24
    sts   med_hist+3, r25        /* previous ← new                               */

    /* c = new sample in r25:r24 */

    /* Sorting network: COMPARE_SWAP = (cp+cpc; brlo skip; movw×3)
     * Swap when a >= b (brlo branches when a < b = no swap needed).
     * Swapping equal values is harmless and saves one extra branch.          */

    /* Step 1: COMPARE_SWAP(a, b) */
    cp    r22, r20
    cpc   r23, r21
    brlo  .Lmed3_step2
    movw  r18, r22
    movw  r22, r20
    movw  r20, r18
.Lmed3_step2:
    /* Step 2: COMPARE_SWAP(b, c) */
    cp    r20, r24
    cpc   r21, r25
    brlo  .Lmed3_step3
    movw  r18, r20
    movw  r20, r24
    movw  r24, r18
.Lmed3_step3:
    /* Step 3: COMPARE_SWAP(a, b) */
    cp    r22, r20
    cpc   r23, r21
    brlo  .Lmed3_done
    movw  r18, r22
    movw  r22, r20
    movw  r20, r18
.Lmed3_done:
    /* Median is b, held in r21:r20 */
    movw  r24, r20
    ret

/* ── ema2_k5_update ──────────────────────────────────────────────────────── */
/*
 * Two cascaded EMA stages, k=5 each.  Second-order low-pass response.
 *
 * Single-stage k=5: fc ≈ fs / (32 × 2π) ≈ fs / 201
 * Cascaded (2 stages): effective rolloff ≈ 40 dB/decade above fc
 *
 * Entry: R25:R24 = new sample (unsigned, 0..1023)
 * Exit:  R25:R24 = filtered output
 * Clobbers: R16, R17, R18, R19
 */
ema2_k5_update:
    /* ── Stage 1 ──────────────────────────────────────────────────── */
    lds   r18, ema2_accum0
    lds   r19, ema2_accum0+1

    movw  r16, r18
    lsr   r17
    ror   r16
    lsr   r17
    ror   r16
    lsr   r17
    ror   r16
    lsr   r17
    ror   r16
    lsr   r17
    ror   r16                    /* r17:r16 = accum0 >> 5                        */

    sub   r18, r16
    sbc   r19, r17
    add   r18, r24
    adc   r19, r25

    sts   ema2_accum0,   r18
    sts   ema2_accum0+1, r19

    /* Stage 1 output → r25:r24 = accum0 >> 5 */
    movw  r24, r18
    lsr   r25
    ror   r24
    lsr   r25
    ror   r24
    lsr   r25
    ror   r24
    lsr   r25
    ror   r24
    lsr   r25
    ror   r24

    /* ── Stage 2 ──────────────────────────────────────────────────── */
    lds   r18, ema2_accum1
    lds   r19, ema2_accum1+1

    movw  r16, r18
    lsr   r17
    ror   r16
    lsr   r17
    ror   r16
    lsr   r17
    ror   r16
    lsr   r17
    ror   r16
    lsr   r17
    ror   r16                    /* r17:r16 = accum1 >> 5                        */

    sub   r18, r16
    sbc   r19, r17
    add   r18, r24
    adc   r19, r25

    sts   ema2_accum1,   r18
    sts   ema2_accum1+1, r19

    movw  r24, r18
    lsr   r25
    ror   r24
    lsr   r25
    ror   r24
    lsr   r25
    ror   r24
    lsr   r25
    ror   r24
    lsr   r25
    ror   r24
    ret

/* ── pid_compute_P ───────────────────────────────────────────────────────── */
/*
 * Proportional term: P = error << Kp_shift
 * Kp_shift = 2 (Kp = 4) in this example.
 *
 * Entry: R25:R24 = error (signed 16-bit, −1023..+1023)
 * Exit:  R25:R24 = P_term (signed 16-bit)
 */
pid_compute_P:
    lsl   r24
    rol   r25
    lsl   r24
    rol   r25                    /* P = error × 4                                */
    ret

/* ── pid_compute_I ───────────────────────────────────────────────────────── */
/*
 * Integral term: I_accum += (error >> Ki_shift)
 * Ki_shift = 4 (Ki = 1/16) in this example.
 *
 * Entry: R25:R24 = error (signed 16-bit)
 * Exit:  R25:R24 = I_term (bytes 1 and 2 of I_accum, scaled for output)
 * Clobbers: R20..R27
 */
pid_compute_I:
    /* Sign-extend error (r25:r24) to 32-bit in r23:r22:r21:r20 */
    movw  r20, r24               /* r21:r20 = error                              */
    clr   r22
    sbrc  r21, 7                 /* check sign bit (r21 = error high byte)       */
    ldi   r22, 0xFF
    mov   r23, r22               /* r23:r22 = sign extension bytes               */

    /* Signed right shift by 4 (Ki_shift): ASR high byte, ROR lower bytes       */
    asr   r23
    ror   r22
    ror   r21
    ror   r20
    asr   r23
    ror   r22
    ror   r21
    ror   r20
    asr   r23
    ror   r22
    ror   r21
    ror   r20
    asr   r23
    ror   r22
    ror   r21
    ror   r20                    /* r23:r22:r21:r20 = (signed error) >> 4       */

    /* I_accum += error_step */
    lds   r24, pid_I_accum
    lds   r25, pid_I_accum+1
    lds   r26, pid_I_accum+2
    lds   r27, pid_I_accum+3

    add   r24, r20
    adc   r25, r21
    adc   r26, r22
    adc   r27, r23

    sts   pid_I_accum,   r24
    sts   pid_I_accum+1, r25
    sts   pid_I_accum+2, r26
    sts   pid_I_accum+3, r27

    /* Return I_term = bytes 1+2 of I_accum (I_accum >> 8, low 16 bits).
     * r25 = byte1, r26 = byte2. MOVW requires even src, so use two MOVs. */
    mov   r24, r25               /* r24 = byte1                                  */
    mov   r25, r26               /* r25 = byte2                                  */
    ret

/* ── pid_compute_D ───────────────────────────────────────────────────────── */
/*
 * Derivative term: D = Kd × (y_prev − y)
 * Kd_shift = 1 (Kd = 2) in this example.
 * Uses the output measurement (not the error) to avoid derivative kick.
 *
 * Entry: R25:R24 = current measured output y (16-bit)
 * Exit:  R25:R24 = D_term (signed 16-bit)
 * Clobbers: R18, R19
 */
pid_compute_D:
    lds   r18, pid_y_prev
    lds   r19, pid_y_prev+1

    sub   r18, r24
    sbc   r19, r25               /* r19:r18 = y_prev − y                        */

    sts   pid_y_prev,   r24
    sts   pid_y_prev+1, r25      /* update y_prev ← y                           */

    lsl   r18
    rol   r19                    /* D_term × 2                                   */

    movw  r24, r18
    ret

/* ── pid_clamp_I ─────────────────────────────────────────────────────────── */
/*
 * Anti-windup: clamp pid_I_accum to [pid_I_min, pid_I_max].
 * All values are 32-bit signed (stored little-endian in SRAM).
 *
 * Clobbers: R16..R23
 */
pid_clamp_I:
    lds   r16, pid_I_accum
    lds   r17, pid_I_accum+1
    lds   r18, pid_I_accum+2
    lds   r19, pid_I_accum+3     /* r19:r18:r17:r16 = I_accum                   */

    /* Compare I_accum with I_min (signed 32-bit) */
    lds   r20, pid_I_min
    lds   r21, pid_I_min+1
    lds   r22, pid_I_min+2
    lds   r23, pid_I_min+3

    cp    r16, r20
    cpc   r17, r21
    cpc   r18, r22
    cpc   r19, r23               /* I_accum − I_min */
    brge  .Lclamp_check_max      /* I_accum >= I_min: check upper bound          */

    /* I_accum < I_min: store I_min */
    sts   pid_I_accum,   r20
    sts   pid_I_accum+1, r21
    sts   pid_I_accum+2, r22
    sts   pid_I_accum+3, r23
    ret

.Lclamp_check_max:
    lds   r20, pid_I_max
    lds   r21, pid_I_max+1
    lds   r22, pid_I_max+2
    lds   r23, pid_I_max+3

    cp    r16, r20
    cpc   r17, r21
    cpc   r18, r22
    cpc   r19, r23               /* I_accum − I_max */
    brlt  .Lclamp_done           /* I_accum < I_max: within bounds               */

    /* I_accum >= I_max: store I_max */
    sts   pid_I_accum,   r20
    sts   pid_I_accum+1, r21
    sts   pid_I_accum+2, r22
    sts   pid_I_accum+3, r23

.Lclamp_done:
    ret
