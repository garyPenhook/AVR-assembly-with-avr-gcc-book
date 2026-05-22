#include <stdint.h>
#include <avr/io.h>

void memcpy_naive(uint8_t *dst, const uint8_t *src, uint8_t len);
void memcpy_fast(uint8_t *dst, const uint8_t *src, uint8_t len);
uint8_t sin8(uint8_t angle);

static const uint8_t src[16] = {
    0x00,0x11,0x22,0x33,0x44,0x55,0x66,0x77,
    0x88,0x99,0xAA,0xBB,0xCC,0xDD,0xEE,0xFF
};

volatile uint8_t dst_naive[16];
volatile uint8_t dst_fast[16];
volatile uint8_t sine_result;

int main(void) {
    memcpy_naive((uint8_t *)dst_naive, src, 16);
    memcpy_fast((uint8_t *)dst_fast,  src, 16);
    sine_result = sin8(64);   /* angle = 64 → ~90 degrees → result ≈ 255   */
    for (;;);
    return 0;
}
