/*
 * uart_tx_bitbang.S — software (bit-banged) UART transmit, 9600 8N1.
 *                     Companion source for the Bit-Banging chapter.
 *
 * No USART peripheral: the frame is shifted out of an ordinary GPIO pin by
 * counting CPU cycles. This is the canonical "why assembly" demo — the bit
 * period is enforced instruction by instruction, so the timing is the code.
 *
 * Line format (8N1, idle high, LSB first):
 *     idle(1) start(0) d0 d1 d2 d3 d4 d5 d6 d7 stop(1) idle(1)...
 *
 * The whole 10-bit frame is assembled into a 16-bit shift register so every
 * bit is emitted by the *same* instruction sequence — and the start/data/stop
 * bits therefore all take exactly the same number of cycles:
 *     bit15..9 = 1 (stop + idle)   bit8..1 = data (LSB first)   bit0 = 0 (start)
 *
 * Timing (factory-default clock: OSC20M / 6 = 3.333 MHz):
 *     BIT_CYCLES = round(3333333 / 9600) = 347 cycles per bit
 *     loop overhead (everything but the delay) = 11 cycles
 *     delay loop = 3 * DELAY_COUNT cycles (incl. its LDI)
 *     => 3*DELAY_COUNT + NOP_PAD + 11 = 347  ->  DELAY_COUNT=112, NOP_PAD=2
 *     actual baud = 3333333 / 347 = 9606 (+0.07% — well inside UART tolerance)
 *
 * The TX pin is PB2 — the same pin USART0 uses on the Curiosity Nano — so the
 * output reaches the on-board debugger's CDC serial port.
 *
 * Output idiom note: the four-instruction SBRC/SBI/SBRS/CBI block drives the
 * pin to the current bit and takes 4 cycles whether the bit is 0 or 1 (the
 * skip lands on the other side), so the period is independent of the data.
 */
#include <avr/io.h>

.equ TXD_BIT,     2             /* PB2 = USART0 TXD on the Curiosity Nano */
.equ DELAY_COUNT, 112           /* 3*112 = 336 cycles of bit-time delay   */
.equ NOP_PAD,     2             /* fine trim: 336 + 2 + 11 overhead = 347 */

/* ── Vector table ─────────────────────────────────────────────────────── */
.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    jmp  main
    .rept 30
    jmp  isr_default
    .endr

/* ── Flash message ────────────────────────────────────────────────────── */
.section .text
.Lmsg:
    .byte 'H', 'i', '!', '\r', '\n'
.equ MSG_LEN, 5
.balign 2

isr_default:
    reti

/*
 * uart_putc — transmit r24 as one 8N1 frame on PB2, LSB first.
 *
 * In:       r24 = byte to send
 * Clobbers: r18 (bit count), r19 (delay), r23 (temp), r24:r25 (frame), T
 * Timing:   each of the 10 bit cells is BIT_CYCLES = 347 cycles.
 */
.global uart_putc
uart_putc:
    /* assemble the 16-bit frame: r25:r24 = stop/idle | data | start */
    mov   r23, r24             /* keep the original data byte           */
    lsl   r24                  /* low byte = data<<1 ; bit0 = 0 (start)  */
    ldi   r25, 0xFE            /* high byte: bits 9..15 = 1 (stop+idle)  */
    bst   r23, 7               /* T = data bit 7                         */
    bld   r25, 0              /* high byte bit0 = data bit7 (frame bit8) */

    ldi   r18, 10              /* start + 8 data + stop                  */
.Lbit:
    sbrc  r24, 0               /* drive TX to the current frame bit...    */
    sbi   VPORTB_OUT, TXD_BIT  /*   ...high if bit = 1                    */
    sbrs  r24, 0
    cbi   VPORTB_OUT, TXD_BIT  /*   ...low  if bit = 0  (4 cycles either) */

    lsr   r25                  /* shift the 16-bit frame right one bit    */
    ror   r24                  /* next frame bit drops into r24 bit0      */

    ldi   r19, DELAY_COUNT     /* hold this bit for one bit time          */
.Ldly:
    dec   r19
    brne  .Ldly
    nop
    nop                        /* NOP_PAD: trim the cell to exactly 347   */

    dec   r18
    brne  .Lbit
    ret

/* ── Demonstration ────────────────────────────────────────────────────── */
.global main
main:
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    /* PB2 idle high, then output (matches the USART chapter's pre-drive). */
    sbi   VPORTB_OUT, TXD_BIT
    sbi   VPORTB_DIR, TXD_BIT

    /* send "Hi!\r\n" once */
    ldi   ZL, lo8(.Lmsg)
    ldi   ZH, hi8(.Lmsg)
    ldi   r20, MSG_LEN
.Lsend:
    lpm   r24, Z+
    rcall uart_putc
    dec   r20
    brne  .Lsend

.Lhalt:
    rjmp  .Lhalt
