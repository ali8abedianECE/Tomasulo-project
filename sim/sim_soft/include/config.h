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

/*
 * Pipelining flags — true means the FU accepts a new op every cycle (throughput=1)
 * even while a previous op is still executing. false means the FU is occupied until
 * the current op finishes (throughput = latency cycles).
 * Example: FMUL pipelined=true, latency=4 means one result per cycle after 4-cycle fill.
 *          FDIV pipelined=false, latency=8 means next op must wait 8 cycles.
 */
constexpr bool PIPE_INT_ALU   = true;   /* ADD SUB AND OR XOR shifts ADDI … */
constexpr bool PIPE_INT_LS    = false;  /* LW SW — memory not pipelined      */
constexpr bool PIPE_BRANCH    = false;  /* BEQ BNE BLT BGE                   */
constexpr bool PIPE_FP_ADDSUB = true;   /* FADD.S FSUB.S                     */
constexpr bool PIPE_FP_MUL    = true;   /* FMUL.S                            */
constexpr bool PIPE_FP_DIV    = false;  /* FDIV.S — stalls FP div unit       */
constexpr bool PIPE_FP_LS     = false;  /* FLW FSW                           */
constexpr bool PIPE_FP_CVT    = true;   /* FCVT.W.S FCVT.S.W                */
constexpr bool PIPE_MISC      = false;  /* NOP HALT                          */

/* Structural sizes — number of entries in each unit. */
constexpr int IQ_CAPACITY   = 8;   /* instruction fetch buffer depth */
constexpr int ROB_SIZE      = 16;  /* reorder buffer entries         */
constexpr int RS_INT_SIZE   = 6;   /* integer reservation stations   */
constexpr int RS_FP_SIZE    = 4;   /* FP reservation stations        */
constexpr int LSB_SIZE      = 8;   /* load/store buffer entries      */

/* Register file sizes (RV32IF: 32 int + 32 FP). */
constexpr int NUM_INT_REGS  = 32;
constexpr int NUM_FP_REGS   = 32;

/* Data memory size in 32-bit words (word address = byte_address >> 2). */
constexpr int MEM_SIZE      = 1024;
