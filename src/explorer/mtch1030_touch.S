/*
 * mtch1030_touch.S — Read the Explorer's three capacitive touch buttons.
 *
 * Curiosity Nano Explorer (EV58G97A). The MTCH1030 touch controller senses the
 * three capacitive pads and drives one OUTx line per button. The controller is
 * configured entirely by hardware straps; the MCU only reads the OUT states.
 *   OUTx idle : high-impedance (read high via pull-up)
 *   OUTx touch: driven LOW
 *   These same signals also reach I/O Expander 2 (see mcp23008_buttons.S).
 *
 * This file reads the three OUT lines directly as GPIO. Wire the touch button
 * signals SW1/SW2/SW3 to PA4/PA5/PA6 (any free inputs) and enable pull-ups.
 * touch_read returns r24 with bit n = 1 when button n is being touched.
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o mtch1030_touch.o mtch1030_touch.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o mtch1030_touch.elf mtch1030_touch.o
 */

#include <avr/io.h>

.equ T0_PIN,    4               /* PA4 <- SW1 / OUT0                          */
.equ T1_PIN,    5               /* PA5 <- SW2 / OUT1                          */
.equ T2_PIN,    6               /* PA6 <- SW3 / OUT2                          */

.section .text
.global main

main:
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    rcall touch_init
.Lloop:
    rcall touch_read            /* r24 bit n = 1 when pad n touched           */
    rjmp  .Lloop

/* ------------------------------------------------------------------------- */
touch_init:
    /* inputs (DIR bits already 0 after reset) with pull-ups enabled */
    ldi   r16, PORT_PULLUPEN_bm
    sts   PORTA_PIN4CTRL, r16
    sts   PORTA_PIN5CTRL, r16
    sts   PORTA_PIN6CTRL, r16
    ret

/* touch_read — sample the three OUT lines; active-low -> 1 = touched */
touch_read:
    in    r18, VPORTA_IN
    clr   r24
    sbrs  r18, T0_PIN          /* pin low (touched) -> skip, set bit          */
    ori   r24, 0x01
    sbrs  r18, T1_PIN
    ori   r24, 0x02
    sbrs  r18, T2_PIN
    ori   r24, 0x04
    ret
