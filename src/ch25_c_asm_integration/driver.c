#include <stdint.h>
/* Prototypes must match the ABI the assembly assumes. */
extern uint16_t asm_add16(uint16_t a, uint16_t b);
extern void     asm_fill(uint8_t *p, uint8_t val, uint8_t n);
extern uint8_t  asm_sum(const uint8_t *p, uint8_t n);

volatile uint16_t sum16;
volatile uint8_t  total;
uint8_t buf[8];

static inline uint8_t nibble_swap(uint8_t x){
    __asm__("swap %0" : "+r"(x));   /* swap nibbles in place */
    return x;
}

int main(void){
    sum16 = asm_add16(0x1234, 0x1111);   /* -> 0x2345 */
    asm_fill(buf, 0xAA, sizeof buf);     /* C passes &buf[0], 0xAA, 8 */
    total = asm_sum(buf, sizeof buf);    /* -> 0x50 (8 * 0xAA mod 256) */
    total += nibble_swap(0x3C);          /* -> +0xC3 */
    __asm__ volatile("" ::: "memory");   /* compiler barrier */
    for(;;){}
}
