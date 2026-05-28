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
    jmp   main
    .rept 30
    jmp   isr_default
    .endr

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

isr_default:
    reti

/*
 * crc8_flash — CRC-8/SMBus over a sequence of Flash bytes
 *
 * Algorithm (MSB-first bit-by-bit):
 *   For each input byte:
 *     1. XOR the byte into the current CRC.
 *     2. For each of the 8 bits (MSB first):
 *        a. Shift CRC left 1 bit (MSB goes to Carry).
 *        b. If MSB was 1 (Carry set): XOR CRC with the polynomial 0x07.
 *        c. If MSB was 0: no XOR; CRC is just the shifted value.
 *   After all bytes: r24 holds the final CRC.
 *
 * In:
 *   Z  = byte address of first Flash byte
 *   r20 = byte count (0 returns CRC = 0x00)
 *
 * Out:
 *   r24 = CRC-8/SMBus result
 *
 * Clobbers:
 *   r18, r19, r20, r24, r25, Z
 */
.global crc8_flash
crc8_flash:
    ldi   r24, 0x00             /* initial CRC value = 0x00                    */
    ldi   r25, CRC8_POLY        /* r25 = polynomial = 0x07 (constant)          */

    tst   r20
    breq  .Lcrc_done            /* zero-length message: return CRC = 0x00      */

.Lcrc_byte:
    lpm   r18, Z+               /* r18 = next input byte from flash, Z++       */
    eor   r24, r18              /* XOR input byte into running CRC             */
    ldi   r19, 8                /* process 8 bits, MSB first                  */

.Lcrc_bit:
    lsl   r24                   /* shift CRC left; old bit 7 → Carry           */
    brcc  .Lcrc_no_xor          /* if bit 7 was 0: no reduction needed         */
    eor   r24, r25              /* bit 7 was 1: reduce modulo polynomial       */
.Lcrc_no_xor:
    dec   r19
    brne  .Lcrc_bit             /* repeat for all 8 bits                       */

    dec   r20
    brne  .Lcrc_byte            /* next input byte                             */

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
