#pragma once

/* Execution latencies in cycles — change here, recompile, done. */
constexpr int LAT_INT_ALU   = 1;  /* ADD SUB AND OR XOR shifts ADDI … */
constexpr int LAT_INT_LS    = 2;  /* LW SW                             */
constexpr int LAT_BRANCH    = 1;  /* BEQ BNE BLT BGE                   */
constexpr int LAT_FP_ADDSUB = 2;  /* FADD.S FSUB.S                     */
constexpr int LAT_FP_MUL    = 4;  /* FMUL.S                            */
constexpr int LAT_FP_DIV    = 8;  /* FDIV.S                            */
constexpr int LAT_FP_LS     = 2;  /* FLW FSW                           */
constexpr int LAT_FP_CVT    = 2;  /* FCVT.W.S FCVT.S.W                */
constexpr int LAT_MISC      = 1;  /* NOP HALT                          */

/* Structural sizes — number of entries in each unit. */
constexpr int IQ_CAPACITY   = 8;   /* instruction fetch buffer depth */
constexpr int ROB_SIZE      = 16;  /* reorder buffer entries         */
constexpr int RS_INT_SIZE   = 6;   /* integer reservation stations   */
constexpr int RS_FP_SIZE    = 4;   /* FP reservation stations        */
constexpr int LSB_SIZE      = 8;   /* load/store buffer entries      */

/* Register file sizes (RV32IF: 32 int + 32 FP). */
constexpr int NUM_INT_REGS  = 32;
constexpr int NUM_FP_REGS   = 32;
