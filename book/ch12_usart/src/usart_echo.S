/*
 * usart_echo.S — USART0 echo terminal
 * Target: ATtiny3217 @ 3.333 MHz internal oscillator
 * Baud: 9600 — BAUD register value = (f_cpu / 16 / baud) × 64
 *            = (3333333 / 16 / 9600) × 64 = 1388.9 → 1389 = 0x056D
 *
 * Behaviour:
 *   Polling TX: transmit "Ready\r\n" on startup.
 *   ISR-driven RX: USART0_RXC ISR fires on each received byte.
 *   ISR reads the byte and writes it back (echo), then returns.
 *
 * Pins (ATtiny3217 default USART0 mux):
 *   TXD → PB2   (configure as output)
 *   RXD ← PB3   (configure as input, no pull-up needed with RS-232 driver)
 */

#include <avr/io.h>

/* Baud rate register for 9600 bps at 3.333 MHz
 * USART0_BAUD = (f_cpu × 64) / (16 × baud)  [asynchronous normal mode]
 *             = (3333333 × 64) / (16 × 9600)
 *             = 213333312 / 153600
 *             = 1389.0  → 0x056D
 */
.equ BAUD_9600,   1389
.equ BAUD_LO,     lo8(1389)   /* 0x6D */
.equ BAUD_HI,     hi8(1389)   /* 0x05 */

.equ TXD_BIT,     2           /* PB2 */
.equ RXD_BIT,     3           /* PB3 */

/* ── Vector table ─────────────────────────────────────────────────────── */
.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    rjmp  main           /* 0x0000: RESET                                   */
    rjmp  isr_default    /* 0x0002: CRCSCAN_NMI                             */
    rjmp  isr_default    /* 0x0004: BOD_VLM                                 */
    rjmp  isr_default    /* 0x0006: PORTA_PORT                              */
    rjmp  isr_default    /* 0x0008: PORTB_PORT                              */
    rjmp  isr_default    /* 0x000A: PORTC_PORT                              */
    rjmp  isr_default    /* 0x000C: RTC_CNT                                 */
    rjmp  isr_default    /* 0x000E: RTC_PIT                                 */
    rjmp  isr_default    /* 0x0010: TCA0_OVF                                */
    rjmp  isr_default    /* 0x0012: TCA0_HUNF                               */
    rjmp  isr_default    /* 0x0014: TCA0_CMP0                               */
    rjmp  isr_default    /* 0x0016: TCA0_CMP1                               */
    rjmp  isr_default    /* 0x0018: TCA0_CMP2                               */
    rjmp  isr_default    /* 0x001A: TCB0_INT                                */
    rjmp  isr_default    /* 0x001C: TCB1_INT                                */
    rjmp  isr_default    /* 0x001E: TCD0_OVF                                */
    rjmp  isr_default    /* 0x0020: TCD0_TRIG                               */
    rjmp  isr_default    /* 0x0022: AC0_AC                                  */
    rjmp  isr_default    /* 0x0024: AC1_AC                                  */
    rjmp  isr_default    /* 0x0026: AC2_AC                                  */
    rjmp  isr_default    /* 0x0028: ADC0_RESRDY                             */
    rjmp  isr_default    /* 0x002A: ADC0_WCOMP                              */
    rjmp  isr_default    /* 0x002C: ADC1_RESRDY                             */
    rjmp  isr_default    /* 0x002E: ADC1_WCOMP                              */
    rjmp  isr_default    /* 0x0030: TWI0_TWIS                               */
    rjmp  isr_default    /* 0x0032: TWI0_TWIM                               */
    rjmp  isr_default    /* 0x0034: SPI0_INT                                */
    rjmp  usart0_rxc_isr /* 0x0036: USART0_RXC ← our RX handler            */
    rjmp  isr_default    /* 0x0038: USART0_DRE                              */
    rjmp  isr_default    /* 0x003A: USART0_TXC                              */
    rjmp  isr_default    /* 0x003C: NVMCTRL_EE                              */

/* ── Text ─────────────────────────────────────────────────────────────── */
.section .text

isr_default:
    reti

/* ── Startup message in flash ─────────────────────────────────────────── */
.Lready_str:
    .byte 'R', 'e', 'a', 'd', 'y', '\r', '\n'
.equ READY_LEN, 7

/* ── usart_tx_byte — send r16 via polling TX ──────────────────────────── */
/*
 * Waits until DREIF (Data Register Empty Flag) is set, then writes r16 to
 * TXDATA. Does not return until the byte is in the shift register.
 * Clobbers: r17 (loop register), r16 unchanged (value written to TXDATA)
 */
usart_tx_byte:
    push  r17
.Lwait_dreif:
    lds   r17, USART0_STATUS
    sbrs  r17, USART_DREIF_bp       /* skip next if DREIF = 1 (ready)       */
    rjmp  .Lwait_dreif
    sts   USART0_TXDATAL, r16       /* write byte — clears DREIF             */
    pop   r17
    ret

/* ── usart_tx_string — send Z-pointed, length-prefixed string ────────── */
/*
 * ZL:ZH = pointer to first byte in flash
 * r18   = byte count
 * Clobbers: r16, r17, r18, Z
 */
usart_tx_string:
    tst   r18
    breq  .Ltx_done
.Ltx_loop:
    lpm   r16, Z+               /* load byte from flash, advance Z           */
    rcall usart_tx_byte
    dec   r18
    brne  .Ltx_loop
.Ltx_done:
    ret

/* ── USART0 RXC ISR ───────────────────────────────────────────────────── */
/*
 * Fires when a byte is received and ready in RXDATAL.
 * Reading RXDATAL clears the RXC flag automatically.
 * Echoes the received byte back via polling TX.
 */
usart0_rxc_isr:
    push  r16
    push  r17
    in    r16, SREG
    push  r16

    lds   r16, USART0_RXDATAL   /* read received byte — clears RXC flag      */
    rcall usart_tx_byte         /* echo it back (polling TX, blocks briefly)  */

    pop   r16
    out   SREG, r16
    pop   r17
    pop   r16
    reti

/* ── main ─────────────────────────────────────────────────────────────── */
.global main
main:
    /* Stack pointer */
    ldi   r16, lo8(RAMEND)
    out   SPL, r16
    ldi   r16, hi8(RAMEND)
    out   SPH, r16

    /* Configure TXD pin PB2 as output */
    sbi   VPORTB_DIR, TXD_BIT

    /* RXD pin PB3: leave as input (default), no pull-up needed */

    /* USART0 setup:
     *   BAUD:    9600 bps register value
     *   CTRLC:   8N1 (8-bit data, no parity, 1 stop bit) — default after reset
     *   CTRLB:   enable TX, enable RX, enable RXCIE (RX Complete Interrupt)
     */
    ldi   r16, BAUD_LO
    sts   USART0_BAUDL, r16
    ldi   r16, BAUD_HI
    sts   USART0_BAUDH, r16

    /* CTRLC default after reset = 0x03 = USART_CMODE_ASYNCHRONOUS_gc |
     * USART_CHSIZE_8BIT_gc | no parity | 1 stop bit — correct for 8N1.
     * No write needed. */

    /* Enable TX + RX + RX Complete interrupt */
    ldi   r16, (USART_TXEN_bm | USART_RXEN_bm | USART_RXCIE_bm)
    sts   USART0_CTRLB, r16

    sei                         /* global interrupt enable                   */

    /* Transmit "Ready\r\n" via polling */
    ldi   ZL, lo8(.Lready_str)
    ldi   ZH, hi8(.Lready_str)
    ldi   r18, READY_LEN
    rcall usart_tx_string

    /* Main loop: idle — RX handled by ISR */
.Lidle:
    rjmp  .Lidle
