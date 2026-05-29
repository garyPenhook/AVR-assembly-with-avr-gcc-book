# GAS Directive Reference

GNU Assembler (`avr-as`) directives used in AVR assembly. Directives begin with
`.` and are not instructions — they control how the assembler lays out output.

---

## Section Directives

```
Directive                     Effect
──────────────────────────────────────────────────────────────────────────────
.section name [,"flags"[,@type]]
                              Switch to named section. Common flags:
                                a = allocatable
                                w = writable
                                x = executable
                              Types: @progbits (data), @nobits (BSS, zero-init)

.text                         Switch to .text (code, flash)
.data                         Switch to .data (initialised SRAM variables)
.bss                          Switch to .bss  (zero-initialised SRAM)
.rodata                       Read-only data (constants in flash on AVR)
```

Common section usage on AVR:

```asm
.section .text          /* executable code (flash) */
.section .data          /* initialised variables (SRAM; copied from flash at startup) */
.section .bss           /* zero-initialised variables (SRAM) */
.section .rodata        /* constants (flash; access via LPM) */
.section .vectors,"ax",@progbits   /* interrupt vector table */
.section .noinit,"aw",@nobits      /* SRAM variables NOT initialised at reset */
```

---

## Symbol Directives

```
Directive                     Effect
──────────────────────────────────────────────────────────────────────────────
.global symbol                Export symbol (visible to linker / other files)
.local  symbol                Mark symbol local (file scope only)
.weak   symbol                Weak symbol: overridden if another file defines it
.type   symbol, @function     Mark symbol as function (for debugging/ELF info)
.type   symbol, @object       Mark symbol as data object
.size   symbol, size          Set symbol size (bytes)
.set    symbol, expr          Define symbol = expr (reassignable)
.equ    symbol, expr          Define symbol = expr (reassignable; synonym of .set)
.equiv  symbol, expr          Like .equ, but errors if symbol already defined
```

Example:

```asm
.global uart_init
.type   uart_init, @function
uart_init:
    /* ... */
    ret
.size uart_init, . - uart_init   /* size = current address minus symbol start */
```

---

## Data Directives

```
Directive        Size per item   Example
──────────────────────────────────────────────────────────────────────────────
.byte  expr[,…]  1 byte          .byte 0x3F, 42, 'A'
.2byte expr[,…]  2 bytes LE      .2byte 0x1234         /* = 0x34, 0x12 in memory */
.word  expr[,…]  2 bytes LE      .word 1000            /* AVR word = 2 bytes */
.long  expr[,…]  4 bytes LE      .long 0xDEADBEEF
.quad  expr[,…]  8 bytes LE      .quad 0
.ascii "str"     n bytes         .ascii "hello"        /* no null terminator */
.asciz "str"     n+1 bytes       .asciz "hello"        /* null terminated */
.string "str"    n+1 bytes       .string "hello"       /* alias for .asciz */
.space n [,fill] n bytes         .space 16, 0xFF       /* fill with 0xFF */
.zero  n         n zero bytes    .zero 64              /* alias for .space n, 0 */
.skip  n [,fill] n bytes         .skip 4               /* alias for .space */
.fill  reps,size,val             .fill 8, 1, 0xAA      /* 8 bytes of 0xAA */
```

---

## Alignment Directives

```
Directive        Effect
──────────────────────────────────────────────────────────────────────────────
.align  n        Align to 2^n byte boundary (with NOP padding in .text)
.balign n [,fill] Align to n byte boundary
.p2align n       Align to 2^n boundary (same as .align on most targets)
.org    expr     Set location counter to expr (absolute address)
```

On AVR, `.align 1` aligns to 2-byte boundary (one AVR word). `.align 2`
aligns to 4 bytes. Useful before jump tables and 16-bit data.

---

## Conditional Assembly

```
Directive        Effect
──────────────────────────────────────────────────────────────────────────────
.ifdef  sym      Include if sym is defined
.ifndef sym      Include if sym is NOT defined
.if     expr     Include if expr != 0
.else            Else branch
.elif   expr     Else-if
.endif           End conditional block
.error "msg"     Abort assembly with message
.warning "msg"   Emit warning, continue
```

Example — select multiply implementation at assemble time:

```asm
#ifdef NOMUL
    rcall mul8u_shiftadd
#else
    mul   r16, r17
    movw  r24, r0
    clr   r1
#endif
```

When using `avr-gcc` as the front-end, `#ifdef`/`#define` (C preprocessor)
work in `.S` files. For plain `avr-as`, use `.ifdef`/`.equ`.

---

## Macro Directives

```
Directive        Effect
──────────────────────────────────────────────────────────────────────────────
.macro name [params]   Begin macro definition
.endm                  End macro definition
.exitm                 Exit macro early
.rept  n               Repeat enclosed block n times
.endr                  End .rept block
.irp   sym, values     Iterate: sym takes each value in turn
.endr
.irpc  sym, chars      Iterate over characters of a string
.endr
```

Example — macro for a 16-bit load:

```asm
.macro  ldw  reg_h, reg_l, value
    ldi   \reg_l, lo8(\value)
    ldi   \reg_h, hi8(\value)
.endm

/* Usage */
ldw   r25, r24, 1999    /* expands to: ldi r24, lo8(1999); ldi r25, hi8(1999) */
```

Example — `.rept` for vector table padding:

```asm
__vectors:
    rjmp  reset_handler
    .rept 25
    rjmp  dummy_isr        /* fill remaining 25 vectors */
    .endr
```

---

## Include Directives

```
Directive           Effect
──────────────────────────────────────────────────────────────────────────────
.include "file"     Textually include file at this point
#include <file>     C preprocessor include (only when assembled via avr-gcc)
```

For AVR with `avr-gcc -x assembler-with-cpp` (the default for `.S` files):

```asm
#include <avr/io.h>        /* defines I/O register names, bit names, RAMEND, etc. */
```

`<avr/io.h>` selects the correct device header based on `-mmcu=` flag.

---

## Listing and Debug Directives

```
Directive            Effect
──────────────────────────────────────────────────────────────────────────────
.file "name"         Set source file name (for debug info)
.line n              Set source line number
.loc file line [col] DWARF location (used by avr-gcc; rarely hand-written)
.stabs "str",n,n,n,n STABS debug info (legacy)
.ident "string"      Embed comment string in .comment ELF section
```

---

## Expression Operators

GAS expressions can use these operators in directives and immediate operands:

```
Operator   Example             Meaning
──────────────────────────────────────────────────────────────────────────────
+          .byte 1+2           Addition
-          .byte 5-3           Subtraction
*          .word 16*1000       Multiplication
/          .byte 255/2         Integer division
%          .byte 17%10         Modulo
<<         .word 1<<8          Left shift
>>         .word 256>>1        Right shift
&          .byte 0xFF & val    Bitwise AND
|          .byte flags | mask  Bitwise OR
^          .byte a ^ b         Bitwise XOR
~          .byte ~mask         Bitwise NOT
lo8(x)     ldi r16, lo8(val)  Low byte of 16-bit value
hi8(x)     ldi r16, hi8(val)  High byte of 16-bit value
hlo8(x)                        Byte 2 (bits 23:16) of 32-bit value
hhi8(x)                        Byte 3 (bits 31:24) of 32-bit value
pm(x)      .word pm(label)     Program memory word address (byte addr >> 1)
.          (dot)               Current location counter (address)
```

---

## Common Patterns

### Define a constant

```asm
.equ  F_CPU,   16000000
.equ  BAUD,    9600
.equ  UBRR_V,  (F_CPU / (16 * BAUD)) - 1   /* = 103 */
```

### Reserve SRAM variable

```asm
.section .bss
my_var:  .byte 0    /* 1-byte variable */
my_word: .2byte 0   /* 2-byte variable, aligned */
my_buf:  .space 64  /* 64-byte buffer */
```

### Initialised variable (copied to SRAM at startup by avr-libc __init)

```asm
.section .data
init_val: .byte 42
```

### Constant in flash (accessed via LPM)

```asm
.section .rodata
my_table:
    .byte 0, 1, 1, 2, 3, 5, 8, 13   /* Fibonacci */
```

### Local labels

```asm
func:
    ldi   r16, 10
1:                  /* local label — referenced as 1f (forward) or 1b (back) */
    dec   r16
    brne  1b        /* branch back to label 1 */
    ret
```

Local labels (numeric) can be reused across the file; `1f` means "next `1:`
going forward", `1b` means "previous `1:` going backward". They do not pollute
the symbol table.
