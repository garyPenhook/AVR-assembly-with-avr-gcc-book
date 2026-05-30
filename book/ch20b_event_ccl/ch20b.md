<!--
DRAFT — verified against ATtiny3216-17-DataSheet (DS40002205A), section 15
(EVSYS) and section 28 (CCL):
  CONFIRMED CCL (p.409): 2 LUTs (LUT0/LUT1) + 1 sequential block; no LUT2CTRLA.
             Register layout matches: CTRLA(RUNSTDBY,ENABLE); SEQCTRL0(SEQSEL);
             LUTnCTRLA(EDGEDET,CLKSRC,FILTSEL,OUTEN,ENABLE);
             LUTnCTRLB(INSEL1,INSEL0); LUTnCTRLC(INSEL2); TRUTHn(TRUTH[7:0]).
  CONFIRMED EVSYS layout: ASYNCCH0..3 (p.155) / SYNCCH0..1 (p.153) +
             ASYNCUSER0..12 (p.158) / SYNCUSER0..1 (p.160).
  CONFIRMED generators: async = OFF,CCL_LUT0/1,AC0_OUT,TCD0_*,RTC_OVF,RTC_CMP,
             PORT pins (CH0=PORTA,CH1=PORTB,CH2=PORTC,CH3=PORTA). sync = TCB0,
             TCA0_OVF_LUNF/HUNF/CMP0..2, PORTC/PORTB pins.
  CONFIRMED users: ASYNCUSER 0=TCB0,1=ADC0,2=CCL_LUT0_EV0,3=CCL_LUT1_EV0,
             4=CCL_LUT0_EV1,5=CCL_LUT1_EV1,6=TCD0_EV0,7=TCD0_EV1,8=EVOUTA(PA2),
             9=EVOUTB(PB2),10=EVOUTC(PC2),11=TCB1,12=ADC1. SYNCUSER 0=TCA0,
             1=USART0. KEY GOTCHA: ADC0 is an ASYNC user; TCA0/TCB0 are SYNC
             generators -> cannot feed ADC0 directly (use RTC/TCD0). Examples
             reflect this.
  CONFIRMED CCL pins (24-pin) from datasheet Table 5-1 (printed p.16, extracted
             as text via get_document_page) AND cross-checked against the DFP
             ATDF <signal> pad entries — both agree: LUT0 IN0=PA0 IN1=PA1 IN2=PA2
             OUT=PA4 (alt PB4); LUT1 IN0=PC3 IN1=PC4 IN2=PC5 OUT=PA7 (alt PC1).
             20-pin SOIC omits PC4/PC5. (src CCL demo still routes out via
             EVSYS->EVOUTA(PA2), so it is package-independent.)
CONSTANTS NOTE: the _gc group-config names below (e.g. EVSYS_ASYNCCH0_RTC_OVF_gc)
exist in iotn3217.h but as C *enum* members, NOT #define macros, so the
assembler cannot see them — assembling a .S that uses a bare _gc gives
"undefined reference". The _bm/_bp bit constants ARE #defines and work in .S.
The companion src/ files therefore define these selection values with .equ from
the datasheet (and build clean with stock avr-gcc). The code blocks in the prose
keep the readable _gc names for clarity; see src/ for the assemblable form.
-->


# Event System and Configurable Custom Logic

The peripherals in the previous chapters all needed the CPU to move data: read a
flag, set a bit, start a conversion. This chapter covers two peripherals that let
other peripherals talk to each other *directly*, with the CPU asleep or busy
elsewhere:

- The **Event System (EVSYS)** routes a signal ("event") from one peripheral to
  another over dedicated channels. A timer overflow can start an ADC conversion,
  or a pin change can reset a counter, with zero instructions executed.
- **Configurable Custom Logic (CCL)** is a small block of programmable logic
  gates. Each look-up table (LUT) implements any Boolean function of up to three
  inputs, optionally clocked or filtered, and its inputs and outputs can be other
  peripherals or pins.

Together they form the chip's "digital fabric": glue logic that used to require
external 74-series chips, now built in and wired in software.

## Chapter structure (read this first)

```
This chapter covers:
  1. Why hardware event routing matters (latency, power, determinism)
  2. EVSYS architecture: generators, channels, users
  3. Asynchronous vs synchronous channels on the ATtiny3217
  4. Example: mirror a pin to an event-output pin (no CPU)
  5. Example: trigger an ADC conversion from a timer event
  6. CCL architecture: LUTs, truth tables, inputs, the sequential block
  7. Example: a LUT as a simple gate driving a pin
  8. Example: feeding a LUT from an event (EVSYS + CCL together)
  9. What you learned, register quick reference, exercises
```

## Why Route Events in Hardware?

Consider starting an ADC conversion every time a timer overflows. The software
way is an interrupt service routine:

```
timer overflow  ->  ISR fires  ->  push regs  ->  write ADC START  ->  pop regs  ->  reti
```

Every step costs cycles, and the time between the overflow and the actual start
*jitters* depending on what the CPU was doing. For sampling at a precise rate,
jitter is noise.

The hardware way is one event channel:

```
timer overflow  ->  event channel  ->  ADC start   (fixed latency, no code)
```

The connection is configured once at startup. After that it works while the CPU
sleeps, which also saves power. The trade-offs:

```
                 Software (ISR)            Event System
──────────────────────────────────────────────────────────────────
Latency          variable (jitter)         fixed, deterministic
CPU cost         cycles per event          zero after setup
Works in sleep   only if ISR wakes CPU     yes (async channels)
Flexibility      arbitrary code            fixed routing + CCL logic
```

## EVSYS Architecture

The Event System has three roles. A peripheral that produces a signal is a
**generator**. A peripheral that consumes one is a **user**. Between them runs a
**channel**:

```
   GENERATOR                CHANNEL              USER
 ┌───────────┐          ┌───────────┐       ┌───────────┐
 │ TCA0 OVF  │─────────▶│ channel n │──────▶│ ADC0 start│
 │ AC0 out   │          └───────────┘       │ TCB capture│
 │ pin edge  │                              │ CCL LUT in │
 │ RTC PIT   │                              │ EVOUT pin  │
 └───────────┘                              └───────────┘
```

You configure two things:

1. **Which generator drives a channel** — write the generator's selection value
   into that channel register.
2. **Which channel a user listens to** — write the channel into that user's
   register.

One generator can feed many users (they all select the same channel). A channel
carries exactly one generator at a time.

## Asynchronous vs Synchronous Channels

The ATtiny3217 (tinyAVR 1-series) splits channels into two kinds. This split is
the most common stumbling block, so it is worth understanding before writing any
code.

```
Async channels   ASYNCCH0..ASYNCCH3   pass events with no clock; work in sleep,
                                      can carry very short pulses and edges.
Sync channels    SYNCCH0..SYNCCH1     events are sampled on the peripheral clock;
                                      needed by users that expect a clocked event.
```

A user can only listen to the channel type it supports. Async users select an
async channel via their `ASYNCUSERn` register; sync users select a sync channel
via `SYNCUSERn`. Match the channel type to both the generator's nature and the
user's requirement.

```
EVSYS registers (tinyAVR 1-series layout):

  EVSYS.ASYNCCH0..3     pick the generator for each async channel
  EVSYS.SYNCCH0..1      pick the generator for each sync channel
  EVSYS.ASYNCUSER0..12  pick the async channel each async user listens to
  EVSYS.SYNCUSER0..1    pick the sync channel each sync user listens to
  EVSYS.ASYNCSTROBE     fire a software event on async channels
  EVSYS.SYNCSTROBE      fire a software event on sync channels
```

Note: this layout differs from the unified `CHANNEL`/`USER` model on the
megaAVR 0-series and newer AVR DA/DB parts. Code from those families does not
port directly.

### Generators (what can drive a channel)

Verified against the ATtiny3217 datasheet (section 15). Peripheral generators
(CCL, AC0, TCD0, RTC) are available on every async channel; the PORT pin
generators differ per channel. Timers TCA0/TCB0 are *sync*-only generators.

```
ASYNC generators (ASYNCCH0..3)        SYNC generators (SYNCCH0..1)
──────────────────────────────────   ──────────────────────────────
OFF            CCL_LUT0  CCL_LUT1     OFF            TCB0
AC0_OUT        RTC_OVF   RTC_CMP      TCA0_OVF_LUNF  TCA0_HUNF
TCD0_CMPBCLR   TCD0_CMPASET           TCA0_CMP0  TCA0_CMP1  TCA0_CMP2
TCD0_CMPBSET   TCD0_PROGEV            PORTC pins, then PORTB pins
PORT pins:  CH0=PORTA  CH1=PORTB
            CH2=PORTC  CH3=PORTA
```

### Users (what can listen to a channel)

Each user has a fixed index; you write the channel number into that user's
register. Async users select an async channel; sync users a sync channel.

```
ASYNC users (write to ASYNCUSERn)     SYNC users (write to SYNCUSERn)
──────────────────────────────────   ──────────────────────────────
0  TCB0            7  TCD0_EV1        0  TCA0
1  ADC0            8  EVOUTA (PA2)    1  USART0
2  CCL_LUT0_EV0    9  EVOUTB (PB2)
3  CCL_LUT1_EV0   10  EVOUTC (PC2)
4  CCL_LUT0_EV1   11  TCB1
5  CCL_LUT1_EV1   12  ADC1
6  TCD0_EV0
```

For a CCL LUT, its first event input (`EVENT0`; the datasheet calls it EVENTA)
arrives through the `..._EV0` user, and the second (`EVENT1` / EVENTB) through
the `..._EV1` user — e.g. LUT0's `EVENT0` is `ASYNCUSER2`.

### A trap: `_gc` constants do not assemble

The code in this chapter uses the readable group-config names like
`EVSYS_ASYNCCH0_RTC_OVF_gc` for clarity. Be aware of a catch when you move to a
`.S` file: in `iotn3217.h` these `_gc` constants are defined as members of a C
`enum`, not as `#define` macros. The assembler only runs the C preprocessor, so
it never sees enum names — assembling a file that uses a bare `_gc` fails with
*"undefined reference"*. (The `_bm` and `_bp` bit constants, by contrast, *are*
`#define` macros and work fine in assembly.)

The fix is to define the value yourself with `.equ`, taking the number from the
datasheet register table. For example, `RTC_OVF` is generator value `0x08` for
an async channel:

```asm
.equ ASYNCCH_RTC_OVF, 0x08      /* datasheet sec.15, ASYNCCHn generator    */
    ldi   r16, ASYNCCH_RTC_OVF
    sts   EVSYS_ASYNCCH0, r16
```

The companion `src/ch20b_event_ccl/` files use this `.equ` style throughout and
assemble cleanly with a stock `avr-gcc`. The register *names* (`EVSYS_ASYNCCH0`,
`CCL_TRUTH0`, …) are plain `#define`s and need no such treatment.

## Example: Mirror a Pin to an Event-Output Pin

The simplest possible event: copy one pin to another with no CPU involvement.
We use PA6 as the source (an async PORTA generator on ASYNCCH0) and route it to
the event-output user `EVOUTA`, which drives the dedicated PA2 event pin.

```asm
    /* --- generator: PA6 edge/level drives async channel 0 --- */
    ldi   r16, EVSYS_ASYNCCH0_PORTA_PIN6_gc
    sts   EVSYS_ASYNCCH0, r16        /* ASYNCCH0 carries PA6                  */

    /* --- user: event output A (PA2) listens to async channel 0 --- */
    ldi   r16, EVSYS_ASYNCUSER8_ASYNCCH0_gc  /* EVOUTA is an async user      */
    sts   EVSYS_ASYNCUSER8, r16

    /* PA2 must be an output for EVOUT to drive it */
    sbi   VPORTA_DIR, 2              /* PA2 = output                          */
```

After this runs, PA2 follows PA6 directly. No interrupt, no loop. `EVOUTA` is
async user 8 and drives PA2; async channel 0's pin generators are the PORTA pins
(so PA6 = `PORTA_PIN6`). Both facts are from the verified tables above.

## Example: Trigger an ADC Conversion From a Timer Event

A periodic, jitter-free sample clock. Here the audit pays off: on the ATtiny3217
**ADC0 is an asynchronous user** (`ASYNCUSER1`), so it can only listen to an
*async* channel. The TCA0/TCB0 overflow events are *synchronous* generators —
they live on `SYNCCH` and cannot feed an async user directly. So we use an async
periodic source instead: the **RTC overflow** (`RTC_OVF`), which is an async
generator. (RTC setup is its own topic; here we add only the event wiring and
the ADC's event trigger.)

```asm
    /* --- generator: RTC overflow drives async channel 0 --- */
    ldi   r16, EVSYS_ASYNCCH0_RTC_OVF_gc
    sts   EVSYS_ASYNCCH0, r16

    /* --- user: ADC0 start (ASYNCUSER1) listens to async channel 0 --- */
    ldi   r16, EVSYS_ASYNCUSER1_ASYNCCH0_gc   /* ADC0 is an async user       */
    sts   EVSYS_ASYNCUSER1, r16

    /* --- ADC: enable event-triggered start --- */
    ldi   r16, ADC_STARTEI_bm        /* start conversion on event input       */
    sts   ADC0_EVCTRL, r16
```

Every RTC overflow now launches a conversion at a fixed delay. The CPU only has
to read `ADC0.RES` when `RESRDY` is set (or have *that* drive another event).
This is the backbone of regular-rate sampling for the digital filters in the
next chapter.

This async/sync mismatch is exactly the trap the previous section warned about:
always check whether your generator and user are on the same channel type before
wiring them. The reference tables below list which side of the fence each one is
on.

## CCL Architecture

Configurable Custom Logic gives you programmable gates. The ATtiny3217 has two
look-up tables, LUT0 and LUT1, plus one sequential-logic block that can pair the
two LUTs into a flip-flop or latch.

Each LUT is a 3-input Boolean function defined by an 8-entry **truth table**:

```
   IN2 IN1 IN0  │ TRUTH bit
   ─────────────┼──────────
    0   0   0   │  bit 0
    0   0   1   │  bit 1
    0   1   0   │  bit 2
    0   1   1   │  bit 3
    1   0   0   │  bit 4
    1   0   1   │  bit 5
    1   1   0   │  bit 6
    1   1   1   │  bit 7
```

The output is whatever bit you placed at the row addressed by the three inputs.
Any 3-input logic function is just the right 8-bit `TRUTHn` value. A few useful
ones:

```
Function (of IN1,IN0; IN2=0)   TRUTH value   Notes
──────────────────────────────────────────────────────────────
Buffer  OUT = IN0              0xAA          IN0 to output
Inverter OUT = !IN0            0x55
AND     OUT = IN0 & IN1        0x88
OR      OUT = IN0 | IN1        0xEE
XOR     OUT = IN0 ^ IN1        0x66
```

Each LUT's inputs are selected independently from a menu: a pin (IO), an event
channel (`EVENT0`/`EVENT1` — the datasheet labels these EVENTA/EVENTB, but the
device header names them `EVENT0`/`EVENT1`), the other LUT's output (LINK), its own filtered
output (FEEDBACK), or a peripheral (AC0, TCB0, TCA0 waveform, USART/SPI, ...).
Selection lives in `LUTnCTRLB` (IN0, IN1) and `LUTnCTRLC` (IN2).

When a LUT input is set to `IO`, or its output is enabled with `OUTEN`, it uses a
fixed pin. On the 24-pin ATtiny3217 (from the datasheet's Multiplexed Signals
table):

```
        IN0   IN1   IN2   OUT (default)   OUT (alternate, via PORTMUX)
LUT0    PA0   PA1   PA2   PA4             PB4
LUT1    PC3   PC4   PC5   PA7             PC1
```

On the 20-pin SOIC package PC4 and PC5 are not bonded out, so LUT1's IN1/IN2 IO
inputs are unavailable there — route those through an event channel instead.

```
CCL registers:

  CCL.CTRLA       module enable, run-in-standby
  CCL.SEQCTRL0    sequential block mode (off / D-FF / JK / latch / RS)
  CCL.LUTnCTRLA   LUT enable, output-to-pin enable, clock source, filter, edge
  CCL.LUTnCTRLB   input select for IN0 and IN1
  CCL.LUTnCTRLC   input select for IN2
  CCL.TRUTHn      the 8-bit truth table
```

Important ordering rule: the LUT control and truth registers are
**enable-protected**. Configure `LUTnCTRLB/C` and `TRUTHn` *before* you set the
`ENABLE` bit in `LUTnCTRLA`, and before the module `ENABLE` in `CCL.CTRLA`.

## Example: A LUT as a Simple Gate Driving a Pin

Make LUT0 compute `OUT = IN0 AND IN1` from two input pins and drive its output
pin, entirely in hardware. We use IO inputs and the AND truth value `0x88`.

```asm
    /* configure inputs FIRST (enable-protected) */
    ldi   r16, CCL_INSEL0_IO_gc | CCL_INSEL1_IO_gc
    sts   CCL_LUT0CTRLB, r16          /* IN0 = pin, IN1 = pin                  */
    ldi   r16, CCL_INSEL2_MASK_gc     /* IN2 unused -> masked to 0            */
    sts   CCL_LUT0CTRLC, r16

    /* truth table: AND of IN1,IN0 */
    ldi   r16, 0x88
    sts   CCL_TRUTH0, r16

    /* enable LUT0 and route its output to the LUT0 pin */
    ldi   r16, CCL_ENABLE_bm | CCL_OUTEN_bm
    sts   CCL_LUT0CTRLA, r16

    /* enable the CCL module */
    ldi   r16, CCL_ENABLE_bm
    sts   CCL_CTRLA, r16
```

The output pin now equals the AND of the two LUT0 input pins, updating with only
gate-propagation delay. With `IO` inputs and `OUTEN`, LUT0 uses fixed pins: IN0 =
PA0, IN1 = PA1, output = PA4 (the alternate output PB4 is selectable via PORTMUX).
So this gate reads PA0 and PA1 and drives their AND onto PA4 — no CPU, no code.

## Example: Feeding a LUT From an Event (EVSYS + CCL Together)

The two peripherals combine: a CCL input can be an EVSYS channel, so logic can
react to any generator the Event System can route. Here LUT1's IN0 comes from
event input `EVENT0` (the datasheet's EVENTA), letting the LUT gate (say) an AC0
or timer signal that arrives over EVSYS.

```asm
    /* route some generator onto an async channel, then to the LUT's EVENT0 */
    ldi   r16, EVSYS_ASYNCCH2_AC0_OUT_gc
    sts   EVSYS_ASYNCCH2, r16

    /* CCL LUTs consume events via dedicated EV users; pick the channel */
    ldi   r16, EVSYS_ASYNCUSER3_ASYNCCH2_gc   /* CCL LUT1 EV0 user           */
    sts   EVSYS_ASYNCUSER3, r16

    /* LUT1 IN0 = EVENT0 (datasheet: EVENTA) */
    ldi   r16, CCL_INSEL0_EVENT0_gc | CCL_INSEL1_MASK_gc
    sts   CCL_LUT1CTRLB, r16
    ldi   r16, CCL_INSEL2_MASK_gc
    sts   CCL_LUT1CTRLC, r16

    ldi   r16, 0xAA                   /* OUT = IN0 (buffer the event)          */
    sts   CCL_TRUTH1, r16

    ldi   r16, CCL_ENABLE_bm | CCL_OUTEN_bm
    sts   CCL_LUT1CTRLA, r16
    ldi   r16, CCL_ENABLE_bm
    sts   CCL_CTRLA, r16
```

This is the pattern behind hardware-only signal conditioning: comparator or
timer signal -> EVSYS -> CCL gate/filter -> output pin or another peripheral,
all without the CPU.

## What You Learned

- The **Event System** routes signals between peripherals over channels, with
  fixed latency and zero CPU cost after setup. Roles are **generator**,
  **channel**, and **user**.
- The ATtiny3217 has **asynchronous** channels (no clock, work in sleep, carry
  edges) and **synchronous** channels (sampled on a clock). A user must select a
  channel of the type it supports.
- Configuration is two writes: generator -> channel register, and channel ->
  user register.
- **CCL** provides programmable gates. Each **LUT** is any 3-input Boolean
  function set by an 8-bit **truth table**, with inputs chosen from pins, events,
  the other LUT, feedback, or peripherals.
- LUT config registers are **enable-protected**: set inputs and truth table
  before enabling the LUT and the module.
- EVSYS and CCL **combine**: a LUT input can be an event channel, building
  hardware signal paths that never touch the CPU.

## Register Quick Reference

```
EVSYS.ASYNCCH0..3     generator select for async channels
EVSYS.SYNCCH0..1      generator select for sync channels
EVSYS.ASYNCUSER0..12  async channel select per user
EVSYS.SYNCUSER0..1    sync channel select per user
EVSYS.ASYNCSTROBE     software event on async channels
EVSYS.SYNCSTROBE      software event on sync channels

CCL.CTRLA             module ENABLE, RUNSTDBY
CCL.SEQCTRL0          sequential block mode
CCL.LUTnCTRLA         ENABLE, OUTEN, CLKSRC, FILTSEL, EDGEDET
CCL.LUTnCTRLB         INSEL0, INSEL1
CCL.LUTnCTRLC         INSEL2
CCL.TRUTHn            8-bit truth table
```

## Exercises

1. Write the `TRUTHn` value for a 3-input majority function (output is 1 when at
   least two of IN0, IN1, IN2 are 1). Verify it against the truth-table diagram.

2. Configure LUT0 as an inverter (`OUT = !IN0`) driven by an input pin and
   observe the output pin. What truth value did you use, and why is it the
   bitwise complement of the buffer value?

3. Route the RTC periodic-interrupt (PIT) event to the ADC start user so the ADC
   samples at the PIT rate. Which channel type (async or sync) is required, and
   why?

4. Combine both peripherals: route AC0's output through an EVSYS channel into a
   CCL LUT that buffers it to a pin. Compare the pin's response time to doing the
   same job with an AC0 interrupt that toggles the pin in software.

5. Use the sequential-logic block: set `SEQCTRL0` to D-flip-flop mode and feed
   LUT0 (D) and LUT1 (clock). What register sequence enables it, and what
   ordering rule must you respect?

---

*Next: Appendix A — Register Reference*
```
