/*
 * blink.S — Toggle PA3 (LED0 on ATtiny3217 Curiosity Nano)
 *
 * Build:
 *   avr-as -mmcu=attiny3217 -o blink.o blink.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o blink.elf blink.o
 *   avr-objcopy -O ihex blink.elf blink.hex
 *
 * Flash (Curiosity Nano onboard debugger):
 *   pymcuprog write -d attiny3217 -t uart -f blink.hex
 *
 * Flash (SerialUPDI adapter):
 *   avrdude -c serialupdi -p attiny3217 -P /dev/ttyUSB0 -U flash:w:blink.hex:i
 */

#include <avr/io.h>

/* ── Vector table ──────────────────────────────────────────────────────────
 * ATtiny3217 reset vector is at byte address 0x0000.
 * We must place a JMP to main here. All other vectors are unused
 * in this example, so we skip past them with .org.
 */
.section .vectors, "ax", @progbits
.global __vectors

__vectors:
    jmp     main                ; reset vector (addr 0x0000)

/* ── Code ──────────────────────────────────────────────────────────────── */
.section .text

/*
 * main — entry point after reset
 *
 * The ATtiny3217 "new-style" PORT peripheral uses memory-mapped registers
 * (not the classic DDRx/PORTx in I/O space). We use STS to write them.
 *
 * PORTA registers (base 0x0400):
 *   PORTA_DIRSET  0x0401  — write 1 to set pin as output (non-destructive)
 *   PORTA_OUTTGL  0x0407  — write 1 to toggle pin atomically
 */
main:
    /* ── Stack pointer init ─────────────────────────────────────────────
     * ATtiny3217 RAMEND = 0x3FFF. SP must point here before any PUSH/CALL.
     * SP is a 16-bit register pair: SPH (0x3E), SPL (0x3D) in I/O space.
     */
    ldi     r16, lo8(RAMEND)        ; low byte of 0x3FFF = 0xFF
    out     SPL, r16
    ldi     r16, hi8(RAMEND)        ; high byte of 0x3FFF = 0x3F
    out     SPH, r16

    /* ── Configure PA3 as output ────────────────────────────────────────
     * Writing 1<<3 (= 0x08) to PORTA_DIRSET sets PA3 as output
     * without disturbing other pins.
     */
    ldi     r16, (1 << 3)           ; PIN3 bitmask = 0x08
    sts     PORTA_DIRSET, r16       ; PA3 → output

/* ── Main loop ─────────────────────────────────────────────────────────── */
loop:
    /* Toggle PA3.  OUTTGL is an atomic toggle: read-modify-write happens
     * inside the peripheral, safe even without disabling interrupts.     */
    ldi     r16, (1 << 3)
    sts     PORTA_OUTTGL, r16

    /* ── Software delay (~0.5 s at default 3.33 MHz clock) ─────────────
     * ATtiny3217 resets with 20 MHz oscillator divided by 6 → 3.33 MHz.
     * Each inner loop iteration = 4 cycles (sbiw=2, brne=2 when taken).
     * We need ~1,665,000 cycles for 0.5 s.
     * 3 nested loops: 25 × 256 × 256 ≈ 1,638,400 iterations × ~1 cycle
     * core ≈ close enough for a blink demo.
     *
     * Registers used: r25:r24 (16-bit counter), r19 (outer counter).
     * r16 is clobbered by the loop but we reload it each toggle anyway.
     */
    ldi     r19, 25                 ; outer loop count
delay_outer:
    ldi     r25, 0                  ; } middle = 256 iterations
    ldi     r24, 0                  ; } inner  = 256 iterations
delay_inner:
    sbiw    r24, 1                  ; r25:r24 -= 1  (2 cycles)
    brne    delay_inner             ; loop if not zero (2 cycles taken, 1 not)
    dec     r19
    brne    delay_outer

    rjmp    loop
