#pragma once
#include "config.h"
#include <cstdint>

/*
 * RV32IF subset — decoded instruction types.
 *
 * Instruction formats (RISC-V standard):
 *   R-type  [31:25 funct7][24:20 rs2][19:15 rs1][14:12 funct3][11:7 rd ][6:0 opcode]
 *   I-type  [31:20 imm12 ][19:15 rs1][14:12 funct3][11:7 rd ][6:0 opcode]
 *   S-type  [31:25 imm[11:5]][24:20 rs2][19:15 rs1][14:12 funct3][11:7 imm[4:0]][6:0 opcode]
 *   B-type  [31 imm12][30:25 imm[10:5]][24:20 rs2][19:15 rs1][14:12 funct3][11:8 imm[4:1]][7 imm11][6:0 opcode]
 *
 * Raw bit fields are not kept after decode; only the fields in Instruction flow downstream.
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

/*
 * Decoded instruction that flows through the pipeline.
 * Register indices are 0-31 for both x-regs and f-regs.
 * The *_fp flags tell each stage which register file to access.
 */
struct Instruction {
    Opcode  op     = Opcode::NOP;
    int     rd     = -1;     /* dest reg index [4:0],  -1 = no writeback */
    int     rs1    = -1;     /* src1 reg index [4:0],  -1 = unused       */
    int     rs2    = -1;     /* src2 reg index [4:0],  -1 = unused       */
    int32_t imm    = 0;      /* sign-extended 32-bit immediate            */
    bool    rd_fp  = false;  /* rd  lives in f0-f31 */
    bool    rs1_fp = false;  /* rs1 lives in f0-f31 */
    bool    rs2_fp = false;  /* rs2 lives in f0-f31 */
    uint32_t pc    = 0;      /* byte address = instruction_index * 4     */
};

/* Execution latency in cycles. */
int latency_of(Opcode op);
/* True if the FU for this opcode is pipelined (throughput=1 even if latency>1). */
bool is_pipelined(Opcode op);
/* Human-readable opcode string for trace output. */
const char* opcode_name(Opcode op);

inline bool is_branch(Opcode op) {
    return op == Opcode::BEQ || op == Opcode::BNE ||
           op == Opcode::BLT || op == Opcode::BGE;
}
inline bool is_load(Opcode op)  { return op == Opcode::LW || op == Opcode::FLW; }
inline bool is_store(Opcode op) { return op == Opcode::SW || op == Opcode::FSW; }
inline bool is_fp_op(Opcode op) {
    return op == Opcode::FADD_S   || op == Opcode::FSUB_S   ||
           op == Opcode::FMUL_S   || op == Opcode::FDIV_S   ||
           op == Opcode::FLW      || op == Opcode::FSW      ||
           op == Opcode::FCVT_W_S || op == Opcode::FCVT_S_W;
}

