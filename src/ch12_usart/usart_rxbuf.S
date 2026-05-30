/*
 * usart_rxbuf.S — USART0 RX with a circular (ring) buffer
 *                 Companion source for Chapter 12: USART (Serial Communication)
 *
 * Where usart_echo.S echoes inside the RXC ISR (blocking on TX), this version
 * decouples receive from transmit with a single-producer/single-consumer ring
 * buffer in SRAM:
 *
 *   Producer: USART0_RXC ISR — drops the byte at rx_buf[head], advances head,
 *             and returns immediately (no TX, no blocking). If the buffer is
 *             full it still READS RXDATAL (to clear RXCIF) and counts the drop.
 *   Consumer: main loop — rx_get pops the oldest byte and echoes it via polling
 *             TX whenever the CPU has spare cycles.
 *
 * Lock-free correctness (no cli/sei around the indices):
 *   - rx_head is written ONLY by the ISR; rx_tail ONLY by main. Each side just
 *     reads the index the other owns.
 *   - rx_head/rx_tail are one byte each, so LDS/STS are atomic — no torn value.
 *   - The producer stores the data byte BEFORE publishing the new head.
 *
 * Full-vs-empty: sacrifice-a-slot scheme. A SIZE-element ring holds SIZE-1
 * bytes. empty = (head == tail); full = ((head+1) wrapped == tail).
 *
 * Target: ATtiny3217 @ 3.333 MHz internal oscillator
 * Baud:   9600 — BAUD register value = (f_cpu × 64) / (16 × baud) = 1389 = 0x056D
 *
 * Pins (ATtiny3217 default USART0 mux):
 *   TXD → PB2   (configure as output)
 *   RXD ← PB3   (input; external UART adapter/debugger drives the line)
 */

#include <avr/io.h>

/* Baud rate register for 9600 bps at 3.333 MHz */
.equ BAUD_LO,     0x6D
.equ BAUD_HI,     0x05

.equ TXD_BIT,     2           /* PB2 */
.equ RXD_BIT,     3           /* PB3 */

/* Ring buffer: power-of-two size so the wrap is a single ANDI.
 * SIZE = 16 holds up to 15 queued bytes (one slot sacrificed). */
.equ RXBUF_SIZE,  16
.equ RXBUF_MASK,  RXBUF_SIZE - 1     /* 0x0F */

/* ── SRAM state ───────────────────────────────────────────────────────── */
.section .bss
rx_buf:   .space RXBUF_SIZE          /* the ring                            */
rx_head:  .space 1                   /* write index — ISR owns              */
rx_tail:  .space 1                   /* read index  — main owns             */
rx_ovf:   .space 1                   /* dropped-byte counter (diagnostics)  */

/* ── Vector table ─────────────────────────────────────────────────────── */
.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    jmp   main           /* 0x0000: RESET                                   */
    jmp   isr_default    /* 0x0004: CRCSCAN_NMI                             */
    jmp   isr_default    /* 0x0008: BOD_VLM                                 */
    jmp   isr_default    /* 0x000C: PORTA_PORT                              */
    jmp   isr_default    /* 0x0010: PORTB_PORT                              */
    jmp   isr_default    /* 0x0014: PORTC_PORT                              */
    jmp   isr_default    /* 0x0018: RTC_CNT                                 */
    jmp   isr_default    /* 0x001C: RTC_PIT                                 */
    jmp   isr_default    /* 0x0020: TCA0_LUNF/TCA0_OVF                      */
    jmp   isr_default    /* 0x0024: TCA0_HUNF                               */
    jmp   isr_default    /* 0x0028: TCA0_LCMP0/TCA0_CMP0                    */
    jmp   isr_default    /* 0x002C: TCA0_LCMP1/TCA0_CMP1                    */
    jmp   isr_default    /* 0x0030: TCA0_CMP2/TCA0_LCMP2                    */
    jmp   isr_default    /* 0x0034: TCB0_INT                                */
    jmp   isr_default    /* 0x0038: TCB1_INT                                */
    jmp   isr_default    /* 0x003C: TCD0_OVF                                */
    jmp   isr_default    /* 0x0040: TCD0_TRIG                               */
    jmp   isr_default    /* 0x0044: AC0_AC                                  */
    jmp   isr_default    /* 0x0048: AC1_AC                                  */
    jmp   isr_default    /* 0x004C: AC2_AC                                  */
    jmp   isr_default    /* 0x0050: ADC0_RESRDY                             */
    jmp   isr_default    /* 0x0054: ADC0_WCOMP                              */
    jmp   isr_default    /* 0x0058: ADC1_RESRDY                             */
    jmp   isr_default    /* 0x005C: ADC1_WCOMP                              */
    jmp   isr_default    /* 0x0060: TWI0_TWIS                               */
    jmp   isr_default    /* 0x0064: TWI0_TWIM                               */
    jmp   isr_default    /* 0x0068: SPI0_INT                                */
    jmp   usart0_rxc_isr /* 0x006C: USART0_RXC ← our RX handler             */
    jmp   isr_default    /* 0x0070: USART0_DRE                              */
    jmp   isr_default    /* 0x0074: USART0_TXC                              */
    jmp   isr_default    /* 0x0078: NVMCTRL_EE                              */

/* ── Text ─────────────────────────────────────────────────────────────── */
.section .text

isr_default:
    reti

/* ── Startup message in flash ─────────────────────────────────────────── */
.Lready_str:
    .byte 'R', 'e', 'a', 'd', 'y', '\r', '\n'
.equ READY_LEN, 7
.balign 2

/* ── usart_tx_byte — send r16 via polling TX ──────────────────────────── */
/* Clobbers: r17 */
usart_tx_byte:
    push  r17
.Lwait_dreif:
    lds   r17, USART0_STATUS
    sbrs  r17, USART_DREIF_bp        /* skip next if DREIF = 1 (ready)       */
    rjmp  .Lwait_dreif
    sts   USART0_TXDATAL, r16        /* write byte — clears DREIF            */
    pop   r17
    ret

/* ── usart_tx_string — send Z-pointed, length-prefixed flash string ────── */
/* ZL:ZH = flash pointer, r18 = byte count.  Clobbers: r16, r17, r18, Z */
usart_tx_string:
    tst   r18
    breq  .Ltx_done
.Ltx_loop:
    lpm   r16, Z+
    rcall usart_tx_byte
    dec   r18
    brne  .Ltx_loop
.Ltx_done:
    ret

/* ── USART0 RXC ISR — producer ────────────────────────────────────────── */
/*
 * Drops the received byte into rx_buf[head] and advances head, then returns.
 * On a full buffer it still reads RXDATAL (clears RXCIF) and bumps rx_ovf.
 * Clobbers (saved/restored): r16, r17, r18, ZL, ZH, SREG.
 */
usart0_rxc_isr:
    push  r16
    push  r17
    push  r18
    push  ZL
    push  ZH
    in    r16, SREG
    push  r16

    lds   r16, USART0_RXDATAL        /* ALWAYS read — clears RXCIF           */

    lds   r17, rx_head               /* r17 = head                           */
    mov   r18, r17
    inc   r18
    andi  r18, RXBUF_MASK            /* r18 = (head + 1) wrapped             */

    lds   ZL, rx_tail                /* ZL = tail (scratch for the compare)  */
    cp    r18, ZL
    breq  .Lrx_full                  /* next == tail → full, drop the byte   */

    ldi   ZL, lo8(rx_buf)
    ldi   ZH, hi8(rx_buf)
    add   ZL, r17                    /* Z = &rx_buf[head]                    */
    adc   ZH, r1
    st    Z, r16                     /* store byte FIRST                     */
    sts   rx_head, r18               /* then publish new head (commit)       */
    rjmp  .Lrx_done

.Lrx_full:
    lds   r16, rx_ovf
    inc   r16
    sts   rx_ovf, r16                /* count the dropped byte               */

.Lrx_done:
    pop   r16
    out   SREG, r16
    pop   ZH
    pop   ZL
    pop   r18
    pop   r17
    pop   r16
    reti

/* ── rx_get — consumer: pop one byte ──────────────────────────────────── */
/*
 * Returns: T = 1 if the buffer was empty (r16 undefined)
 *          T = 0 and r16 = oldest byte otherwise
 * Clobbers: r16, r17, Z
 */
rx_get:
    lds   r16, rx_tail
    lds   r17, rx_head
    cp    r16, r17
    brne  .Lrx_have                  /* head != tail → a byte is waiting     */
    set                              /* T = 1 → empty                        */
    ret

.Lrx_have:
    ldi   ZL, lo8(rx_buf)
    ldi   ZH, hi8(rx_buf)
    add   ZL, r16
    adc   ZH, r1
    ld    r17, Z                     /* r17 = rx_buf[tail]                   */
    inc   r16
    andi  r16, RXBUF_MASK
    sts   rx_tail, r16               /* publish new tail (consume)           */
    mov   r16, r17                   /* return byte in r16                   */
    clt                              /* T = 0 → valid byte                   */
    ret

/* ── main ─────────────────────────────────────────────────────────────── */
.global main
main:
    /* Stack pointer */
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    clr   r1                         /* establish the r1 == 0 convention     */

    /* Drive PB2 high before TXEN takes over the TXD pin */
    sbi   VPORTB_OUT, TXD_BIT
    sbi   VPORTB_DIR, TXD_BIT
    /* RXD pin PB3: leave as input (default) */

    /* Ring buffer indices start equal → empty.  r1 is 0. */
    sts   rx_head, r1
    sts   rx_tail, r1
    sts   rx_ovf,  r1

    /* USART0: baud, then TXEN+RXEN, then RXCIE */
    ldi   r16, BAUD_LO
    sts   USART0_BAUDL, r16
    ldi   r16, BAUD_HI
    sts   USART0_BAUDH, r16

    ldi   r16, (USART_TXEN_bm | USART_RXEN_bm)
    sts   USART0_CTRLB, r16
    ldi   r16, USART_RXCIE_bm
    sts   USART0_CTRLA, r16

    sei

    /* Transmit "Ready\r\n" via polling */
    ldi   ZL, lo8(.Lready_str)
    ldi   ZH, hi8(.Lready_str)
    ldi   r18, READY_LEN
    rcall usart_tx_string

    /* Drain loop: pop buffered bytes and echo them (non-blocking RX path) */
.Lmain_loop:
    rcall rx_get
    brts  .Lmain_loop                /* T = 1 → empty, keep polling          */
    rcall usart_tx_byte              /* T = 0 → r16 has a byte; echo it      */
    rjmp  .Lmain_loop
