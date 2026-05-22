/*
 * main.c — call assembly CRC-8 routine from C
 * Target: ATtiny3217 @ 3.333 MHz
 *
 * Build:
 *   avr-gcc -mmcu=attiny3217 -O2 -o crc_demo.elf main.c crc8.S
 *   avr-objcopy -O ihex crc_demo.elf crc_demo.hex
 */

#include <stdint.h>
#include <avr/io.h>

/* Declare the assembly function — implemented in crc8.S */
uint8_t crc8(const uint8_t *data, uint8_t len);

/* Store checksum here so the linker keeps the call (not optimised away) */
volatile uint8_t result;

int main(void) {
    const uint8_t msg[] = {0x01, 0x02, 0x03, 0x04};

    result = crc8(msg, sizeof(msg));
    /* Expected CRC-8/SMBUS of {0x01,0x02,0x03,0x04} = 0x84 */

    for (;;);
    return 0;
}
