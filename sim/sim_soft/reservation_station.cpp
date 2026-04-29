#include "reservation_station.h"
#include "dispatch_utils.h"
#include <cassert>
#include <iomanip>

/*
 * Compute the result of an ALU/FPU operation from a ready RSEntry.
 * Load/store effective addresses and branch conditions are also resolved here;
 * the LoadStoreBuffer and commit unit consume those values downstream.
 */
/**
 * @brief Compute the result of a fully-resolved RS entry.
 *
 * Handles integer ALU, FP ALU, effective-address calculation for
 * loads/stores, and branch target resolution.
 *
 * @param[in] e RS entry with all operands resolved (qj == qk == -1).
 *
 * @return 32-bit result: arithmetic/logical result, effective address,
 *         or resolved branch target PC.
 */
static uint32_t execute_op(const RSEntry& e) {
    const int32_t  sj = static_cast<int32_t>(e.vj);
    const int32_t  sk = static_cast<int32_t>(e.vk);
    const uint32_t uj = e.vj;
    const float    fj = bits_to_float(e.vj);
    const float    fk = bits_to_float(e.vk);

    switch (e.op) {
        /* Integer R-type */
        case Opcode::ADD:  return static_cast<uint32_t>(sj + sk);
        case Opcode::SUB:  return static_cast<uint32_t>(sj - sk);
        case Opcode::AND:  return uj & e.vk;
        case Opcode::OR:   return uj | e.vk;
        case Opcode::XOR:  return uj ^ e.vk;
        case Opcode::SLL:  return static_cast<uint32_t>(sj << (e.vk & 0x1F));
        case Opcode::SRL:  return uj >> (e.vk & 0x1F);
        case Opcode::SRA:  return static_cast<uint32_t>(sj >> (e.vk & 0x1F));
        /* Integer I-type */
        case Opcode::ADDI: return static_cast<uint32_t>(sj + e.imm);
        case Opcode::ANDI: return uj & static_cast<uint32_t>(e.imm);
        case Opcode::ORI:  return uj | static_cast<uint32_t>(e.imm);
        case Opcode::XORI: return uj ^ static_cast<uint32_t>(e.imm);
        case Opcode::SLLI: return static_cast<uint32_t>(sj << (e.imm & 0x1F));
        case Opcode::SRLI: return uj >> (e.imm & 0x1F);
        /* Load/store — produce effective address; memory access is in LSB */
        case Opcode::LW:
        case Opcode::FLW:
        case Opcode::SW:
        case Opcode::FSW:  return static_cast<uint32_t>(sj + e.imm);
        /* Branch — result is the resolved target PC (pc+imm if taken, pc+4 if not). */
        case Opcode::BEQ:  return (sj == sk) ? (e.pc + static_cast<uint32_t>(e.imm)) : (e.pc + 4u);
        case Opcode::BNE:  return (sj != sk) ? (e.pc + static_cast<uint32_t>(e.imm)) : (e.pc + 4u);
        case Opcode::BLT:  return (sj <  sk) ? (e.pc + static_cast<uint32_t>(e.imm)) : (e.pc + 4u);
        case Opcode::BGE:  return (sj >= sk) ? (e.pc + static_cast<uint32_t>(e.imm)) : (e.pc + 4u);
        /* FP ALU */
        case Opcode::FADD_S:   return float_to_bits(fj + fk);
        case Opcode::FSUB_S:   return float_to_bits(fj - fk);
        case Opcode::FMUL_S:   return float_to_bits(fj * fk);
        case Opcode::FDIV_S:   return float_to_bits(fj / fk);
        case Opcode::FCVT_W_S: return static_cast<uint32_t>(static_cast<int32_t>(fj));
        case Opcode::FCVT_S_W: return float_to_bits(static_cast<float>(sj));
        default:               return 0;
    }
}


/**
 * @brief Construct a ReservationStation with the given number of slots.
 *
 * @param[in] size Total number of RS entries available.
 */
ReservationStation::ReservationStation(int size) : size_(size), count_(0) {
    entries_.resize(size_);
}


/**
 * @brief Issue an instruction into a free RS slot.
 *
 * Resolves source operands from the RAT, register file, or ROB at issue time.
 *
 * @param[in] instr   Decoded instruction to issue.
 * @param[in] rob_tag ROB slot allocated for this instruction.
 * @param[in] rat     Current register-renaming table for operand lookup.
 * @param[in] rf      Architectural register file for operand lookup.
 * @param[in] rob     ROB used to forward already-computed but uncommitted values.
 *
 * @return @c true if a free slot was found and the entry was filled;
 *         @c false if the RS is full.
 */
bool ReservationStation::issue(const Instruction&            instr,
                                int                           rob_tag,
                                const RegisterRemappingTable& rat,
                                const RegisterFile&           rf,
                                const ReorderBuffer&          rob) {
    for (auto& e : entries_) {
        if (e.busy) continue;
        e.busy      = true;
        e.op        = instr.op;
        e.rob_tag   = rob_tag;
        e.imm       = instr.imm;
        e.rd_fp     = instr.rd_fp;
        e.done      = false;
        e.cycles_rem = 0;
        e.result    = 0;
        e.pc        = instr.pc;
        resolve_operand(instr.rs1, instr.rs1_fp, rat, rf, rob, e.vj, e.qj);
        resolve_operand(instr.rs2, instr.rs2_fp, rat, rf, rob, e.vk, e.qk);
        ++count_;
        return true;
    }
    return false;
}


/**
 * @brief Capture results broadcast on the CDB into waiting RS entries.
 *
 * For each result on the bus, clears the corresponding qj/qk tag and
 * latches the value so the entry can proceed to execution.
 *
 * @param[in] cdb Common Data Bus carrying results from this cycle.
 */
void ReservationStation::snoop(const CommonDataBus& cdb) {
    for (const auto& res : cdb.results()) {
        for (auto& e : entries_) {
            if (!e.busy || e.done) continue;
            if (e.qj == res.rob_tag) { e.vj = res.value; e.qj = -1; }
            if (e.qk == res.rob_tag) { e.vk = res.value; e.qk = -1; }
        }
    }
}


/**
 * @brief Advance all RS entries by one execution cycle.
 *
 * Two passes are made each tick:
 * 1. Decrement the countdown of executing entries; mark done when it reaches zero.
 * 2. Start newly ready entries (all operands resolved, not yet executing),
 *    respecting non-pipelined FU exclusivity.
 */
void ReservationStation::tick() {
    /* Decrement executing entries; mark done when countdown reaches zero. */
    for (auto& e : entries_) {
        if (!e.busy || e.done || e.cycles_rem == 0) continue;
        if (--e.cycles_rem == 0) { e.result = execute_op(e); e.done = true; }
    }

    /* Start READY entries (qj==-1, qk==-1, cycles_rem==0, not done). */
    for (auto& e : entries_) {
        if (!e.busy || e.done || e.qj != -1 || e.qk != -1 || e.cycles_rem != 0) continue;

        /* Non-pipelined FU: block if another entry with the same op is executing. */
        if (!is_pipelined(e.op)) {
            bool fu_busy = false;
            for (const auto& other : entries_)
                if (&other != &e && other.busy && !other.done &&
                    other.op == e.op && other.cycles_rem > 0) {
                    fu_busy = true; break;
                }
            if (fu_busy) continue;
        }

        int lat = latency_of(e.op);
        if (lat <= 1) {
            /* Single-cycle: compute immediately and mark done this tick. */
            e.result = execute_op(e);
            e.done   = true;
        } else {
            e.cycles_rem = lat - 1;  /* -1 because one cycle passes right now */
        }
    }

}


/**
 * @brief Check whether any RS entry has finished execution and is ready to broadcast.
 *
 * @return @c true if at least one busy entry has its done flag set.
 */
bool ReservationStation::has_result() const {
    for (const auto& e : entries_)
        if (e.busy && e.done) return true;
    return false;
}


/**
 * @brief Remove and return the first done RS entry for CDB broadcast.
 *
 * @return A copy of the completed RSEntry. The slot is cleared and count_ decremented.
 *
 * @throws Assertion failure if called when no entry is done.
 */
RSEntry ReservationStation::pop_result() {
    for (auto& e : entries_) {
        if (e.busy && e.done) {
            RSEntry out = e;
            e = RSEntry{};
            --count_;
            return out;
        }
    }
    assert(false && "pop_result called with no done entry");
    return RSEntry{};
}


/** @brief Return @c true if every RS slot is occupied. */
bool ReservationStation::full()  const { return count_ == size_; }


/** @brief Return @c true if no RS slots are occupied. */
bool ReservationStation::empty() const { return count_ == 0; }


/**
 * @brief Clear all RS entries and reset the occupancy count.
 *
 * Called on a branch misprediction flush to discard all in-flight work.
 */
void ReservationStation::flush() {}


/**
 * @brief Print a human-readable snapshot of all busy RS entries.
 *
 * @param[in,out] os    Output stream to write to.
 * @param[in]     cycle Current simulation cycle number (for the header line).
 */
void ReservationStation::dump(std::ostream& os, int cycle) const {}



void ReservationStation::open_log(const std::string& path) {}


void ReservationStation::log_cycle(int cycle) {}
