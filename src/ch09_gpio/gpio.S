/*
 * gpio.S — GPIO: configure output LED, poll input button with debounce.
 *           Companion source for Chapter 9: GPIO
 *
 * Covers:
 *   ATtiny3217 Port Architecture: VPORT (I/O space) vs full PORT (memory-mapped)
 *   Configuring a GPIO Output: SBI VPORTA_DIR; SBI VPORTA_OUT (active-low LED)
 *   Configuring a GPIO Input with Pull-Up: PORTB_PIN2CTRL with PORT_PULLUPEN_bm
 *   SBIS / SBIC — single-cycle bit test on VPORT registers (I/O addr 0x00–0x1F)
 *   Debounce: software delay + re-sample to reject contact bounce (~20 ms)
 *   Worked Example: Button-Controlled LED — poll, debounce, toggle, wait-release
 *   OUTTGL atomic toggle: safer than read-XOR-write across interrupt boundaries
 *
 * Hardware (ATtiny3217):
 *   LED0   PA3, active-low (drive 0 = on)
 *   Button PB2, active-low (pressed = 0); internal pull-up enabled
 *
 * Default clock: 20 MHz / 6 = 3.333 MHz on factory-default ATtiny3217
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o gpio.o gpio.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o gpio.elf gpio.o
 *   avr-objdump -d gpio.elf
 *   avr-objcopy -O ihex gpio.elf gpio.hex
 */

#include <avr/io.h>

/* ── Pin assignments ──────────────────────────────────────────────────────── */
.equ LED_BIT,         3    /* PA3: LED0, active-low                           */
.equ BTN_BIT,         2    /* PB2: button, active-low, internal pull-up       */

/* ── Debounce loop count ─────────────────────────────────────────────────── */
/* Target: ~20 ms at 3.333 MHz.                                               */
/* Inner loop: SBIW (2 cy) + BRNE taken (2 cy) = 4 cy/iteration.             */
/* 3 333 333 Hz × 0.020 s ÷ 4 cy ≈ 16 666 iterations.                       */
/* Adjust for different clocks: count = f_cpu_hz * 0.020 / 4                 */
.equ DEBOUNCE_COUNT,  16666

/* ── Vector table ─────────────────────────────────────────────────────────── */
.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    rjmp main               /* 0x0000: RESET */

/* ── Code ─────────────────────────────────────────────────────────────────── */
.section .text
.global main

main:
    /* Initialize stack pointer to top of SRAM */
    ldi  r16, hi8(RAMEND)
    out  SPH, r16
    ldi  r16, lo8(RAMEND)
    out  SPL, r16

    /* ── Configure PA3 as output (LED off initially) ─────────────────────
     *
     * VPORTA_DIR lives at I/O address 0x00.
     * SBI: atomically sets one bit, 1 cycle on ATtiny3217.
     * CBI: atomically clears one bit, 1 cycle on ATtiny3217.
     *
     * Equivalent using full PORT registers (atomic set/clear):
     *   ldi r16, (1 << LED_BIT)
     *   sts PORTA_DIRSET, r16    ; atomic: set bit 3 of DIR
     *   sts PORTA_OUTSET, r16    ; atomic: set bit 3 of OUT (LED off)
     */
    sbi  VPORTA_DIR, LED_BIT   /* PA3 = output                               */
    sbi  VPORTA_OUT, LED_BIT   /* LED off (active-low)                       */

    /* ── Configure PB2 as input with internal pull-up ────────────────────
     *
     * DIR defaults to 0 (input) — no DIRCLR needed.
     * Pull-up is configured in PORTB_PIN2CTRL (memory 0x0432).
     * This register is above the I/O space so LDS/STS is required.
     *
     * PORT_PULLUPEN_bm = 0x08 (bit 3): enable pull-up
     * ISC bits [2:0] = 0x00: interrupt disabled, input buffer active
     */
    ldi  r16, PORT_PULLUPEN_bm /* 0x08                                       */
    sts  PORTB_PIN2CTRL, r16   /* PB2: input + pull-up, no interrupt yet      */

    /* ── Main polling loop ───────────────────────────────────────────────
     *
     * Button circuit: PB2 — [button] — GND, pull-up to VCC.
     *   Not pressed: PB2 = 1 (pull-up holds high)
     *   Pressed:     PB2 = 0 (button pulls low)
     *
     * SBIS skips if the bit is SET (= 1). So SBIS skips when NOT pressed.
     */
.Lloop:
    sbis VPORTB_IN, BTN_BIT    /* skip if PB2 = 1 (not pressed)              */
    rjmp .Lpressed              /* PB2 = 0: button down                       */
    rjmp .Lloop

    /* ── Button pressed: debounce, confirm, then toggle LED ─────────────
     *
     * PORTA_OUTTGL (0x0407): write 1 to a bit to atomically toggle that
     * output bit.  Safer than read-VPORTA_OUT / XOR / write-VPORTA_OUT
     * because no interrupt can observe a partial state.
     */
.Lpressed:
    rcall delay_20ms
    sbic VPORTB_IN, BTN_BIT    /* skip if PB2 is still low (pressed)         */
    rjmp .Lloop                 /* bounce/glitch: ignore                      */

    ldi  r16, (1 << LED_BIT)
    sts  PORTA_OUTTGL, r16     /* toggle PA3                                  */

.Lwait_release:
    sbis VPORTB_IN, BTN_BIT    /* skip if PB2 = 1 (released)                 */
    rjmp .Lwait_release         /* still pressed: keep waiting                */

    rcall delay_20ms            /* debounce the release edge                  */
    rjmp .Lloop

/* ── delay_20ms ──────────────────────────────────────────────────────────────
 *
 * Busy-wait ~20 ms at 3.333 MHz (default ATtiny3217 clock).
 * Tune DEBOUNCE_COUNT for other frequencies.
 *
 * Uses r26:r27 (XL:XH). The caller in this example does not keep live values
 * there across the RCALL.
 * SBIW updates flags; the caller does not rely on flags across the RCALL.
 *
 * Cycle count from RCALL through RET on AVRxt:
 *   RCALL(2) + LDI×2(2) + N×SBIW(2) + (N-1)×BRNE_taken(2)
 *   + BRNE_exit(1) + RET(4) = 4×N + 7 cycles.
 */
delay_20ms:
    ldi  r26, lo8(DEBOUNCE_COUNT)
    ldi  r27, hi8(DEBOUNCE_COUNT)
.Ldly_loop:
    sbiw r26, 1                /* 2 cycles: r27:r26 -= 1                      */
    brne .Ldly_loop             /* 2 cycles taken, 1 on fall-through           */
    ret
