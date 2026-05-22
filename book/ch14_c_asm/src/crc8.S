/*
 * crc8.S — CRC-8/SMBUS subroutine, callable from C
 * Target:  ATtiny3217 (or any AVR with avr-gcc)
 * Polynomial: 0x07 (x^8 + x^2 + x + 1), initial value 0x00
 *
 * C prototype (declare in caller's .c file):
 *   uint8_t crc8(const uint8_t *data, uint8_t len);
 *
 * GCC AVR calling convention:
 *   data → R25:R24  (16-bit pointer, high:low)
 *   len  → R22      (8-bit, occupies lower byte of R23:R22 pair)
 *   return R24      (8-bit return value)
 *
 * Registers clobbered (all caller-saved, no push/pop needed):
 *   R24 (accumulator / return), R25 (polynomial), R18 (current byte),
 *   R19 (bit counter), R20 (length counter), R30:R31 (Z pointer)
 *
 * Algorithm: bit-by-bit (no lookup table):
 *   for each byte b in data[0..len-1]:
 *       crc ^= b
 *       for i in 0..7:
 *           if crc & 0x80:
 *               crc = (crc << 1) ^ 0x07
 *           else:
 *               crc <<= 1
 */

#include <avr/io.h>

.equ CRC8_POLY, 0x07

.section .text
.global crc8
crc8:
    movw  ZL, r24               /* Z = data pointer (copy from R25:R24)     */
    mov   r20, r22              /* r20 = len                                */
    ldi   r24, 0x00             /* CRC accumulator = 0                      */
    ldi   r25, CRC8_POLY        /* r25 = 0x07 (polynomial constant)         */
                                /* safe: pointer already copied to Z        */
    tst   r20
    breq  .Lcrc_done            /* if len == 0, return 0                    */

.Lcrc_byte:
    ld    r18, Z+               /* load next byte from SRAM, advance Z      */
    eor   r24, r18              /* XOR byte into CRC accumulator            */
    ldi   r19, 8                /* process 8 bits                           */

.Lcrc_bit:
    lsl   r24                   /* shift MSB into carry flag                */
    brcc  .Lcrc_no_xor          /* if carry = 0, no feedback                */
    eor   r24, r25              /* carry = 1: XOR with polynomial (0x07)    */
.Lcrc_no_xor:
    dec   r19
    brne  .Lcrc_bit             /* next bit                                 */

    dec   r20
    brne  .Lcrc_byte            /* next byte                                */

.Lcrc_done:
    ret                         /* R24 holds the final CRC-8 value          */
