/*
 * crc8.S - standalone CRC-8/SMBus demonstration
 * Target: ATtiny3217
 *
 * Polynomial: 0x07 (x^8 + x^2 + x + 1)
 * Initial value: 0x00
 * Bit order: MSB first
 *
 * The program computes CRC-8/SMBus over four bytes in Flash:
 *   01 02 03 04
 * Expected result: 0xE3
 *
 * Result is stored in SRAM at crc_result, then the program halts.
 */

#include <avr/io.h>

.equ CRC8_POLY, 0x07
.equ MSG_LEN,   4

/* -- Vector table ------------------------------------------------------- */
.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    rjmp  main
    .fill 30, 2, 0xCFFF

/* -- Flash test message ------------------------------------------------- */
.section .text
.Lmsg:
    .byte 0x01, 0x02, 0x03, 0x04
.balign 2

/* -- SRAM result byte --------------------------------------------------- */
.section .bss
.global crc_result
crc_result:
    .skip 1

/* -- Code --------------------------------------------------------------- */
.section .text

/*
 * crc8_flash
 *
 * In:
 *   Z  = byte address of first Flash byte
 *   r20 = byte count
 *
 * Out:
 *   r24 = CRC-8/SMBus result
 *
 * Clobbers:
 *   r18, r19, r20, r24, r25, Z
 */
.global crc8_flash
crc8_flash:
    ldi   r24, 0x00
    ldi   r25, CRC8_POLY

    tst   r20
    breq  .Lcrc_done

.Lcrc_byte:
    lpm   r18, Z+
    eor   r24, r18
    ldi   r19, 8

.Lcrc_bit:
    lsl   r24
    brcc  .Lcrc_no_xor
    eor   r24, r25
.Lcrc_no_xor:
    dec   r19
    brne  .Lcrc_bit

    dec   r20
    brne  .Lcrc_byte

.Lcrc_done:
    ret

.global main
main:
    /* Stack pointer */
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    /* Compute CRC over the Flash message. */
    ldi   ZL, lo8(.Lmsg)
    ldi   ZH, hi8(.Lmsg)
    ldi   r20, MSG_LEN
    rcall crc8_flash

    /* Store result for debugger or memory inspection. */
    sts   crc_result, r24

.Lhalt:
    rjmp  .Lhalt
