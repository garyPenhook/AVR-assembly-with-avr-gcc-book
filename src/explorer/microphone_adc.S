/*
 * microphone_adc.S — Sample the Explorer's MEMS microphone with ADC0.
 *
 * Curiosity Nano Explorer (EV58G97A). MEMS mic + MCP6022 amplifier (gain 1 /
 * 221 / 1001 selectable with switch S200). The amplified, biased output is an
 * analog signal centred near mid-supply.
 *   Signal : Explorer "MICROPHONE OUT" = analog channel ADC6 -> AIN6 (PA6)
 *
 * The amplifier is biased by the MCP1501 reference, so the signal is roughly
 * centred. Use the external VREFA reference (board 3.0V) for the full range.
 * Read continuously (free-running) to capture audio; this example takes a
 * single sample for clarity.
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o microphone_adc.o microphone_adc.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o microphone_adc.elf microphone_adc.o
 */

#include <avr/io.h>

.equ MIC_CHANNEL,   6           /* AIN6 = PA6 = Explorer ADC6                 */

.section .text
.global main

main:
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    rcall adc_init
.Lloop:
    rcall mic_sample            /* r25:r24 = 10-bit sample                    */
    rjmp  .Lloop                /* stream samples (process r25:r24 here)      */

/* ------------------------------------------------------------------------- */
adc_init:
    ldi   r16, (1 << 6) | (2 << 4) | 0x03   /* SAMPCAP, REFSEL=ext, DIV16    */
    sts   ADC0_CTRLC, r16
    ldi   r16, 0x40
    sts   ADC0_CTRLD, r16
    ldi   r16, 4                /* short sample length (low-Z amp output)    */
    sts   ADC0_SAMPCTRL, r16
    ldi   r16, MIC_CHANNEL
    sts   ADC0_MUXPOS, r16
    /* FREERUN + ENABLE so conversions repeat back-to-back */
    ldi   r16, ADC_FREERUN_bm | ADC_ENABLE_bm
    sts   ADC0_CTRLA, r16
    ldi   r16, ADC_STCONV_bm    /* kick off the first conversion             */
    sts   ADC0_COMMAND, r16
    ret

/* mic_sample — wait for the next free-running result; returns r25:r24 */
mic_sample:
    lds   r17, ADC0_INTFLAGS
    sbrs  r17, ADC_RESRDY_bp
    rjmp  mic_sample
    lds   r24, ADC0_RESL
    lds   r25, ADC0_RESH        /* reading RESH clears RESRDY                */
    ret
