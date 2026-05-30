/* sinref.c - host reference model for q15_sin.S (ch26).
 * Mirrors the assembly's exact fixed-point integer operations (arithmetic
 * shifts, Q15 coeffs, Q14 input) and sweeps all valid inputs, reporting the
 * worst-case error against the C library sin(). Build & run on the host:
 *     gcc -O2 -o sinref sinref.c -lm && ./sinref
 * An instruction-level simulation (with correct AVR carry semantics) confirms
 * q15_sin.S reproduces this model bit-for-bit on all 25737 inputs. */
#include <stdio.h>
#include <stdint.h>
#include <math.h>
static const int16_t c1=32761, c3=-5434, c5=248;
static inline int16_t smul(int16_t a,int16_t b,int sh){int32_t p=(int32_t)a*b; return (int16_t)(p>>sh);}
/* find the raw (unsaturated) value range of the last product */
int32_t q15_sin_raw(int16_t x){
    int16_t x2=smul(x,x,15), p=c5;
    p=(int16_t)(c3+smul(p,x2,13));
    p=(int16_t)(c1+smul(p,x2,13));
    return ((int32_t)p*x)>>14;            /* raw, may exceed 32767 */
}
int16_t q15_sin(int16_t x){               /* saturating version */
    int32_t r=q15_sin_raw(x);
    if(r>32767) r=32767;
    return (int16_t)r;
}
int main(void){
    int32_t rawmax=-1<<30; double rawat=0;
    for(int i=0;i<=25736;i++){int32_t r=q15_sin_raw((int16_t)i); if(r>rawmax){rawmax=r;rawat=i/16384.0;}}
    printf("raw max = %d  (Q15 max is 32767) at x=%.4f  -> overshoot of %d LSB\n",rawmax,rawat,rawmax-32767);
    double maxe=0,at=0;
    for(int i=0;i<=25736;i++){double x=i/16384.0,a=q15_sin((int16_t)i)/32768.0,e=fabs(a-sin(x)); if(e>maxe){maxe=e;at=x;}}
    printf("SATURATED max|err| = %.6e (~%.1f LSB) at x=%.4f\n",maxe,maxe*32768,at);
    return 0;
}
