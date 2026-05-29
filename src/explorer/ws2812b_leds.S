/*
 * ws2812b_leds.S — Drive the Explorer's 8 addressable RGB LEDs (WS2812B-like).
 *
 * Curiosity Nano Explorer (EV58G97A). Eight FR5050RGB4C addressable LEDs. A
 * MCP6561 comparator level-translates the control signal from the CNANO socket.
 *   Data    : Explorer "WS2812B RGB" = IO-27 (this file assumes a jumper to PA5)
 *   Power   : select source with J316; external supply via J302 for long strips.
 *
 * TIMING-CRITICAL. Per the Explorer appendix (Table 10-1):
 *   T0H 0.2-0.4 us, T0L 0.8 us, T1H 0.7-1.0 us, T1L 0.7 us, period >= 1.2 us,
 *   reset > 200 us.  Each LED takes 24 bits in G,R,B order, MSB first.
 *
 * This needs a fast, predictable clock: it switches CLK_PER to 20 MHz (1 cycle
 * = 50 ns) and bit-bangs with counted cycles. The high/low windows below target
 * ~6 cycles (0 high), ~16 cycles (1 high), ~24-cycle bit period. Interrupts must
 * stay disabled during a frame. Verify the waveform on a scope and tune the NOP
 * padding for your exact build.
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o ws2812b_leds.o ws2812b_leds.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o ws2812b_leds.elf ws2812b_leds.o
 */

#include <avr/io.h>

.equ DPIN,          5           /* PA5 <- Explorer IO-27 (WS2812B data)      */
.equ NLEDS,         8
.equ CCP_IOREG_KEY, 0xD8

.section .rodata
/* 8 LEDs x 3 bytes (G, R, B). A simple rainbow-ish pattern. */
framebuf:
    .byte 0x20,0x00,0x00,  0x00,0x20,0x00,  0x00,0x00,0x20,  0x20,0x20,0x00
    .byte 0x00,0x20,0x20,  0x20,0x00,0x20,  0x10,0x10,0x10,  0x20,0x10,0x00

.section .text
.global main

main:
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    rcall clock_20mhz
    sbi   VPORTA_DIR, DPIN
    cbi   VPORTA_OUT, DPIN

    ldi   ZL, lo8(framebuf)
    ldi   ZH, hi8(framebuf)
    ldi   r24, NLEDS * 3
    rcall ws2812_send

.Lhalt:
    rjmp  .Lhalt

/* ------------------------------------------------------------------------- */
/* clock_20mhz — disable the main prescaler (20 MHz / 1) via CCP             */
clock_20mhz:
    ldi   r16, CCP_IOREG_KEY
    ldi   r17, 0x00            /* MCLKCTRLB: PEN = 0 -> no prescale          */
    sts   CPU_CCP, r16
    sts   CLKCTRL_MCLKCTRLB, r17
    ret

/* ------------------------------------------------------------------------- */
/*
 * ws2812_send — stream r24 bytes from Z to the LED chain
 * Clobbers: r16, r18, r19, r24, Z
 * Interrupts should be disabled by the caller for a clean frame.
 */
ws2812_send:
    cli
.Lbyte:
    ld    r18, Z+              /* next colour byte                          */
    ldi   r19, 8              /* 8 bits, MSB first                         */
.Lbit:
    sbi   VPORTA_OUT, DPIN     ; line high                          (1 cyc)
    nop
    nop
    nop                        ; ~6-cycle minimum high (the "0" high time)
    lsl   r18                  ; MSB -> carry                       (1 cyc)
    brcc  .Lzero               ; bit == 0 -> short high             (1/2)
    /* bit == 1: keep the line high to ~16 cycles total */
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    cbi   VPORTA_OUT, DPIN     ; line low
    nop
    nop
    rjmp  .Lbit_done
.Lzero:
    cbi   VPORTA_OUT, DPIN     ; drop after the short high
    /* pad the longer "0" low time */
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
.Lbit_done:
    dec   r19
    brne  .Lbit
    dec   r24
    brne  .Lbyte
    sei
    ret
