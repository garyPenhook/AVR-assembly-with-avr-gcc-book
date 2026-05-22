/* scheduler_nb.S — non-blocking USART variant, ATtiny3217 Curiosity Nano
 *
 * Extends scheduler.S with:
 *   - 8-byte TX ring buffer
 *   - USART0_DRE ISR fills TXDATAL from buffer (non-blocking send)
 *   - task_uart enqueues a multi-byte status string each second
 *
 * Hardware:
 *   LED0  = PA3, active low
 *   USART0 TX = PB2 (9600 baud, 3.333 MHz)
 *   TCB0  = 1 ms tick
 */

#include <avr/io.h>

#define LED_PIN      3
#define LED_PERIOD   500
#define UART_PERIOD  1000
#define BAUD_9600    1389
#define TXBUF_SIZE   8          /* must be power of two                       */
#define TXBUF_MASK   (TXBUF_SIZE - 1)

/* ── Vector table ──────────────────────────────────────────────────────── */
.section .vectors, "ax", @progbits
    jmp   reset_handler
    jmp   default_isr           /* 0x0004 CRCSCAN_NMI                         */
    jmp   default_isr           /* 0x0008 BOD_VLM                             */
    jmp   default_isr           /* 0x000C PORTA_PORT                          */
    jmp   default_isr           /* 0x0010 PORTB_PORT                          */
    jmp   default_isr           /* 0x0014 PORTC_PORT                          */
    jmp   default_isr           /* 0x0018 RTC_CNT                             */
    jmp   default_isr           /* 0x001C RTC_PIT                             */
    jmp   default_isr           /* 0x0020 TCA0_LUNF                           */
    jmp   default_isr           /* 0x0024 TCA0_OVF                            */
    jmp   default_isr           /* 0x0028 TCA0_CMP0                           */
    jmp   default_isr           /* 0x002C TCA0_CMP1                           */
    jmp   default_isr           /* 0x0030 TCA0_CMP2                           */
    jmp   tcb0_isr              /* 0x0034 TCB0_INT                            */
    jmp   default_isr           /* 0x0038 TCB1_INT                            */
    jmp   default_isr           /* 0x003C TWI0_TWIS                           */
    jmp   default_isr           /* 0x0040 TWI0_TWIM                           */
    jmp   default_isr           /* 0x0044 SPI0_INT                            */
    jmp   default_isr           /* 0x0048 USART0_RXC                          */
    jmp   usart0_dre_isr        /* 0x004C USART0_DRE                          */
    .fill 6 * 4, 1, 0xFF        /* remaining vectors                          */

/* ── SRAM variables ────────────────────────────────────────────────────── */
.section .bss
tick_flag:  .byte 0
led_cnt:    .word 0
uart_cnt:   .word 0
tx_buf:     .space TXBUF_SIZE   /* ring buffer                                */
tx_head:    .byte 0             /* write index (task writes here)             */
tx_tail:    .byte 0             /* read index (ISR reads here)                */

/* Heartbeat string "Hbeat\r\n" stored in flash */
.section .rodata
heartbeat_str:
    .ascii "Hbeat\r\n"
#define HEARTBEAT_LEN 7

/* ── Code ───────────────────────────────────────────────────────────────── */
.section .text

/* ── TCB0 ISR ───────────────────────────────────────────────────────────── */
tcb0_isr:
    push  r16
    in    r16, _SFR_IO_ADDR(SREG)
    push  r16
    ldi   r16, TCB_CAPT_bm
    sts   TCB0_INTFLAGS, r16
    ldi   r16, 1
    sts   tick_flag, r16
    pop   r16
    out   _SFR_IO_ADDR(SREG), r16
    pop   r16
    reti

/* ── USART0 DRE ISR — feeds TX ring buffer to TXDATAL ──────────────────── */
usart0_dre_isr:
    push  r16
    in    r16, _SFR_IO_ADDR(SREG)
    push  r16
    push  r26
    push  r27
    push  r28
    push  r29

    lds   r26, tx_tail          /* tail index                                 */
    lds   r27, tx_head          /* head index                                 */
    cp    r26, r27              /* tail == head → buffer empty                */
    breq  .Ldre_disable

    /* load byte at tx_buf[tail] */
    ldi   r28, lo8(tx_buf)
    ldi   r29, hi8(tx_buf)
    add   r28, r26              /* Y = &tx_buf[tail]                          */
    adc   r29, r1               /* propagate carry; r1 = 0                    */
    ld    r16, Y                /* fetch byte                                 */

    sts   USART0_TXDATAL, r16   /* send it                                    */

    /* advance tail */
    inc   r26
    andi  r26, TXBUF_MASK
    sts   tx_tail, r26

    /* check if buffer now empty; if so, disable DRE interrupt */
    lds   r27, tx_head
    cp    r26, r27
    brne  .Ldre_exit
.Ldre_disable:
    /* disable USART0_DRE interrupt to avoid spurious firings when empty      */
    lds   r16, USART0_CTRLA
    andi  r16, ~(USART_DREIE_bm)
    sts   USART0_CTRLA, r16
.Ldre_exit:
    pop   r29
    pop   r28
    pop   r27
    pop   r26
    pop   r16
    out   _SFR_IO_ADDR(SREG), r16
    pop   r16
    reti

default_isr:
    reti

/* ── uart_enqueue — add byte R16 to TX ring buffer ─────────────────────── */
/* Clobbers: R16-R18, R26-R27. Does not block — drops byte if buffer full.  */
uart_enqueue:
    lds   r17, tx_head
    mov   r18, r17
    inc   r18
    andi  r18, TXBUF_MASK       /* next = (head + 1) & mask                  */
    lds   r17, tx_tail
    cp    r18, r17
    breq  .Lenq_full            /* next == tail → buffer full, drop byte     */

    /* store byte */
    lds   r17, tx_head
    ldi   r26, lo8(tx_buf)
    ldi   r27, hi8(tx_buf)
    add   r26, r17
    adc   r27, r1
    st    X, r16

    /* advance head */
    inc   r17
    andi  r17, TXBUF_MASK
    sts   tx_head, r17

    /* enable DRE interrupt to start transmission if not already running      */
    lds   r16, USART0_CTRLA
    ori   r16, USART_DREIE_bm
    sts   USART0_CTRLA, r16
.Lenq_full:
    ret

/* ── Reset handler ──────────────────────────────────────────────────────── */
reset_handler:
    ldi   r16, hi8(RAMEND)
    out   _SFR_IO_ADDR(SPH), r16
    ldi   r16, lo8(RAMEND)
    out   _SFR_IO_ADDR(SPL), r16
    clr   r1                  /* zero register used in ADC-with-carry idioms */

    sbi   VPORTA_DIR, LED_PIN
    sbi   VPORTA_OUT, LED_PIN   /* LED off (active low)                       */
    sbi   VPORTB_DIR, 2         /* PB2 = TX output                            */

    rcall tcb0_init
    rcall usart0_init
    sei
    rjmp  main_loop

tcb0_init:
    ldi   r16, lo8(3332)
    sts   TCB0_CCMPL, r16
    ldi   r16, hi8(3332)
    sts   TCB0_CCMPH, r16
    ldi   r16, 0
    sts   TCB0_CTRLB, r16
    ldi   r16, TCB_CAPT_bm
    sts   TCB0_INTCTRL, r16
    ldi   r16, TCB_ENABLE_bm
    sts   TCB0_CTRLA, r16
    ret

usart0_init:
    ldi   r16, lo8(BAUD_9600)
    sts   USART0_BAUDL, r16
    ldi   r16, hi8(BAUD_9600)
    sts   USART0_BAUDH, r16
    ldi   r16, USART_TXEN_bm
    sts   USART0_CTRLB, r16
    /* DRE interrupt starts disabled; uart_enqueue enables it as needed       */
    ret

/* ── Main loop ──────────────────────────────────────────────────────────── */
main_loop:
.Lwait_tick:
    lds   r16, tick_flag
    tst   r16
    breq  .Lwait_tick
    clr   r16
    sts   tick_flag, r16
    rcall task_led
    rcall task_uart
    rjmp  main_loop

/* ── task_led ────────────────────────────────────────────────────────────── */
task_led:
    lds   r24, led_cnt
    lds   r25, led_cnt+1
    adiw  r24, 1
    sts   led_cnt, r24
    sts   led_cnt+1, r25
    cpi   r24, lo8(LED_PERIOD)
    ldi   r16, hi8(LED_PERIOD)
    cpc   r25, r16
    brlo  .Lled_ret
    clr   r24
    clr   r25
    sts   led_cnt, r24
    sts   led_cnt+1, r25
    ldi   r16, (1 << LED_PIN)
    sts   PORTA_OUTTGL, r16
.Lled_ret:
    ret

/* ── task_uart — enqueue "Hbeat\r\n" once per second ───────────────────── */
task_uart:
    lds   r24, uart_cnt
    lds   r25, uart_cnt+1
    adiw  r24, 1
    sts   uart_cnt, r24
    sts   uart_cnt+1, r25
    cpi   r24, lo8(UART_PERIOD)
    ldi   r16, hi8(UART_PERIOD)
    cpc   r25, r16
    brlo  .Ltx_ret
    clr   r24
    clr   r25
    sts   uart_cnt, r24
    sts   uart_cnt+1, r25

    /* enqueue each byte of heartbeat_str from flash via LPM                 */
    ldi   r30, lo8(heartbeat_str)
    ldi   r31, hi8(heartbeat_str)
    ldi   r18, HEARTBEAT_LEN
.Ltx_loop:
    lpm   r16, Z+               /* Z = R31:R30; fetch byte, advance pointer  */
    rcall uart_enqueue
    dec   r18
    brne  .Ltx_loop
.Ltx_ret:
    ret
