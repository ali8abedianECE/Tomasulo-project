#pragma once
#include "config.h"
#include <cstdint>

/**
 * @brief All opcodes supported by the RV32IF pipeline.
 *
 * Instruction formats (RISC-V standard):
 *   R-type  [31:25 funct7][24:20 rs2][19:15 rs1][14:12 funct3][11:7 rd ][6:0 opcode]
 *   I-type  [31:20 imm12 ][19:15 rs1][14:12 funct3][11:7 rd ][6:0 opcode]
 *   S-type  [31:25 imm[11:5]][24:20 rs2][19:15 rs1][14:12 funct3][11:7 imm[4:0]][6:0 opcode]
 *   B-type  [31 imm12][30:25 imm[10:5]][24:20 rs2][19:15 rs1][14:12 funct3][11:8 imm[4:1]][7 imm11][6:0 opcode]
 *
 * Raw bit fields are not preserved after decode; only the Instruction struct fields flow downstream.
 */
enum class Opcode : uint8_t {
    /* Integer R-type */
    ADD, SUB, AND, OR, XOR, SLL, SRL, SRA,
    /* Integer I-type  (imm[11:0] sign-extended to 32 bits) */
    ADDI, ANDI, ORI, XORI, SLLI, SRLI,
    /* Integer load/store
     * LW : rd = Mem[rs1+imm]           I-type imm[11:0]
     * SW : Mem[rs1+imm] = rs2          S-type imm[11:0] split */
    LW, SW,
    /* Branch (B-type, imm = sign-extended byte offset, target = PC+imm) */
    BEQ, BNE, BLT, BGE,
    /* FP ALU single-precision R-type (funct7 distinguishes op) */
    FADD_S, FSUB_S, FMUL_S, FDIV_S,
    /* FP load/store — same addressing as LW/SW, dest/src is f-register
     * FLW : fd = Mem[rs1+imm]
     * FSW : Mem[rs1+imm] = fs2 */
    FLW, FSW,
    /* FP <-> Int conversion (R-type shell, one src one dst)
     * FCVT_W_S : xd  = (int32_t) fs1   f-reg src, x-reg dst
     * FCVT_S_W : fd  = (float)   xs1   x-reg src, f-reg dst */
    FCVT_W_S,
    FCVT_S_W,
    NOP,
    HALT
};

/**
 * @brief Decoded instruction that flows through the pipeline.
 *
 * Register indices are 0-31 for both x-regs and f-regs.
 * The @c *_fp flags tell each stage which register file to use for each field.
 */
struct Instruction {
    Opcode  op     = Opcode::NOP;
    int     rd     = -1;     ///< Destination register index (0-31); -1 = no writeback.
    int     rs1    = -1;     ///< Source register 1 index (0-31); -1 = unused.
    int     rs2    = -1;     ///< Source register 2 index (0-31); -1 = unused.
    int32_t imm    = 0;      ///< Sign-extended 32-bit immediate.
    bool    rd_fp  = false;  ///< True if @c rd lives in the FP register file (f0-f31).
    bool    rs1_fp = false;  ///< True if @c rs1 lives in the FP register file (f0-f31).
    bool    rs2_fp = false;  ///< True if @c rs2 lives in the FP register file (f0-f31).
    uint32_t pc    = 0;      ///< Byte address of this instruction (instruction_index * 4).
};

/**
 * @brief Return the execution latency of @p op in cycles.
 * @param[in] op  Opcode to query.
 * @return        Number of cycles from issue to result available on the CDB.
 */
int latency_of(Opcode op);

/**
 * @brief Return whether the functional unit for @p op is pipelined.
 *
 * A pipelined FU accepts a new operation every cycle even if a prior one has not
 * finished.  A non-pipelined FU must drain completely before accepting the next op.
 *
 * @param[in] op  Opcode to query.
 * @return        True if the FU is fully pipelined (throughput = 1 op/cycle).
 */
bool is_pipelined(Opcode op);

/**
 * @brief Return a human-readable name for @p op (used in trace and log output).
 * @param[in] op  Opcode to stringify.
 * @return        Null-terminated ASCII string, e.g. "ADD", "FMUL.S".
 */
const char* opcode_name(Opcode op);

/** @brief True if @p op is a conditional branch (BEQ, BNE, BLT, BGE). */
inline bool is_branch(Opcode op) {
    return op == Opcode::BEQ || op == Opcode::BNE ||
           op == Opcode::BLT || op == Opcode::BGE;
}

/** @brief True if @p op reads from memory (LW, FLW). */
inline bool is_load(Opcode op)  { return op == Opcode::LW || op == Opcode::FLW; }

/** @brief True if @p op writes to memory (SW, FSW). */
inline bool is_store(Opcode op) { return op == Opcode::SW || op == Opcode::FSW; }

/**
 * @brief True if @p op belongs to the FP instruction set
 *        (FADD.S, FSUB.S, FMUL.S, FDIV.S, FLW, FSW, FCVT.W.S, FCVT.S.W).
 */
inline bool is_fp_op(Opcode op) {
    return op == Opcode::FADD_S   || op == Opcode::FSUB_S   ||
           op == Opcode::FMUL_S   || op == Opcode::FDIV_S   ||
           op == Opcode::FLW      || op == Opcode::FSW      ||
           op == Opcode::FCVT_W_S || op == Opcode::FCVT_S_W;
}
