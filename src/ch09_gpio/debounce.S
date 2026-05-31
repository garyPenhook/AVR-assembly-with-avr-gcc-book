/*
 * debounce.S — non-blocking software debounce by periodic sampling.
 *              Companion source for Chapter 9 (GPIO), Debounce section.
 *
 * Covers:
 *   Periodic-sampling debounce: a timer ISR samples the button at a fixed
 *   rate (here ~5 ms) and feeds each sample into a shift-register integrator.
 *   The debounced state only changes after a full window of agreeing samples,
 *   so contact bounce — which settles in under ~10 ms — is rejected without
 *   any blocking delay. The CPU is free between ticks.
 *
 *   debounce_update (the reusable core):
 *     sample = (PB2 reads low) ? 1 : 0          ; active-low button = pressed
 *     history = (history << 1) | sample
 *     history == 0xFF -> 8 agreeing "pressed"  samples -> confirmed press
 *     history == 0x00 -> 8 agreeing "released" samples -> confirmed release
 *   A fresh 0 -> 1 transition of the debounced state is one clean press
 *   event; this demo toggles LED0 on each such event.
 *
 * Target: factory-default ATtiny3217, 20 MHz / 6 = 3.333 MHz.
 *   TCA0 FRQ (CTC) mode, prescaler DIV64, TOP = 260:
 *     f_tick = 3333333 / (64 * (260 + 1)) = 199.6 Hz  -> 5.01 ms per sample
 *     8 samples -> ~40 ms debounce window.
 *
 * Hardware: LED0 on PA3 (active-low). Button on PB2 (input, internal pull-up;
 *           pressed pulls the pin to GND).
 */

#include <avr/io.h>

.equ LED_BIT,          3        /* PA3, Curiosity Nano LED0     */
.equ BTN_BIT,          2        /* PB2, button (active-low)     */

.equ TCA_TOP_LO,       0x04     /* lo8(260)                     */
.equ TCA_TOP_HI,       0x01     /* hi8(260)                     */
.equ TCA_FRQ_MODE,     0x01     /* CTRLB: TCA_SINGLE_WGMODE_FRQ_gc          */
.equ TCA_DIV64_ENABLE, 0x0B     /* CTRLA: CLKSEL_DIV64_gc (0x5<<1) | ENABLE */

/* ── Vector table ─────────────────────────────────────────────────────── */
.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    jmp  main            /* 0x0000: RESET                                   */
    .rept 9
    jmp  isr_default     /* 0x0004 .. 0x0024                                */
    .endr
    jmp  tca0_cmp0_isr   /* 0x0028: TCA0_LCMP0/TCA0_CMP0 — the sample tick  */
    .rept 20
    jmp  isr_default
    .endr

/* ── State (SRAM) ─────────────────────────────────────────────────────── */
.section .bss
.global btn_history
btn_history:
    .skip 1                     /* rolling window of raw samples            */
.global btn_state
btn_state:
    .skip 1                     /* debounced state: 0 = released, 1 = pressed */

/* ── Text ─────────────────────────────────────────────────────────────── */
.section .text

isr_default:
    reti

/*
 * debounce_update — take one sample and update the debounced state.
 *
 * Call this at a fixed rate (every ~5 ms here). On a clean press edge it
 * toggles LED0. Self-contained: reads the pin, owns btn_history / btn_state.
 *
 * Clobbers: r24, r25, SREG, T flag.
 */
.global debounce_update
debounce_update:
    /* sample = 1 when the (active-low) button reads low */
    in    r24, VPORTB_IN
    bst   r24, BTN_BIT          /* T = pin level (1 = released)             */
    clr   r24
    bld   r24, 0                /* r24 bit0 = pin level                     */
    ldi   r25, 1
    eor   r24, r25              /* bit0 = !pin -> 1 means pressed            */

    /* history = (history << 1) | sample */
    lds   r25, btn_history
    lsl   r25
    or    r25, r24
    sts   btn_history, r25

    cpi   r25, 0xFF             /* full window pressed?                     */
    breq  .Ldb_pressed
    cpi   r25, 0x00             /* full window released?                    */
    breq  .Ldb_released
    ret                         /* still bouncing: no state change          */

.Ldb_pressed:
    lds   r24, btn_state
    cpi   r24, 1
    breq  .Ldb_ret              /* already pressed: not a new edge          */
    ldi   r24, 1
    sts   btn_state, r24        /* latch pressed                            */
    ldi   r24, (1 << LED_BIT)
    sts   PORTA_OUTTGL, r24     /* one clean press -> toggle LED0           */
.Ldb_ret:
    ret

.Ldb_released:
    clr   r24
    sts   btn_state, r24        /* latch released                          */
    ret

/* ── TCA0 CMP0 ISR — fires every ~5 ms ────────────────────────────────── */
tca0_cmp0_isr:
    push  r16
    in    r16, SREG
    push  r16
    push  r24
    push  r25

    rcall debounce_update

    ldi   r16, TCA_SINGLE_CMP0_bm   /* clear CMP0 flag (write-1-to-clear)   */
    sts   TCA0_SINGLE_INTFLAGS, r16

    pop   r25
    pop   r24
    pop   r16
    out   SREG, r16
    pop   r16
    reti

/* ── main ─────────────────────────────────────────────────────────────── */
.global main
main:
    /* Stack pointer */
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    /* PA3 = output, LED off (active-low: drive high) */
    sbi   VPORTA_DIR, LED_BIT
    sbi   VPORTA_OUT, LED_BIT

    /* PB2 = input with pull-up. DIR bit already 0 after reset; enable the
     * pull-up via PORTB.PIN2CTRL.PULLUPEN. */
    ldi   r16, PORT_PULLUPEN_bm
    sts   PORTB_PIN2CTRL, r16

    /* Start the debounced-released state cleanly (history all-ones). */
    ldi   r16, 0xFF
    sts   btn_history, r16
    clr   r16
    sts   btn_state, r16

    /* TCA0: FRQ mode, CMP0 = TOP, CMP0 interrupt, prescaler 64, enable. */
    ldi   r16, TCA_FRQ_MODE
    sts   TCA0_SINGLE_CTRLB, r16
    ldi   r16, TCA_TOP_LO
    sts   TCA0_SINGLE_CMP0L, r16
    ldi   r16, TCA_TOP_HI
    sts   TCA0_SINGLE_CMP0H, r16
    ldi   r16, TCA_SINGLE_CMP0_bm
    sts   TCA0_SINGLE_INTCTRL, r16
    ldi   r16, TCA_DIV64_ENABLE
    sts   TCA0_SINGLE_CTRLA, r16

    sei                         /* the sample tick drives everything        */

.Lidle:
    rjmp  .Lidle                /* CPU free between 5 ms ticks               */
