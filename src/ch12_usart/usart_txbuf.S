/*
 * usart_txbuf.S — non-blocking TX via a circular buffer drained by USART0_DRE
 *                 Companion source for Chapter 12: USART (Serial Communication)
 *                 Reference implementation for Exercise 5(a).
 *
 * The polling transmitter (usart_tx_byte) blocks the caller until each byte is
 * accepted. This version is the mirror image of the RX ring buffer: the caller
 * just drops a byte into a SRAM ring with tx_put and returns immediately, while
 * the USART0_DRE (Data Register Empty) interrupt drains one byte per fire in the
 * background.
 *
 *   Producer: tx_put (main context) — enqueues a byte and ENABLES DREIE.
 *   Consumer: USART0_DRE ISR — sends one queued byte per interrupt and, when the
 *             buffer empties, DISABLES DREIE so the interrupt stops re-firing.
 *
 * Why DREIE must be turned off when empty: DREIF is level-sensitive — it stays
 * set whenever TXDATA is free. If DREIE were left enabled with nothing to send,
 * the DRE interrupt would fire back-to-back forever, starving everything else.
 * Enabling DREIE is therefore "start draining"; disabling it is "done."
 *
 * Shared register: CTRLA holds DREIE and is written by BOTH main (enable) and
 * the ISR (disable). That read-modify-write is guarded by cli/sei in tx_put.
 * The ring indices need no guard: tx_head is written only by main, tx_tail only
 * by the ISR, and byte LDS/STS are atomic (the SPSC argument from the RX text).
 *
 * RX here is trivially polled in main so the TX/DRE machinery stays the focus.
 *
 * Target: ATtiny3217 @ 3.333 MHz internal oscillator.  Baud 9600 = 0x056D.
 * Pins (default USART0 mux):  TXD → PB2 (output),  RXD ← PB3 (input).
 */

#include <avr/io.h>

.equ BAUD_LO,     0x6D
.equ BAUD_HI,     0x05
.equ TXD_BIT,     2

.equ TXBUF_SIZE,  16
.equ TXBUF_MASK,  TXBUF_SIZE - 1     /* 0x0F (power-of-two wrap)             */

/* ── SRAM state ───────────────────────────────────────────────────────── */
.section .bss
tx_buf:   .space TXBUF_SIZE          /* the ring (holds up to 15 bytes)     */
tx_head:  .space 1                   /* write index — main owns             */
tx_tail:  .space 1                   /* read index  — DRE ISR owns          */

/* ── Vector table ─────────────────────────────────────────────────────── */
.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    jmp   main           /* 0x0000: RESET                                   */
    jmp   isr_default    /* 0x0004                                          */
    jmp   isr_default    /* 0x0008                                          */
    jmp   isr_default    /* 0x000C                                          */
    jmp   isr_default    /* 0x0010                                          */
    jmp   isr_default    /* 0x0014                                          */
    jmp   isr_default    /* 0x0018                                          */
    jmp   isr_default    /* 0x001C                                          */
    jmp   isr_default    /* 0x0020                                          */
    jmp   isr_default    /* 0x0024                                          */
    jmp   isr_default    /* 0x0028                                          */
    jmp   isr_default    /* 0x002C                                          */
    jmp   isr_default    /* 0x0030                                          */
    jmp   isr_default    /* 0x0034                                          */
    jmp   isr_default    /* 0x0038                                          */
    jmp   isr_default    /* 0x003C                                          */
    jmp   isr_default    /* 0x0040                                          */
    jmp   isr_default    /* 0x0044                                          */
    jmp   isr_default    /* 0x0048                                          */
    jmp   isr_default    /* 0x004C                                          */
    jmp   isr_default    /* 0x0050                                          */
    jmp   isr_default    /* 0x0054                                          */
    jmp   isr_default    /* 0x0058                                          */
    jmp   isr_default    /* 0x005C                                          */
    jmp   isr_default    /* 0x0060                                          */
    jmp   isr_default    /* 0x0064                                          */
    jmp   isr_default    /* 0x0068                                          */
    jmp   isr_default    /* 0x006C: USART0_RXC (polled here)                */
    jmp   usart0_dre_isr /* 0x0070: USART0_DRE ← our TX drain handler       */
    jmp   isr_default    /* 0x0074: USART0_TXC                              */
    jmp   isr_default    /* 0x0078: NVMCTRL_EE                              */

/* ── Text ─────────────────────────────────────────────────────────────── */
.section .text

isr_default:
    reti

/* ── Greeting string in flash ─────────────────────────────────────────── */
.Lhello_str:
    .byte 'T', 'X', ' ', 'b', 'u', 'f', 'f', 'e', 'r', ' '
    .byte 'r', 'e', 'a', 'd', 'y', '\r', '\n'
.equ HELLO_LEN, 17
.balign 2

/* ── USART0 DRE ISR — consumer: send one queued byte ──────────────────────
 * Fires while DREIE is set and TXDATA is free. Sends one byte from tx_buf and
 * advances tx_tail. When the buffer is empty, disables DREIE so it stops.
 * Saved/restored: r16, r17, ZL, ZH, SREG.
 */
usart0_dre_isr:
    push  r16
    push  r17
    push  ZL
    push  ZH
    in    r16, SREG
    push  r16

    lds   r16, tx_tail               /* r16 = tail                           */
    lds   r17, tx_head               /* r17 = head                           */
    cp    r16, r17
    breq  .Ldre_empty                /* head == tail → nothing left to send  */

    ldi   ZL, lo8(tx_buf)
    ldi   ZH, hi8(tx_buf)
    add   ZL, r16                    /* Z = &tx_buf[tail]                    */
    adc   ZH, r1
    ld    r17, Z                     /* r17 = byte                           */
    sts   USART0_TXDATAL, r17        /* send it — clears DREIF               */

    inc   r16
    andi  r16, TXBUF_MASK
    sts   tx_tail, r16               /* publish new tail (consume)           */
    rjmp  .Ldre_done

.Ldre_empty:
    lds   r16, USART0_CTRLA
    andi  r16, lo8(~USART_DREIE_bm)  /* clear DREIE → stop the interrupt     */
    sts   USART0_CTRLA, r16

.Ldre_done:
    pop   r16
    out   SREG, r16
    pop   ZH
    pop   ZL
    pop   r17
    pop   r16
    reti

/* ── tx_put — enqueue r16 for transmit, non-blocking once there is room ───
 * Stores the byte and enables DREIE so the DRE ISR drains it. If the buffer is
 * full, busy-waits for the ISR to make room — so call ONLY from main context
 * with interrupts enabled, never from an ISR.
 * Preserves: r16.  Clobbers: r17, r18, Z.
 */
tx_put:
    push  r17
    push  r18
.Ltx_wait_room:
    lds   r17, tx_head               /* r17 = head                           */
    mov   r18, r17
    inc   r18
    andi  r18, TXBUF_MASK            /* r18 = next = (head + 1) & mask       */
    lds   ZL, tx_tail                /* ZL = tail (scratch for compare)      */
    cp    r18, ZL
    breq  .Ltx_wait_room            /* full → wait for the DRE ISR to drain  */

    ldi   ZL, lo8(tx_buf)
    ldi   ZH, hi8(tx_buf)
    add   ZL, r17                    /* Z = &tx_buf[head]                    */
    adc   ZH, r1
    st    Z, r16                     /* store byte FIRST                     */
    sts   tx_head, r18               /* then publish new head                */

    /* Enable DREIE. CTRLA is shared with the ISR, so guard the RMW.         */
    cli
    lds   r17, USART0_CTRLA
    ori   r17, USART_DREIE_bm
    sts   USART0_CTRLA, r17
    sei

    pop   r18
    pop   r17
    ret

/* ── tx_puts — enqueue a length-prefixed flash string via tx_put ──────────
 * ZL:ZH = flash pointer, r18 = byte count.  Clobbers: r16, r17, r18, r19, Z.
 */
tx_puts:
    movw  r24, ZL                    /* save flash pointer across tx_put     */
    mov   r19, r18                   /* r19 = remaining count                */
.Ltxs_loop:
    tst   r19
    breq  .Ltxs_done
    movw  ZL, r24
    lpm   r16, Z+
    movw  r24, ZL                    /* advance saved pointer                */
    rcall tx_put                     /* tx_put clobbers Z, not r24/r19       */
    dec   r19
    rjmp  .Ltxs_loop
.Ltxs_done:
    ret

/* ── main ─────────────────────────────────────────────────────────────── */
.global main
main:
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    clr   r1                         /* establish the r1 == 0 convention     */

    /* Drive PB2 high before TXEN takes over the TXD pin */
    sbi   VPORTB_OUT, TXD_BIT
    sbi   VPORTB_DIR, TXD_BIT

    /* TX ring starts empty */
    sts   tx_head, r1
    sts   tx_tail, r1

    /* USART0: baud, then TXEN+RXEN. CTRLA stays 0 — no RXCIE (we poll RX),
     * no DREIE yet (tx_put turns it on when there is data to send). */
    ldi   r16, BAUD_LO
    sts   USART0_BAUDL, r16
    ldi   r16, BAUD_HI
    sts   USART0_BAUDH, r16
    ldi   r16, (USART_TXEN_bm | USART_RXEN_bm)
    sts   USART0_CTRLB, r16
    sts   USART0_CTRLA, r1           /* CTRLA = 0                            */

    sei

    /* Queue the greeting — returns immediately; the DRE ISR transmits it. */
    ldi   ZL, lo8(.Lhello_str)
    ldi   ZH, hi8(.Lhello_str)
    ldi   r18, HELLO_LEN
    rcall tx_puts

    /* Echo loop: poll RX, hand each byte to the non-blocking transmitter. */
.Lloop:
    lds   r16, USART0_STATUS
    sbrs  r16, USART_RXCIF_bp
    rjmp  .Lloop
    lds   r16, USART0_RXDATAL        /* read byte — clears RXCIF             */
    rcall tx_put                     /* enqueue for TX (DRE drains it)       */
    rjmp  .Lloop
