# UPDI — The Unified Program and Debug Interface

Every program you write in this book eventually ends up on the ATtiny3217 as
bytes in flash. UPDI is the hardware interface that puts those bytes there. It
also provides the debugging channel that chapter 3A uses. Understanding UPDI
from first principles — the wire protocol, the instruction set, the key
mechanism, the register map — gives you a complete picture of what happens
between typing `avrdude` and seeing your LED blink.

This chapter covers everything from the physical layer through the full
programming sequence:

1. What UPDI is, and how it differs from the ISP interface it replaced.
2. The single-wire UART physical layer: frame formats, baud rate, guard time.
3. Three ways to enable UPDI on the RESET pin.
4. The eight UPDI instructions and their wire transactions.
5. Key-protected operations: chip erase, NVM programming, user-row write.
6. The full UPDI register map with every bit explained.
7. Hardware adapters: jtag2updi (legacy), SerialUPDI (diode or resistor method),
   and the on-board nEDBG on the Curiosity Nano.
8. Software tools: avrdude and pymcuprog command references.
9. On-chip debugging (OCD) capabilities exposed through UPDI.
10. Troubleshooting: error signatures, contention, fuse lock-out, HV recovery.

---

## ISP vs UPDI: Why Microchip Changed the Interface

Classic AVR devices (ATmega328P and earlier) use the **In-System Programming
(ISP)** interface for programming. ISP is SPI-based and requires four
dedicated pins: SCK, MOSI, MISO, and RESET. Programming is synchronous — the
host clocks every bit.

Modern AVRs (tinyAVR 0/1/2-series, megaAVR 0-series, AVR DA/DB/DD/EA-series)
released since 2016 use **UPDI** instead:

```
Feature          ISP (ATmega328P)        UPDI (ATtiny3217)
────────────────────────────────────────────────────────────────
Pins used        SCK + MOSI + MISO + RST  One pin: RESET/PA0
Protocol         SPI (4-wire synchronous) Half-duplex async UART
Baud detection   Fixed clock from host    Auto-baud from SYNCH char
Breakpoints      2 hardware only          2 hardware + unlimited software
Memory access    Sequential only          Full memory map random access
Fuse locking     SPIEN fuse               RSTPINCFG + HV override
OCD support      debugWIRE (separate)     Built-in, same pin
Max baud rate    1 MHz                    900 kbps (@ 5 V)
```

UPDI consolidates programming and debugging onto one pin with no clock
line, no separate MISO/MOSI, and no dedicated SPI peripheral required in
the programmer.

---

## The Physical Layer

### The Single UPDI Pin

On the ATtiny3217, PA0 is a three-function pin labelled `PA0/RESET/UPDI` in
the datasheet (physical pin 16 on the 20-SOIC package; pin 23 on the 24-VQFN).
Which function is active depends on the `RSTPINCFG` bits in `FUSE.SYSCFG0`:

```
RSTPINCFG[1:0]   PA0 pin function
──────────────────────────────────────
0x0              GPIO  — PA0 is general-purpose I/O; UPDI inaccessible without HV
0x1              UPDI  — factory default; UPDI takes over the pin
0x2              RESET — external reset input; UPDI inaccessible without HV
Other            Reserved
```

Factory default: `SYSCFG0` resets to `0xC4`, placing `RSTPINCFG[1:0]` at `0b01`
(0x1 = UPDI mode). A freshly manufactured ATtiny3217 always comes up in UPDI mode.

The UPDI pin has a constant internal pull-up when UPDI is active. The protocol
is **half-duplex, single-wire, asynchronous UART** with:

- 8 data bits
- 1 parity bit (even parity, can be disabled)
- 2 stop bits
- Auto-baud (the baud rate is measured from each SYNCH character)
- No baud rate register — the programmer drives timing entirely

---

## Frame Formats

The UPDI recognises five types of frames on the wire:

```
Frame   Bit pattern                          Meaning
──────────────────────────────────────────────────────────────────────────
DATA    [St][D0..D7][P][S1][S2]              Normal 8-bit data byte
IDLE    12 high bits                         Line idle / gap
BREAK   12 low bits                          Reset UPDI to default state
SYNCH   DATA frame with value 0x55           Set baud rate for next transaction
ACK     DATA frame with value 0x40           Target confirms successful ST/STS
```

Every DATA frame: Start bit (low), 8 data bits LSB first, 1 even parity
bit, 2 stop bits (high).  Total: 12 bit-periods per byte.

### BREAK Character

A BREAK is 12 consecutive low bits — the line held low for 12 bit-periods.
BREAK resets the UPDI internal state machine back to idle and clears any
error condition. It also resets the UPDI oscillator to the 4 MHz default.

To guarantee detection in all cases, the programmer sends **two consecutive
BREAK frames**. The first BREAK may be missed if the UPDI is mid-transaction,
but it will cause a framing or contention error that aborts the transaction;
the second BREAK is then detected cleanly.

Minimum BREAK duration at each clock setting:

```
UPDICLKDIV   UPDI Clock   Minimum BREAK Duration
──────────────────────────────────────────────────
0x3 (default)   4 MHz          24.60 ms
0x2             8 MHz          12.30 ms
0x1            16 MHz           6.15 ms
```

### SYNCH Character (0x55)

The SYNCH byte `0x55` has alternating 0/1 bits. The UPDI measures the time
between transitions to derive the baud rate used by the programmer. This baud
rate is then used for all subsequent frames in the transaction.

Every new instruction must be preceded by a SYNCH. The only exception is when
using REPEAT: only the first instruction after a REPEAT needs a SYNCH.

### Guard Time

After the programmer sends an instruction, the UPDI must change direction from
receive to transmit before it can reply. The guard time is a configurable
number of IDLE bits inserted before the first reply byte:

```
GTVAL[2:0]   Guard Time (UPDI clock cycles)
─────────────────────────────────────────────
0x0 (default)   128 cycles
0x1              64 cycles
0x2              32 cycles
0x3              16 cycles
0x4               8 cycles
0x5               4 cycles
0x6               2 cycles
0x7          Reserved
```

The programmer must wait for at least the guard time before sampling the
reply. In practice, tools leave at least two guard-time cycles from the
programmer side as well.

### Baud Rate Limits

UPDI baud rate limits depend on VDD:

```
VDD Range            Max Baud Rate
───────────────────────────────────
1.8 V – 5.5 V         225 kbps
2.2 V – 5.5 V         450 kbps
2.7 V – 5.5 V         900 kbps
```

Practical tools typically use 115,200 or 230,400 bps for maximum
compatibility. The ATtiny3217 Curiosity Nano's on-board programmer
uses 225 kbps by default.

---

## UPDI Enable Sequences

UPDI must be enabled before communication can begin. There are two methods.

### Standard Enable (RSTPINCFG = 0x1)

When `RSTPINCFG = 0x1` (factory default), PA0 is dedicated to UPDI and
carries a constant pull-up. The programmer drives the pin low for at least
200 ns to trigger the enable handshake:

```
Programmer          UPDI Pin             UPDI State
──────────────────────────────────────────────────────────────────
  Pull-up active                         Pin held high by pull-up
  Drive pin LOW                          Edge detector triggers
  (hold ≥ 200 ns)
  Release pin (Hi-Z)                     UPDI holds low while clock starts
                     ← UPDI releases →
                     Pin goes HIGH        Clock ready, UPDI waiting
  Send 0x55 SYNCH                        Baud rate locked, UPDI enabled
  (within 16.4 ms
   of pin going high)
  First instruction                      Ready to accept instructions
```

If SYNCH is not sent within 16.4 ms (65536 UPDI clock cycles at 4 MHz),
UPDI disables itself and the sequence must restart.

Timing parameters (from Electrical Characteristics, §36.21):

```
Symbol    Description                              Min      Max    Unit
────────────────────────────────────────────────────────────────────────
TRES      Duration of Handshake/BREAK              10       200    µs
TUPDI     Duration of UPDI.txd = 0                 10       200    µs
TDeb0     Duration of Debugger.txd = 0            200 ns     1     µs
TDebZ     Duration of Debugger.txd = z            200     14000    µs
```

### High-Voltage (HV) Override

When `RSTPINCFG = 0x0` (GPIO) or `0x2` (RESET), UPDI is inaccessible
without HV. Applying a 12 V pulse to PA0 switches the pin to UPDI mode
regardless of fuse settings. This is the only recovery path from GPIO mode.

```
Step    Action
──────────────────────────────────────────────────────────
1       Reset the device (recommended before HV sequence).
2       Apply 12 V pulse to PA0; hold for 100 µs–1 ms, then tri-state.
3       Hold HV for ≥ 200 µs, ≤ 14 ms.
4       Remove HV (tri-state).
5       Programmer drives PA0 LOW to release UPDI reset.
6       Release PA0 (Hi-Z); UPDI drives LOW until clock ready.
7       Wait for PA0 to go HIGH (UPDI clock ready).
8       Send SYNCH (0x55) within TDebZ.
9       Send NVMPROG key immediately after first SYNCH.
10      Program device; then write UPDIDIS to disable UPDI.
```

After an HV-enable session, the RESET pin remains in UPDI configuration
until a Power-on Reset (POR). Issuing UPDIDIS does not restore PA0 to GPIO —
only POR does. This means HV enables temporary UPDI access without
permanently changing the fuse.

HV-specific timing (from figure 33-6 in the datasheet):

```
Symbol      Description                          Min      Max    Unit
──────────────────────────────────────────────────────────────────────
THV_ramp    HV rise time                          10       4000   ns/µs (10 ns–4 ms)
TRES        HV pulse hold duration                10        200   µs
TUPDI       UPDI holds pin low after HV edge      10        200   µs
TDeb0       Programmer drives pin LOW            200 ns      1    µs
TDebZ       Pin-high to first SYNCH start        200      14000   µs
```

---

## UPDI Disabling

End every UPDI session by writing `UPDIDIS = 1` in `UPDI.CTRLB`. This:

- Issues a system reset, returning the CPU to the Run state.
- Lowers the UPDI clock request, reducing power consumption.
- Clears all UPDI KEYs and configuration.

If the session ends without disabling UPDI, the oscillator request remains
active, causing higher idle power consumption.

---

## The UPDI Instruction Set

The UPDI has eight instructions. Every instruction must be preceded by a SYNCH
character (except instructions inside a REPEAT sequence after the first). The
instruction is a single byte encoding an opcode and size fields.

```
Instruction   Opcode Bits     Purpose
─────────────────────────────────────────────────────────────────
LDS           0b00_aaaa_bb     Load (read) from data space, direct address
STS           0b01_aaaa_bb     Store (write) to data space, direct address
LD            0b00_1pp_aa_bb   Load from data space, indirect via pointer
ST            0b01_1pp_aa_bb   Store to data space, indirect via pointer
LDCS          0b10_0_ccccc     Load from UPDI CS register space
STCS          0b11_0_ccccc     Store to UPDI CS register space
REPEAT        0b10_00001_bb    Set repeat counter
KEY           0b11_00_s_c_1    Send key or receive SIB
```

Size fields:
```
Size A (address)    0x0 = 1 byte   0x1 = 2 bytes   0x2 = 3 bytes (>64 KB)
Size B (data)       0x0 = 1 byte   0x1 = 2 bytes
CS Address          5-bit field, selects UPDI CS register (0x00–0x0C)
```

### LDS — Load Data Space, Direct Address

Read a byte or word from any address in the data space.

```
Wire sequence:

Programmer → UPDI:  [SYNCH][LDS opcode][addr_lo][addr_hi]
UPDI → Programmer:  (guard time)  [data_byte]

If Size A = 2 bytes, addr is 2 bytes (covers tinyAVR ≤ 64 KB data space).
```

Example: read `PORTB.IN` at data address `0x0428` (PORTB base `0x0420` + IN offset `0x08`):

```
Send: 0x55 0x04 0x28 0x04
Recv: <value of PORTB.IN>
```

Note: `0x04` is `LDS` with Size A = word (2 bytes), Size B = byte.

### STS — Store Data Space, Direct Address

Write a byte or word to any address in the data space.

```
Wire sequence:

Programmer → UPDI:  [SYNCH][STS opcode][addr_lo][addr_hi]
UPDI → Programmer:  (guard time) [ACK 0x40]
Programmer → UPDI:  [data_byte]
UPDI → Programmer:  (guard time) [ACK 0x40]
```

The double-ACK confirms both the address phase and the data phase.

### LD — Load Data Space, Indirect (via Pointer Register)

First write the pointer register with an ST to pointer address, then use LD
with pointer post-increment to stream data. Most useful with REPEAT.

```
Set pointer:  SYNCH + ST(ptr) + addr_lo + addr_hi → ACK
Read bytes:   SYNCH + LD(*(ptr++)) → data_0, data_1, ..., data_n
```

### ST — Store Data Space, Indirect (via Pointer Register)

Write the pointer register, then stream bytes to consecutive addresses.
Most useful for writing flash page buffers.

```
Set pointer:  SYNCH + ST(ptr) + addr_lo + addr_hi → ACK
Write bytes:  SYNCH + ST(*(ptr++)) + data_0 → ACK
              (REPEAT handles subsequent bytes without extra SYNCH)
```

### LDCS — Load UPDI Control/Status Register

Read one byte from the UPDI internal CS register space (not the device
memory map). Used to check UPDI status, error signatures, and ASI state.

```
Wire sequence:
Programmer → UPDI:  [SYNCH][LDCS opcode with 5-bit CS address]
UPDI → Programmer:  (guard time) [register_value]
```

### STCS — Store UPDI Control/Status Register

Write one byte to a UPDI internal CS register. No ACK is generated.

```
Wire sequence:
Programmer → UPDI:  [SYNCH][STCS opcode with 5-bit CS address][data_byte]
```

Common uses: set GTVAL, enable IBDLY, write UPDIDIS to end session, change
clock speed via ASI_CTRLA.

### REPEAT — Set Repeat Counter

Load a repeat count N. The next instruction executes N+1 times, with the
overhead of SYNCH and opcode omitted after the first iteration.

```
Wire sequence:
Programmer → UPDI:  [SYNCH][REPEAT opcode][repeat_count]
Programmer → UPDI:  [SYNCH][next instruction + operands]
                    [data_1][data_2]...[data_N]   (no SYNCH between repeats)
```

Maximum repeat count: 255 (giving 256 total executions). Only LD and ST
with pointer post-increment (`*(ptr++)`) make sense with REPEAT. To abort
a REPEAT in progress, send a BREAK.

Example: write 128 bytes to the flash page buffer for page 0, starting at
`0x8000` (mapped flash start in data space on the ATtiny3217):

```
1. SYNCH + ST(ptr) + 0x00 + 0x80  → ACK   (set pointer to 0x8000)
2. SYNCH + REPEAT  + 0x7F                  (repeat 127 more times = 128 total)
3. SYNCH + ST(*(ptr++)) + byte_0 → ACK
   byte_1 → ACK
   byte_2 → ACK
   ...
   byte_127 → ACK
```

### KEY — Send Activation Key or Read SIB

Unlock a protected feature by sending an 8-byte (64-bit) key. Also used to
request the 16-byte System Information Block.

```
Wire sequence (send key):
Programmer → UPDI:  [SYNCH][KEY opcode][key_7][key_6]...[key_0]
(No response generated — check ASI_KEY_STATUS with LDCS to confirm.)

Wire sequence (request SIB):
Programmer → UPDI:  [SYNCH][KEY opcode with SIB=1]
UPDI → Programmer:  (guard time) [sib_0][sib_1]...[sib_15]
```

Available keys (bytes transmitted LSB first):

```
Key Name        Hex Signature (byte 0 first)    Size
──────────────────────────────────────────────────────────
Chip Erase      4E 56 4D 45 72 61 73 65        64-bit
NVMPROG         4E 56 4D 50 72 6F 67 20        64-bit
USERROW-Write   4E 56 4D 55 73 26 74 65        64-bit
```

The System Information Block (SIB) identifies the device to the programmer:

```
Byte Range   Field           Content
──────────────────────────────────────────────────
[0–6]        Family_ID       ASCII, e.g. "tinyAVR" (7 bytes)
[7]          Reserved        —
[8–10]       NVM_VERSION     NVM controller version (3 bytes)
[11–13]      OCD_VERSION     OCD controller version (3 bytes)
[14]         Reserved        —
[15]         DBG_OSC_FREQ    Debug oscillator frequency class
```

---

## Key-Protected Operations

Three operations require keys: chip erase, NVM programming, and user-row
write. All three follow the same structure: send key → reset → poll status →
perform operation → reset again.

### Chip Erase

Chip erase clears all flash and lock bits. EEPROM is also erased unless
the `EESAVE` fuse (SYSCFG0 bit 0) is set — except on a locked device,
where EEPROM is always erased regardless of `EESAVE`. The User Row is
never affected by chip erase. Chip erase is the only way to unlock a
locked device.

```
Step  Action
────────────────────────────────────────────────────────────────────────
1.    Send Chip Erase key with KEY instruction.
2.    (Optional) LDCS ASI_KEY_STATUS → confirm CHIPERASE bit = 1.
3.    STCS ASI_RESET_REQ ← 0x59   (assert system reset)
4.    STCS ASI_RESET_REQ ← 0x00   (release system reset)
5.    LDCS ASI_SYS_STATUS → poll until LOCKSTATUS = 0.
6.    (Optional) LDCS ASI_SYS_STATUS → check ERASE_FAILED = 0 if present.
      Note: the ERASE_FAILED bit appears in the chip erase procedure in the
      datasheet text (§33.3.8.1) but is absent from the ASI_SYS_STATUS
      register description. Checking LOCKSTATUS = 0 (step 5) is the
      reliable completion test.
7.    Done. Device is unlocked; full UPDI bus access is restored.
```

Caution: the BOD is forced on during chip erase. If VDD is below the BOD
threshold the erase will not complete.

### NVM Programming

After chip erase (or on an already-unlocked device):

```
Step  Action
────────────────────────────────────────────────────────────────────────
1.    (If locked) perform Chip Erase first.
2.    Send NVMPROG key with KEY instruction.
3.    (Optional) LDCS ASI_KEY_STATUS → confirm NVMPROG bit = 1.
4.    STCS ASI_RESET_REQ ← 0x59   (assert system reset; halts CPU)
5.    STCS ASI_RESET_REQ ← 0x00   (release system reset)
6.    LDCS ASI_SYS_STATUS → poll until NVMPROG bit = 1.
7.    Write data to flash via STS / ST + REPEAT targeting mapped flash.
      (Use NVMCTRL commands: see Chapter 16 for the NVMCTRL write flow.)
8.    STCS ASI_RESET_REQ ← 0x59   (assert reset to end programming)
9.    STCS ASI_RESET_REQ ← 0x00   (release reset)
10.   Programming complete. UPDI regains access; CPU is running.
```

Writing to flash via UPDI follows exactly the NVMCTRL sequence from Chapter 16
(page-buffer fill → `PAGEERASEWRITE` command), except the CPU is halted and
the programmer drives every store.

### User Row Programming on a Locked Device

The USERROW is a 64-byte area of non-volatile memory distinct from flash. It
can be updated even when the device lock bits are set — the device can be
field-updated without revealing the program.

```
Step  Action
────────────────────────────────────────────────────────────────────────
1.    Send USERROW-Write key with KEY instruction.
2.    (Optional) LDCS ASI_KEY_STATUS → confirm UROWWRITE bit = 1.
3.    STCS ASI_RESET_REQ ← 0x59 / 0x00  (reset cycle)
4.    LDCS ASI_SYS_STATUS → poll until UROWPROG = 1.
5.    Write 64 bytes of data to the first 64 bytes of RAM (address 0x3800,
      the start of SRAM on the ATtiny3217) using ST + REPEAT.
      (Only the first 64 bytes of RAM are accessible; writes outside this
       range are silently ignored.)
6.    STCS ASI_SYS_CTRLA ← UROWWRITE_FINAL = 1  (commit RAM → user row)
7.    LDCS ASI_SYS_STATUS → poll until UROWPROG = 0.
8.    STCS ASI_KEY_STATUS ← UROWWRITE = 1  (invalidate key)
9.    STCS ASI_RESET_REQ ← 0x59 / 0x00  (final reset)
10.   User row programming complete.
```

---

## The UPDI Register Map

UPDI registers live in an internal CS (Control/Status) space addressed by the
5-bit CS field in LDCS/STCS instructions, not in the normal I/O address space.
The CPU cannot read them.

```
CS Addr   Register Name     Reset    Access   Description
────────────────────────────────────────────────────────────────────────
0x00      STATUSA           0x10     R        Status A (UPDI revision)
0x01      STATUSB           0x00     R        Status B (error signature)
0x02      CTRLA             0x00     R/W      Control A (timing, parity)
0x03      CTRLB             0x00     R/W      Control B (disable UPDI)
0x04–06   Reserved          —        —        —
0x07      ASI_KEY_STATUS    0x00     R/W      Key activation status
0x08      ASI_RESET_REQ     0x00     R/W      System reset request
0x09      ASI_CTRLA         0x03     R/W      UPDI clock select
0x0A      ASI_SYS_CTRLA     0x00     R/W      System control (CLKREQ, UROWDONE)
0x0B      ASI_SYS_STATUS    0x01     R        System status
0x0C      ASI_CRC_STATUS    0x00     R        CRC check result
```

### STATUSA (0x00) — Status A

```
Bit    Name          Reset   Access
────────────────────────────────────
[7:4]  UPDIREV[3:0]  0x1     R       UPDI implementation revision
[3:0]  —             —       —       Reserved
```

The ATtiny3217 returns `UPDIREV = 1` (reset value `0x10` = bits[7:4] = 1).

### STATUSB (0x01) — Status B

```
Bit    Name        Reset   Access
──────────────────────────────────
[2:0]  PESIG[2:0]  0x0     R       Error signature (cleared on read)

PESIG value   Error type
──────────────────────────────────────────────────────────
0x0           No error (default)
0x1           Parity error (wrong parity bit sampled)
0x2           Frame error (wrong stop bits sampled)
0x3           Access layer time-out (ACC layer no response)
0x4           Clock recovery error (wrong start bit sampled)
0x5           Reserved
0x6           Bus error (address or access privilege violation)
0x7           Contention error (both sides driving the line)
```

When an error occurs, read STATUSB after a BREAK + SYNCH to find out what
went wrong before retrying.

### CTRLA (0x02) — Control A

```
Bit   Name     Reset   Access   Description
──────────────────────────────────────────────────────────────────────
7     IBDLY    0       R/W      Inter-Byte Delay Enable.
                                1 = insert 2 IDLE bits between bytes in
                                multi-byte LD(S) reads. Prevents overflow
                                when the host processes data slowly.
6     —        —       —        Reserved
5     PARD     0       R/W      Parity Disable. 1 = ignore parity bit.
                                Use only for testing.
4     DTD      0       R/W      Disable Time-Out Detection.
                                1 = disable 65536-cycle ACC-layer timeout.
3     RSD      0       R/W      Response Signature Disable.
                                1 = suppress ACK generation (faster bulk NVM
                                writes when timing is known).
[2:0] GTVAL    0x0     R/W      Guard Time Value (see table above).
```

### CTRLB (0x03) — Control B

```
Bit   Name       Reset   Access   Description
────────────────────────────────────────────────────────────────────
4     NACKDIS    0       R/W      Disable NACK during system reset.
3     CCDETDIS   0       R/W      Disable contention detection.
2     UPDIDIS    0       R/W      Write 1 to disable UPDI, reset device,
                                  clear all keys and configuration.
```

### ASI_KEY_STATUS (0x07)

```
Bit   Name        Reset   Access   Description
──────────────────────────────────────────────────────────
5     UROWWRITE   0       R/W      USERROW-Write key decoded and active.
                                   Write 1 to invalidate key after user
                                   row programming.
4     NVMPROG     0       R        NVMPROG key decoded. Cleared when
                                   NVMPROG mode starts.
3     CHIPERASE   0       R        Chip Erase key decoded. Cleared by
                                   the reset issued in erase sequence.
```

### ASI_RESET_REQ (0x08)

```
Bit    Name        Reset   Access
[7:0]  RSTREQ      0x00    R/W

Value    Action
──────────────────────────────────
0x59     Assert system reset (CPU halted, peripherals running)
0x00     Release system reset (CPU resumes)
Other    Clears reset condition
```

The UPDI itself is NOT reset by this register — it continues running so
the programmer can poll status.

### ASI_CTRLA (0x09)

```
Bit    Name           Reset   Access   Description
──────────────────────────────────────────────────────────────────
[1:0]  UPDICLKSEL     0x3     R/W      UPDI clock frequency:
                                       0x0 = Reserved
                                       0x1 = 16 MHz
                                       0x2 = 8 MHz
                                       0x3 = 4 MHz (default)
```

Use 16 MHz UPDI clock only when BOD is at its highest level.

### ASI_SYS_CTRLA (0x0A)

```
Bit   Name                Reset   Access   Description
──────────────────────────────────────────────────────────────────────
1     UROWWRITE_FINAL     0       R/W      Write 1 when user-row RAM is
                                           ready to commit to NVM. Only
                                           writable when UROWWRITE key active.
0     CLKREQ              0       R/W      1 = keep system clock running even
                                           in sleep modes (default when UPDI
                                           is enabled). 0 = lower clock request.
```

### ASI_SYS_STATUS (0x0B)

```
Bit   Name         Reset   Access   Description
────────────────────────────────────────────────────────────────────
5     RSTSYS       0       R        1 = system domain in reset. Cleared on read.
4     INSLEEP      0       R        1 = system domain in Idle or deeper sleep.
3     NVMPROG      0       R        1 = NVM Programming mode active; safe to write.
2     UROWPROG     0       R        1 = User Row Programming active.
0     LOCKSTATUS   1       R        1 = device is locked. 0 after chip erase.
```

### ASI_CRC_STATUS (0x0C)

```
Bit    Name           Reset   Access
[2:0]  CRC_STATUS     0x0     R

Value   Meaning
─────────────────────────────────────────
0x0     CRC not enabled
0x1     CRC enabled, still running
0x2     CRC done — PASSED
0x4     CRC done — FAILED
```

---

## Hardware Adapters

### The nEDBG: Curiosity Nano On-Board Programmer

The ATtiny3217 Curiosity Nano board includes a dedicated microcontroller
(**nEDBG**, nano Embedded Debugger) that connects to the ATtiny3217's UPDI pin.
No external hardware is needed.

```
Curiosity Nano (top view, simplified)

 ┌─────────────────────────────────────────────────────┐
 │  USB-C        nEDBG (UPDI host)                     │
 │  connector   ┌─────────────┐    ATtiny3217           │
 │  ────────────│  ATsamD21   │───PA0 (UPDI/RESET)     │
 │              │  (debugger) │───VCC                   │
 │              │             │───GND                   │
 │              └─────────────┘                         │
 └─────────────────────────────────────────────────────┘
```

The USB connection to your PC presents as a CDC serial port and a HID device.
avrdude uses the `curiosity_updi` programmer type to communicate with it.
No diodes, no resistors, no extra hardware required.

---

### jtag2updi (Legacy Firmware Programmer)

**jtag2updi** was the first widely-used DIY UPDI programmer. It is open-source
firmware (by ElTangas, 2018–2020) that runs on a spare Arduino (typically an
Arduino Nano or Uno with an ATmega328P or ATmega4809). The Arduino emulates
a JTAG-to-UPDI bridge, which avrdude speaks to as if it were an Atmel ICE.

jtag2updi has largely been superseded by SerialUPDI (see below), but the
firmware is still available at `github.com/ElTangas/jtag2updi` and works with
avrdude's `jtag2updi` programmer type.

**jtag2updi Circuit:**

The key requirement is a series resistor between the Arduino's digital output
(Arduino pin 6 by default) and the target's UPDI pin. This isolates the two
microcontrollers and prevents bus contention.

```
Arduino (jtag2updi firmware)          Target ATtiny3217
 ──────────────────────────           ──────────────────────────
 GND ──────────────────────────────── GND
 5V or 3.3V ──────────────────────── VCC  (match target voltage)
 Pin 6 (TX)  ──── 4.7 kΩ ──────────── PA0 (UPDI)

```

Note: the 4.7 kΩ is appropriate specifically for jtag2updi because the
firmware drives the line as a push-pull output with its own current limiting
logic. Do NOT use this value with SerialUPDI adapters (see below).

**Full jtag2updi schematic (through-hole, breadboard friendly):**

```
                          4.7 kΩ
Arduino Nano              ┌───┐             ATtiny3217 target
 ┌────────────┐           │   │          ┌──────────────────┐
 │         D6 │───────────┤   ├──────────│ PA0 (UPDI/RESET) │
 │        GND │───────────────────────────│ GND              │
 │   5V / 3V3 │───────────────────────────│ VCC              │
 └────────────┘                          └──────────────────┘

(USB to PC for avrdude)
```

**avrdude command for jtag2updi:**

```bash
avrdude -c jtag2updi -p t3217 -P /dev/ttyUSB0 -b 115200 \
        -U flash:w:firmware.hex:i
```

**Limitations of jtag2updi:**
- Baud rate limited to approximately 115,200 bps in practice.
- The firmware is complex and had known stability issues with some AVR targets.
- Performance significantly slower than SerialUPDI at equivalent baud rates.
- As of 2021, the jtag2updi project is in maintenance-only mode.

---

### SerialUPDI: Direct USB Serial Adapter

SerialUPDI (by Spence Konde and Quentin Bolsée, 2020–2021) uses a standard
USB-to-serial adapter directly as a UPDI programmer with minimal external
circuitry. It is significantly faster and simpler than jtag2updi and is now
the recommended DIY approach.

The key insight is that UPDI is a half-duplex single-wire UART. A serial
adapter's TX and RX lines can be combined with a small diode (or resistor) to
create a single bidirectional line.

#### Required Hardware

1. A USB-to-serial adapter (CH340, CP2102, or FT232RL recommended).
2. One **Schottky diode** (BAT43, BAT54, 1N5817, or similar). A Schottky diode
   is strongly preferred over a regular silicon diode; the lower forward voltage
   drop avoids signal integrity problems at higher baud rates.
3. An optional 470 Ω series resistor (provides short-circuit protection).

#### Recommended Wiring: Diode Method

```
USB Serial Adapter (with internal TX resistor 1–2 kΩ, e.g. CH340)

 ┌────────────────────┐
 │  DTR               │
 │  RX  ──────────────┼───────────────────────── PA0 (UPDI)
 │  TX  ──┤< Schottky │                           │
 │        (BAT43)     │    470 Ω optional          │
 │  VCC ──────────────┼───────────────────────── VCC
 │  GND ──────────────┼───────────────────────── GND
 └────────────────────┘

Band of diode points toward TX (current flows TX → junction → UPDI/RX).
```

```
ASCII schematic detail:

  TX ──────┤►├──────┬──── PA0 (UPDI)
                    │
  RX ──────────────'
  
  (diode band = ►, toward TX side)
```

The diode allows TX to drive the UPDI line high/low, while the target's
UPDI responses flow back on RX without the diode blocking them. RX and TX
are tied together at the UPDI pin junction.

#### Wiring: Resistor Method (PyUPDI Classic)

If no Schottky diode is available, a resistor can be used. The total resistance
(adapter's TX series resistor + external resistor) must sum to approximately
**4.7 kΩ**:

```
  TX ────── 4.7 kΩ ──────┬──── PA0 (UPDI)
  (if no internal R)      │
  RX ────────────────────'
```

If the adapter already has a 1–2 kΩ internal TX resistor, add enough to total
4.7 kΩ. The resistor method is less tolerant of voltage drops and high-speed
signalling; prefer the diode method.

#### Adapter Voltage Considerations

- The ATtiny3217 runs at 3.3 V on the Curiosity Nano.
- Many CH340 adapters output 5 V logic levels even with a 3.3 V VCC jumper.
  Check your adapter datasheet.
- A 470 Ω series resistor on the UPDI line also provides some protection
  from level mismatch.

#### FTDI FT232RL Latency

The FT232RL defaults to a USB latency timer of 16 ms, which makes UPDI
programming extremely slow (each page write requires multiple USB round trips).
Set the latency timer to 1 ms before using with SerialUPDI:

- **Linux:** `echo 1 | sudo tee /sys/bus/usb-serial/devices/ttyUSB0/latency_timer`
- **Windows:** Device Manager → Ports → FT232R → Properties → Port Settings →
  Advanced → Latency Timer → 1 ms

#### avrdude Command for SerialUPDI

```bash
# Write flash at 230400 baud (general purpose speed)
avrdude -c serialupdi -p t3217 -P /dev/ttyUSB0 -b 230400 \
        -U flash:w:firmware.hex:i

# Read flash to file
avrdude -c serialupdi -p t3217 -P /dev/ttyUSB0 -b 230400 \
        -U flash:r:readback.hex:i

# Write fuses (set OSCCFG to select 20 MHz internal oscillator)
avrdude -c serialupdi -p t3217 -P /dev/ttyUSB0 -b 230400 \
        -U fuse2:w:0x02:m

# Perform chip erase
avrdude -c serialupdi -p t3217 -P /dev/ttyUSB0 -b 230400 -e

# Windows: substitute COM3 (or whichever port) for /dev/ttyUSB0
```

#### Speed by Adapter (ATtiny3217, 128-byte page)

```
Adapter       115200 baud   230400 baud   460800 baud   Notes
──────────────────────────────────────────────────────────────────
CH340G        8.4 W/8.5 R  14.6 W/16.6 R  6.0 W/26.8 R  Best value
FT232RL       8.7 W/8.8 R  16.6 W/16.4 R 10.4 W/28.2 R  Needs 1 ms latency
CP2102        8.7 W/8.8 R  16.3 W/16.5 R       N/A       No 345600 by default
```

(kb/s; W = write, R = read. ATtiny with 128-byte pages measured on Linux.)

---

## pymcuprog: Microchip's Python UPDI Tool

pymcuprog is Microchip's official Python implementation of the UPDI programming
protocol. It is the reference implementation and the basis from which SerialUPDI
was derived. Install via pip:

```bash
pip install pymcuprog
```

Common operations:

```bash
# Read device ID (confirm connection)
pymcuprog ping -t uart -u /dev/ttyUSB0 -d attiny3217

# Write flash from hex file
pymcuprog write -t uart -u /dev/ttyUSB0 -d attiny3217 \
         --filename firmware.hex

# Erase flash
pymcuprog erase -t uart -u /dev/ttyUSB0 -d attiny3217

# Read fuses
pymcuprog read -t uart -u /dev/ttyUSB0 -d attiny3217 -m fuses

# Write a single fuse (FUSE2, index 2)
pymcuprog write -t uart -u /dev/ttyUSB0 -d attiny3217 \
         -m fuses --offset 2 --literal 0x02
```

pymcuprog is slower than the avrdude SerialUPDI implementation for large flash
writes but is more portable and easier to script for custom workflows.

---

## On-Chip Debugging (OCD) via UPDI

The same UPDI pin that programs the device also provides the debugging channel
used in Chapter 3A. The OCD controller is accessed through the UPDI ACC layer
with no additional wiring.

OCD capabilities on the ATtiny3217:

```
Feature                         Capability
────────────────────────────────────────────────────────────────────────
Hardware breakpoints            2 (set via OCD registers; no flash writes needed)
Software breakpoints            Unlimited (BREAK opcode patched into flash)
Program counter readout         Real-time PC via UPDI CS register read
Stack pointer readout           SP available via data space read at any time
SREG readout                    Status register readable at any time
Memory access while halted      Full read/write access to all memory-mapped I/O
Run/Stop/Reset control          Via ASI_SYS_STATUS and ASI_RESET_REQ
Non-intrusive monitoring        Can read PC/SP/SREG without halting CPU
Sleep mode debugging            CLKREQ bit keeps ACC layer accessible in sleep
```

The OCD debug key (required to unlock OCD Stop mode for full register access)
is not published in the public datasheet but is available to tools like
avarice and openOCD that speak to the ATtiny3217 via the Curiosity Nano's
nEDBG. The GDB + avarice flow described in Chapter 3A uses this path.

---

## Fuses That Affect UPDI Access

The following fuses in `FUSE.SYSCFG0` directly control UPDI accessibility:

```
SYSCFG0 address: 0x1285  (FUSE peripheral base 0x1280 + offset 0x05)

SYSCFG0 bits [3:2] = RSTPINCFG[1:0]
──────────────────────────────────────────────────────────────────────
0x0   PA0 = GPIO.   UPDI completely inaccessible. HV required to recover.
0x1   PA0 = UPDI  (default). No external reset. Debugger connects freely.
0x2   PA0 = RESET.  External reset active. UPDI inaccessible without HV.
0x3   Reserved.
```

**Do not set RSTPINCFG = 0x0 unless you have a high-voltage programmer.**

Check current fuse settings before programming them:

```bash
avrdude -c serialupdi -p t3217 -P /dev/ttyUSB0 -b 230400 \
        -U fuses:r:current_fuses.bin:r -v
```

The fuse layout for the ATtiny3217 (all 9 bytes, byte index 0–8):

```
Fuse Index   Name       Relevant Fields
──────────────────────────────────────────────────────────────────
0            WDTCFG     Watchdog config
1            BODCFG     Brown-out detector config
2            OSCCFG     Clock source (0x01=16 MHz, 0x02=20 MHz)
(no index 3)
4            TCD0CFG    TCD0 config
5            SYSCFG0    RSTPINCFG (bits[3:2]), CRCSRC (bits[7:6]), EESAVE (bit 0)
6            SYSCFG1    SUT startup time (bits[2:0])
7            APPEND     Application code end (× 256 bytes)
8            BOOTEND    Boot section end (× 256 bytes)
```

---

## Troubleshooting

### Connection Fails Immediately

1. Verify `RSTPINCFG ≠ 0x0` (GPIO mode). If it is, you need an HV programmer.
2. Check VCC and GND connections.
3. Try reducing baud rate (`-b 57600`).
4. On Linux, verify you are in the `dialout` group: `sudo usermod -aG dialout $USER`.

### Error: "UPDI contention" or PESIG = 0x7

The UPDI line is being driven simultaneously by programmer and target.
Common causes:
- LED on the RX line of the USB serial adapter (the weak UPDI driver cannot
  overcome the LED load — remove the RX LED or use an adapter without one).
- Series resistor on the target board too large (> 2.2 kΩ). Replace with 470 Ω
  or short it.
- Wrong diode orientation.

### Error: PESIG = 0x1 (Parity) or 0x2 (Frame)

Baud rate mismatch. Either the SYNCH character was corrupted, or the adapter
is outputting a baud rate different from what avrdude requested. Try 57600 baud
to rule out signal integrity issues.

### Error: PESIG = 0x6 (Bus error)

Attempt to access a protected address. Usually means the NVMPROG key was not
sent before trying to write flash, or the device lock bits are set. Run a chip
erase first.

### PESIG = 0x3 (Access Layer Timeout)

The UPDI ACC layer could not get bus access within 65536 UPDI clock cycles.
Usually caused by the CPU being stuck in an infinite loop that monopolises
the bus. Issue BREAK + system reset, then retry.

### Device Locked (LOCKSTATUS = 1)

Send the Chip Erase key and perform the chip erase sequence. All flash and
user data will be lost, but the device will be unlocked and reprogrammable.

### Recovery from RSTPINCFG = 0x0 (No UPDI Access)

You need a high-voltage programmer capable of applying a 12 V pulse to PA0.
Options:
- MPLAB Snap (Microchip's official programmer, supports HV UPDI).
- JTAG2UPDI with HV hardware modifications.
- Custom HV circuit: a MOSFET-based 12 V boost with precise timing control.

Once recovered via HV programming, immediately write correct fuses to restore
`RSTPINCFG = 0x1` or `0x2` before disconnecting.

---

## Complete Wire-Level Walk-Through: Programming One Flash Page

To make the protocol concrete, here is the full UPDI byte sequence that
writes a single 128-byte page of flash to address `0x0000` on the ATtiny3217
from scratch using SerialUPDI. Values are hexadecimal.

```
1. BREAK (×2):    Two 12-bit low sequences ~25 ms each

2. SYNCH + LDCS STATUSA (read revision, confirm link):
   Send: 55 80
   Recv: 10   (UPDIREV = 1)

3. SYNCH + KEY (NVMPROG key, LSB first):
   Send: 55 E4 4E 56 4D 50 72 6F 67 20

4. SYNCH + LDCS ASI_KEY_STATUS (confirm NVMPROG bit set):
   Send: 55 87
   Recv: 10   (bit 4 = NVMPROG active)

5. SYNCH + STCS ASI_RESET_REQ ← 0x59 (assert reset):
   Send: 55 C8 59

6. SYNCH + STCS ASI_RESET_REQ ← 0x00 (release reset):
   Send: 55 C8 00

7. SYNCH + LDCS ASI_SYS_STATUS (poll until NVMPROG=1):
   Send: 55 8B
   Recv: 08   (bit 3 = NVMPROG active; CPU halted)

8. Set NVMCTRL CMD = PAGEERASEWRITE (0x03):
   SYNCH + STS addr=0x1000 data=0x03
   Send: 55 44 00 10 03   (STS, 2-byte addr, 1-byte data; addr=NVMCTRL.CTRLA)
   Recv: 40 40             (two ACKs)

9. Set pointer to mapped flash page 0 (0x8000 = mapped flash start):
   SYNCH + ST(ptr) ← 0x8000:
   Send: 55 6A 00 80       (ST ptr, 2-byte address 0x8000)
   Recv: 40                (ACK)

10. SYNCH + REPEAT 127 (128 total writes):
    Send: 55 A0 7F

11. SYNCH + ST(*(ptr++)) + 128 bytes of data:
    Send: 55 64 <byte_0>
    Recv: 40               (ACK for byte_0)
    Send: <byte_1>
    Recv: 40
    ... (continue for all 128 bytes)

12. Poll NVMCTRL.STATUS until FBUSY = 0 (write+erase complete):
    SYNCH + LDS addr=0x1002 (NVMCTRL.STATUS):
    Send: 55 04 02 10
    Recv: <status>  — poll until bit 0 (FBUSY) = 0

13. STCS ASI_RESET_REQ ← 0x59 / 0x00 (final reset):
    Send: 55 C8 59
    Send: 55 C8 00

14. STCS CTRLB ← UPDIDIS=1 (disable UPDI, return to normal run):
    Send: 55 C3 04
```

The full 128-byte page write including all overhead typically completes in
under 10 ms at 230400 baud plus the 4 ms PAGEERASEWRITE NVM time.

---

## Summary

UPDI is a single-wire, half-duplex UART that replaces ISP on all modern AVR
devices. It provides:

- Full read/write access to every byte in the device's memory map.
- A key mechanism that unlocks three UPDI-initiated protected operations:
  chip erase, NVM programming, and user row write.
- Built-in on-chip debugging (OCD) on the same pin.
- Hardware-enforced protection via lock bits, bypassed only by chip erase.
- An HV override that can restore access even when the UPDI pin has been
  repurposed as a GPIO.

For daily development with the ATtiny3217 Curiosity Nano, the on-board nEDBG
handles everything transparently. For standalone boards or custom hardware,
a CH340-based SerialUPDI adapter with a single Schottky diode is all that is
needed to program and debug.

The protocol details in this chapter — frame formats, instruction encodings,
key signatures, register addresses — are the same across the entire modern
AVR family: tinyAVR 0/1/2, megaAVR 0, and all AVR DA/DB/DD/EA parts. Once
you know the ATtiny3217's UPDI, you know UPDI everywhere.
