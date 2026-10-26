/*
 * Copyright (c) 2026 Cache55
 *
 * Use of this source code is governed by a MIT-style
 * license that can be found in the LICENSE file or at
 * https://opensource.org/licenses/MIT
 */

/*
 * ARM <-> Thumb interworking call sites.
 *
 * Every site is a function taking a value in r0 and returning it in r0. It
 * calls one callee with one call instruction; the callee adds 1, and the site
 * adds 0x40 after the call returns. So a site returns r0 + 0x41 only if the
 * call reached the callee, the callee returned to the instruction right after
 * the call, and both ran in the right state. A return that lands a halfword
 * off, or in the wrong state, runs garbage: a wrong sum or an exception at an
 * address inside the site.
 *
 * Call instructions covered:
 *   Thumb caller: bl, blx <imm>, blx <reg>, bx <reg>, ldr pc (literal), the
 *                 "bx pc" veneer to ARM
 *   ARM caller:   bl, blx <imm> (H bit: Thumb targets at %4 == 0 and 2),
 *                 blx <reg>, bx <reg>, ldr pc (literal), mov pc, <reg>
 * Callee returns: bx lr, pop {pc}, ldr pc, [sp], #8, mov pc, lr, and callees
 *                 that themselves call across states (chain).
 *
 * Alignment: each Thumb site is generated at every halfword offset inside a
 * 64 byte (cache line) block, so 32 bit calls also straddle the line and
 * returns land at every alignment; ARM sites sweep every word offset. The page
 * sites put a 32 bit Thumb call across a 4KB page boundary.
 *
 * Interrupts at fixed points: the C side can run a site with IRQs masked and
 * a reschedule SGI already pending on its own cpu. The first IRQ point,
 * "cpsie i; isb", then takes the interrupt right after the isb (the context
 * synchronization guarantees it is taken there, also on an out of order core
 * that would otherwise let younger instructions commit first), so the
 * exception return goes to exactly that instruction:
 *   _ic sites       IRQ point right before the call: IRQ at the call
 *   _ir sites       IRQ point at the return address: IRQ where it lands
 *   *_irq callees   IRQ point first: just inside the callee, after the switch
 * Sites without an IRQ point leave the IRQ pending for the C side.
 *
 * The table (iw_table_start .. iw_table_end) lists every site: function,
 * name, and IW_F_IRQ when running it that way must take the IRQ inside it.
 */
#include <lk/asm.h>

#define IW_F_IRQ 1

.syntax unified

/* ---------------------------------------------------------------- table */

.pushsection .rodata.iw_table, "a"
    .balign 4
    .global iw_table_start
iw_table_start:
.popsection

/* IW_F_IRQ when the site has an IRQ point, or calls an *_irq callee */
.macro iw_flagword irq, target
    .ifnc   \irq,
    .word   IW_F_IRQ
    .exitm
    .endif
    .ifc    \target,iw_t_irq
    .word   IW_F_IRQ
    .exitm
    .endif
    .ifc    \target,iw_a_irq
    .word   IW_F_IRQ
    .exitm
    .endif
    .word   0
.endm

.macro iw_entry fn, desc, irq, target
    .pushsection .rodata.iw_table, "a"
    .word   \fn
    .word   .Liw_name\@
    iw_flagword \irq, \target
    .popsection
    .pushsection .rodata.iw_names, "a"
.Liw_name\@:
    .asciz  "\desc"
    .popsection
.endm

.macro tfunc name
    .thumb
    .thumb_func
    .global \name
    .type   \name, %function
\name:
.endm

.macro afunc name
    .arm
    .global \name
    .type   \name, %function
\name:
.endm

/* an IRQ point: unmask IRQs, and the isb makes a pending one be taken here */
.macro iw_irq_on
    cpsie   i
    isb
.endm

.text

/* -------------------------------------------------------------- callees */
/* Each adds 1 to r0. Thumb ones sit at both word alignments. */

    .balign 64
tfunc iw_t_bx0                  /* Thumb, address % 4 == 0, bx lr */
    adds    r0, r0, #1
    bx      lr

    .balign 64
    .thumb
    nop
tfunc iw_t_bx2                  /* Thumb, address % 4 == 2, bx lr */
    adds    r0, r0, #1
    bx      lr

    .balign 64
    .thumb
    nop
tfunc iw_t_pop                  /* Thumb, pop {pc} (interworking load) */
    push    {r4, lr}
    adds    r0, r0, #1
    pop     {r4, pc}

    .balign 64
tfunc iw_t_ldr                  /* Thumb, ldr pc, [sp], #8 (interworking load) */
    str     lr, [sp, #-8]!
    adds    r0, r0, #1
    ldr     pc, [sp], #8

    .balign 64
    .thumb
    nop
tfunc iw_t_mov                  /* Thumb, mov pc, lr: stays Thumb, Thumb callers only */
    adds    r0, r0, #1
    mov     pc, lr

    .balign 64
    .thumb
    nop
tfunc iw_t_chain                /* Thumb -> ARM -> back, then return */
    push    {r4, lr}
    blx     iw_a_bx
    pop     {r4, pc}

    .balign 64
    .thumb
    nop
tfunc iw_t_irq                  /* Thumb, %4 == 2: IRQ point right after the entry */
    iw_irq_on
    adds    r0, r0, #1
    bx      lr

    .balign 64
afunc iw_a_bx                   /* ARM, bx lr */
    add     r0, r0, #1
    bx      lr

    .balign 64
afunc iw_a_pop                  /* ARM, pop {pc} (LDM, interworking) */
    push    {r4, lr}
    add     r0, r0, #1
    pop     {r4, pc}

    .balign 64
afunc iw_a_ldr                  /* ARM, ldr pc, [sp], #8 (interworking load) */
    str     lr, [sp, #-8]!
    add     r0, r0, #1
    ldr     pc, [sp], #8

    .balign 64
afunc iw_a_mov                  /* ARM, mov pc, lr: interworks in ARM state (v7+) */
    add     r0, r0, #1
    mov     pc, lr

    .balign 64
afunc iw_a_chain                /* ARM -> Thumb (%4 == 2) -> back, then return */
    push    {r4, lr}
    blx     iw_t_bx2
    pop     {r4, pc}

    .balign 64
afunc iw_a_irq                  /* ARM: IRQ point right after the entry */
    iw_irq_on
    add     r0, r0, #1
    bx      lr

/* --------------------------------------------------- Thumb call kinds */
/* tsetup_<kind> runs before the alignment padding, tcall_<kind> is the call. */

.macro tsetup_bl target, ret, lit
.endm
.macro tcall_bl target, ret, lit
    bl      \target
.endm

.macro tsetup_blxi target, ret, lit
.endm
.macro tcall_blxi target, ret, lit
    blx     \target
.endm

.macro tsetup_blxr target, ret, lit
    ldr     r4, =\target
.endm
.macro tcall_blxr target, ret, lit
    blx     r4
.endm

/* lr = the return label with the Thumb bit; a literal reaches any distance */
.macro tsetup_bxr target, ret, lit
    ldr     r4, =\target
    ldr     lr, =(\ret + 1)
.endm
.macro tcall_bxr target, ret, lit
    bx      r4
.endm

.macro tsetup_ldrpc target, ret, lit
    ldr     lr, =(\ret + 1)
.endm
/* LDR (literal) to pc is an interworking load; the site emits the literal */
.macro tcall_ldrpc target, ret, lit
    ldr.w   pc, \lit
.endm

/* IRQ points: cpsie i in front of the call (_ic) or at the return (_ir) */
.macro iw_irq_at where, irq
    .ifc    \irq,\where
    iw_irq_on
    .endif
.endm

/* a Thumb site: push, setup, \pad halfwords of nop, the call, the check */
.macro tsite kind, target, pad, irq=
    .balign 64
tfunc iw_ts_\kind\()_\target\()_\pad\()\irq
    push    {r4, lr}
    tsetup_\kind \target, .Liw_ret\@, .Liw_lit\@
    .rept   \pad
    nop
    .endr
    iw_irq_at _ic, \irq
    tcall_\kind \target, .Liw_ret\@, .Liw_lit\@
.Liw_ret\@:
    iw_irq_at _ir, \irq
    adds    r0, r0, #0x40
    pop     {r4, pc}
    .balign 4
.Liw_lit\@:
    .word   \target
    .ltorg
    iw_entry iw_ts_\kind\()_\target\()_\pad\()\irq, "T \kind -> \target +\pad\irq", \irq, \target
.endm

/* "bx pc" veneer: a Thumb site that switches itself to ARM, then calls */
.macro tsite_bxpc target, pad
    .balign 64
tfunc iw_ts_bxpc_\target\()_\pad
    push    {r4, lr}
    .rept   \pad
    nop
    .endr
    .balign 4
    bx      pc                  /* pc reads as . + 4: ARM state at the next word */
    nop
    .arm
    bl      \target
    add     r0, r0, #0x40
    pop     {r4, pc}            /* ARM LDM: back to the Thumb caller */
    .ltorg
    iw_entry iw_ts_bxpc_\target\()_\pad, "T bxpc -> \target +\pad", , \target
.endm

/* a 32 bit Thumb call at offset 4094 of a page: its second half on the next */
.macro tsite_page kind, target, irq=
tfunc iw_tp_\kind\()_\target\()\irq
    push    {r4, lr}
    tsetup_\kind \target, .Liw_ret\@, .Liw_lit\@
    b.w     .Liw_call\@
    .ltorg
    .balign 4096
    .ifc    \irq,_ic
    .skip   4088
.Liw_call\@:                    /* the b.w lands on the cpsie, at 4088 ... */
    iw_irq_on                   /* ... + isb: the IRQ is taken at the call, 4094 */
    .else
    .skip   4094
.Liw_call\@:
    .endif
    tcall_\kind \target, .Liw_ret\@, .Liw_lit\@
.Liw_ret\@:
    iw_irq_at _ir, \irq
    adds    r0, r0, #0x40
    pop     {r4, pc}
    .balign 4
.Liw_lit\@:
    .word   \target
    .ltorg
    iw_entry iw_tp_\kind\()_\target\()\irq, "T \kind -> \target page-straddle\irq", \irq, \target
.endm

/* ----------------------------------------------------- ARM call kinds */

.macro asetup_bl target, ret
.endm
.macro acall_bl target, ret
    bl      \target
.endm

.macro asetup_blxi target, ret
.endm
.macro acall_blxi target, ret
    blx     \target
.endm

.macro asetup_blxr target, ret
    ldr     r4, =\target
.endm
.macro acall_blxr target, ret
    blx     r4
.endm

.macro asetup_bxr target, ret
    ldr     r4, =\target
    adr     lr, \ret
.endm
.macro acall_bxr target, ret
    bx      r4
.endm

.macro asetup_ldrpc target, ret
    adr     lr, \ret
.endm
.macro acall_ldrpc target, ret
    ldr     pc, =\target
.endm

.macro asetup_movpc target, ret
    ldr     r4, =\target
.endm
.macro acall_movpc target, ret
    mov     lr, pc              /* lr = . + 8: the instruction after the mov pc */
    mov     pc, r4              /* ALU write to pc: interworks in ARM state */
.endm

.macro asite kind, target, pad, irq=
    .balign 64
afunc iw_as_\kind\()_\target\()_\pad\()\irq
    push    {r4, lr}
    asetup_\kind \target, .Liw_ret\@
    .rept   \pad
    nop
    .endr
    iw_irq_at _ic, \irq         /* movpc: before the mov lr, pc; mov pc pair */
    acall_\kind \target, .Liw_ret\@
.Liw_ret\@:
    iw_irq_at _ir, \irq
    add     r0, r0, #0x40
    pop     {r4, pc}
    .ltorg
    iw_entry iw_as_\kind\()_\target\()_\pad\()\irq, "A \kind -> \target +\pad\irq", \irq, \target
.endm

/* ------------------------------------------------------------ sweeps */

#define THUMB_PADS 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
#define ARM_PADS   0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15

/* Thumb targets any caller may use, ARM targets, the Thumb-only one, and
 * the callees with an IRQ point at their entry */
#define T_TARGETS  iw_t_bx0, iw_t_bx2, iw_t_pop, iw_t_ldr, iw_t_chain
#define A_TARGETS  iw_a_bx, iw_a_pop, iw_a_ldr, iw_a_mov, iw_a_chain
#define IRQ_T      iw_t_irq
#define IRQ_A      iw_a_irq

.macro tsweep kind, irq, targets:vararg
    .irp target, \targets
    .irp pad, THUMB_PADS
    tsite \kind, \target, \pad, \irq
    .endr
    .endr
.endm

.macro asweep kind, irq, targets:vararg
    .irp target, \targets
    .irp pad, ARM_PADS
    asite \kind, \target, \pad, \irq
    .endr
    .endr
.endm

/*
 * Every Thumb and ARM call kind for one IRQ placement ("", _ic or _ir).
 * TT / AT are parenthesised target lists (a preprocessor macro, so a list can
 * be one argument); ';' separates the assembler statements.
 */
#define IW_UNPAREN(...) __VA_ARGS__
#define SWEEP_ALL(irq, TT, AT) \
    tsweep bl,    irq, IW_UNPAREN TT, iw_t_mov ; \
    tsweep blxi,  irq, IW_UNPAREN AT ; \
    tsweep blxr,  irq, IW_UNPAREN TT, iw_t_mov, IW_UNPAREN AT ; \
    tsweep bxr,   irq, IW_UNPAREN TT, iw_t_mov, IW_UNPAREN AT ; \
    tsweep ldrpc, irq, IW_UNPAREN TT, iw_t_mov, IW_UNPAREN AT ; \
    asweep bl,    irq, IW_UNPAREN AT ; \
    asweep blxi,  irq, IW_UNPAREN TT ; \
    asweep blxr,  irq, IW_UNPAREN TT, IW_UNPAREN AT ; \
    asweep bxr,   irq, IW_UNPAREN TT, IW_UNPAREN AT ; \
    asweep ldrpc, irq, IW_UNPAREN TT, IW_UNPAREN AT ; \
    asweep movpc, irq, IW_UNPAREN TT, IW_UNPAREN AT

    /* Thumb -> Thumb, Thumb -> ARM, ARM -> ARM, ARM -> Thumb (both
     * alignments), direct and via register / load / ALU write to pc */

    /* no IRQ point in the site; the *_irq callees take it after the switch */
    SWEEP_ALL(, (T_TARGETS, IRQ_T), (A_TARGETS, IRQ_A))
    /* IRQ exactly at the call instruction */
    SWEEP_ALL(_ic, (T_TARGETS), (A_TARGETS))
    /* IRQ exactly where the return lands */
    SWEEP_ALL(_ir, (T_TARGETS), (A_TARGETS))

    /* Thumb -> ARM through the bx pc veneer */
    .irp target, A_TARGETS, IRQ_A
    .irp pad, THUMB_PADS
    tsite_bxpc \target, \pad
    .endr
    .endr

    /* 32 bit Thumb calls straddling a 4KB page, also with the IRQ at the
     * straddling call and at its return */
    .irp irq, , _ic, _ir
    tsite_page bl,    iw_t_bx0, \irq
    tsite_page bl,    iw_t_bx2, \irq
    tsite_page blxi,  iw_a_bx,  \irq
    tsite_page ldrpc, iw_t_bx2, \irq
    tsite_page ldrpc, iw_a_bx,  \irq
    .endr

.pushsection .rodata.iw_table, "a"
    .global iw_table_end
iw_table_end:
.popsection

/* ------------------------------------------------------- relocatable blob */
/*
 * Position independent copies of the page-straddling Thumb calls, for the C
 * side to copy into a fresh mapping made of 4KB pages: the kernel image is
 * mapped with 1MB sections, so there both halves of a straddling call share
 * one TLB entry, while in the copy the second half needs its own page walk.
 * Only pc-relative branches, so the blob runs at any address. Each entry
 * straddles its own page boundary: page 0 holds the entries and callees, each
 * call sits at offset 4094 of the next odd page.
 */

.macro blob_call entry, insn, callee, irq=
    .thumb
    .balign 4096
    .ifc    \irq,_ic
    .skip   4088
.Lblob_\entry:
    iw_irq_on                   /* IRQ taken at the straddling call */
    .else
    .skip   4094
.Lblob_\entry:
    .endif
    \insn   \callee             /* offset 4094: second half on the next page */
    .ifc    \irq,_ir
    iw_irq_on                   /* IRQ where the return lands, next page */
    .endif
    adds    r0, r0, #0x40
    pop     {r4, pc}
    .balign 4096                /* the next call gets a fresh page pair */
.endm

    .balign 4096
    .global iw_blob_start
iw_blob_start:

.macro blob_entry entry
tfunc iw_blob_\entry
    push    {r4, lr}
    b.w     .Lblob_\entry
.endm

    blob_entry bl
    blob_entry blx
    blob_entry bl_ic
    blob_entry blx_ic
    blob_entry bl_ir
    blob_entry blx_ir

    .balign 64
tfunc iw_blob_t_callee
    adds    r0, r0, #1
    bx      lr

    .balign 64
afunc iw_blob_a_callee
    add     r0, r0, #1
    bx      lr

    blob_call bl,     bl,  iw_blob_t_callee
    blob_call blx,    blx, iw_blob_a_callee
    blob_call bl_ic,  bl,  iw_blob_t_callee, _ic
    blob_call blx_ic, blx, iw_blob_a_callee, _ic
    blob_call bl_ir,  bl,  iw_blob_t_callee, _ir
    blob_call blx_ir, blx, iw_blob_a_callee, _ir

    .global iw_blob_end
iw_blob_end:
