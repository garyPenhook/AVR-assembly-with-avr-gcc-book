# Bit-Banging a UART

The USART chapter used dedicated hardware to send serial data: you load a byte
and the peripheral clocks it out at the configured baud rate. Bit-banging does
the same job with no peripheral at all — just an ordinary GPIO pin and a loop
that counts CPU cycles. It is slower to design and burns the CPU while it runs,
but it works on any pin, on a part whose USART is busy or absent, and it is the
purest demonstration of why assembly matters: here, the timing *is* the code.

This chapter builds a software UART transmitter. The receiver is harder and is
discussed at the end. The transmitter is the right place to learn the core
skill — making a loop take an exact, known number of cycles — because the same
technique drives every timing-critical protocol: WS2812 LEDs (where a bit is
~350 ns), 1-Wire, software SPI, and DHT-style sensors.

This chapter covers:

1. The asynchronous serial frame, and why timing is the whole problem
2. Turning a baud rate into a cycle count
3. A delay loop with an exact, known duration
4. Driving a pin in constant time regardless of the data bit
5. Assembling the frame so every bit costs the same
6. The complete `uart_putc`, annotated cycle by cycle
7. Retargeting the baud rate and clock; the limits of bit-banging

---

## The Serial Frame

Asynchronous serial (the "UART" line format) sends one byte as a frame of bits,
each held on the wire for one **bit time**. There is no clock line — the
receiver recovers timing from the falling edge of the start bit, then samples
each following bit at its expected center. That only works if sender and
receiver agree on the bit time to within a couple of percent.

For 8N1 (8 data bits, no parity, 1 stop bit), idle-high, **LSB first**:

```
idle   start   d0  d1  d2  d3  d4  d5  d6  d7   stop   idle
 1   →   0   →  ─────────── 8 data bits ──────   1   →  1
         ↑                                        ↑
   falling edge                            line returns high
   (receiver syncs here)
```

The transmitter's only job is to put each of those ten bits on the pin and hold
it for exactly one bit time. Everything in this chapter is in service of "hold
it for exactly one bit time."

---

## From Baud Rate to Cycle Count

A baud rate is bits per second. One bit time, measured in CPU cycles, is:

```
BIT_CYCLES = f_cpu / baud
```

On the factory-default ATtiny3217 clock (OSC20M / 6 = 3.333 MHz) at 9600 baud:

```
BIT_CYCLES = 3333333 / 9600 = 347.2  ->  347 cycles
```

Rounding to 347 gives an actual rate of `3333333 / 347 = 9606` baud — an error
of **+0.06%**. A UART receiver samples at mid-bit and tolerates roughly ±2-3%
of accumulated error across a frame, so a fraction of a percent is comfortable.

The task is now concrete: **make each bit cell take exactly 347 CPU cycles.**
That is an instruction-counting problem, and on AVR every instruction's cycle
count is fixed and documented, so it is solvable exactly.

---

## A Delay of an Exact Length

The workhorse is a counted delay loop:

```asm
    ldi   r19, COUNT
.Ldly:
    dec   r19
    brne  .Ldly
```

On the ATtiny3217 core, `DEC` is 1 cycle, `BRNE` is 2 cycles when the branch is
taken and 1 when it falls through. For `COUNT` iterations the loop body costs:

```
(COUNT-1) iterations taken:  (1 + 2) cycles each
1 final iteration:           (1 + 1) cycles
loop total:                  3*COUNT - 1
plus the LDI:                3*COUNT cycles
```

So `LDI` + loop is exactly `3 * COUNT` cycles. To hit a target that is not a
multiple of three, pad with `NOP`s (1 cycle each). That is the entire trick: a
multiple-of-three delay from the loop, plus up to two `NOP`s to trim.

---

## Driving the Pin in Constant Time

A subtle trap: the obvious "if the bit is 1 set the pin, else clear it" branches,
and a taken branch costs a different number of cycles than a skipped one — so a
`1` bit and a `0` bit would have *different* periods, smearing the timing in a
data-dependent way. The fix is an idiom that takes the same time either way:

```asm
    sbrc  r24, 0               ; skip next if frame bit 0 is clear
    sbi   VPORTB_OUT, TXD_BIT  ;   bit = 1: drive high
    sbrs  r24, 0               ; skip next if frame bit 0 is set
    cbi   VPORTB_OUT, TXD_BIT  ;   bit = 0: drive low
```

`SBI`/`CBI` are 1 cycle on this core; `SBRC`/`SBRS` are 1 cycle normally and 2
when they skip a one-word instruction. Trace both values:

```
bit = 1:  sbrc (no skip, 1) + sbi (1) + sbrs (skip cbi, 2)          = 4 cycles
bit = 0:  sbrc (skip sbi, 2) + sbrs (no skip, 1) + cbi (1)          = 4 cycles
```

Four cycles regardless of the data — the skip simply lands on the other
instruction. The pin is driven correctly and the bit cell's length never depends
on what is being sent. (`VPORTB_OUT` is at I/O address `0x05`, in the
`SBI`/`CBI`-addressable low range, so single-cycle bit writes are available.)

---

## Assembling the Frame

Rather than special-case the start and stop bits, pack the whole 10-bit frame —
plus idle ones — into a 16-bit shift register and emit it one bit at a time with
the *same* code. Then start, data, and stop bits all cost identical cycles.

```
bit:   15 14 13 12 11 10  9 | 8  7  6  5  4  3  2  1 | 0
       ───── idle/stop ─────   d7 d6 d5 d4 d3 d2 d1 d0   start
        1  1  1  1  1  1  1    ←──── data (LSB first) ──   0
```

So the low byte is `data << 1` (shifting the start `0` into bit 0), and the high
byte is `0xFE` with the data's top bit dropped into its bit 0:

```asm
    mov   r23, r24             ; keep the original data
    lsl   r24                  ; low byte = data<<1, bit0 = 0 (start)
    ldi   r25, 0xFE            ; high byte: bits 9..15 = 1 (stop + idle)
    bst   r23, 7               ; T = data bit 7
    bld   r25, 0               ; high byte bit 0 = data bit 7 (frame bit 8)
```

Emitting `start, d0..d7, stop` is then just "output bit 0, shift the 16-bit
register right, repeat 10 times." The shift is `LSR` on the high byte feeding
`ROR` on the low byte.

---

## The Complete Transmitter

The full source is [uart_tx_bitbang.S](src/uart_tx_bitbang.S). The constants are
derived once from the target:

```asm
.equ DELAY_COUNT, 112          /* 3*112 = 336 cycles of bit-time delay */
.equ NOP_PAD,     2            /* 336 + 2 + 11 overhead = 347 = BIT_CYCLES */
```

```asm
.global uart_putc
uart_putc:
    mov   r23, r24             /* assemble the 16-bit frame...           */
    lsl   r24
    ldi   r25, 0xFE
    bst   r23, 7
    bld   r25, 0

    ldi   r18, 10              /* start + 8 data + stop                  */
.Lbit:
    sbrc  r24, 0               /* drive TX to frame bit 0  (4 cycles,     */
    sbi   VPORTB_OUT, TXD_BIT  /*   independent of the bit value)         */
    sbrs  r24, 0
    cbi   VPORTB_OUT, TXD_BIT

    lsr   r25                  /* shift the frame right one bit  (2)      */
    ror   r24

    ldi   r19, DELAY_COUNT     /* bit-time delay: ldi + loop = 336 (1+335)*/
.Ldly:
    dec   r19
    brne  .Ldly
    nop                        /* trim: NOP_PAD = 2                       */
    nop

    dec   r18                  /* next bit  (1)                           */
    brne  .Lbit                /* (2 taken)                               */
    ret
```

Adding up one bit cell:

```
output idiom (sbrc/sbi/sbrs/cbi)   4
shift (lsr + ror)                  2
ldi + delay loop                 336   (= 3 * 112)
nop + nop                          2
dec + brne (taken)                 3
-------------------------------------
per bit                          347 cycles  ->  9606 baud
```

Every one of the ten bit cells runs this identical path, so each is 347 cycles
(the final stop bit is one cycle shorter, since its `BRNE` falls through — the
line stays idle-high afterward, so it does not matter). The byte goes out LSB
first, framed by a low start bit and a high stop bit, at 9600 baud.

`main` sets PB2 idle-high and an output, then sends a short message a byte at a
time. PB2 is the pin USART0 uses on the Curiosity Nano, so the bit-banged output
reaches the on-board debugger's serial port exactly as the hardware USART's
would — a terminal at 9600 8N1 shows `Hi!`.

---

## Retargeting and Limits

To change the baud rate or clock, recompute `BIT_CYCLES = f_cpu / baud`, then
solve `3*DELAY_COUNT + NOP_PAD + 11 = BIT_CYCLES` for the loop count and pad
(the constant `11` is the fixed per-bit overhead: output 4, shift 2, nop-slots,
loop tail). At very high baud the delay shrinks until the 11-cycle overhead
dominates and the rate can no longer be hit precisely; at very low baud `COUNT`
may exceed 255 and the delay needs a 16-bit counter or a nested loop.

Bit-banging trades hardware for cycles, and the trade has sharp edges:

```
Hardware USART                  Bit-banged UART
----------------------------    ----------------------------------
Clocks bits in the background   Burns the CPU for the whole frame
Fixed pins                      Any GPIO pin
Interrupt on each byte          An interrupt mid-frame corrupts timing
Baud from a divider register    Baud from a hand-counted loop
```

The third row is the one that bites: because the timing lives in the instruction
stream, an interrupt firing mid-frame adds its latency to a bit cell and skews
the rest of the byte. Bit-banged transmit usually runs with interrupts disabled
for the duration of the frame, or budgets a worst-case ISR that is far shorter
than the timing margin.

Receive is harder still. The transmitter chooses when each edge happens; the
receiver must *find* the start edge (typically a pin-change interrupt or a tight
polling loop), wait half a bit time to reach the first bit's center, then sample
every bit time after that — all while tolerating the sender's clock being a
little off. It is doable with the same cycle-counting tools, but the timing
budget is tighter and the edge cases (framing errors, noise on the start edge)
are real. For two-way serial on a part with a spare USART, use the hardware.

---

## Summary

```
Bit-banging: emit a serial frame from a GPIO pin by counting CPU cycles.

Bit time:    BIT_CYCLES = f_cpu / baud   (3.333 MHz, 9600 -> 347 cycles)

Exact delay: ldi + (dec; brne) loop = 3*COUNT cycles; trim with NOPs.

Constant-time pin: sbrc/sbi/sbrs/cbi drives the pin in 4 cycles whether the
  bit is 0 or 1 (the skip lands on the other instruction) — no data-dependent
  timing.

Frame as a shift register: pack start(0) + 8 data + stop(1) + idle(1s) into a
  16-bit value; emit bit 0, shift right, x10 — every bit cell identical.

Caveats: CPU is busy for the whole frame; disable interrupts (or bound ISR
  latency) so nothing skews the timing; receive is markedly harder.
```

---

## Exercises

1. Recompute `DELAY_COUNT` and `NOP_PAD` for 19200 baud at 3.333 MHz. What is the
   actual baud and the error? How much delay is left once the 11-cycle overhead
   is removed?

2. The output idiom takes 4 cycles for both bit values. Rewrite the pin drive
   with an ordinary `BRNE`/`RJMP` branch and show, cycle by cycle, how a `1` bit
   and a `0` bit end up with different periods.

3. `uart_putc` runs with interrupts wherever the caller left them. Add the
   `CLI`/`SEI` guard around the frame and explain why a single timer ISR firing
   between two bits would corrupt the byte without it.

4. Change the clock to 20 MHz (no /6 prescaler) and retarget for 115200 baud.
   Does the 11-cycle overhead still leave room to hit the rate? What is the
   smallest delay you can express, and what baud does that cap correspond to?

5. Extend `main` to send a NUL-terminated string instead of a fixed-length one:
   loop until the loaded byte is zero. Which register holds the byte, and where
   does the terminator test go?

6. Sketch the receive side: a pin-change interrupt catches the start edge, then
   the handler delays half a bit time and samples eight bits one bit time apart.
   Why the *half* bit time first, and what goes wrong if it is omitted?

---

*Next: SPI & TWI (I2C) Overview*
