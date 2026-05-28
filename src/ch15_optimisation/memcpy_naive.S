/* memcpy_naive.S — single-byte-per-iteration memcpy baseline
 *                   Companion source for Chapter 15: Optimisation Techniques
 *                   (see "Loop Unrolling" section — naive version for comparison)
 *
 * One LD + one ST per byte: straightforward but loop overhead is 2 cycles
 * (DEC + BRNE) per byte.  For large buffers, this is measurably slower
 * than the unrolled 4x version in memcpy_fast.S.
 * Compare symbol sizes: avr-nm --size-sort bench.elf
 */

#include <avr/io.h>

/* memcpy_naive -- copy len bytes from src to dst, one byte per loop
 *
 * Register interface used by the assembly benchmark:
 *   dst   R25:R24  (pointer)
 *   src   R23:R22  (pointer)
 *   len   R20      (uint8_t)
 */

.section .text
.global memcpy_naive
.type   memcpy_naive, @function
memcpy_naive:
    movw  ZL, r22           /* Z = src                                      */
    movw  XL, r24           /* X = dst                                      */
    tst   r20
    breq  .Lnaive_done

.Lnaive_loop:
    ld    r18, Z+            /* load byte from src, advance src              */
    st    X+, r18            /* store byte to dst, advance dst               */
    dec   r20
    brne  .Lnaive_loop

.Lnaive_done:
    ret

.size   memcpy_naive, .-memcpy_naive
