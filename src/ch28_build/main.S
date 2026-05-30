/* main.S - top-level program that uses only vec_add from the library */
#include <avr/io.h>
.section .text
.global main
main:
    ldi   r24, lo8(1000)
    ldi   r25, hi8(1000)
    ldi   r22, lo8(337)
    ldi   r23, hi8(337)
    rcall vec_add               /* resolved from vec.o at link time */
    sts   result, r24
    sts   result+1, r25
loop:
    rjmp  loop

.section .bss
.global result
result: .skip 2
