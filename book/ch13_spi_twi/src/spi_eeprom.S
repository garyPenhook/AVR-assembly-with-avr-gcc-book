/*
 * spi_eeprom.S — write one byte to a 25LC010A SPI EEPROM
 * Target:  ATtiny3217 @ 3.333 MHz internal oscillator
 * Wiring:
 *   PA1 (MOSI) → EEPROM SI
 *   PA2 (MISO) ← EEPROM SO
 *   PA3 (SCK)  → EEPROM SCK
 *   PA4 (CS)   → EEPROM CS̄  (active-low, software-controlled)
 *   3.3 V / GND as required; WP and HOLD tied high.
 *
 * What it does:
 *   1. Send WREN (Write Enable) command.
 *   2. Send WRITE command, address 0x00, data byte 0xA5.
 *   3. Poll status register until WIP (Write-In-Progress) clears.
 *   4. Halt.
 */

#include <avr/io.h>

/* ── 25LC010A command opcodes ─────────────────────────────────────────── */
.equ EEPROM_READ,   0x03    /* read memory                                 */
.equ EEPROM_WRITE,  0x02    /* write memory (page write)                   */
.equ EEPROM_WREN,   0x06    /* write enable latch                          */
.equ EEPROM_WRDI,   0x04    /* write disable                               */
.equ EEPROM_RDSR,   0x05    /* read status register                        */
.equ EEPROM_WRSR,   0x01    /* write status register                       */

.equ WIP_BIT,       0       /* status register bit 0: Write-In-Progress    */

/* ── Port A pin assignments ───────────────────────────────────────────── */
.equ MOSI_BIT,      1       /* PA1 output                                  */
.equ MISO_BIT,      2       /* PA2 input  (default)                        */
.equ SCK_BIT,       3       /* PA3 output                                  */
.equ CS_BIT,        4       /* PA4 output, CS active-low                   */

/* ── SPI0_CTRLA bit positions (used with ldi / sts) ─────────────────── */
/* MASTER = bit 5, ENABLE = bit 0, PRESC DIV/4 = 0b00 in bits[2:1]       */

/* ── Vector table ─────────────────────────────────────────────────────── */
.section .vectors, "ax", @progbits
.global __vectors
__vectors:
    rjmp  main          /* 0x0000: RESET                                    */
    .fill 30, 2, 0xCFFF /* fill remaining vectors with RJMP . (self-loop)  */

/* ── Text ─────────────────────────────────────────────────────────────── */
.section .text

/* ── spi_transfer — exchange one byte over SPI ──────────────────────── */
/*
 * Sends r16 and simultaneously receives a byte.
 * Returns received byte in r16.
 * Clobbers: r17 (status poll scratch)
 */
.global spi_transfer
spi_transfer:
    sts   SPI0_DATA, r16            /* writing DATA starts the transfer      */
.Lspi_wait:
    lds   r17, SPI0_INTFLAGS
    sbrs  r17, SPI_IF_bp            /* SPI_IF set when transfer complete      */
    rjmp  .Lspi_wait
    lds   r16, SPI0_DATA            /* reading DATA clears SPI_IF            */
    ret

/* ── cs_assert / cs_deassert — software chip-select ─────────────────── */
cs_assert:
    cbi   VPORTA_OUT, CS_BIT        /* CS low = selected                     */
    ret

cs_deassert:
    sbi   VPORTA_OUT, CS_BIT        /* CS high = deselected                  */
    ret

/* ── eeprom_wren — send Write Enable Latch command ──────────────────── */
eeprom_wren:
    rcall cs_assert
    ldi   r16, EEPROM_WREN
    rcall spi_transfer
    rcall cs_deassert
    ret

/* ── eeprom_write_byte — write one byte to EEPROM ───────────────────── */
/*
 * r24 = 8-bit EEPROM address (0x00–0x7F for 25LC010A)
 * r22 = data byte to write
 * Clobbers: r16, r17
 */
eeprom_write_byte:
    rcall eeprom_wren               /* must send WREN before every write     */

    rcall cs_assert
    ldi   r16, EEPROM_WRITE
    rcall spi_transfer              /* send WRITE opcode                     */
    mov   r16, r24
    rcall spi_transfer              /* send address byte                     */
    mov   r16, r22
    rcall spi_transfer              /* send data byte                        */
    rcall cs_deassert
    ret

/* ── eeprom_wait_wip — poll WIP until write cycle completes ─────────── */
/*
 * The 25LC010A has a maximum write cycle time of 5 ms.
 * Poll status register; wait until WIP (bit 0) = 0.
 */
eeprom_wait_wip:
.Lwip_poll:
    rcall cs_assert
    ldi   r16, EEPROM_RDSR
    rcall spi_transfer              /* send RDSR opcode                      */
    ldi   r16, 0xFF                 /* dummy byte: drives SCK to clock out SR*/
    rcall spi_transfer              /* r16 now holds status register         */
    rcall cs_deassert
    sbrc  r16, WIP_BIT              /* skip branch if WIP = 0 (done)         */
    rjmp  .Lwip_poll
    ret

/* ── main ─────────────────────────────────────────────────────────────── */
.global main
main:
    /* Stack pointer */
    ldi   r16, hi8(RAMEND)
    out   SPH, r16
    ldi   r16, lo8(RAMEND)
    out   SPL, r16

    /* Configure PA1 (MOSI), PA3 (SCK), PA4 (CS) as outputs.
     * PA2 (MISO) stays as input (reset default). */
    ldi   r16, (1 << MOSI_BIT) | (1 << SCK_BIT) | (1 << CS_BIT)
    out   VPORTA_DIR, r16

    /* Deselect EEPROM: CS high */
    sbi   VPORTA_OUT, CS_BIT

    /* SPI0 initialisation — master, SPI mode 0 (CPOL=0, CPHA=0), f/4
     *
     * SPI0_CTRLB: SSD_bm (bit 2) — disable hardware SS so we drive CS
     *             manually via VPORTA_OUT.  MODE = 0b00 = SPI mode 0.
     * SPI0_CTRLA: MASTER_bm | ENABLE_bm, PRESC=DIV4 (bits[2:1]=0b00).
     */
    ldi   r16, SPI_SSD_bm           /* slave select disabled (manual CS)     */
    sts   SPI0_CTRLB, r16

    ldi   r16, (SPI_MASTER_bm | SPI_ENABLE_bm)
    sts   SPI0_CTRLA, r16

    /* Write 0xA5 to EEPROM address 0x00 */
    ldi   r24, 0x00                 /* address                               */
    ldi   r22, 0xA5                 /* data                                  */
    rcall eeprom_write_byte

    /* Wait for internal write cycle to complete */
    rcall eeprom_wait_wip

    /* Halt */
.Lhalt:
    rjmp  .Lhalt
