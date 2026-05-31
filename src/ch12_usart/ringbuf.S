/*
 * ringbuf.S — reusable byte ring buffer (circular FIFO), peripheral-agnostic
 *             Companion source for Chapter 12: USART (Serial Communication)
 *
 * This is a LIBRARY, not a program: no vector table, no main. Assemble it to an
 * object file and link it with a driver that supplies the control block(s) and
 * calls these routines. One instance per buffer; you may have as many as you
 * like (RX, TX, a log, ...) — each is just a control block in SRAM.
 *
 * Control block layout (allocate in .bss, 3 header bytes + the buffer):
 *
 *     offset 0:  head    write index (producer owns)
 *     offset 1:  tail    read index  (consumer owns)
 *     offset 2:  mask    capacity-1; capacity MUST be a power of two
 *     offset 3:  buf[capacity]
 *
 *   Example, a 16-byte instance:
 *       .section .bss
 *       my_rb:  .space 3 + 16        ; head, tail, mask, then 16 data bytes
 *
 * Sizing: capacity is a power of two so the wrap is a single AND with `mask`.
 * Sacrifice-a-slot full/empty scheme: a capacity-N buffer holds N-1 bytes.
 *     empty = (head == tail)
 *     full  = ((head + 1) & mask == tail)
 *
 * Concurrency: this is a single-producer / single-consumer (SPSC) lock-free
 * queue. ONE context may call rb_put (it alone writes head); ONE other context
 * may call rb_get (it alone writes tail). Each side only reads the index the
 * other owns, and byte loads/stores are atomic on AVR, so no cli/sei is needed.
 * Do NOT call rb_put from two contexts, or rb_get from two contexts.
 *
 * ABI: routines take the control-block address in Y (r28:r29) and PRESERVE it.
 * They assume the standard r1 == 0 convention (this book maintains it).
 *
 * Pointer-pair note: Y and Z are the only pointers with displacement
 * addressing (ldd/std Yq/Zq), which is why the control block lives in Y; Z is
 * used internally to address the data slot.
 */

#include <avr/io.h>

.equ RB_HEAD, 0
.equ RB_TAIL, 1
.equ RB_MASK, 2
.equ RB_DATA, 3

.section .text

/* ── rb_init — set an empty buffer and record its mask ────────────────────
 *   In:  Y  = &control block
 *        r16 = mask (capacity-1; capacity must be a power of two)
 *   Out: head = tail = 0, mask = r16
 *   Preserves: Y, r16.  Clobbers: nothing else.
 */
.global rb_init
rb_init:
    std   Y+RB_HEAD, r1              /* head = 0  (r1 == 0)                   */
    std   Y+RB_TAIL, r1              /* tail = 0                              */
    std   Y+RB_MASK, r16             /* mask = capacity-1                     */
    ret

/* ── rb_put — enqueue one byte ────────────────────────────────────────────
 *   In:  Y  = &control block
 *        r16 = byte to store
 *   Out: T = 1 if the buffer was full (byte NOT stored)
 *        T = 0 if the byte was enqueued
 *   Preserves: Y, r16.  Clobbers: r17, r18, Z.
 */
.global rb_put
rb_put:
    ldd   r17, Y+RB_HEAD            /* r17 = head                            */
    mov   r18, r17
    inc   r18
    ldd   ZL, Y+RB_MASK             /* (reuse ZL as scratch for the mask)    */
    and   r18, ZL                   /* r18 = next = (head + 1) & mask        */
    ldd   ZL, Y+RB_TAIL             /* ZL = tail                             */
    cp    r18, ZL
    breq  .Lrb_put_full            /* next == tail → full                    */

    movw  ZL, YL                    /* Z = &control block                    */
    adiw  ZL, RB_DATA               /* Z = &buf[0]                           */
    add   ZL, r17                   /* Z = &buf[head]                        */
    adc   ZH, r1
    st    Z, r16                    /* store byte FIRST                      */
    std   Y+RB_HEAD, r18           /* then publish new head (commit)         */
    clt                             /* T = 0 → stored                        */
    ret

.Lrb_put_full:
    set                             /* T = 1 → full, nothing stored          */
    ret

/* ── rb_get — dequeue the oldest byte ─────────────────────────────────────
 *   In:  Y  = &control block
 *   Out: T = 1 if the buffer was empty (r16 undefined)
 *        T = 0 and r16 = oldest byte otherwise
 *   Preserves: Y.  Clobbers: r16, r17, r18, Z.
 */
.global rb_get
rb_get:
    ldd   r17, Y+RB_TAIL           /* r17 = tail                            */
    ldd   r18, Y+RB_HEAD           /* r18 = head                            */
    cp    r17, r18
    breq  .Lrb_get_empty          /* head == tail → empty                   */

    movw  ZL, YL                    /* Z = &control block                    */
    adiw  ZL, RB_DATA               /* Z = &buf[0]                           */
    add   ZL, r17                   /* Z = &buf[tail]                        */
    adc   ZH, r1
    ld    r16, Z                    /* r16 = buf[tail]                       */
    inc   r17
    ldd   r18, Y+RB_MASK
    and   r17, r18                  /* tail = (tail + 1) & mask              */
    std   Y+RB_TAIL, r17           /* publish new tail (consume)             */
    clt                             /* T = 0 → valid byte in r16             */
    ret

.Lrb_get_empty:
    set                             /* T = 1 → empty                         */
    ret
