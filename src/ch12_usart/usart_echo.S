/*
 * usart_echo.S — USART0 echo terminal
 *                Companion source for Chapter 12: USART (Serial Communication)
 *
 * Covers:
 *   Baud rate register calculation: BAUD = (f_cpu × 64) / (16 × baud)
 *   8N1 frame format: CTRLC default 0x03 = async, 8-bit, no parity, 1 stop
 *   TX pin pre-drive: SBI VPORTB_OUT before TXEN prevents a spurious low glitch
 *   Polling TX (usart_tx_byte): spin on DREIF before writing TXDATAL
 *   Flash string TX (usart_tx_string): LPM loop with length counter
 *   ISR-driven RX (USART0_RXC): reading RXDATAL clears the RXC flag
 *   RXCIE enable in CTRLA: ISR fires on each received byte, echoes it back
 *   Mixed polling TX + ISR RX: safe when ISR does not also poll TXDATAL
 *
 * Target: ATtiny3217 @ 3.333 MHz internal oscillator
 * Baud: 9600 — BAUD register value = (f_cpu / 16 / baud) × 64
 *            = (3333333 / 16 / 9600) × 64 = 1388.9 → 1389 = 0x056D
 *
 * Pins (ATtiny3217 default USART0 mux):
 *   TXD → PB2   (configure as output)
 *   RXD ← PB3   (input; external UART adapter/debugger drives the line)
 */

#include <avr/io.h>

/* Baud rate register for 9600 bps at 3.333 MHz
 * USART0_BAUD = (f_cpu × 64) / (16 × baud)  [asynchronous normal mode]
 *             = (3333333 × 64) / (16 × 9600)
 *             = 213333312 / 153600
 *             = 1388.9  → round to 1389 = 0x056D
 */
.equ BAUD_9600,   1389
.equ BAUD_LO,     0x6D
.equ BAUD_HI,     0x05

.equ TXD_BIT,     2           /* PB2 */
.equ RXD_BIT,     3           /* PB3 */

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
    jmp   isr_default    /* 0x0020: TCA0_LUNF/TCA0_OVF                     */
    jmp   isr_default    /* 0x0024: TCA0_HUNF                               */
    jmp   isr_default    /* 0x0028: TCA0_LCMP0/TCA0_CMP0                   */
    jmp   isr_default    /* 0x002C: TCA0_LCMP1/TCA0_CMP1                   */
    jmp   isr_default    /* 0x0030: TCA0_CMP2/TCA0_LCMP2                   */
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
    jmp   usart0_rxc_isr /* 0x006C: USART0_RXC ← our RX handler            */
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
/*
 * Waits until DREIF (Data Register Empty Flag) is set, then writes r16 to
 * TXDATA. Returns after the byte is accepted into the transmit buffer.
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
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    /* Drive PB2 high before TXEN takes over the TXD pin */
    sbi   VPORTB_OUT, TXD_BIT
    sbi   VPORTB_DIR, TXD_BIT

    /* RXD pin PB3: leave as input (default) */

    /* USART0 setup:
     *   BAUD:    9600 bps register value
     *   CTRLC:   8N1 (8-bit data, no parity, 1 stop bit) — default after reset
     *   CTRLB:   enable TX and RX
     *   CTRLA:   enable RXCIE (RX Complete Interrupt)
     */
    ldi   r16, BAUD_LO
    sts   USART0_BAUDL, r16
    ldi   r16, BAUD_HI
    sts   USART0_BAUDH, r16

    /* CTRLC default after reset = 0x03 = USART_CMODE_ASYNCHRONOUS_gc |
     * USART_CHSIZE_8BIT_gc | no parity | 1 stop bit — correct for 8N1.
     * No write needed. */

    /* Enable TX + RX */
    ldi   r16, (USART_TXEN_bm | USART_RXEN_bm)
    sts   USART0_CTRLB, r16

    /* Enable RX Complete interrupt */
    ldi   r16, USART_RXCIE_bm
    sts   USART0_CTRLA, r16

    sei                         /* global interrupt enable                   */

    /* Transmit "Ready\r\n" via polling */
    ldi   ZL, lo8(.Lready_str)
    ldi   ZH, hi8(.Lready_str)
    ldi   r18, READY_LEN
    rcall usart_tx_string

    /* Main loop: idle — RX handled by ISR */
.Lidle:
    rjmp  .Lidle
