#ifndef COMPLIANCE_TEST_H
#define COMPLIANCE_TEST_H

#include "compliance_io.h"

/*
 * Target: Tomasulo RV32I OoO processor.
 *
 * HALT mechanism: the decoder maps any instruction with opcode 0x73
 * (RISC-V SYSTEM / ECALL) to OP_HALT, so a plain 'ecall' stops the
 * pipeline.  No privilege modes, no trap handlers.
 *
 * Memory layout (MEM_SIZE = 1024 words = 4096 bytes):
 *   0x0000-0x03FF  .text  (code, 1 KB)
 *   0x0400-0x0FFF  .data  (signature + variables, 3 KB)
 */

#define RVTEST_RV32U    \
  .macro init;          \
  .endm

#define RVTEST_CODE_BEGIN         \
  .section .text.init;            \
  .align 2;                       \
  .globl _start;                  \
_start:                           \
  init;

/* ecall (0x00000073) -> OP_HALT in our decoder */
#define RVTEST_CODE_END           \
  ecall

#define RVTEST_PASS               \
  ecall

#define RVTEST_FAIL               \
  ecall

#define RVTEST_DATA_BEGIN         \
  .pushsection .data;             \
  .align 4;                       \
  .globl begin_signature;         \
begin_signature:

#define RVTEST_DATA_END           \
  .globl end_signature;           \
end_signature:                    \
  .popsection

#endif /* COMPLIANCE_TEST_H */
