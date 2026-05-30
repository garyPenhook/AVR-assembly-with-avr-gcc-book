/* asm_funcs.S — assembly functions callable from C (avr-gcc ABI) */
#include <avr/io.h>
.section .text

/* uint16_t asm_add16(uint16_t a, uint16_t b)
 *   args:   a = r25:r24, b = r23:r22   (allocated descending from r25)
 *   return: r25:r24
 *   clobbers only call-used regs (r24,r25), so no save/restore needed. */
.global asm_add16
asm_add16:
    add   r24, r22
    adc   r25, r23
    ret

/* void asm_fill(uint8_t *p, uint8_t val, uint8_t n)
 *   args: p = r25:r24 (pointer), val = r22, n = r20
 *   fills n bytes at p with val. Uses X; r26/r27 are call-used. */
.global asm_fill
asm_fill:
    movw  r26, r24            /* X = p */
    tst   r20                 /* n == 0? nothing to do */
    breq  2f
1:  st    X+, r22
    dec   r20
    brne  1b
2:  ret

/* uint8_t asm_sum(const uint8_t *p, uint8_t n)
 *   args: p = r25:r24, n = r22 ; return r24
 *   sums n bytes. Demonstrates returning an 8-bit value in r24. */
.global asm_sum
asm_sum:
    movw  r30, r24            /* Z = p */
    clr   r24                 /* accumulator (also the return reg) */
    tst   r22
    breq  4f
3:  ld    r0, Z+
    add   r24, r0
    dec   r22
    brne  3b
4:  clr   r1                  /* restore the zero-register (we used r0/r1 area) */
    ret
