/* dds.S — Direct Digital Synthesis on ATtiny3217 Curiosity Nano
 *           Companion source for Chapter 18A: DDS and Phase Accumulator Math
 *
 * Covers:
 *   Phase accumulator: 16-bit register pair incremented by tuning word M each sample
 *   Tuning word: M = (F_out × 2^N) / F_sample = (440 × 65536) / 7992 = 3608 for A4
 *   LUT lookup: high byte of accumulator (bits [15:8]) indexes the 256-entry sine table
 *   TCB0 as sample clock: CCMP=416 → 7992 Hz ISR, sets TCA0 PWM duty each sample
 *   TCA0 single-slope PWM: 8-bit duty in CMP0, period set by PER=255, ~13 kHz PWM
 *   Frequency resolution: F_sample / 2^16 = 7992 / 65536 ≈ 0.122 Hz per LSB of M
 *
 * Generates a sine wave via 16-bit phase accumulator and 256-entry flash table.
 * Output: 8-bit PWM on PB0 (TCA0 WO0) at ~13 kHz PWM rate.
 * Sample rate: ~7992 Hz (TCB0 CCMP=416, F_CPU=3,333,333 Hz).
 * Default tone: A4 = 440 Hz, tuning word M = 3608.
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
#define M_A4         3608           /* 439.99 Hz */
#define M_C4         2145           /* 261.58 Hz */
#define M_E4         2703           /* 329.63 Hz */

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
    jmp   default_isr            /* 0x0020  TCA0_LUNF/OVF                      */
    jmp   default_isr            /* 0x0024  TCA0_HUNF                          */
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
    .byte 152, 155, 158, 162, 165, 167, 170, 173
    .byte 176, 179, 182, 185, 188, 190, 193, 196
    .byte 198, 201, 203, 206, 208, 211, 213, 215
    .byte 218, 220, 222, 224, 226, 228, 230, 232
    .byte 234, 235, 237, 238, 240, 241, 243, 244
    .byte 245, 246, 248, 249, 250, 250, 251, 252
    .byte 253, 253, 254, 254, 254, 255, 255, 255
    .byte 255, 255, 255, 255, 254, 254, 254, 253
    .byte 253, 252, 251, 250, 250, 249, 248, 246
    .byte 245, 244, 243, 241, 240, 238, 237, 235
    .byte 234, 232, 230, 228, 226, 224, 222, 220
    .byte 218, 215, 213, 211, 208, 206, 203, 201
    .byte 198, 196, 193, 190, 188, 185, 182, 179
    .byte 176, 173, 170, 167, 165, 162, 158, 155
    .byte 152, 149, 146, 143, 140, 137, 134, 131
    .byte 128, 124, 121, 118, 115, 112, 109, 106
    .byte 103, 100,  97,  93,  90,  88,  85,  82
    .byte  79,  76,  73,  70,  67,  65,  62,  59
    .byte  57,  54,  52,  49,  47,  44,  42,  40
    .byte  37,  35,  33,  31,  29,  27,  25,  23
    .byte  21,  20,  18,  17,  15,  14,  12,  11
    .byte  10,   9,   7,   6,   5,   5,   4,   3
    .byte   2,   2,   1,   1,   1,   0,   0,   0
    .byte   0,   0,   0,   0,   1,   1,   1,   2
    .byte   2,   3,   4,   5,   5,   6,   7,   9
    .byte  10,  11,  12,  14,  15,  17,  18,  20
    .byte  21,  23,  25,  27,  29,  31,  33,  35
    .byte  37,  40,  42,  44,  47,  49,  52,  54
    .byte  57,  59,  62,  65,  67,  70,  73,  76
    .byte  79,  82,  85,  88,  90,  93,  97, 100
    .byte 103, 106, 109, 112, 115, 118, 121, 124

/* ── Default ISR ─────────────────────────────────────────────────────────── */
default_isr:
    reti

/* ── DDS Sample Clock ISR (TCB0 CAPT, fires at 7992 Hz) ─────────────────── */
/*
 * dds_isr — advance the phase accumulator and write the next PWM sample
 *
 * Cycle budget: 417 cycles per sample period
 * Cycle cost:   ~61 cycles (14.6% CPU; PUSH=1, POP=2 on AVRxt)
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
    push  r16                            /* 1 cycle                      */
    in    r16, _SFR_IO_ADDR(SREG)        /* 1 cycle                      */
    push  r16                            /* 1 cycle: save SREG value      */
    push  r17                            /* 1 cycle                      */
    push  r18                            /* 1 cycle                      */
    push  r19                            /* 1 cycle                      */
    push  r20                            /* 1 cycle                      */
    push  r21                            /* 1 cycle                      */
    push  r30                            /* 1 cycle: save ZL              */
    push  r31                            /* 1 cycle: save ZH              */

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

    /* Load tuning word for A4 (440 Hz):  M = 3608 = 0x0E18 */
    ldi   r16, lo8(M_A4)                /* 0x18                         */
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
