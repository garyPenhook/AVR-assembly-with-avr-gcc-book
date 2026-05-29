/*
 * potentiometer_adc.S — Read the Explorer's rotary potentiometer with ADC0.
 *
 * Curiosity Nano Explorer (EV58G97A). 10 kohm potentiometer, 0..3.3V output.
 *   Signal : Explorer "POT-METER" = analog channel ADC7 -> ATtiny3217 AIN7 (PA7)
 *
 * The pot swings the full 0..VDD range, so use an external reference. Route the
 * board's MCP1501 3.0V reference to the CNANO VREFA pin (AIN0 / PA0) and select
 * REFSEL = external. (For a 0..1.1V signal you could use the internal reference
 * with REFSEL = 0 instead, like the book's ADC chapter.)
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o potentiometer_adc.o potentiometer_adc.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o potentiometer_adc.elf potentiometer_adc.o
 */

#include <avr/io.h>

.equ POT_CHANNEL,   7           /* AIN7 = PA7 = Explorer ADC7                 */

.section .text
.global main

main:
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    rcall adc_init
    rcall pot_read              /* r25:r24 = 10-bit result                    */

.Lhalt:
    rjmp  .Lhalt

/* ------------------------------------------------------------------------- */
adc_init:
    /* CTRLC: SAMPCAP=1, REFSEL=2 (external VREFA), PRESC=DIV16 */
    ldi   r16, (1 << 6) | (2 << 4) | 0x03
    sts   ADC0_CTRLC, r16
    ldi   r16, 0x40             /* INITDLY = 32 ADC clocks                   */
    sts   ADC0_CTRLD, r16
    ldi   r16, 8                /* small extra sample length                 */
    sts   ADC0_SAMPCTRL, r16
    ldi   r16, POT_CHANNEL
    sts   ADC0_MUXPOS, r16
    ldi   r16, ADC_ENABLE_bm    /* 10-bit, single-ended, enable              */
    sts   ADC0_CTRLA, r16
    ret

/* pot_read — one conversion; returns r25:r24 (high:low) */
pot_read:
    ldi   r16, ADC_STCONV_bm
    sts   ADC0_COMMAND, r16
.Lwait:
    lds   r17, ADC0_INTFLAGS
    sbrs  r17, ADC_RESRDY_bp
    rjmp  .Lwait
    lds   r24, ADC0_RESL
    lds   r25, ADC0_RESH
    ret
