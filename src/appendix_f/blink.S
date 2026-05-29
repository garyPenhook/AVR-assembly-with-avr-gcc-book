; blink.S - ATtiny3217: blink the user LED on PA3 with a busy-wait delay.
;
; Worked example for Appendix F (Inspecting Your Binaries). VPORTA is in the
; low I/O space, so we reach it with the single-cycle bit instructions
; sbi/cbi. Addresses are written out by hand so the file is self-contained.
;
; Build:
;   avr-gcc -mmcu=attiny3217 -nostartfiles -e main blink.S -o blink.elf
; Inspect:
;   avr-size    -C --mcu=attiny3217 blink.elf
;   avr-objdump -d blink.elf
;   avr-objcopy -O ihex -j .text -j .data blink.elf blink.hex

        .equ    VPORTA_DIR, 0x00        ; VPORTA.DIR  - data direction
        .equ    VPORTA_OUT, 0x01        ; VPORTA.OUT  - output drive

        .section .text
        .global main

main:
        sbi     VPORTA_DIR, 3           ; PA3 as output
loop:
        sbi     VPORTA_OUT, 3           ; LED on
        rcall   delay
        cbi     VPORTA_OUT, 3           ; LED off
        rcall   delay
        rjmp    loop

; ---- crude busy-wait: counts a 16-bit value down to zero ----
delay:
        ldi     r24, lo8(40000)
        ldi     r25, hi8(40000)
1:      sbiw    r24, 1
        brne    1b
        ret
