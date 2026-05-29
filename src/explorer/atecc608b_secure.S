/*
 * atecc608b_secure.S — Wake the Explorer's ATECC608B and run an Info command.
 *
 * Curiosity Nano Explorer (EV58G97A). ATECC608B CryptoAuthentication device
 * on the shared I2C bus.
 *   I2C address : 0x58 (7-bit)
 *   Bus         : COM-section I2C -> TWI0 (SDA = PB1, SCL = PB0)
 *
 * ADVANCED / illustrative. The ATECC protocol is packet-based:
 *
 *   wake : hold SDA low > 60 us, then wait tWHI (~1.5 ms)
 *   cmd  : word-address 0x03, then [count][opcode][p1][p2lo][p2hi][crclo][crchi]
 *   resp : [count][data...][crclo][crchi]   (read after the exec delay)
 *
 * This issues Info(mode=Revision): opcode 0x30, p1 0x00, p2 0x0000. The
 * 4-byte revision is returned. CRC-16 (poly 0x8005, reflected) protects each
 * packet. Exec time and response handling are simplified with fixed delays;
 * production code should poll properly. Verify behaviour on hardware.
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o atecc608b_secure.o atecc608b_secure.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o atecc608b_secure.elf atecc608b_secure.o
 */

#include <avr/io.h>

.equ ATECC_ADDR,    0x58
.equ WA_COMMAND,    0x03        /* word address: command                      */
.equ SDA_PIN,       1           /* PB1 = SDA                                  */
.equ TWI_BAUD_100K, 12

.equ TWI_BUSSTATE_IDLE_gc,  0x01
.equ TWI_MCMD_RECVTRANS_gc, 0x02
.equ TWI_MCMD_STOP_gc,      0x03

.section .bss
cmdbuf:     .skip 8             /* count, op, p1, p2lo, p2hi, crclo, crchi    */
respbuf:    .skip 8             /* count + 4 data + 2 crc                     */

.section .text
.global main

main:
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    rcall atecc_wake            /* dedicated low pulse on SDA                 */
    rcall twi_init
    rcall atecc_info            /* send Info(Revision)                        */
    rcall delay_5ms             /* wait for command execution                 */
    rcall atecc_read_resp       /* respbuf[0]=count, [1..4]=revision          */

.Lhalt:
    rjmp  .Lhalt

/* ------------------------------------------------------------------------- */
/* atecc_wake — drive SDA low as GPIO > 60 us, release, wait tWHI            */
atecc_wake:
    cbi   VPORTB_OUT, SDA_PIN
    sbi   VPORTB_DIR, SDA_PIN    /* SDA driven low                            */
    ldi   r24, 1
    rcall delay_us_x100          /* ~100 us low                               */
    cbi   VPORTB_DIR, SDA_PIN    /* release (TWI/pull-up takes over)          */
    rcall delay_5ms              /* generous tWHI                             */
    ret

/* ------------------------------------------------------------------------- */
twi_init:
    ldi   r16, TWI_BAUD_100K
    sts   TWI0_MBAUD, r16
    ldi   r16, TWI_ENABLE_bm
    sts   TWI0_MCTRLA, r16
    ldi   r16, TWI_BUSSTATE_IDLE_gc
    sts   TWI0_MSTATUS, r16
    ret

/* ------------------------------------------------------------------------- */
/* atecc_info — build and send the Info(Revision) command packet             */
atecc_info:
    ldi   YL, lo8(cmdbuf)
    ldi   YH, hi8(cmdbuf)
    ldi   r16, 7                /* count                                     */
    st    Y+, r16
    ldi   r16, 0x30             /* opcode: Info                              */
    st    Y+, r16
    ldi   r16, 0x00             /* param1: Revision mode                     */
    st    Y+, r16
    ldi   r16, 0x00             /* param2 low                                */
    st    Y+, r16
    ldi   r16, 0x00             /* param2 high                               */
    st    Y+, r16

    /* CRC over the first 5 bytes (count..param2) */
    ldi   ZL, lo8(cmdbuf)
    ldi   ZH, hi8(cmdbuf)
    ldi   r20, 5
    rcall crc16_atecc           /* r25:r24 = CRC                             */
    st    Y+, r24               /* crc low                                   */
    st    Y+, r25               /* crc high                                  */

    /* transmit: word address 0x03, then 7 packet bytes */
    ldi   r24, ATECC_ADDR
    lsl   r24
    sts   TWI0_MADDR, r24
    rcall wait_wif
    ldi   r16, WA_COMMAND
    sts   TWI0_MDATA, r16
    rcall wait_wif

    ldi   ZL, lo8(cmdbuf)
    ldi   ZH, hi8(cmdbuf)
    ldi   r20, 7
.Ltx:
    ld    r16, Z+
    sts   TWI0_MDATA, r16
    rcall wait_wif
    dec   r20
    brne  .Ltx
    ldi   r16, TWI_MCMD_STOP_gc
    sts   TWI0_MCTRLB, r16
    ret

/* atecc_read_resp — read a 7-byte Info response into respbuf               */
atecc_read_resp:
    ldi   r24, ATECC_ADDR
    lsl   r24
    ori   r24, 0x01
    sts   TWI0_MADDR, r24        /* START + read                             */

    ldi   YL, lo8(respbuf)
    ldi   YH, hi8(respbuf)
    ldi   r20, 7
.Lrx:
    rcall wait_rif
    lds   r16, TWI0_MDATA
    st    Y+, r16
    dec   r20
    breq  .Lrx_last
    ldi   r16, TWI_MCMD_RECVTRANS_gc
    sts   TWI0_MCTRLB, r16
    rjmp  .Lrx
.Lrx_last:
    ldi   r16, TWI_ACKACT_bm | TWI_MCMD_STOP_gc
    sts   TWI0_MCTRLB, r16
    ret

/* ------------------------------------------------------------------------- */
/*
 * crc16_atecc — ATECC CRC-16 (poly 0x8005, reflected per byte)
 * Z = data, r20 = length; returns r25:r24 = CRC
 * Clobbers r16, r18, r19, r20, r21
 */
crc16_atecc:
    clr   r24                   /* CRC low                                   */
    clr   r25                   /* CRC high                                  */
.Lc_byte:
    ld    r18, Z+               /* data byte                                 */
    ldi   r19, 8                /* 8 bits                                    */
.Lc_bit:
    /* data_bit = r18 & 1 ; crc_bit = crc[15] */
    mov   r16, r25
    andi  r16, 0x80             /* crc[15] in bit7 of r16                     */
    /* crc <<= 1 */
    lsl   r24
    rol   r25
    /* compute data_bit (in C of next test) XOR crc_bit */
    mov   r21, r18
    andi  r21, 0x01             /* data_bit in bit0                          */
    /* shift crc_bit (bit7) down to bit0 */
    swap  r16
    lsr   r16
    lsr   r16
    lsr   r16                   /* r16 bit0 = old crc[15]                     */
    eor   r21, r16             /* (data_bit ^ crc_bit) in bit0               */
    sbrc  r21, 0
    rjmp  .Lc_xor
.Lc_next_bit:
    lsr   r18                   /* next data bit -> bit0                      */
    dec   r19
    brne  .Lc_bit
    dec   r20
    brne  .Lc_byte
    ret
.Lc_xor:
    ldi   r16, 0x05
    eor   r24, r16
    ldi   r16, 0x80
    eor   r25, r16
    rjmp  .Lc_next_bit

/* ------------------------------------------------------------------------- */
/* delay_us_x100 — r24 * ~100 us at 3.333 MHz */
delay_us_x100:
.Lu_outer:
    ldi   r26, lo8(110)
    ldi   r27, hi8(110)
.Lu_inner:
    sbiw  r26, 1
    brne  .Lu_inner
    dec   r24
    brne  .Lu_outer
    ret

/* delay_5ms — ~5 ms at 3.333 MHz */
delay_5ms:
    ldi   r24, 50
    rjmp  delay_us_x100

wait_wif:
    lds   r17, TWI0_MSTATUS
    sbrs  r17, TWI_WIF_bp
    rjmp  wait_wif
    ret
wait_rif:
    lds   r17, TWI0_MSTATUS
    sbrs  r17, TWI_RIF_bp
    rjmp  wait_rif
    ret
