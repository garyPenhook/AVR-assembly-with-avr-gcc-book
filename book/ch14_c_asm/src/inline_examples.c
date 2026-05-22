/*
 * inline_examples.c — asm volatile examples for Chapter 14
 * Target: ATtiny3217 (any avr-gcc target)
 *
 * These are standalone utility functions showing inline assembly patterns.
 * Include in a project as needed.
 */

#include <stdint.h>
#include <avr/io.h>

/* ── Example 1: bare NOP ─────────────────────────────────────────────── */
/* Insert exactly one NOP instruction (1 cycle, no operands). */
static inline void nop(void) {
    asm volatile ("nop");
}

/* ── Example 2: save SREG and disable interrupts ─────────────────────── */
/* Returns previous SREG so caller can restore it later. */
static inline uint8_t save_and_cli(void) {
    uint8_t sreg;
    asm volatile (
        "in   %0, %1"   "\n\t"
        "cli"           "\n\t"
        : "=r" (sreg)                        /* output: sreg → any register  */
        : "I"  (_SFR_IO_ADDR(SREG))          /* input: SREG as I/O addr      */
        /* no clobbers: cli only touches the I bit inside SREG,
           which is captured in the output operand                           */
    );
    return sreg;
}

/* ── Example 3: restore SREG (re-enable interrupts if they were on) ──── */
static inline void restore_sreg(uint8_t sreg) {
    asm volatile (
        "out  %0, %1"   "\n\t"
        :                                     /* no outputs                  */
        : "I" (_SFR_IO_ADDR(SREG)), "r" (sreg)
    );
}

/* ── Example 4: rotate left through carry ────────────────────────────── */
/* LSL shifts the MSB into carry; returns result in same register.        */
static inline uint8_t rol8(uint8_t val) {
    asm volatile (
        "lsl  %0"
        : "+r" (val)    /* "+r": read-write, same register as input/output  */
    );
    return val;
}

/* ── Example 5: exchange nibbles (swap high/low 4 bits) ─────────────── */
/* AVR SWAP instruction — no C equivalent without shifting.              */
static inline uint8_t swap_nibbles(uint8_t val) {
    asm volatile (
        "swap %0"
        : "+r" (val)
    );
    return val;
}

/* ── Demonstration: atomic 16-bit counter increment ─────────────────── */
/*
 * Incrementing a 16-bit variable is not atomic on AVR — it compiles to
 * two 8-bit instructions. An ISR firing between them corrupts the value.
 * Use save_and_cli / restore_sreg to make it atomic:
 */
static volatile uint16_t packet_count;

void count_packet(void) {
    uint8_t sreg = save_and_cli();
    packet_count++;
    restore_sreg(sreg);
}
