/* ============================================================
 * adc_event_trigger.S — start ADC0 conversions from an EVSYS event
 * Target: ATtiny3217 @ 3.333 MHz (default OSC20M /6)
 * Build:  avr-gcc -mmcu=attiny3217 -nostartfiles adc_event_trigger.S \
 *                 -o adc_event_trigger.elf
 * ============================================================
 *
 * Demonstrates:
 *   - the async/sync rule: ADC0 is an ASYNC user (ASYNCUSER1), so it
 *     must be driven by an ASYNC generator. TCA0/TCB0 overflow are SYNC
 *     generators and CANNOT feed it. We use RTC overflow (async).
 *   - ADC event-triggered start (ADC0.EVCTRL.STARTEI)
 *   - the CPU only reads the result; conversions launch in hardware
 *
 * Signal path:
 *   RTC overflow --ASYNCCH0--> ADC0 start (ASYNCUSER1), each RTC period
 *
 * Verified values (ATtiny3217 datasheet DS40002205A):
 *   p.119  ASYNCCH0 generator: RTC_OVF = 0x08
 *   p.121  ASYNCUSER1 = ADC0; channel select ASYNCCH0 = 0x03
 * NOTE: RTC bring-up (clock select, PER, sync-busy handling) is its own
 * chapter; the few lines here are a minimal default setup so the example
 * runs. The EVSYS + ADC wiring is the point.
 *
 * Registers used:
 *   r16 = scratch ; r17 = result low ; r18 = result high
 * ============================================================ */
#include <avr/io.h>

/* EVSYS selection values (datasheet sec.15; no _gc macros in the header) */
.equ ASYNCCH0_RTC_OVF,  0x08     /* ASYNCCHn generator: RTC overflow       */
.equ ASYNCUSER_SEL_CH0, 0x03     /* ASYNCUSERn listens to ASYNCCH0         */

/* single-bit fields */
.equ RTC_RTCEN,    0x01          /* RTC.CTRLA  bit0  RTC enable            */
.equ RTC_CLK_INT32K, 0x00        /* RTC.CLKSEL internal 32.768 kHz (reset) */
.equ ADC_STARTEI,  0x01          /* ADC0.EVCTRL bit0  start on event       */
.equ ADC_ENABLE,   0x01          /* ADC0.CTRLA  bit0  enable ADC           */
.equ ADC_RESRDY,   0             /* ADC0.INTFLAGS bit0  result ready       */

.section .text
.global main

main:
    /* ---------- minimal RTC: periodic overflow from internal 32 kHz ------- */
    ldi   r16, RTC_CLK_INT32K
    sts   RTC_CLKSEL, r16
    ldi   r16, 0x20
    sts   RTC_PER, r16               /* PER low  — short period               */
    ldi   r16, 0x00
    sts   RTC_PER + 1, r16           /* PER high                              */
    ldi   r16, RTC_RTCEN
    sts   RTC_CTRLA, r16             /* enable RTC                            */

    /* ---------- EVSYS: RTC overflow -> ADC0 start ---------- */
    ldi   r16, ASYNCCH0_RTC_OVF
    sts   EVSYS_ASYNCCH0, r16        /* RTC_OVF onto async channel 0          */
    ldi   r16, ASYNCUSER_SEL_CH0
    sts   EVSYS_ASYNCUSER1, r16      /* ADC0 (async user 1) listens to ch0    */

    /* ---------- ADC0: enable + event-triggered start ---------- */
    ldi   r16, ADC_STARTEI
    sts   ADC0_EVCTRL, r16           /* start a conversion on each event      */
    ldi   r16, ADC_ENABLE
    sts   ADC0_CTRLA, r16            /* enable ADC0 (10-bit default)          */

    /* ---------- main loop: harvest results as they appear ---------- */
loop:
    lds   r16, ADC0_INTFLAGS
    sbrs  r16, ADC_RESRDY            /* skip rjmp when a result is ready      */
    rjmp  loop
    lds   r17, ADC0_RESL             /* read low first...                     */
    lds   r18, ADC0_RESH             /* ...then high (clears RESRDY)          */
    rjmp  loop
