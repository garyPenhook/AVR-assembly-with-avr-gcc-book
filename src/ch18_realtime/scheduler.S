/* scheduler.S — two-task cooperative scheduler, ATtiny3217 Curiosity Nano
 *
 * Hardware:
 *   LED0  = PA3, active low
 *   USART0 TX = PB2
 *   TCB0  = 1 ms periodic interrupt (F_CPU = 3 333 333 Hz)
 *
 * Tasks:
 *   task_led  — toggle LED0 every 500 ticks (500 ms → 1 Hz blink)
 *   task_uart — send 'H' over USART0 every 1000 ticks (1 s)
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -nodefaultlibs -o scheduler.elf scheduler.S
 *   avr-objcopy -O ihex scheduler.elf scheduler.hex
 *   avrdude -p t3217 -c serialupdi -P /dev/ttyUSB0 -U flash:w:scheduler.hex:i
 */

#include <avr/io.h>

#define LED_PIN      3
#define LED_PERIOD   500
#define UART_PERIOD  1000
/* BAUD register for 9600 at 3.333 MHz: 64*3333333/(16*9600) = 1389 */
#define BAUD_9600    1389

/* ── Vector table ──────────────────────────────────────────────────────── */
.section .vectors, "ax", @progbits
    jmp   reset_handler         /* 0x0000  RESET                              */
    jmp   default_isr           /* 0x0004  CRCSCAN_NMI                        */
    jmp   default_isr           /* 0x0008  BOD_VLM                            */
    jmp   default_isr           /* 0x000C  PORTA_PORT                         */
    jmp   default_isr           /* 0x0010  PORTB_PORT                         */
    jmp   default_isr           /* 0x0014  PORTC_PORT                         */
    jmp   default_isr           /* 0x0018  RTC_CNT                            */
    jmp   default_isr           /* 0x001C  RTC_PIT                            */
    jmp   default_isr           /* 0x0020  TCA0_LUNF                          */
    jmp   default_isr           /* 0x0024  TCA0_OVF                           */
    jmp   default_isr           /* 0x0028  TCA0_CMP0                          */
    jmp   default_isr           /* 0x002C  TCA0_CMP1                          */
    jmp   default_isr           /* 0x0030  TCA0_CMP2                          */
    jmp   tcb0_isr              /* 0x0034  TCB0_INT                           */
    jmp   default_isr           /* 0x0038  TCB1_INT                           */
    jmp   default_isr           /* 0x003C  TCD0_OVF                           */
    jmp   default_isr           /* 0x0040  TCD0_TRIG                          */
    jmp   default_isr           /* 0x0044  AC0_AC                             */
    jmp   default_isr           /* 0x0048  AC1_AC                             */
    jmp   default_isr           /* 0x004C  AC2_AC                             */
    jmp   default_isr           /* 0x0050  ADC0_RESRDY                        */
    jmp   default_isr           /* 0x0054  ADC0_WCOMP                         */
    jmp   default_isr           /* 0x0058  ADC1_RESRDY                        */
    jmp   default_isr           /* 0x005C  ADC1_WCOMP                         */
    jmp   default_isr           /* 0x0060  TWI0_TWIS                          */
    jmp   default_isr           /* 0x0064  TWI0_TWIM                          */
    jmp   default_isr           /* 0x0068  SPI0_INT                           */
    jmp   default_isr           /* 0x006C  USART0_RXC                         */
    jmp   default_isr           /* 0x0070  USART0_DRE                         */
    jmp   default_isr           /* 0x0074  USART0_TXC                         */
    jmp   default_isr           /* 0x0078  NVMCTRL_EE                         */

/* ── SRAM variables ────────────────────────────────────────────────────── */
.section .bss
tick_flag:  .byte 0
led_cnt:    .word 0
uart_cnt:   .word 0

/* ── Code ───────────────────────────────────────────────────────────────── */
.section .text

/* ── TCB0 ISR (1 ms tick) ───────────────────────────────────────────────── */
tcb0_isr:
    push  r16
    in    r16, _SFR_IO_ADDR(SREG)
    push  r16
    ldi   r16, TCB_CAPT_bm
    sts   TCB0_INTFLAGS, r16    /* clear interrupt flag                       */
    ldi   r16, 1
    sts   tick_flag, r16
    pop   r16
    out   _SFR_IO_ADDR(SREG), r16
    pop   r16
    reti

default_isr:
    reti

/* ── Reset handler ──────────────────────────────────────────────────────── */
reset_handler:
    ldi   r16, hi8(RAMEND)
    out   _SFR_IO_ADDR(SPH), r16
    ldi   r16, lo8(RAMEND)
    out   _SFR_IO_ADDR(SPL), r16
    clr   r1                  /* project zero register for ADC-with-carry use */

    sbi   VPORTA_DIR, LED_PIN   /* PA3 output                                */
    sbi   VPORTA_OUT, LED_PIN   /* HIGH = LED off (active low)                */
    sbi   VPORTB_OUT, 2         /* idle-high before enabling USART TX         */
    sbi   VPORTB_DIR, 2         /* PB2 output (USART0 TX)                    */

    rcall tcb0_init
    rcall usart0_init
    sei
    rjmp  main_loop

/* ── TCB0 init ──────────────────────────────────────────────────────────── */
tcb0_init:
    ldi   r16, lo8(3332)
    sts   TCB0_CCMPL, r16
    ldi   r16, hi8(3332)
    sts   TCB0_CCMPH, r16
    ldi   r16, 0
    sts   TCB0_CTRLB, r16       /* CNTMODE = 0: periodic interrupt            */
    ldi   r16, TCB_CAPT_bm
    sts   TCB0_INTCTRL, r16
    ldi   r16, TCB_ENABLE_bm
    sts   TCB0_CTRLA, r16
    ret

/* ── USART0 init ─────────────────────────────────────────────────────────── */
usart0_init:
    ldi   r16, lo8(BAUD_9600)
    sts   USART0_BAUDL, r16
    ldi   r16, hi8(BAUD_9600)
    sts   USART0_BAUDH, r16
    ldi   r16, USART_TXEN_bm
    sts   USART0_CTRLB, r16
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
    sts   PORTA_OUTTGL, r16     /* toggle PA3                                 */
.Lled_ret:
    ret

/* ── task_uart ───────────────────────────────────────────────────────────── */
task_uart:
    lds   r24, uart_cnt
    lds   r25, uart_cnt+1
    adiw  r24, 1
    sts   uart_cnt, r24
    sts   uart_cnt+1, r25
    cpi   r24, lo8(UART_PERIOD)
    ldi   r16, hi8(UART_PERIOD)
    cpc   r25, r16
    brlo  .Luart_ret
    clr   r24
    clr   r25
    sts   uart_cnt, r24
    sts   uart_cnt+1, r25
.Luart_dreif:
    lds   r16, USART0_STATUS
    sbrs  r16, USART_DREIF_bp
    rjmp  .Luart_dreif
    ldi   r16, 'H'
    sts   USART0_TXDATAL, r16
.Luart_ret:
    ret
