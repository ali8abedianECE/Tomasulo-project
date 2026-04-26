#include "instruction.h"

/* Latency constants come from config.h via instruction.h */

int latency_of(Opcode op) {
    switch (op) {
        case Opcode::ADD:      return LAT_INT_ALU;
        case Opcode::SUB:      return LAT_INT_ALU;
        case Opcode::AND:      return LAT_INT_ALU;
        case Opcode::OR:       return LAT_INT_ALU;
        case Opcode::XOR:      return LAT_INT_ALU;
        case Opcode::SLL:      return LAT_INT_ALU;
        case Opcode::SRL:      return LAT_INT_ALU;
        case Opcode::SRA:      return LAT_INT_ALU;
        case Opcode::ADDI:     return LAT_INT_ALU;
        case Opcode::ANDI:     return LAT_INT_ALU;
        case Opcode::ORI:      return LAT_INT_ALU;
        case Opcode::XORI:     return LAT_INT_ALU;
        case Opcode::SLLI:     return LAT_INT_ALU;
        case Opcode::SRLI:     return LAT_INT_ALU;
        case Opcode::LW:       return LAT_INT_LS;
        case Opcode::SW:       return LAT_INT_LS;
        case Opcode::BEQ:      return LAT_BRANCH;
        case Opcode::BNE:      return LAT_BRANCH;
        case Opcode::BLT:      return LAT_BRANCH;
        case Opcode::BGE:      return LAT_BRANCH;
        case Opcode::FADD_S:   return LAT_FP_ADDSUB;
        case Opcode::FSUB_S:   return LAT_FP_ADDSUB;
        case Opcode::FMUL_S:   return LAT_FP_MUL;
        case Opcode::FDIV_S:   return LAT_FP_DIV;
        case Opcode::FLW:      return LAT_FP_LS;
        case Opcode::FSW:      return LAT_FP_LS;
        case Opcode::FCVT_W_S: return LAT_FP_CVT;
        case Opcode::FCVT_S_W: return LAT_FP_CVT;
        default:               return LAT_MISC;
    }
}

const char* opcode_name(Opcode op) {
    switch (op) {
        case Opcode::ADD:      return "ADD";
        case Opcode::SUB:      return "SUB";
        case Opcode::AND:      return "AND";
        case Opcode::OR:       return "OR";
        case Opcode::XOR:      return "XOR";
        case Opcode::SLL:      return "SLL";
        case Opcode::SRL:      return "SRL";
        case Opcode::SRA:      return "SRA";
        case Opcode::ADDI:     return "ADDI";
        case Opcode::ANDI:     return "ANDI";
        case Opcode::ORI:      return "ORI";
        case Opcode::XORI:     return "XORI";
        case Opcode::SLLI:     return "SLLI";
        case Opcode::SRLI:     return "SRLI";
        case Opcode::LW:       return "LW";
        case Opcode::SW:       return "SW";
        case Opcode::BEQ:      return "BEQ";
        case Opcode::BNE:      return "BNE";
        case Opcode::BLT:      return "BLT";
        case Opcode::BGE:      return "BGE";
        case Opcode::FADD_S:   return "FADD.S";
        case Opcode::FSUB_S:   return "FSUB.S";
        case Opcode::FMUL_S:   return "FMUL.S";
        case Opcode::FDIV_S:   return "FDIV.S";
        case Opcode::FLW:      return "FLW";
        case Opcode::FSW:      return "FSW";
        case Opcode::FCVT_W_S: return "FCVT.W.S";
        case Opcode::FCVT_S_W: return "FCVT.S.W";
        case Opcode::NOP:      return "NOP";
        case Opcode::HALT:     return "HALT";
        default:               return "???";
    }
}
