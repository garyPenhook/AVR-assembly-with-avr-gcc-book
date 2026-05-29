/*
 * microsd_spi.S — SPI-mode init skeleton for the Explorer's microSD socket.
 *
 * Curiosity Nano Explorer (EV58G97A). microSD card socket on the SPI bus.
 *   SPI bus : COM-section SPI0 (MOSI = PA1, MISO = PA2, SCK = PA3)
 *   CS      : Explorer "uSD CS/D3" = IO-25 (this file assumes a jumper to PC1)
 *   (A 47 kohm pull-up on MISO makes it idle high.)
 *
 * SPI-mode card bring-up (this skeleton does the first steps):
 *   1. >= 74 clocks with CS high and MOSI high (card enters SPI mode)
 *   2. CMD0  (GO_IDLE_STATE),  CRC 0x95, expect R1 = 0x01
 *   3. CMD8  (SEND_IF_COND),   arg 0x000001AA, CRC 0x87, read R1 + 4 bytes
 * A full driver then loops ACMD41 until ready and issues CMD58. Initialise at
 * <= 400 kHz, then raise the clock. Verify on hardware.
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o microsd_spi.o microsd_spi.S
 *   avr-gcc -mmcu=attiny3217 -nostartfiles -o microsd_spi.elf microsd_spi.o
 */

#include <avr/io.h>

.equ CS_PIN,    1               /* PC1 <- Explorer IO-25 (uSD CS)            */
.equ SPI_PRESC_DIV128,  (3 << 1)    /* PRESC field value (SPI_PRESC_DIV128_gc) */

.section .bss
r7buf:      .skip 4             /* CMD8 trailing 4 bytes                     */

.section .text
.global main

main:
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    rcall spi_init_slow
    rcall sd_power_on_clocks

    /* CMD0: arg 0, CRC 0x95 -> expect R1 = 0x01 (idle) */
    ldi   r24, 0
    clr   r18
    clr   r19
    clr   r20
    clr   r21
    ldi   r22, 0x95
    rcall sd_send_cmd          /* r24 = R1                                  */

    /* CMD8: arg 0x000001AA, CRC 0x87 */
    ldi   r24, 8
    clr   r18                  /* arg[31:24]                                */
    clr   r19                  /* arg[23:16]                                */
    ldi   r20, 0x01            /* arg[15:8]                                 */
    ldi   r21, 0xAA            /* arg[7:0]                                  */
    ldi   r22, 0x87
    rcall sd_send_cmd          /* r24 = R1                                  */
    rcall sd_read_r7tail       /* read 4 trailing bytes into r7buf          */

.Lhalt:
    rjmp  .Lhalt

/* ------------------------------------------------------------------------- */
/* spi_init_slow — SPI0 master, slow clock (prescaler /128) for card init    */
spi_init_slow:
    ldi   r16, (1 << 1) | (1 << 3)
    out   VPORTA_DIR, r16
    sbi   VPORTC_DIR, CS_PIN
    sbi   VPORTC_OUT, CS_PIN    /* CS idle high                              */
    ldi   r16, SPI_SSD_bm
    sts   SPI0_CTRLB, r16
    /* master, PRESC /128, enable -> ~26 kHz at 3.333 MHz (well under 400k)  */
    ldi   r16, SPI_MASTER_bm | SPI_PRESC_DIV128 | SPI_ENABLE_bm
    sts   SPI0_CTRLA, r16
    ret

/* sd_power_on_clocks — 80 clocks (10 bytes of 0xFF) with CS high */
sd_power_on_clocks:
    sbi   VPORTC_OUT, CS_PIN
    ldi   r20, 10
.Lpc:
    ldi   r16, 0xFF
    rcall spi_xfer
    dec   r20
    brne  .Lpc
    ret

/*
 * sd_send_cmd — send a 6-byte SPI command and read the R1 response
 *   r24 = command index, r18:r19:r20:r21 = arg[31:0], r22 = CRC byte
 *   returns r24 = R1 (0xFF if no response within the poll window)
 */
sd_send_cmd:
    cbi   VPORTC_OUT, CS_PIN
    mov   r16, r24
    ori   r16, 0x40            /* start bits 01 + command index             */
    rcall spi_xfer
    mov   r16, r18
    rcall spi_xfer
    mov   r16, r19
    rcall spi_xfer
    mov   r16, r20
    rcall spi_xfer
    mov   r16, r21
    rcall spi_xfer
    mov   r16, r22
    rcall spi_xfer            /* CRC (+ stop bit)                          */

    /* poll up to 256 bytes for a response (bit7 clears) */
    ldi   r20, 0
.Lr1:
    ldi   r16, 0xFF
    rcall spi_xfer
    sbrs  r16, 7              /* response when MSB = 0                      */
    rjmp  .Lr1_done
    dec   r20
    brne  .Lr1
.Lr1_done:
    mov   r24, r16
    /* leave CS asserted for any trailing read; caller raises it or reads R7 */
    ret

/* sd_read_r7tail — read 4 trailing bytes (CMD8/CMD58), then deselect */
sd_read_r7tail:
    ldi   YL, lo8(r7buf)
    ldi   YH, hi8(r7buf)
    ldi   r20, 4
.Lr7:
    ldi   r16, 0xFF
    rcall spi_xfer
    st    Y+, r16
    dec   r20
    brne  .Lr7
    sbi   VPORTC_OUT, CS_PIN
    ldi   r16, 0xFF            /* extra clocks after deselect               */
    rcall spi_xfer
    ret

/* spi_xfer — r16 out, returns r16 in */
spi_xfer:
    sts   SPI0_DATA, r16
.Lsx:
    lds   r17, SPI0_INTFLAGS
    sbrs  r17, SPI_IF_bp
    rjmp  .Lsx
    lds   r16, SPI0_DATA
    ret
