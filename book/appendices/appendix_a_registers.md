# ATtiny3217 Register Reference

Quick lookup for registers used throughout this book. The ATtiny3217 is an
AVRXMEGA3 device. All peripheral registers are memory-mapped and require
`LDS`/`STS` unless noted otherwise.

> **VPORT exception**: Virtual PORT registers at 0x0000–0x001F are within the
> I/O space and can be accessed with `IN`/`OUT`, `SBI`/`CBI`, `SBIS`/`SBIC`
> in a single cycle. All other peripheral registers require `LDS`/`STS`.

> **CPU registers**: SREG (0x003F), SPH (0x003E), SPL (0x003D) are accessible
> with `IN`/`OUT` using their I/O addresses directly (no +0x20 offset needed on
> AVRXMEGA3 — these addresses are already the memory-mapped addresses, and the
> I/O address equals the memory address for registers at 0x0000–0x003F).

---

## CPU Registers

```
Register   Mem Addr   Access      Description
─────────────────────────────────────────────────────────────────────
SREG       0x003F     IN/OUT      Status Register (I T H S V N Z C)
SPH        0x003E     IN/OUT      Stack Pointer High
SPL        0x003D     IN/OUT      Stack Pointer Low
CCP        0x0034     LDS/STS     Configuration Change Protection
```

SREG, SPH, and SPL sit within the range 0x0000–0x003F and are accessible via
`IN`/`OUT` using the address directly. The `CCP` register requires `LDS`/`STS`.

### SREG Bit Layout

```
Bit:  7    6    5    4    3    2    1    0
Name: I    T    H    S    V    N    Z    C
      │    │    │    │    │    │    │    └─ Carry
      │    │    │    │    │    │    └────── Zero
      │    │    │    │    │    └─────────── Negative
      │    │    │    │    └──────────────── Overflow (two's complement)
      │    │    │    └───────────────────── Sign (N XOR V)
      │    │    └────────────────────────── Half-carry (nibble carry)
      │    └─────────────────────────────── Bit Copy Storage (T flag)
      └──────────────────────────────────── Global Interrupt Enable
```

### Configuration Change Protection (CCP)

Certain registers are protected against accidental writes. Before writing to a
protected register, write the appropriate key to CCP. The protected register
must then be written within 4 CPU cycles.

```
Key    Value   Protects
───────────────────────────────────────────────────────────────
IOREG  0xD8    I/O registers (e.g. CLKCTRL, BOD, OSC settings)
SPM    0x9D    NVM (flash/EEPROM) write commands
```

Example — disable clock prescaler to run at 20 MHz:

```asm
    ldi   r16, 0xD8           ; CCP key for I/O register changes
    sts   0x0034, r16         ; write to CCP
    sts   0x0061, r1          ; write 0 to CLKCTRL_MCLKCTRLB (clear PEN)
                               ; must complete within 4 cycles of CCP write
```

---

## CLKCTRL — Clock Controller

Base address: 0x0060. All registers require `LDS`/`STS` and CCP protection
where noted.

```
Register              Mem Addr   CCP?   Description
─────────────────────────────────────────────────────────────────────────
CLKCTRL_MCLKCTRLA     0x0060     Yes    Main clock source select
CLKCTRL_MCLKCTRLB     0x0061     Yes    Main clock prescaler
CLKCTRL_MCLKLOCK      0x0062     Yes    Lock register (prevents further changes)
CLKCTRL_MCLKSTATUS    0x0063     No     Status (read-only)
```

### MCLKCTRLA — Main Clock Source Select

```
Bit:  7      6:2    1:0
      CLKOUT  —     CLKSEL
```

```
CLKSEL   Source
──────────────────────────────────────
  0x0    20 MHz internal oscillator  ← factory default
  0x1    32 KHz internal ULP oscillator
  0x2    32.768 KHz external crystal (XOSC32K)
  0x3    External clock on CLKI pin
```

Setting CLKOUT (bit 7) routes the main clock to the CLKOUT pin.

### MCLKCTRLB — Main Clock Prescaler

```
Bit:  7:5    4:1    0
       —     PDIV   PEN
```

```
PEN    Prescaler enable (1 = prescaler active, 0 = disabled)

PDIV   Division factor (when PEN=1)
  0x0   /2
  0x1   /4
  0x2   /8
  0x3   /16
  0x4   /32
  0x5   /64
  0x6   /6   ← factory default (20 MHz / 6 = 3.333 MHz)
  0x7   /10
  0x8   /12
  0x9   /24
  0xA   /48
```

Factory default: PDIV=0x6 (divide by 6), PEN=1 → **3.333 MHz** system clock.

To run at full **20 MHz**: write 0x00 to MCLKCTRLB (clears PEN) — requires CCP
key 0xD8 first. To run at **10 MHz**: write PEN=1, PDIV=0x1 (divide by 2).

### MCLKSTATUS — Status (read-only)

```
Bit:  7        6        5        4        3        2        1        0
      EXTS     XOSC32KS SOSC     OSC32KS  OSC20MS  —        —        SOSC
```

```
Bit name   Description
────────────────────────────────────────────────────────
OSC20MS    1 = 20 MHz oscillator is stable and running
OSC32KS    1 = 32 KHz oscillator is stable
SOSC       1 = System oscillator is stable
EXTS       1 = External clock source is active
```

---

## GPIO Registers

The AVRXMEGA3 GPIO model is completely different from classic AVR. Each port
has a full set of direction/output/input/control registers at a fixed base
address. Atomic set/clear/toggle registers eliminate the need for
read-modify-write sequences.

### Port Base Addresses

```
Port   Base Addr
────────────────
PORTA  0x0400
PORTB  0x0420
PORTC  0x0440
```

### Per-Port Register Map (offset from base)

```
Offset   Register        Description
──────────────────────────────────────────────────────────────────────
+0x00    PORTx_DIR       Data direction register (1=output, 0=input)
+0x01    PORTx_DIRSET    Write 1 to set direction bits (atomic)
+0x02    PORTx_DIRCLR    Write 1 to clear direction bits (atomic)
+0x03    PORTx_DIRTGL    Write 1 to toggle direction bits (atomic)
+0x04    PORTx_OUT       Output value register
+0x05    PORTx_OUTSET    Write 1 to set output bits (atomic)
+0x06    PORTx_OUTCLR    Write 1 to clear output bits (atomic)
+0x07    PORTx_OUTTGL    Write 1 to toggle output bits (atomic)
+0x08    PORTx_IN        Input value (reads current pin state)
+0x09    PORTx_INTFLAGS  Pin-change interrupt flags (W1C)
+0x0A    PORTx_PORTCTRL  Port control register
+0x10    PORTx_PIN0CTRL  Pin 0 config (pull-up, invert, ISC)
+0x11    PORTx_PIN1CTRL  Pin 1 config
+0x12    PORTx_PIN2CTRL  Pin 2 config
+0x13    PORTx_PIN3CTRL  Pin 3 config
+0x14    PORTx_PIN4CTRL  Pin 4 config
+0x15    PORTx_PIN5CTRL  Pin 5 config
+0x16    PORTx_PIN6CTRL  Pin 6 config
+0x17    PORTx_PIN7CTRL  Pin 7 config
```

### PORTA Absolute Addresses

```
Register           Mem Addr   Description
──────────────────────────────────────────────────────────────────────
PORTA_DIR          0x0400     Direction
PORTA_DIRSET       0x0401     Set direction (atomic)
PORTA_DIRCLR       0x0402     Clear direction (atomic)
PORTA_DIRTGL       0x0403     Toggle direction (atomic)
PORTA_OUT          0x0404     Output value
PORTA_OUTSET       0x0405     Set output (atomic)
PORTA_OUTCLR       0x0406     Clear output (atomic)
PORTA_OUTTGL       0x0407     Toggle output (atomic)
PORTA_IN           0x0408     Input value
PORTA_INTFLAGS     0x0409     Interrupt flags
PORTA_PORTCTRL     0x040A     Port control
PORTA_PIN0CTRL     0x0410     PA0 config (UPDI pin — do not reconfigure)
PORTA_PIN1CTRL     0x0411     PA1 config (SPI MOSI default)
PORTA_PIN2CTRL     0x0412     PA2 config (SPI MISO default)
PORTA_PIN3CTRL     0x0413     PA3 config (LED0 — Curiosity Nano)
PORTA_PIN4CTRL     0x0414     PA4 config (SPI SS default)
PORTA_PIN5CTRL     0x0415     PA5 config
PORTA_PIN6CTRL     0x0416     PA6 config
PORTA_PIN7CTRL     0x0417     PA7 config
```

### PORTB Absolute Addresses

```
Register           Mem Addr   Description
──────────────────────────────────────────────────────────────────────
PORTB_DIR          0x0420     Direction
PORTB_DIRSET       0x0421     Set direction (atomic)
PORTB_DIRCLR       0x0422     Clear direction (atomic)
PORTB_DIRTGL       0x0423     Toggle direction (atomic)
PORTB_OUT          0x0424     Output value
PORTB_OUTSET       0x0425     Set output (atomic)
PORTB_OUTCLR       0x0426     Clear output (atomic)
PORTB_OUTTGL       0x0427     Toggle output (atomic)
PORTB_IN           0x0428     Input value
PORTB_INTFLAGS     0x0429     Interrupt flags
PORTB_PORTCTRL     0x042A     Port control
PORTB_PIN0CTRL     0x0430     PB0 config (TWI SDA default)
PORTB_PIN1CTRL     0x0431     PB1 config (TWI SCL default)
PORTB_PIN2CTRL     0x0432     PB2 config (USART0 TX — Curiosity Nano)
PORTB_PIN3CTRL     0x0433     PB3 config (USART0 RX — Curiosity Nano)
PORTB_PIN4CTRL     0x0434     PB4 config
PORTB_PIN5CTRL     0x0435     PB5 config
PORTB_PIN6CTRL     0x0436     PB6 config
PORTB_PIN7CTRL     0x0437     PB7 config
```

### PORTC Absolute Addresses

```
Register           Mem Addr   Description
──────────────────────────────────────────────────────────────────────
PORTC_DIR          0x0440     Direction
PORTC_DIRSET       0x0441     Set direction (atomic)
PORTC_DIRCLR       0x0442     Clear direction (atomic)
PORTC_DIRTGL       0x0443     Toggle direction (atomic)
PORTC_OUT          0x0444     Output value
PORTC_OUTSET       0x0445     Set output (atomic)
PORTC_OUTCLR       0x0446     Clear output (atomic)
PORTC_OUTTGL       0x0447     Toggle output (atomic)
PORTC_IN           0x0448     Input value
PORTC_INTFLAGS     0x0449     Interrupt flags
PORTC_PORTCTRL     0x044A     Port control
PORTC_PIN0CTRL     0x0450     PC0 config
PORTC_PIN1CTRL     0x0451     PC1 config
PORTC_PIN2CTRL     0x0452     PC2 config
PORTC_PIN3CTRL     0x0453     PC3 config
PORTC_PIN4CTRL     0x0454     PC4 config
PORTC_PIN5CTRL     0x0455     PC5 config
PORTC_PIN6CTRL     0x0456     PC6 config (not present on 20-pin package)
PORTC_PIN7CTRL     0x0457     PC7 config (not present on 20-pin package)
```

### PINnCTRL Bit Layout

Each `PORTx_PINnCTRL` register configures one pin independently.

```
Bit:  7      6:3    3        2:0
      INVEN   —     PULLUPEN  ISC[2:0]
      │              │         │
      │              │         └─ Input Sense Configuration (see below)
      │              └─────────── 1 = enable internal pull-up resistor
      └────────────────────────── 1 = invert pin (input and output)
```

```
ISC[2:0]   Input Sense Configuration
──────────────────────────────────────────────────
  0x0      INTDISABLE  No interrupt; digital input buffer enabled
  0x1      BOTHEDGES   Interrupt on both rising and falling edges
  0x2      RISING      Interrupt on rising edge only
  0x3      FALLING     Interrupt on falling edge only
  0x4      INPUT_DISABLE  Digital input buffer disabled (reduces power)
  0x5      LEVEL       Interrupt on low level
```

### Virtual PORT Registers (VPORT) — Fast I/O

VPORTs mirror the key PORT registers into I/O space (0x0000–0x001F). They can
be accessed with `IN`/`OUT` (1 cycle), `SBI`/`CBI`, and `SBIS`/`SBIC`. Writing
to `VPORT_IN` toggles the corresponding output bit (same as `OUTTGL`).

```
Register        Addr    Mirrors
──────────────────────────────────────────────────────────────────────
VPORTA_DIR      0x0000  PORTA_DIR   (1=output)
VPORTA_OUT      0x0001  PORTA_OUT
VPORTA_IN       0x0002  PORTA_IN    (write 1 to toggle output)
VPORTA_INTFLAGS 0x0003  PORTA_INTFLAGS

VPORTB_DIR      0x0004  PORTB_DIR
VPORTB_OUT      0x0005  PORTB_OUT
VPORTB_IN       0x0006  PORTB_IN
VPORTB_INTFLAGS 0x0007  PORTB_INTFLAGS

VPORTC_DIR      0x0008  PORTC_DIR
VPORTC_OUT      0x0009  PORTC_OUT
VPORTC_IN       0x000A  PORTC_IN
VPORTC_INTFLAGS 0x000B  PORTC_INTFLAGS
```

Use VPORT registers with `IN`/`OUT` for single-cycle access. Use the full PORT
registers with `LDS`/`STS` when you need atomic set/clear/toggle or pin config.

---

## Curiosity Nano Pin Assignments

```
Signal         Port Pin   Mem Addr (PINnCTRL)   Notes
──────────────────────────────────────────────────────────────────────
LED0           PA3        0x0413                Active low — drive LOW to light
USART0 TX      PB2        0x0432                To on-board debugger virtual COM port
USART0 RX      PB3        0x0433                From on-board debugger virtual COM port
UPDI           PA0        0x0410                Programming/debug — do not reconfigure
```

### LED and Button Quick Reference

```
LED0 on  (light):  STS PORTA_OUTCLR, (1<<3)   ; clear PA3 (active low)
LED0 off (dark):   STS PORTA_OUTSET, (1<<3)   ; set PA3
LED0 toggle:       STS PORTA_OUTTGL, (1<<3)   ; toggle PA3

The ATtiny3217 Curiosity Nano does not provide a dedicated user pushbutton.
For button examples, wire an external active-low button to a free GPIO and
enable that pin's internal pull-up.
```

---

## TCA0 — Timer/Counter Type A (16-bit)

Base address: 0x0A00 (single-slope mode, the default). TCA0 is a general-purpose
16-bit timer supporting normal, CTC, and PWM modes.

```
Register                Mem Addr   Description
──────────────────────────────────────────────────────────────────────
TCA0_SINGLE_CTRLA       0x0A00     Prescaler select (CLKSEL), enable (ENABLE)
TCA0_SINGLE_CTRLB       0x0A01     Waveform mode (WGMODE), compare enables
TCA0_SINGLE_CTRLC       0x0A02     Force compare outputs
TCA0_SINGLE_CTRLD       0x0A03     Split mode enable
TCA0_SINGLE_CTRLECLR    0x0A04     Control E clear
TCA0_SINGLE_CTRLESET    0x0A05     Control E set
TCA0_SINGLE_INTCTRL     0x0A06     Interrupt enable (OVF, CMP0, CMP1, CMP2)
TCA0_SINGLE_INTFLAGS    0x0A07     Interrupt flags (W1C)
TCA0_SINGLE_EVCTRL      0x0A09     Event control
TCA0_SINGLE_DBGCTRL     0x0A0E     Debug control
TCA0_SINGLE_TEMP        0x0A0F     Temp register for 16-bit read/write
TCA0_SINGLE_CNT         0x0A20     Counter value (16-bit, write low byte first)
TCA0_SINGLE_PER         0x0A26     Period / TOP value (16-bit)
TCA0_SINGLE_CMP0        0x0A28     Compare/capture 0 (16-bit)
TCA0_SINGLE_CMP1        0x0A2A     Compare/capture 1 (16-bit)
TCA0_SINGLE_CMP2        0x0A2C     Compare/capture 2 (16-bit)
TCA0_SINGLE_PERBUF      0x0A36     Period buffer (double-buffered)
TCA0_SINGLE_CMP0BUF     0x0A38     Compare 0 buffer
TCA0_SINGLE_CMP1BUF     0x0A3A     Compare 1 buffer
TCA0_SINGLE_CMP2BUF     0x0A3C     Compare 2 buffer
```

### CTRLA — Prescaler and Enable

```
Bit:  7:4    3:1       0
       —     CLKSEL    ENABLE
```

```
CLKSEL   Prescaler
──────────────────
  0x0    DIV1     (no prescaling)
  0x1    DIV2
  0x2    DIV4
  0x3    DIV8
  0x4    DIV16
  0x5    DIV64
  0x6    DIV256
  0x7    DIV1024
```

Example — 1 Hz overflow at 3.333 MHz with DIV64 (prescaled clock = 52,083 Hz,
PER = 52082):

```asm
    ldi  r16, 0x0B              ; CLKSEL=DIV64 (bits 3:1 = 101), ENABLE=1
    sts  0x0A00, r16            ; TCA0_SINGLE_CTRLA
    ldi  r16, lo8(52082)
    sts  0x0A26, r16            ; TCA0_SINGLE_PER low byte
    ldi  r16, hi8(52082)
    sts  0x0A27, r16            ; TCA0_SINGLE_PER high byte
    ldi  r16, 0x01              ; OVF interrupt enable
    sts  0x0A06, r16            ; TCA0_SINGLE_INTCTRL
```

### CTRLB — Waveform Mode

```
WGMODE[2:0] (bits 2:0)   Mode
──────────────────────────────────────────
  0x0                     Normal (count up, overflow at PER)
  0x1                     Frequency (toggle WO, reset at CMP0)
  0x2                     Single-slope PWM
  0x5                     Dual-slope PWM (overflow at BOTTOM and TOP)
  0x6                     Dual-slope PWM (overflow at TOP only)
  0x7                     Dual-slope PWM (overflow at BOTTOM only)
```

---

## TCB0 / TCB1 — Timer/Counter Type B (16-bit)

Type B timers are 16-bit, single-channel timers suited for periodic interrupts,
input capture, and PWM. TCB0 and TCB1 share the same register layout.

```
TCB0 base: 0x0A40
TCB1 base: 0x0A50
```

```
Offset   Register        Description
──────────────────────────────────────────────────────────────────────
+0x00    TCBn_CTRLA      Clock select, enable
+0x01    TCBn_CTRLB      Compare/capture mode, output enable
+0x04    TCBn_EVCTRL     Event control
+0x05    TCBn_INTCTRL    CAPT interrupt enable (bit 0)
+0x06    TCBn_INTFLAGS   CAPT interrupt flag (bit 0, W1C)
+0x07    TCBn_STATUS     RUN flag (bit 0, read-only)
+0x08    TCBn_DBGCTRL    Debug control
+0x09    TCBn_TEMP       Temp register for 16-bit read/write
+0x0A    TCBn_CNTL       Counter low byte
+0x0B    TCBn_CNTH       Counter high byte
+0x0C    TCBn_CCMPL      Compare/capture low byte
+0x0D    TCBn_CCMPH      Compare/capture high byte
```

### CTRLA — Clock Select and Enable

```
Bit:  7:3    2:1       0
       —     CLKSEL    ENABLE
```

```
CLKSEL   Clock source
──────────────────────────────────────
  0x0    CLKPER   (same as system clock)
  0x1    CLKPER/2
  0x2    TCA0     (TCB clocked from TCA0 overflow)
```

### CTRLB — Mode (CMODE)

```
CMODE[2:0] (bits 2:0)   Mode
──────────────────────────────────────────────────────────────
  0x0                    Periodic Interrupt  ← default, most common
  0x1                    Timeout Check
  0x2                    Input Capture on Event
  0x3                    Input Capture Frequency Measurement
  0x4                    Input Capture Pulse-Width Measurement
  0x5                    Input Capture Freq+PW Measurement
  0x6                    Single Shot
  0x7                    8-bit PWM
```

In Periodic Interrupt mode (CMODE=0), the counter counts up to CCMP, fires the
CAPT interrupt, then resets to zero. CCMP sets the period (TOP).

Example — 1 kHz periodic interrupt at 3.333 MHz:

```asm
    ldi  r16, lo8(3332)         ; CCMP = (f_cpu / f_irq) - 1 = 3332
    sts  0x0A4C, r16            ; TCB0_CCMPL
    ldi  r16, hi8(3332)
    sts  0x0A4D, r16            ; TCB0_CCMPH
    ldi  r16, 0x01              ; CAPT interrupt enable
    sts  0x0A45, r16            ; TCB0_INTCTRL
    ldi  r16, 0x01              ; CLKSEL=CLKPER, ENABLE=1
    sts  0x0A40, r16            ; TCB0_CTRLA
```

---

## USART0

Base address: 0x0800. On the Curiosity Nano board, USART0 is connected to the
on-board debugger (PB2=TX, PB3=RX), providing a virtual COM port over USB.

```
Register          Mem Addr   Description
──────────────────────────────────────────────────────────────────────
USART0_RXDATAL    0x0800     Receive data (low byte, 8-bit data here)
USART0_RXDATAH    0x0801     Receive data high + error flags
USART0_TXDATAL    0x0802     Transmit data (write byte here to send)
USART0_TXDATAH    0x0803     Transmit data high (9-bit mode only)
USART0_STATUS     0x0804     Status flags
USART0_CTRLA      0x0805     Interrupt enables
USART0_CTRLB      0x0806     Receiver/transmitter enable
USART0_CTRLC      0x0807     Frame format (default = 8N1)
USART0_BAUDL      0x0808     Baud rate register low byte
USART0_BAUDH      0x0809     Baud rate register high byte
USART0_CTRLD      0x080A     Auto-baud, IRCOM
USART0_DBGCTRL    0x080B     Debug control
USART0_EVCTRL     0x080C     Event control
USART0_TXPLCTRL   0x080D     TX pin LINAUTO
USART0_RXPLCTRL   0x080E     RX pin LINAUTO
```

### STATUS Bits

```
Bit:  7      6      5      4      3       2      1:0
      RXCIF  TXCIF  DREIF  FERR   BUFOVF  PERR   —

RXCIF   Receive Complete Interrupt Flag  (1 = unread data in RXDATA)
TXCIF   Transmit Complete Interrupt Flag (1 = TX shift register empty)
DREIF   Data Register Empty Flag        (1 = OK to write next byte to TXDATA)
FERR    Frame Error
BUFOVF  Buffer Overflow
PERR    Parity Error
```

### CTRLA — Interrupt Enables

```
Bit:  7      6      5      4:2    1      0
      RXCIE  TXCIE  DREIE  —      LBME   ABEIE

RXCIE   Receive Complete IE
TXCIE   Transmit Complete IE
DREIE   Data Register Empty IE (triggers when ready for next transmit byte)
```

### CTRLB — Enable Bits

```
Bit:  7    6    5:4    3       2      1:0
      RXEN TXEN MPCM   RXMODE  ODME   —

RXEN    1 = enable receiver
TXEN    1 = enable transmitter
RXMODE  0x0=NORMAL, 0x1=CLK2X, 0x2=GENAUTO, 0x3=LINAUTO
```

### CTRLC — Frame Format

```
Default value: 0x03 = 8N1 (8 data bits, no parity, 1 stop bit)

Bit:  7:6       5:4     3     2:0
      CMODE     PMODE   SBMODE CHSIZE

CMODE   0x0=ASYNCHRONOUS, 0x1=SYNCHRONOUS, 0x2=IRCOM, 0x3=MSPI
PMODE   0x0=DISABLED, 0x2=EVEN, 0x3=ODD
SBMODE  0=1 stop bit, 1=2 stop bits
CHSIZE  0x0=5-bit, 0x1=6-bit, 0x2=7-bit, 0x3=8-bit, 0x4-0x6=reserved, 0x7=9-bit
```

### Baud Rate Formula and Common Values

Normal asynchronous mode:

```
BAUD_REG = (f_cpu × 64) / (16 × baud_rate)
         = (f_cpu × 4) / baud_rate
```

```
Baud Rate   f_cpu = 3.333 MHz   f_cpu = 20 MHz
            BAUD_REG (hex)      BAUD_REG (hex)
──────────────────────────────────────────────────
   9600     0x056D  (1389)      0x2098  (8344)
  19200     0x02B7  (694)       0x104C  (4172)
  38400     0x015B  (347)       0x0826  (2086)
  57600     0x00E2  (226)       0x0571  (1393)
 115200     0x0074  (116)       0x02B9  (697)
```

---

## SPI0

Base address: 0x08C0. Default pin assignments: MOSI=PA1, MISO=PA2, SCK=PA3, SS=PA4.

```
Register        Mem Addr   Description
──────────────────────────────────────────────────────────────────────
SPI0_CTRLA      0x08C0     Control A: DORD, MASTER, CLK2X, PRESC[1:0], ENABLE
SPI0_CTRLB      0x08C1     Control B: BUFEN, SSD, MODE[1:0]
SPI0_INTCTRL    0x08C2     Interrupt enables: IE, SSIE, TXCIE, RXCIE
SPI0_INTFLAGS   0x08C3     Interrupt flags: IF(7), WRCOL(0)
SPI0_DATA       0x08C4     TX/RX data register
```

### CTRLA Bits

```
Bit:  7      6      5      4:3      2      1      0
      DORD   MASTER CLK2X  PRESC    —      —      ENABLE

DORD    0=MSB first, 1=LSB first
MASTER  0=slave, 1=master
CLK2X   1=double clock speed
PRESC   0x0=DIV4, 0x1=DIV16, 0x2=DIV64, 0x3=DIV128
ENABLE  1=enable SPI
```

### SPI Clock Rates

```
PRESC   CLK2X=0         CLK2X=1
──────────────────────────────────
  0x0   f_cpu / 4       f_cpu / 2
  0x1   f_cpu / 16      f_cpu / 8
  0x2   f_cpu / 64      f_cpu / 32
  0x3   f_cpu / 128     f_cpu / 64
```

---

## TWI0 — Two-Wire Interface (I2C)

Base address: 0x08A0. Default pins: SDA=PB0, SCL=PB1. Requires external 4.7 kΩ
pull-up resistors on SDA and SCL lines.

```
Register        Mem Addr   Description
──────────────────────────────────────────────────────────────────────
TWI0_CTRLA      0x08A0     SDA hold time, fast-mode plus enable
TWI0_DUALCTRL   0x08A1     Dual-mode control
TWI0_MCTRLA     0x08A2     Master: RIEN, WIEN, QCEN, TIMEOUT, SMEN, ENABLE
TWI0_MCTRLB     0x08A3     Master: FLUSH, ACKACT, MCMD[1:0]
TWI0_MSTATUS    0x08A4     Master status flags
TWI0_MBAUD      0x08A5     Master baud rate
TWI0_MADDR      0x08A6     Master address (write triggers START condition)
TWI0_MDATA      0x08A7     Master data register (read/write)
TWI0_SCTRLA     0x08A8     Slave: DIEN, APIEN, PIEN, PMEN, SMEN, ENABLE
TWI0_SCTRLB     0x08A9     Slave: ACKACT, SCMD[1:0]
TWI0_SSTATUS    0x08AA     Slave status flags
TWI0_SADDR      0x08AB     Slave address
TWI0_SDATA      0x08AC     Slave data
TWI0_SADDRMASK  0x08AD     Slave address mask
```

### MSTATUS Bits

```
Bit:  7    6    5        4      3        2       1:0
      RIF  WIF  CLKHOLD  RXACK  ARBLOST  BUSERR  BUSSTATE

RIF       Read Interrupt Flag
WIF       Write Interrupt Flag
CLKHOLD   Clock hold (SCL stretched by master)
RXACK     Received ACK (0=ACK received, 1=NACK)
ARBLOST   Arbitration lost
BUSERR    Bus error
BUSSTATE  0x0=UNKNOWN, 0x1=IDLE, 0x2=OWNER, 0x3=BUSY
```

### MCTRLB — Master Command

```
MCMD[1:0]   Command
────────────────────────────────────────
  0x0       NOACT      No action
  0x1       REPSTART   Issue repeated START
  0x2       RECVTRANS  Continue (ACK) / send byte
  0x3       STOP       Issue STOP condition
```

### Baud Rate Formula

```
BAUD = (f_cpu / f_scl - 10) / 2        (for f_cpu in Hz, f_scl in Hz)

100 kHz at 3.333 MHz:  BAUD = (3333333 / 100000 - 10) / 2 ≈ 12
400 kHz at 3.333 MHz:  BAUD = (3333333 / 400000 - 10) / 2 ≈ 2 (use fast-mode+)
100 kHz at 20 MHz:     BAUD = (20000000 / 100000 - 10) / 2 = 95
400 kHz at 20 MHz:     BAUD = (20000000 / 400000 - 10) / 2 = 20
```

---

## ADC0

Base address: 0x0600. The ATtiny3217 ADC is 10-bit (or 8-bit selectable).

```
Register        Mem Addr   Description
──────────────────────────────────────────────────────────────────────
ADC0_CTRLA      0x0600     Enable, resolution, free-run, left-adjust
ADC0_CTRLB      0x0601     Sample accumulation (SAMPNUM)
ADC0_CTRLC      0x0602     Prescaler, reference select, sample capacitor
ADC0_CTRLD      0x0603     Init delay, auto-sample delay
ADC0_CTRLE      0x0604     Window comparator mode
ADC0_SAMPCTRL   0x0605     Sample length extension
ADC0_MUXPOS     0x0606     Input mux (selects channel)
ADC0_COMMAND    0x0608     Write bit 0 (STCONV) to start conversion
ADC0_EVCTRL     0x0609     Event trigger enable
ADC0_INTCTRL    0x060A     RESRDY(0) and WCMP(1) interrupt enables
ADC0_INTFLAGS   0x060B     Interrupt flags (W1C)
ADC0_DBGCTRL    0x060C     Debug run control
ADC0_TEMP       0x060D     Temporary register
ADC0_RESL       0x0610     Result low byte
ADC0_RESH       0x0611     Result high byte
ADC0_WINLT      0x0612     Window comparator low threshold
ADC0_WINHT      0x0614     Window comparator high threshold
ADC0_CALIB      0x0616     Calibration
```

### CTRLA Bits

```
Bit:  7      6:5    4         3        2       1         0
      —      —      LEFTADJ   RESSEL   FREERUN RUNSTDBY  ENABLE

LEFTADJ   1=result left-adjusted in 16-bit register (8-bit in RESH)
RESSEL    0=10-bit result, 1=8-bit result
FREERUN   1=continuous conversions
ENABLE    1=enable ADC
```

### CTRLC — Prescaler and Reference

```
Bit:  7:6    5:4      3        2:0
      —      REFSEL   SAMPCAP  PRESC

REFSEL   0x0=INTREF (internal), 0x1=VDDIO2/10, 0x2=reserved, 0x3=VREFA (external)
SAMPCAP  1=reduced sample capacitance (for high-impedance sources)
PRESC    ADC clock prescaler (see table below)
```

```
PRESC   Division
────────────────
  0x0   DIV2
  0x1   DIV4
  0x2   DIV8
  0x3   DIV16
  0x4   DIV32
  0x5   DIV64
  0x6   DIV128
  0x7   DIV256
```

ADC requires 50–1500 kHz clock. At 3.333 MHz use DIV8 (417 kHz) or DIV16
(208 kHz). At 20 MHz use DIV32 (625 kHz) or DIV64 (312 kHz).

### MUXPOS — Input Mux

```
MUXPOS   Channel
──────────────────────────────────────
  0x00   AIN0 (PA0 — also UPDI, avoid)
  0x01   AIN1 (PA1)
  0x02   AIN2 (PA2)
  0x03   AIN3 (PA3)
  0x04   AIN4 (PA4)
  0x05   AIN5 (PA5)
  0x06   AIN6 (PA6)
  0x07   AIN7 (PA7)
  0x08   AIN8 (PB5)
  0x09   AIN9 (PB4)
  0x0A   AIN10 (PB1)
  0x0B   AIN11 (PB0)
  0x1B   Reserved for ADC0 / PTC
  0x1C   DAC0
  0x1D   INTREF     (internal reference voltage)
  0x1E   TEMPSENSE  (internal temperature sensor)
  0x1F   GND
```

### Internal Reference Voltage

The internal reference is configured via VREF peripheral (base 0x00A0):

```
Register         Mem Addr   Description
──────────────────────────────────────────────────────────────────────
VREF_CTRLA       0x00A0     ADC0 and DAC0 reference select
VREF_CTRLB       0x00A1     ADC0 reference force enable
```

```
VREF_CTRLA bits 6:4 (ADC0REFSEL):
  0x0   0.55V
  0x1   1.1V
  0x2   2.5V
  0x3   4.3V
  0x4   1.5V
```

Default internal reference: 1.1V.

---

## NVMCTRL — Non-Volatile Memory Controller

Base address: 0x1000. Writing flash or EEPROM requires writing the CCP_SPM key
(0x9D) to CCP before the command, then completing the write within 4 cycles.

```
Register            Mem Addr   Description
──────────────────────────────────────────────────────────────────────
NVMCTRL_CTRLA       0x1000     Command register (write CCP key first)
NVMCTRL_CTRLB       0x1001     Boot lock, application code write protect
NVMCTRL_STATUS      0x1002     Status flags (read-only)
NVMCTRL_INTCTRL     0x1003     EEREADY interrupt enable
NVMCTRL_INTFLAGS    0x1004     EEREADY interrupt flag (W1C)
NVMCTRL_DATA        0x1006     Data register (16-bit)
NVMCTRL_ADDR        0x1008     Address register (16-bit)
```

### CTRLA — NVM Commands

```
CMD[2:0] (bits 2:0)   Command
──────────────────────────────────────────────────────────────────────
  0x00                NOCMD          No operation
  0x01                PAGEWRITE      Write page buffer to flash
  0x02                PAGEERASE      Erase one page of flash
  0x03                PAGEERASEWRITE Erase and write in one operation
  0x04                PAGEBUFCLR     Clear page write buffer
  0x05                CHIPERASE      Erase entire chip (flash + EEPROM)
  0x06                EEERASE        Erase EEPROM
  0x07                FUSEWRITE      Write fuse bytes
```

### STATUS Bits

```
Bit:  2        1       0
      WRERROR  EEBUSY  FBUSY

FBUSY    1 = flash write/erase in progress
EEBUSY   1 = EEPROM write/erase in progress
WRERROR  1 = write error occurred
```

### Memory Layout

```
Region   Start      End        Size    Notes
──────────────────────────────────────────────────────────────────────
Flash    0x0000     0x7FFF     32 KB   Program memory (word-addressed by PC)
SRAM     0x3800     0x3FFF     2 KB    Data memory (avr-ld origin 0x803800)
EEPROM   0x1400     0x14FF     256 B   (memory-mapped for read; use NVMCTRL to write)
Fuses    0x1280     0x128A              Written via UPDI/avrdude
```

Flash page size: 64 bytes. EEPROM page size: 32 bytes.

---

## Interrupt Vector Table

All vectors are 4-byte (2-word) entries. Use `JMP` (4-byte instruction) for
targets anywhere in the 32 KB flash, or `RJMP` + `NOP` (2+2 bytes) to keep the
same slot size.

```
Vector   Byte Addr   Name                   Description
──────────────────────────────────────────────────────────────────────────────
   0     0x0000      RESET                  Power-on / external / WDT reset
   1     0x0004      CRCSCAN_NMI            CRC scan non-maskable interrupt
   2     0x0008      BOD_VLM                Brown-out detection voltage level monitor
   3     0x000C      PORTA_PORT             Port A pin-change interrupt
   4     0x0010      PORTB_PORT             Port B pin-change interrupt
   5     0x0014      PORTC_PORT             Port C pin-change interrupt
   6     0x0018      RTC_CNT                RTC overflow / compare match
   7     0x001C      RTC_PIT                RTC periodic interrupt timer
   8     0x0020      TCA0_OVF / TCA0_LUNF   TCA0 overflow (single) / low underflow (split)
   9     0x0024      TCA0_HUNF              TCA0 high byte underflow (split mode)
  10     0x0028      TCA0_CMP0 / TCA0_LCMP0 TCA0 compare 0 match
  11     0x002C      TCA0_CMP1 / TCA0_LCMP1 TCA0 compare 1 match
  12     0x0030      TCA0_CMP2 / TCA0_LCMP2 TCA0 compare 2 match
  13     0x0034      TCB0_INT               TCB0 capture interrupt
  14     0x0038      TCB1_INT               TCB1 capture interrupt
  15     0x003C      TWI0_TWIS              TWI0 slave interrupt
  16     0x0040      TWI0_TWIM              TWI0 master interrupt
  17     0x0044      SPI0_INT               SPI0 transfer complete
  18     0x0048      USART0_RXC             USART0 receive complete
  19     0x004C      USART0_DRE             USART0 data register empty
  20     0x0050      USART0_TXC             USART0 transmit complete
  21     0x0054      AC0_AC                 Analog comparator interrupt
  22     0x0058      ADC0_RESRDY            ADC0 result ready
  23     0x005C      ADC0_WCMP              ADC0 window comparator match
  24     0x0060      CCL_CCL                Configurable custom logic interrupt
  25     0x0064      NVMCTRL_EE             EEPROM ready
```

Minimal startup with vector table in assembly:

```asm
    .section .vectors,"ax",@progbits
    jmp  _start              ; 0x0000 RESET — must be first
    jmp  _unhandled          ; 0x0004 CRCSCAN_NMI
    ; ... one jmp per vector ...

    .section .text
_unhandled:
    rjmp _unhandled          ; spin on unhandled interrupts

_start:
    ; ... init stack, SRAM, then jump to main
```

---

## Fuses

Fuses are one-time-programmable configuration bytes written via UPDI using
`avrdude`. Factory defaults are shown. Unlike ATmega, there is no separate
CKDIV, BOOTRST, or BOOTSZ fuse.

```
Fuse     Mem Addr   Default   Description
──────────────────────────────────────────────────────────────────────
FUSE0    0x1280     0x00      APPEND[7:0]   — application code end page
FUSE1    0x1281     0x00      BOOTEND[7:0]  — boot section end page (0=none)
FUSE2    0x1282     0x02      OSCCFG        — oscillator config
FUSE4    0x1284     0xF6      SYSCFG0       — CRC, reset pin, UPDI pin config
FUSE5    0x1285     0x07      SYSCFG1       — startup time SUT[2:0]
FUSE6    0x1286     0x00      (same as FUSE0 on this device)
FUSE7    0x1287     0x00      (same as FUSE1)
FUSE8    0x1288     0xAA      LOCKBIT
```

### FUSE2 — OSCCFG

```
Bit:  1       0
      FREQSEL FREQSEL

FREQSEL  0=16 MHz internal oscillator base
         1=20 MHz internal oscillator base  ← factory default (0x02)
```

The clock prescaler in CLKCTRL_MCLKCTRLB further divides this frequency.
Factory default: 20 MHz / 6 = 3.333 MHz.

### FUSE4 — SYSCFG0

```
Bit:  7:6    5:4      3:2         1:0
      CRCSRC RSTPINCFG UPDIPINCFG —

RSTPINCFG  0x0=GPIO, 0x1=UPDI, 0x2=RESET  (0xF6 default = RESET=GPIO, UPDI active)
CRCSRC     0x3=no CRC check (default)
```

### Writing Fuses with avrdude

```
avrdude -c serialupdi -p t3217 -P /dev/ttyUSB0 -b 115200 \
        -U fuse2:w:0x02:m

avrdude -c serialupdi -p t3217 -P /dev/ttyUSB0 -b 115200 \
        -U fuse0:w:0x00:m -U fuse1:w:0x00:m -U fuse2:w:0x02:m \
        -U fuse4:w:0xF6:m -U fuse5:w:0x07:m
```

> **Warning**: Setting RSTPINCFG incorrectly can disable the UPDI programming
> interface, effectively bricking the device. Never modify FUSE4 unless certain.
