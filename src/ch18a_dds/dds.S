/* dds.S — Direct Digital Synthesis on ATtiny3217 Curiosity Nano
 *           Companion source for Chapter 18A: DDS and Phase Accumulator Math
 *
 * Covers:
 *   Phase accumulator: 16-bit register pair incremented by tuning word M each sample
 *   Tuning word: M = (F_out × 2^N) / F_sample = (440 × 65536) / 7992 = 3610 for A4
 *   LUT lookup: high byte of accumulator (bits [15:8]) indexes the 256-entry sine table
 *   TCB0 as sample clock: CCMP=416 → 7992 Hz ISR, sets TCA0 PWM duty each sample
 *   TCA0 single-slope PWM: 8-bit duty in CMP0, period set by PER=255, ~13 kHz PWM
 *   Frequency resolution: F_sample / 2^16 = 7992 / 65536 ≈ 0.122 Hz per LSB of M
 *
 * Generates a sine wave via 16-bit phase accumulator and 256-entry flash table.
 * Output: 8-bit PWM on PB0 (TCA0 WO0) at ~13 kHz PWM rate.
 * Sample rate: ~7992 Hz (TCB0 CCMP=416, F_CPU=3,333,333 Hz).
 * Default tone: A4 = 440 Hz, tuning word M = 3610.
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -nodefaultlibs -o dds.elf dds.S
 *   avr-objdump -h dds.elf
 *   avr-objcopy -O ihex dds.elf dds.hex
 *   avrdude -p t3217 -c serialupdi -P /dev/ttyUSB0 -U flash:w:dds.hex:i
 */

#include <avr/io.h>

#define F_CPU        3333333UL
#define F_SAMPLE     7992           /* actual: F_CPU / (CCMP+1) = 3333333/417  */
#define TCB_CCMP     416            /* 0x01A0 — yields 7992 Hz sample clock     */

/* Tuning words (M = round(f_out * 65536 / 7992)) */
#define M_A4         3610           /* 440.24 Hz */
#define M_C4         2145           /* 261.63 Hz */
#define M_E4         2702           /* 329.88 Hz */

/* TCA0 split-mode register names use TCA0_SPLIT_* prefix in avr/io.h */

/* ── Interrupt Vector Table ──────────────────────────────────────────────── */
.section .vectors, "ax", @progbits

    jmp   reset_handler          /* 0x0000  RESET                              */
    jmp   default_isr            /* 0x0004  CRCSCAN_NMI                        */
    jmp   default_isr            /* 0x0008  BOD_VLM                            */
    jmp   default_isr            /* 0x000C  PORTA_PORT                         */
    jmp   default_isr            /* 0x0010  PORTB_PORT                         */
    jmp   default_isr            /* 0x0014  PORTC_PORT                         */
    jmp   default_isr            /* 0x0018  RTC_CNT                            */
    jmp   default_isr            /* 0x001C  RTC_PIT                            */
    jmp   default_isr            /* 0x0020  TCA0_LUNF                          */
    jmp   default_isr            /* 0x0024  TCA0_OVF                           */
    jmp   default_isr            /* 0x0028  TCA0_CMP0                          */
    jmp   default_isr            /* 0x002C  TCA0_CMP1                          */
    jmp   default_isr            /* 0x0030  TCA0_CMP2                          */
    jmp   dds_isr                /* 0x0034  TCB0_INT — DDS sample clock        */
    jmp   default_isr            /* 0x0038  TCB1_INT                           */
    jmp   default_isr            /* 0x003C  TCD0_OVF                           */
    jmp   default_isr            /* 0x0040  TCD0_TRIG                          */
    jmp   default_isr            /* 0x0044  AC0_AC                             */
    jmp   default_isr            /* 0x0048  AC1_AC                             */
    jmp   default_isr            /* 0x004C  AC2_AC                             */
    jmp   default_isr            /* 0x0050  ADC0_RESRDY                        */
    jmp   default_isr            /* 0x0054  ADC0_WCOMP                         */
    jmp   default_isr            /* 0x0058  ADC1_RESRDY                        */
    jmp   default_isr            /* 0x005C  ADC1_WCOMP                         */
    jmp   default_isr            /* 0x0060  TWI0_TWIS                          */
    jmp   default_isr            /* 0x0064  TWI0_TWIM                          */
    jmp   default_isr            /* 0x0068  SPI0_INT                           */
    jmp   default_isr            /* 0x006C  USART0_RXC                         */
    jmp   default_isr            /* 0x0070  USART0_DRE                         */
    jmp   default_isr            /* 0x0074  USART0_TXC                         */
    jmp   default_isr            /* 0x0078  NVMCTRL_EE                         */

/* ── SRAM Variables ──────────────────────────────────────────────────────── */
.section .bss

phase_accum:    .byte 0             /* 16-bit accumulator, low byte             */
                .byte 0             /* 16-bit accumulator, high byte (= index)  */
phase_step:     .byte 0             /* 16-bit tuning word M, low byte           */
                .byte 0             /* 16-bit tuning word M, high byte          */

/* ── Sine Lookup Table ───────────────────────────────────────────────────── */
/* 256 unsigned bytes in flash.  value[i] = round(127.5 + 127.5 * sin(2*pi*i/256))
 * Generated with:
 *   python3 -c "import math; \
 *     t=[round(127.5+127.5*math.sin(2*math.pi*i/256)) for i in range(256)]; \
 *     print(', '.join(str(v) for v in t))"
 *
 * Aligned to a 256-byte flash boundary so that hi8(sine_table) is a stable
 * page address and the ISR can use MOV ZL, r17 with no carry adjustment.
 */
.section .text
.balign 256
sine_table:
    .byte 128, 131, 134, 137, 140, 143, 146, 149
    .byte 152, 155, 158, 161, 164, 167, 170, 172
    .byte 175, 178, 181, 184, 186, 189, 192, 194
    .byte 197, 199, 202, 204, 207, 209, 211, 213
    .byte 216, 218, 220, 222, 224, 226, 227, 229
    .byte 231, 232, 234, 235, 237, 238, 239, 241
    .byte 242, 243, 244, 245, 246, 247, 248, 248
    .byte 249, 250, 250, 251, 251, 252, 252, 252
    .byte 252, 252, 252, 252, 251, 251, 250, 250
    .byte 249, 248, 248, 247, 246, 245, 244, 243
    .byte 242, 241, 239, 238, 237, 235, 234, 232
    .byte 231, 229, 227, 226, 224, 222, 220, 218
    .byte 216, 213, 211, 209, 207, 204, 202, 199
    .byte 197, 194, 192, 189, 186, 184, 181, 178
    .byte 175, 172, 170, 167, 164, 161, 158, 155
    .byte 152, 149, 146, 143, 140, 137, 134, 131
    .byte 128, 124, 121, 118, 115, 112, 109, 106
    .byte 103, 100,  97,  94,  91,  88,  85,  83
    .byte  80,  77,  74,  71,  69,  66,  63,  61
    .byte  58,  56,  53,  51,  48,  46,  44,  42
    .byte  39,  37,  35,  33,  31,  29,  28,  26
    .byte  24,  23,  21,  20,  18,  17,  16,  14
    .byte  13,  12,  11,  10,   9,   8,   7,   7
    .byte   6,   5,   5,   4,   4,   3,   3,   3
    .byte   3,   3,   3,   3,   4,   4,   5,   5
    .byte   6,   7,   7,   8,   9,  10,  11,  12
    .byte  13,  14,  16,  17,  18,  20,  21,  23
    .byte  24,  26,  28,  29,  31,  33,  35,  37
    .byte  39,  42,  44,  46,  48,  51,  53,  56
    .byte  58,  61,  63,  66,  69,  71,  74,  77
    .byte  80,  83,  85,  88,  91,  94,  97, 100
    .byte 103, 106, 109, 112, 115, 118, 121, 124

/* ── Default ISR ─────────────────────────────────────────────────────────── */
default_isr:
    reti

/* ── DDS Sample Clock ISR (TCB0 CAPT, fires at 7992 Hz) ─────────────────── */
/*
 * dds_isr — advance the phase accumulator and write the next PWM sample
 *
 * Cycle budget: 417 cycles per sample period
 * Cycle cost:   ~52 cycles (12.5% CPU)
 *
 * Register use:
 *   r16  scratch (SREG save slot, interrupt flag clear, PWM zero-extend)
 *   r17  phase_accum high byte = table index after update
 *   r18  phase_accum low byte
 *   r19  phase_step high byte
 *   r20  phase_step low byte
 *   r21  sine sample from LPM
 *   Z    flash table pointer
 */
dds_isr:
    /* ── Prologue: save SREG and all used registers ─────────────────── */
    push  r16                            /* 2 cycles                     */
    in    r16, _SFR_IO_ADDR(SREG)        /* 1 cycle                      */
    push  r16                            /* 2 cycles: save SREG value     */
    push  r17                            /* 2 cycles                     */
    push  r18                            /* 2 cycles                     */
    push  r19                            /* 2 cycles                     */
    push  r20                            /* 2 cycles                     */
    push  r21                            /* 2 cycles                     */
    push  r30                            /* 2 cycles: save ZL             */
    push  r31                            /* 2 cycles: save ZH             */

    /* ── Clear TCB0 CAPT interrupt flag (write 1 to clear) ──────────── */
    ldi   r16, TCB_CAPT_bm               /* 1 cycle                      */
    sts   TCB0_INTFLAGS, r16             /* 2 cycles                     */

    /* ── Load phase accumulator (little-endian: low byte first) ─────── */
    lds   r18, phase_accum               /* 3 cycles: low byte           */
    lds   r17, phase_accum+1             /* 3 cycles: high byte          */

    /* ── Load phase step (tuning word M) ────────────────────────────── */
    lds   r20, phase_step                /* 3 cycles: low byte           */
    lds   r19, phase_step+1              /* 3 cycles: high byte          */

    /* ── Advance accumulator: phase_accum += phase_step (16-bit wrap) ─ */
    add   r18, r20                       /* 1 cycle: low  + carry out    */
    adc   r17, r19                       /* 1 cycle: high + carry in     */
    /* Overflow (carry out of ADC r17) is silently discarded — the
     * intended modulo-65536 wrap.                                        */

    /* ── Store updated accumulator ──────────────────────────────────── */
    sts   phase_accum,   r18             /* 2 cycles                     */
    sts   phase_accum+1, r17             /* 2 cycles                     */

    /* ── Table lookup: sample = sine_table[r17] ─────────────────────── */
    /* With .balign 256, lo8(sine_table)=0x00 and hi8(sine_table) is the
     * flash page address.  ZL = r17 selects the entry within the page.  */
    ldi   ZH, hi8(sine_table)            /* 1 cycle: page address        */
    mov   ZL, r17                        /* 1 cycle: entry index         */
    lpm   r21, Z                         /* 3 cycles: fetch byte         */

    /* ── Write sample to PWM duty register ──────────────────────────── */
    sts   TCA0_SPLIT_LCMP0, r21         /* 2 cycles: 8-bit PWM, PB0     */

    /* ── Epilogue: restore registers and return ─────────────────────── */
    pop   r31                            /* 2 cycles: restore ZH         */
    pop   r30                            /* 2 cycles: restore ZL         */
    pop   r21                            /* 2 cycles                     */
    pop   r20                            /* 2 cycles                     */
    pop   r19                            /* 2 cycles                     */
    pop   r18                            /* 2 cycles                     */
    pop   r17                            /* 2 cycles                     */
    pop   r16                            /* 2 cycles: SREG saved value   */
    out   _SFR_IO_ADDR(SREG), r16        /* 1 cycle: restore SREG        */
    pop   r16                            /* 2 cycles: restore r16        */
    reti                                 /* 4 cycles                     */

/* ── TCB0 Initialisation — sample clock ─────────────────────────────────── */
/*
 * tcb0_dds_init — configure TCB0 for DDS sample clock
 *
 * CCMP = 416 (0x01A0) → period = 417 cycles → f_s = 3,333,333/417 = 7992 Hz
 * Clobbers: R16
 */
tcb0_dds_init:
    ldi   r16, lo8(TCB_CCMP)            /* 0xA0                         */
    sts   TCB0_CCMPL, r16
    ldi   r16, hi8(TCB_CCMP)            /* 0x01                         */
    sts   TCB0_CCMPH, r16               /* latches both bytes atomically */

    ldi   r16, 0                        /* CNTMODE=0: Periodic Interrupt */
    sts   TCB0_CTRLB, r16

    ldi   r16, TCB_CAPT_bm              /* enable CAPT interrupt         */
    sts   TCB0_INTCTRL, r16

    ldi   r16, TCB_ENABLE_bm            /* CLK_PER (no prescaler), enable */
    sts   TCB0_CTRLA, r16
    ret

/* ── TCA0 Split-Mode PWM Initialisation ─────────────────────────────────── */
/*
 * tca0_pwm_init — configure TCA0 low counter for 8-bit PWM on WO0 (PB0)
 *
 * PWM frequency = F_CPU / (LPER+1) = 3,333,333 / 256 = 13,021 Hz
 * A low-pass RC filter on PB0 recovers the audio waveform.
 * Clobbers: R16
 */
tca0_pwm_init:
    ldi   r16, TCA_SPLIT_SPLITM_bm
    sts   TCA0_SPLIT_CTRLD, r16         /* enable split mode             */

    ldi   r16, TCA_SPLIT_ENABLE_bm       /* CLK_PER (DIV1 = 0) | ENABLE   */
    sts   TCA0_SPLIT_CTRLA, r16

    ldi   r16, TCA_SPLIT_LCMP0EN_bm
    sts   TCA0_SPLIT_CTRLB, r16         /* enable WO0 output compare     */

    ldi   r16, 255
    sts   TCA0_SPLIT_LPER, r16          /* 8-bit PWM period              */

    ldi   r16, 128
    sts   TCA0_SPLIT_LCMP0, r16         /* initial duty = mid-scale      */

    sbi   VPORTB_DIR, 0                 /* PB0 as output                 */
    ret

/* ── Reset Handler ───────────────────────────────────────────────────────── */
reset_handler:
    /* Stack pointer: top of SRAM */
    ldi   r16, hi8(RAMEND)
    out   _SFR_IO_ADDR(SPH), r16
    ldi   r16, lo8(RAMEND)
    out   _SFR_IO_ADDR(SPL), r16

    clr   r1                            /* project zero register         */

    /* Zero SRAM variables — not provided by -nostartfiles runtime */
    clr   r16
    sts   phase_accum,   r16
    sts   phase_accum+1, r16
    sts   phase_step,    r16
    sts   phase_step+1,  r16

    /* Initialise PWM output then sample clock */
    rcall tca0_pwm_init
    rcall tcb0_dds_init

    /* Load tuning word for A4 (440 Hz):  M = 3610 = 0x0E1A */
    ldi   r16, lo8(M_A4)                /* 0x1A                         */
    sts   phase_step, r16
    ldi   r16, hi8(M_A4)                /* 0x0E                         */
    sts   phase_step+1, r16

    /* Enable global interrupts — DDS ISR starts firing immediately */
    sei

.Lmain_idle:
    /* All synthesis work is done in dds_isr.
     * The main loop can run cooperative tasks here.
     * To change the output frequency at run time, write a new M to
     * phase_step (low byte) and phase_step+1 (high byte) with interrupts
     * disabled around the two-byte write:
     *
     *   cli
     *   sts phase_step,   r_m_lo
     *   sts phase_step+1, r_m_hi
     *   sei
     */
    rjmp  .Lmain_idle
