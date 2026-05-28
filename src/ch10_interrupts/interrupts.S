/*
 * interrupts.S — external pin interrupt toggles LED on ATtiny3217.
 *                Companion source for Chapter 10: Interrupts
 *
 * Covers:
 *   Interrupt Vector Table — 4-byte (JMP) entries; slot numbers and addresses
 *   ISR prologue/epilogue — PUSH r16; IN r16, SREG; PUSH r16 / reverse at end
 *   Why save SREG: interrupted code may be between a compare and its branch
 *   RETI vs RET — RETI exits CPUINT state and re-enables interrupt nesting
 *   Write-1-to-clear flag protocol: SBI VPORTB_INTFLAGS clears the pending bit
 *   PORTB_PIN2CTRL: PORT_ISC_FALLING_gc + PORT_PULLUPEN_bm in one STS write
 *   SEI placement: configure hardware BEFORE enabling global interrupts
 *   Idle main loop: production code would SLEEP here instead of spin-wait
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
 * Default clock: 20 MHz / 6 = 3.333 MHz on factory-default ATtiny3217
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o interrupts.o interrupts.S
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
/* Combined = 0x08 | 0x03 = 0x0B. */
.equ BTN_CTRL,  0x0B        /* PORT_PULLUPEN_bm | PORT_ISC_FALLING_gc         */

/* ══════════════════════════════════════════════════════════════════════════
 * INTERRUPT VECTOR TABLE
 *
 * ATtiny3217: 4-byte (2-word) entries.  Use JMP to fill each slot.
 * avr-libc defines _VECTOR_SIZE = 4 for this device, so vector n starts
 * at byte address n*4.
 *
 * RESET      _VECTOR(0)  0x0000  — not in the _VECTOR() sequence; just the
 *                                   first instruction executed after reset.
 * CRCSCAN_NMI _VECTOR(1) 0x0004
 * BOD_VLM    _VECTOR(2)  0x0008
 * PORTA_PORT _VECTOR(3)  0x000C
 * PORTB_PORT _VECTOR(4)  0x0010  ← our button interrupt
 * PORTC_PORT _VECTOR(5)  0x0014
 * RTC_CNT    _VECTOR(6)  0x0018
 * RTC_PIT    _VECTOR(7)  0x001C
 * TCA0_LUNF/TCA0_OVF _VECTOR(8)  0x0020
 * TCA0_HUNF  _VECTOR(9)  0x0024
 * TCA0_LCMP0/TCA0_CMP0 _VECTOR(10) 0x0028
 * TCA0_LCMP1/TCA0_CMP1 _VECTOR(11) 0x002C
 * TCA0_CMP2/TCA0_LCMP2 _VECTOR(12) 0x0030
 * TCB0_INT   _VECTOR(13) 0x0034
 * TCB1_INT   _VECTOR(14) 0x0038
 * TCD0_OVF   _VECTOR(15) 0x003C
 * TCD0_TRIG  _VECTOR(16) 0x0040
 * AC0_AC     _VECTOR(17) 0x0044
 * AC1_AC     _VECTOR(18) 0x0048
 * AC2_AC     _VECTOR(19) 0x004C
 * ADC0_RESRDY _VECTOR(20) 0x0050
 * ADC0_WCOMP  _VECTOR(21) 0x0054
 * ADC1_RESRDY _VECTOR(22) 0x0058
 * ADC1_WCOMP  _VECTOR(23) 0x005C
 * TWI0_TWIS  _VECTOR(24) 0x0060
 * TWI0_TWIM  _VECTOR(25) 0x0064
 * SPI0_INT   _VECTOR(26) 0x0068
 * USART0_RXC _VECTOR(27) 0x006C
 * USART0_DRE _VECTOR(28) 0x0070
 * USART0_TXC _VECTOR(29) 0x0074
 * NVMCTRL_EE _VECTOR(30) 0x0078
 * ══════════════════════════════════════════════════════════════════════════ */

.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    jmp main                /* 0x0000: RESET                                  */
    jmp isr_default         /* 0x0004: CRCSCAN_NMI                            */
    jmp isr_default         /* 0x0008: BOD_VLM                                */
    jmp isr_default         /* 0x000C: PORTA_PORT                             */
    jmp portb_isr           /* 0x0010: PORTB_PORT  ← button interrupt         */
    jmp isr_default         /* 0x0014: PORTC_PORT                             */
    jmp isr_default         /* 0x0018: RTC_CNT                                */
    jmp isr_default         /* 0x001C: RTC_PIT                                */
    jmp isr_default         /* 0x0020: TCA0_LUNF/TCA0_OVF                     */
    jmp isr_default         /* 0x0024: TCA0_HUNF                              */
    jmp isr_default         /* 0x0028: TCA0_LCMP0/TCA0_CMP0                  */
    jmp isr_default         /* 0x002C: TCA0_LCMP1/TCA0_CMP1                  */
    jmp isr_default         /* 0x0030: TCA0_CMP2/TCA0_LCMP2                  */
    jmp isr_default         /* 0x0034: TCB0_INT                               */
    jmp isr_default         /* 0x0038: TCB1_INT                               */
    jmp isr_default         /* 0x003C: TCD0_OVF                               */
    jmp isr_default         /* 0x0040: TCD0_TRIG                              */
    jmp isr_default         /* 0x0044: AC0_AC                                 */
    jmp isr_default         /* 0x0048: AC1_AC                                 */
    jmp isr_default         /* 0x004C: AC2_AC                                 */
    jmp isr_default         /* 0x0050: ADC0_RESRDY                            */
    jmp isr_default         /* 0x0054: ADC0_WCOMP                             */
    jmp isr_default         /* 0x0058: ADC1_RESRDY                            */
    jmp isr_default         /* 0x005C: ADC1_WCOMP                             */
    jmp isr_default         /* 0x0060: TWI0_TWIS                              */
    jmp isr_default         /* 0x0064: TWI0_TWIM                              */
    jmp isr_default         /* 0x0068: SPI0_INT                               */
    jmp isr_default         /* 0x006C: USART0_RXC                             */
    jmp isr_default         /* 0x0070: USART0_DRE                             */
    jmp isr_default         /* 0x0074: USART0_TXC                             */
    jmp isr_default         /* 0x0078: NVMCTRL_EE                             */

/* ══════════════════════════════════════════════════════════════════════════
 * isr_default — catch-all for unhandled interrupts.
 * RETI completes the CPUINT interrupt return and resumes interrupted code.
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
 *   5. RETI: return through CPUINT and resume main code.
 *
 * Stack usage: 2 bytes (return address) + 2 bytes (PUSH r16 × 2) = 4 bytes.
 *
 * Why save SREG?
 *   Arithmetic and logic instructions modify SREG flags.  If an ISR uses one
 *   of them while interrupted code is between a compare and branch, the flags
 *   it relied on may be overwritten.  Save and restore SREG in every ISR.
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
    /* which clears the flag.  If not cleared, it remains pending.       */
    sbi   VPORTB_INTFLAGS, BTN_BIT  /* clear PORTB pin 2 interrupt flag      */

    /* ── Epilogue: restore state ─────────────────────────────────────── */
    pop   r16                  /* pop saved SREG value                        */
    out   SREG, r16            /* restore SREG exactly                         */
    pop   r16                  /* restore r16                                 */
    reti                       /* pop PC, exit CPUINT ISR state, resume main  */

/* ══════════════════════════════════════════════════════════════════════════
 * main
 * ══════════════════════════════════════════════════════════════════════════ */
.global main

main:
    /* Initialize stack pointer */
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

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
     * SEI sets the I bit in SREG.  The instruction after SEI executes before
     * any pending interrupt is serviced.  Configure hardware before SEI.
     */
    sei

    /* ── Idle loop ───────────────────────────────────────────────────── */
    /* Main code has nothing to do — all work happens in portb_isr.      */
    /* A production program would use SLEEP here to save power.          */
.Lidle:
    rjmp  .Lidle
