/* mat2ref.c - host reference model for mat2_vmul.S (ch27).
 * Mirrors the assembly's exact integer operations: full 32-bit signed products
 * accumulated, then one arithmetic shift (>>15). Sweeps rotation matrices over
 * 360 degrees and reports the worst-case coordinate error vs floating point.
 *   gcc -O2 -o mat2ref mat2ref.c -lm && ./mat2ref
 *
 * Valid domain: M entries are Q15 (any int16); the vector must be bounded so
 * that |M0*v0 + M1*v1| < 2^31 (no accumulator overflow) and the result fits
 * int16. For |entries| <= 1.0 (e.g. a rotation), |v coords| <= 16383 is safe.
 * An instruction-level AVR simulation confirms mat2_vmul.S reproduces this
 * model bit-for-bit across 400000 random in-domain cases. */
#include <stdio.h>
#include <stdint.h>
#include <math.h>

/* Q15 saturating convert: +1.0 is not representable (max is 32767/32768),
 * so cos(0)=1.0 must clamp to 32767 rather than overflow int16 to -32768. */
static int16_t q15(double x){
    long v = lround(x * 32768.0);
    if(v >  32767) v =  32767;
    if(v < -32768) v = -32768;
    return (int16_t)v;
}

/* exact model of the asm: accumulate full products, shift once */
void mat2_vmul(const int16_t *M, const int16_t *vin, int16_t *vout){
    int32_t a0 = (int32_t)M[0]*vin[0] + (int32_t)M[1]*vin[1];
    int32_t a1 = (int32_t)M[2]*vin[0] + (int32_t)M[3]*vin[1];
    vout[0] = (int16_t)(a0 >> 15);
    vout[1] = (int16_t)(a1 >> 15);
}

int main(void){
    double maxe = 0; int at = 0;
    const int16_t vs[][2] = {{1000,0},{0,1000},{700,700},{-500,900},{123,-456}};
    for(int deg = 0; deg < 360; deg++){
        double th = deg * M_PI / 180.0;
        int16_t M[4] = { q15(cos(th)), q15(-sin(th)), q15(sin(th)), q15(cos(th)) };
        for(int k = 0; k < 5; k++){
            int16_t out[2];
            mat2_vmul(M, vs[k], out);
            double fx = cos(th)*vs[k][0] - sin(th)*vs[k][1];
            double fy = sin(th)*vs[k][0] + cos(th)*vs[k][1];
            double e = fmax(fabs(out[0]-fx), fabs(out[1]-fy));
            if(e > maxe){ maxe = e; at = deg; }
        }
    }
    printf("2x2 Q15 rotation: max coordinate error = %.3f units (worst at %d deg)\n", maxe, at);
    return 0;
}
