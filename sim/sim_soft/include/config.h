#pragma once

/** @defgroup latencies Execution Latencies
 *  @brief Pipeline depth for each functional unit, in cycles.
 *
 *  Change any constant here and recompile; every component picks up the new value.
 *  @{
 */
constexpr int LAT_INT_ALU   = 1;  ///< ADD, SUB, AND, OR, XOR, shifts, ADDI variants.
constexpr int LAT_INT_LS    = 2;  ///< LW, SW - single memory-access stage.
constexpr int LAT_BRANCH    = 1;  ///< BEQ, BNE, BLT, BGE.
constexpr int LAT_FP_ADDSUB = 2;  ///< FADD.S, FSUB.S.
constexpr int LAT_FP_MUL    = 4;  ///< FMUL.S.
constexpr int LAT_FP_DIV    = 8;  ///< FDIV.S - unpipelined; stalls the FP divide unit.
constexpr int LAT_FP_LS     = 2;  ///< FLW, FSW.
constexpr int LAT_FP_CVT    = 2;  ///< FCVT.W.S, FCVT.S.W.
constexpr int LAT_MISC      = 1;  ///< NOP, HALT.
/** @} */

/** @defgroup pipelining Pipelining Flags
 *  @brief Whether a functional unit accepts a new operation every cycle.
 *
 *  @c true  - throughput = 1 op/cycle even while earlier ops are still executing.\n
 *  @c false - next op must wait until the current one finishes (throughput = 1/latency).
 *
 *  Example: FMUL pipelined=true, latency=4 → one result per cycle after the 4-cycle fill.\n
 *           FDIV pipelined=false, latency=8 → next divide must wait 8 cycles.
 *  @{
 */
constexpr bool PIPE_INT_ALU   = true;   ///< ADD, SUB, AND, OR, XOR, shifts, ADDI variants.
constexpr bool PIPE_INT_LS    = false;  ///< LW, SW - memory is not pipelined.
constexpr bool PIPE_BRANCH    = false;  ///< BEQ, BNE, BLT, BGE.
constexpr bool PIPE_FP_ADDSUB = true;   ///< FADD.S, FSUB.S.
constexpr bool PIPE_FP_MUL    = true;   ///< FMUL.S.
constexpr bool PIPE_FP_DIV    = false;  ///< FDIV.S - stalls the FP divide unit.
constexpr bool PIPE_FP_LS     = false;  ///< FLW, FSW.
constexpr bool PIPE_FP_CVT    = true;   ///< FCVT.W.S, FCVT.S.W.
constexpr bool PIPE_MISC      = false;  ///< NOP, HALT.
/** @} */

/** @defgroup sizes Structural Sizes
 *  @brief Entry counts for each pipeline buffer.  Change here and recompile.
 *  @{
 */
constexpr int IQ_CAPACITY    = 8;   ///< Instruction fetch buffer depth (entries).
constexpr int IQ_FETCH_WIDTH = 1;   ///< Instructions fetched and dispatched per cycle.
constexpr int ROB_SIZE            = 16;  ///< Reorder buffer entries.
constexpr int RS_ALU_SIZE         = 6;   ///< Integer ALU RS slots (ADD/SUB/logic/shift/imm).
constexpr int RS_BRANCH_SIZE      = 2;   ///< Branch RS slots (BEQ/BNE/BLT/BGE).
constexpr int RS_FP_ADDSUB_SIZE   = 3;   ///< FP add/sub RS slots (FADD.S, FSUB.S).
constexpr int RS_FP_MUL_SIZE      = 2;   ///< FP multiply RS slots (FMUL.S).
constexpr int RS_FP_DIV_SIZE      = 2;   ///< FP divide RS slots (FDIV.S - unpipelined).
constexpr int RS_FP_CVT_SIZE      = 2;   ///< FP conversion RS slots (FCVT.W.S, FCVT.S.W).
constexpr int LSB_SIZE            = 8;   ///< Load/store buffer entries.
/** @} */

/** @defgroup regcounts Register File Dimensions
 *  @brief RV32IF: 32 integer registers (x0-x31) and 32 FP registers (f0-f31).
 *  @{
 */
constexpr int NUM_INT_REGS  = 32;  ///< Number of integer architectural registers.
constexpr int NUM_FP_REGS   = 32;  ///< Number of FP architectural registers.
/** @} */

/** @brief Data memory capacity in 32-bit words.  Byte address = word_index * 4. */
constexpr int MEM_SIZE      = 1024;
