/*
 * interrupts.S — external pin interrupt toggles LED on ATtiny3217.
 *
 * Hardware:
 *   LED0   PA3, active-low   (0 = on)
 *   Button PB2, active-low   (pressed = 0); internal pull-up enabled
 *
 * Interrupt:  PORTB_PORT fires on falling edge of PB2 (button press).
 *             The ISR toggles PA3, clears the flag, and returns.
 *
 * Main loop:  does nothing (CPU could sleep here to save power).
 *
 * Default clock: 20 MHz / 6 = 3.333 MHz
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -c -o interrupts.o interrupts.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o interrupts.elf interrupts.o
 *   avr-objdump -d interrupts.elf
 *   avr-objcopy -O ihex interrupts.elf interrupts.hex
 */

#include <avr/io.h>

/* ── Pin assignments ──────────────────────────────────────────────────────── */
.equ LED_BIT,    3          /* PA3: LED0, active-low                          */
.equ BTN_BIT,    2          /* PB2: button, active-low, pull-up               */

/* ── Interrupt sense configuration ───────────────────────────────────────── */
/* PORT_ISC_FALLING_gc = 0x03: interrupt on falling edge (press = high→low).  */
/* PORT_PULLUPEN_bm    = 0x08: enable internal pull-up.                        */
/* Combined = 0x08 | 0x03 = 0x0B.  Use literal: avr-as cannot | enum values. */
.equ BTN_CTRL,  0x0B        /* PORT_PULLUPEN_bm | PORT_ISC_FALLING_gc         */

/* ══════════════════════════════════════════════════════════════════════════
 * INTERRUPT VECTOR TABLE
 *
 * ATtiny3217: 2-byte (1-word) entries.  Use RJMP — not JMP (4 bytes).
 * Vector numbers from iotn3217.h; each _VECTOR(n) = byte address n*2.
 *
 * RESET      _VECTOR(0)  0x0000  — not in the _VECTOR() sequence; just the
 *                                   first instruction executed after reset.
 * CRCSCAN_NMI _VECTOR(1) 0x0002
 * BOD_VLM    _VECTOR(2)  0x0004
 * PORTA_PORT _VECTOR(3)  0x0006
 * PORTB_PORT _VECTOR(4)  0x0008  ← our button interrupt
 * PORTC_PORT _VECTOR(5)  0x000A
 * RTC_CNT    _VECTOR(6)  0x000C
 * RTC_PIT    _VECTOR(7)  0x000E
 * TCA0_OVF   _VECTOR(8)  0x0010
 * TCA0_HUNF  _VECTOR(9)  0x0012
 * TCA0_CMP0  _VECTOR(10) 0x0014
 * TCA0_CMP1  _VECTOR(11) 0x0016
 * TCA0_CMP2  _VECTOR(12) 0x0018
 * TCB0_INT   _VECTOR(13) 0x001A
 * TCB1_INT   _VECTOR(14) 0x001C
 * TCD0_OVF   _VECTOR(15) 0x001E
 * TCD0_TRIG  _VECTOR(16) 0x0020
 * AC0_AC     _VECTOR(17) 0x0022
 * AC1_AC     _VECTOR(18) 0x0024
 * AC2_AC     _VECTOR(19) 0x0026
 * ADC0_RESRDY _VECTOR(20) 0x0028
 * ADC0_WCOMP  _VECTOR(21) 0x002A
 * ADC1_RESRDY _VECTOR(22) 0x002C
 * ADC1_WCOMP  _VECTOR(23) 0x002E
 * TWI0_TWIS  _VECTOR(24) 0x0030
 * TWI0_TWIM  _VECTOR(25) 0x0032
 * SPI0_INT   _VECTOR(26) 0x0034
 * USART0_RXC _VECTOR(27) 0x0036
 * USART0_DRE _VECTOR(28) 0x0038
 * USART0_TXC _VECTOR(29) 0x003A
 * NVMCTRL_EE _VECTOR(30) 0x003C
 * ══════════════════════════════════════════════════════════════════════════ */

.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    rjmp main               /* 0x0000: RESET                                  */
    rjmp isr_default        /* 0x0002: CRCSCAN_NMI                            */
    rjmp isr_default        /* 0x0004: BOD_VLM                                */
    rjmp isr_default        /* 0x0006: PORTA_PORT                             */
    rjmp portb_isr          /* 0x0008: PORTB_PORT  ← button interrupt         */
    rjmp isr_default        /* 0x000A: PORTC_PORT                             */
    rjmp isr_default        /* 0x000C: RTC_CNT                                */
    rjmp isr_default        /* 0x000E: RTC_PIT                                */
    rjmp isr_default        /* 0x0010: TCA0_OVF                               */
    rjmp isr_default        /* 0x0012: TCA0_HUNF                              */
    rjmp isr_default        /* 0x0014: TCA0_CMP0                              */
    rjmp isr_default        /* 0x0016: TCA0_CMP1                              */
    rjmp isr_default        /* 0x0018: TCA0_CMP2                              */
    rjmp isr_default        /* 0x001A: TCB0_INT                               */
    rjmp isr_default        /* 0x001C: TCB1_INT                               */
    rjmp isr_default        /* 0x001E: TCD0_OVF                               */
    rjmp isr_default        /* 0x0020: TCD0_TRIG                              */
    rjmp isr_default        /* 0x0022: AC0_AC                                 */
    rjmp isr_default        /* 0x0024: AC1_AC                                 */
    rjmp isr_default        /* 0x0026: AC2_AC                                 */
    rjmp isr_default        /* 0x0028: ADC0_RESRDY                            */
    rjmp isr_default        /* 0x002A: ADC0_WCOMP                             */
    rjmp isr_default        /* 0x002C: ADC1_RESRDY                            */
    rjmp isr_default        /* 0x002E: ADC1_WCOMP                             */
    rjmp isr_default        /* 0x0030: TWI0_TWIS                              */
    rjmp isr_default        /* 0x0032: TWI0_TWIM                              */
    rjmp isr_default        /* 0x0034: SPI0_INT                               */
    rjmp isr_default        /* 0x0036: USART0_RXC                             */
    rjmp isr_default        /* 0x0038: USART0_DRE                             */
    rjmp isr_default        /* 0x003A: USART0_TXC                             */
    rjmp isr_default        /* 0x003C: NVMCTRL_EE                             */

/* ══════════════════════════════════════════════════════════════════════════
 * isr_default — catch-all for unhandled interrupts.
 * RETI re-enables interrupts and returns to interrupted code.
 * If an unexpected interrupt fires, execution silently resumes.
 * (For debugging, replace RETI with a trap: rjmp .)
 * ══════════════════════════════════════════════════════════════════════════ */
.section .text

isr_default:
    reti

/* ══════════════════════════════════════════════════════════════════════════
 * portb_isr — PORTB_PORT interrupt service routine.
 *
 * Fires on: falling edge of PB2 (button pressed).
 *
 * Action:
 *   1. Save SREG + r16 on stack.
 *   2. Toggle LED0 (PA3) via PORTA_OUTTGL.
 *   3. Clear PORTB interrupt flag for bit BTN_BIT (write-1-to-clear).
 *   4. Restore SREG + r16.
 *   5. RETI: return and re-enable interrupts.
 *
 * Stack usage: 2 bytes (return address) + 2 bytes (PUSH r16 × 2) = 4 bytes.
 *
 * Why save SREG?
 *   Any arithmetic or logical instruction modifies SREG flags.  If the ISR
 *   uses any such instruction (including SBIW, STS, LDI) and the interrupted
 *   code was in the middle of a compare-branch sequence, the flags it relied
 *   on will be overwritten.  Always save and restore SREG in every ISR.
 * ══════════════════════════════════════════════════════════════════════════ */
portb_isr:
    /* ── Prologue: save state ────────────────────────────────────────── */
    push  r16                  /* save r16 so we can use it                   */
    in    r16, SREG            /* SREG into r16 (IN from I/O addr 0x3F)       */
    push  r16                  /* save SREG on stack                          */

    /* ── Body: toggle LED ────────────────────────────────────────────── */
    ldi   r16, (1 << LED_BIT)
    sts   PORTA_OUTTGL, r16    /* atomic toggle PA3                           */

    /* ── Clear interrupt flag ───────────────────────────────────────── */
    /* PORTB_INTFLAGS (memory 0x0429) uses write-1-to-clear.             */
    /* VPORTB_INTFLAGS at I/O 0x07 is an alias — SBI writes 1 to bit 2, */
    /* which clears the flag.  If not cleared, RETI re-fires instantly.  */
    sbi   VPORTB_INTFLAGS, BTN_BIT  /* clear PORTB pin 2 interrupt flag      */

    /* ── Epilogue: restore state ─────────────────────────────────────── */
    pop   r16                  /* pop saved SREG value                        */
    out   SREG, r16            /* restore SREG — interrupt flag (I) stays 0   */
                               /* until RETI re-enables it                    */
    pop   r16                  /* restore r16                                 */
    reti                       /* pop PC, set I=1, resume main code           */

/* ══════════════════════════════════════════════════════════════════════════
 * main
 * ══════════════════════════════════════════════════════════════════════════ */
.global main

main:
    /* Initialize stack pointer */
    ldi   r16, lo8(RAMEND)
    out   SPL, r16
    ldi   r16, hi8(RAMEND)
    out   SPH, r16

    /* Configure PA3 as output (LED off) */
    sbi   VPORTA_DIR, LED_BIT  /* PA3 = output                               */
    sbi   VPORTA_OUT, LED_BIT  /* LED off (active-low)                       */

    /* Configure PB2: input, pull-up, falling-edge interrupt
     *
     * PORTB_PIN2CTRL (0x0432):
     *   bits 2:0 = ISC = PORT_ISC_FALLING_gc (0x03) — sense falling edge
     *   bit 3    = PULLUPEN = 1               (0x08) — pull-up enabled
     *   combined = BTN_CTRL = 0x0B
     */
    ldi   r16, BTN_CTRL
    sts   PORTB_PIN2CTRL, r16  /* configure PB2: pull-up + falling edge ISC   */

    /* Enable global interrupts
     *
     * SEI sets the I bit in SREG.  After this instruction, any pending
     * interrupt may fire before the next instruction.  Ensure all
     * hardware is configured before SEI.
     */
    sei

    /* ── Idle loop ───────────────────────────────────────────────────── */
    /* Main code has nothing to do — all work happens in portb_isr.      */
    /* A production program would use SLEEP here to save power.          */
.Lidle:
    rjmp  .Lidle
