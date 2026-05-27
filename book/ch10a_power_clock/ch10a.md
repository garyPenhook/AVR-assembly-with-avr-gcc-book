# Power and Clock Options

Clock and power control sit between GPIO/interrupts and the timing peripherals.
Before you trust a timer period, a USART baud rate, or a delay loop, you need to
know what clock the CPU and peripheral bus are using. Before you put a device to
sleep, you need to know which clock domains stop and which interrupt sources can
wake the part again.

This chapter covers the ATtiny3217 clock controller (`CLKCTRL`), the sleep
controller (`SLPCTRL`), and the brown-out detector / voltage level monitor
(`BOD` / `VLM`) from the point of view of assembly code.

---

## The Default Clock

After reset, the ATtiny3217 uses the internal 16/20 MHz oscillator (`OSC20M`) as
the main clock source. On the Curiosity Nano parts used in this book, the
oscillator fuse selects 20 MHz and the main prescaler starts enabled with a
divide-by-6 setting:

```
20 MHz / 6 = 3.333333 MHz
```

That default is why earlier examples use 3.333 MHz for rough delay loops and
timer math. If your firmware changes the prescaler, every software delay,
timer TOP value, PWM period, and asynchronous serial baud calculation must be
checked again.

The important distinction:

```
CLK_MAIN  selected oscillator before the main prescaler
CLK_PER   prescaled clock distributed to CPU-visible peripherals
CLK_CPU   CPU/SRAM/NVM clock derived from the same main clock path
```

Many datasheet tables and register descriptions say `CLK_PER` because the
peripheral bus sees the prescaled clock. In most examples in this book, that is
also the effective CPU instruction clock.

---

## Clock Sources

`CLKCTRL_MCLKCTRLA.CLKSEL` chooses the main clock source:

```
CLKSEL   Source
0x0      OSC20M: 16/20 MHz internal oscillator
0x1      OSCULP32K: 32.768 kHz internal ultra-low-power oscillator
0x2      XOSC32K: 32.768 kHz external crystal oscillator
0x3      EXTCLK: external clock input
```

The internal oscillator is the normal choice for examples and general firmware.
It needs no external parts and starts quickly. The 32 kHz sources are useful for
low-power timing, RTC/PIT work, or applications where a watch crystal gives
better long-term timing than the internal ULP oscillator.

External clock options require board-level care. The datasheet warns that when
switching to an external main clock, hardware waits for clock edges before the
switch completes. If the selected external clock is not present, firmware may
not be able to switch away again without a reset. Treat external clock selection
as a board configuration decision, not as a casual run-time experiment.

---

## Main Prescaler

`CLKCTRL_MCLKCTRLB` controls the main prescaler:

```
Bit:  7:5    4:1       0
      -      PDIV      PEN
```

`PEN = 0` disables the prescaler and passes `CLK_MAIN` through undivided.
`PEN = 1` enables the prescaler, with `PDIV` selecting the division factor:

```
PDIV   Division
0x0    /2
0x1    /4
0x2    /8
0x3    /16
0x4    /32
0x5    /64
0x8    /6
0x9    /10
0xA    /12
0xB    /24
0xC    /48
```

The reset value of `MCLKCTRLB` is `0x11`: `PDIV = 0x8`, `PEN = 1`, so the
prescaler divides by 6.

Use documented field values together with header bit-position and bit-mask names
when possible:

```asm
    .equ  MCLKCTRLB_DIV24, ((0x0B << CLKCTRL_PDIV_gp) | CLKCTRL_PEN_bm)

    ldi   r17, MCLKCTRLB_DIV24
    rcall clock_write_mclkctrlb
```

That is clearer and safer than hard-coding `0x17`.

---

## Configuration Change Protection

Clock registers that can destabilize the system are protected by CCP
(Configuration Change Protection). To write one of these registers, write the
I/O protection key (`0xD8`) to `CPU_CCP`, then write the
protected register immediately.

For example, this subroutine writes a new value to `CLKCTRL_MCLKCTRLB`.
The new prescaler byte is passed in `r17`:

```asm
.equ CCP_IOREG_KEY, 0xD8

clock_write_mclkctrlb:
    ldi   r16, CCP_IOREG_KEY
    sts   CPU_CCP, r16
    sts   CLKCTRL_MCLKCTRLB, r17
    ret
```

Do not insert a call, branch, long calculation, or unrelated register write
between `CPU_CCP` and the protected register write. The protected write must
land inside the timed CCP window.

---

## Waiting for Clock Switches

When firmware changes the main clock source, `CLKCTRL_MCLKSTATUS.SOSC` reports
that the system oscillator is still changing. Status bits also report whether
the selected oscillator is stable:

```
Bit      Meaning
EXTS     external clock has started
XOSC32KS 32.768 kHz crystal oscillator is stable
OSC32KS  internal 32.768 kHz oscillator is stable
OSC20MS  16/20 MHz oscillator is stable
SOSC     main clock source switch in progress
```

A conservative clock-source switch follows this shape:

```asm
    ; configure/enable the new oscillator if needed
    ; write CLKCTRL_MCLKCTRLA through CCP

.Lwait_switch:
    lds   r16, CLKCTRL_MCLKSTATUS
    sbrc  r16, CLKCTRL_SOSC_bp
    rjmp  .Lwait_switch
```

Prescaler-only changes do not normally need this wait loop, but they still need
the CCP unlock.

---

## Sleep Modes

`SLPCTRL_CTRLA` selects the sleep mode and enables sleep entry:

```
SMODE   Mode
0x0     Idle
0x1     Standby
0x2     Power-down
```

`SEN` must be set before executing the `SLEEP` instruction.

```
    .equ  SLPCTRL_MODE_PDOWN, (0x02 << SLPCTRL_SMODE_gp)

    ldi   r16, (SLPCTRL_MODE_PDOWN | SLPCTRL_SEN_bm)
    sts   SLPCTRL_CTRLA, r16
    sleep
```

Sleep does not mean "resume later by magic." An enabled interrupt source must
wake the device. The CPU wakes, executes the ISR, returns with `RETI`, and then
continues at the instruction after `SLEEP`.

### Idle

Idle stops CPU execution but leaves peripherals running. All interrupt sources
can wake the device. Use Idle when you want lower power without changing much
about the rest of the system.

### Standby

Standby stops more of the system. Peripherals that need to keep working must
support and enable their own `RUNSTDBY` bit. Wake-up time may include oscillator
start-up time unless the needed oscillator is already running.

### Power-down

Power-down is the deepest sleep mode. The datasheet lists BOD, WDT, and the RTC
PIT as active. Wake sources are limited: pin-change interrupt, PIT, VLM, TWI
address match, and CCL. Only the PIT part of the RTC is available in
Power-down.

That limitation is important. A TCA0 compare interrupt will not wake a
Power-down system because TCA0 is not running there. Use PIT or a pin-change
interrupt for deep-sleep wakeups.

### RTC/PIT clock-source changes

The RTC and PIT use `CLK_RTC`, which is configured via `RTC_CLKSEL`. The datasheet
notes that the clock source for `CLK_RTC` must only be changed when the RTC/PIT
peripheral is disabled. In practice that means: disable RTC (`RTC_RTCEN=0`) and
PIT (`RTC_PITEN=0`), wait for any synchronization-busy flags to clear, then write
`RTC_CLKSEL`, then re-enable the function you need.

---

## Brown-Out and VLM

The Brown-Out Detector monitors `VDD` against a fuse-selected threshold and can
reset the device before voltage drops too low for reliable operation. The
Voltage Level Monitor is an early-warning interrupt source set above the BOD
threshold.

Key points for firmware:

- The BOD level and the Active/Idle BOD operating mode are loaded from fuses at
  reset and cannot be changed by normal software.
- The Standby/Power-down BOD mode is also loaded from fuses, but the `SLEEP`
  field in `BOD_CTRLA` can be changed at run time through CCP.
- VLM follows the BOD mode. If BOD is disabled, enabling the VLM interrupt alone
  is not enough.
- VLM can wake from Power-down and can give code a chance to save state before a
  brown-out reset threshold is reached.

For many small examples, the right policy is simple: leave BOD fuse policy alone
and do not spend power-tuning effort until the application has a measured
current budget.

---

## Worked Example: Change the Prescaler

`src/clock_prescale.S` shows a minimal firmware image that changes the main
prescaler through CCP and blinks LED0. It starts from the factory default
3.333 MHz, switches to 20 MHz, blinks quickly, then switches to 416.7 kHz
(`20 MHz / 48`) and blinks slowly.

Build:

```sh
avr-gcc -mmcu=attiny3217 -x assembler-with-cpp -c -o clock_prescale.o src/clock_prescale.S
avr-gcc -mmcu=attiny3217 -nostartfiles -o clock_prescale.elf clock_prescale.o
avr-objdump -d clock_prescale.elf
```

The important routine is short:

```asm
clock_write_mclkctrlb:
    ldi   r16, CCP_IOREG_KEY
    sts   CPU_CCP, r16
    sts   CLKCTRL_MCLKCTRLB, r17
    ret
```

If the LED timing changes when this program runs, the CPU really did change
speed. That is a crude test, but it is a useful first confirmation before you
start recalculating timer and baud-rate values.

---

## Worked Example: Power-Down Wake from PIT

`src/sleep_pit.S` configures the RTC PIT from the internal 1 kHz clock, enables a
1024-cycle PIT interrupt, selects Power-down sleep, and sleeps in the foreground
loop. Each PIT interrupt wakes the device and toggles LED0.

The foreground loop is intentionally boring:

```asm
.Lsleep_forever:
    sleep
    rjmp  .Lsleep_forever
```

The useful work happens in the wake ISR. This is the usual low-power shape:
configure a wake source, enable global interrupts, enter sleep, do brief work
after wake, and go back to sleep.

---

## Practical Rules

1. Decide the clock frequency before writing timer, USART, ADC, or delay-loop
   code.
2. Use header bit masks/positions such as `CLKCTRL_PDIV_gp` and
   `CLKCTRL_PEN_bm` instead of scattering raw register bytes through code.
3. Keep the CCP unlock and protected write adjacent.
4. Do not enter sleep until at least one valid wake interrupt is configured and
   global interrupts are enabled.
5. Use Idle for simple interrupt-driven waiting, Standby for peripheral-assisted
   waiting, and Power-down only when the wake source is known to work there.
6. Treat BOD fuses as part of the hardware power policy. Runtime code can adjust
   only the sleep-mode BOD behavior.

Microchip source notes:

- ATtiny3216/3217 Complete Datasheet DS40002205A, sections 10 (`CLKCTRL`), 11
  (`SLPCTRL`), and 17 (`BOD`).
- Microchip online peripheral address map lists `SLPCTRL` at `0x0050`,
  `CLKCTRL` at `0x0060`, and `BOD` at `0x0080`.
- The avr-libc device header `iotn3217.h` defines the register names, bit masks,
  and bit positions used by the assembly examples.

---

## Exercises

1. Change `clock_prescale.S` to use `/24` instead of `/48`. What byte should
   `MCLKCTRLB` receive?
2. Recalculate the Chapter 11 TCA0 `CMP0` value for a 20 MHz clock with the
   timer prescaler still set to 1024.
3. Change `sleep_pit.S` from PIT period field value `0x09` (1024 cycles) to
   `0x0A` (2048 cycles). How often should the LED toggle from the 1 kHz PIT
   clock?
4. Replace the PIT wake source with a PORT pin-change wake source. Which sleep
   modes can still wake from that interrupt?
5. Enable VLM interrupt-on-crossing in a test program. Why should this be tested
   with a current-limited bench supply instead of a normal USB cable?
