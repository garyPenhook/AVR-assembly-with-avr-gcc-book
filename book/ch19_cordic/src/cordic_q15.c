#include <stdint.h>

static const uint16_t cordic_atan_bam16[12] = {
    0x2000, 0x12E4, 0x09FB, 0x0511,
    0x028B, 0x0146, 0x00A3, 0x0051,
    0x0029, 0x0014, 0x000A, 0x0005
};

#define CORDIC_K_Q15 ((int16_t)0x4DB9)

/*
 * cordic_sincos_bam16
 *
 * Input:
 *   angle      - BAM16 angle, 0x0000..0xFFFF for 0..360 degrees
 *
 * Output:
 *   *cos_q15   - cosine in signed Q1.15
 *   *sin_q15   - sine   in signed Q1.15
 *
 * Notes:
 *   - Uses 12 CORDIC stages.
 *   - Reduces the input angle into the first quadrant, then applies
 *     final sign correction.
 *   - Written as a simple correctness reference for AVR builds.
 */
void cordic_sincos_bam16(uint16_t angle, int16_t *cos_q15, int16_t *sin_q15)
{
    uint8_t quadrant = angle >> 14;
    int16_t z;
    int8_t cos_sign = 1;
    int8_t sin_sign = 1;

    switch (quadrant) {
    case 0:
        z = (int16_t)angle;
        break;
    case 1:
        z = (int16_t)(0x8000u - angle);
        cos_sign = -1;
        break;
    case 2:
        z = (int16_t)(angle - 0x8000u);
        cos_sign = -1;
        sin_sign = -1;
        break;
    default:
        z = (int16_t)(0u - angle);
        sin_sign = -1;
        break;
    }

    int16_t x = CORDIC_K_Q15;
    int16_t y = 0;

    for (uint8_t i = 0; i < 12; i++) {
        int16_t x_shift = (int16_t)(x >> i);
        int16_t y_shift = (int16_t)(y >> i);
        int16_t x_new;
        int16_t y_new;

        if (z >= 0) {
            x_new = (int16_t)(x - y_shift);
            y_new = (int16_t)(y + x_shift);
            z = (int16_t)(z - (int16_t)cordic_atan_bam16[i]);
        } else {
            x_new = (int16_t)(x + y_shift);
            y_new = (int16_t)(y - x_shift);
            z = (int16_t)(z + (int16_t)cordic_atan_bam16[i]);
        }

        x = x_new;
        y = y_new;
    }

    *cos_q15 = (cos_sign > 0) ? x : (int16_t)-x;
    *sin_q15 = (sin_sign > 0) ? y : (int16_t)-y;
}
