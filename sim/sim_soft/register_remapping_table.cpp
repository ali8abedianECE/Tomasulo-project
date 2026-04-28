#include "register_remapping_table.h"
#include <cassert>
#include <iomanip>

RegisterRemappingTable::RegisterRemappingTable() {
    flush();
}

RATEntry RegisterRemappingTable::lookup(int reg_idx, bool fp) const {
    assert(reg_idx >= 0 && reg_idx < (fp ? NUM_FP_REGS : NUM_INT_REGS));
    return fp ? fp_rat_[reg_idx] : int_rat_[reg_idx];
}

void RegisterRemappingTable::map(int reg_idx, bool fp, int rob_tag) {
    assert(reg_idx >= 0 && reg_idx < (fp ? NUM_FP_REGS : NUM_INT_REGS));
    if (!fp && reg_idx == 0) return;  /* x0 is hardwired, never remapped */
    RATEntry& e = fp ? fp_rat_[reg_idx] : int_rat_[reg_idx];
    e.valid   = true;
    e.rob_tag = rob_tag;
}

void RegisterRemappingTable::commit(int reg_idx, bool fp, int rob_tag) {
    assert(reg_idx >= 0 && reg_idx < (fp ? NUM_FP_REGS : NUM_INT_REGS));
    RATEntry& e = fp ? fp_rat_[reg_idx] : int_rat_[reg_idx];
    /* Guard: a newer instruction may have re-mapped this register already. */
    if (e.valid && e.rob_tag == rob_tag)
        e = {false, -1};
}

void RegisterRemappingTable::flush() {
    for (int i = 0; i < NUM_INT_REGS; ++i) int_rat_[i] = {false, -1};
    for (int i = 0; i < NUM_FP_REGS;  ++i) fp_rat_[i]  = {false, -1};
}

void RegisterRemappingTable::dump(std::ostream& os, int cycle) const {
    os << "[RAT  cycle=" << std::setw(4) << cycle << "]\n";
    os << "  INT:";
    for (int i = 0; i < NUM_INT_REGS; ++i)
        if (int_rat_[i].valid)
            os << " x" << i << "->ROB" << int_rat_[i].rob_tag;
    os << "\n  FP: ";
    for (int i = 0; i < NUM_FP_REGS; ++i)
        if (fp_rat_[i].valid)
            os << " f" << i << "->ROB" << fp_rat_[i].rob_tag;
    os << "\n";
}

void RegisterRemappingTable::open_log(const std::string& path) {
    log_.open(path, std::ios::out | std::ios::trunc);
}

void RegisterRemappingTable::log_cycle(int cycle) {
    if (log_.is_open())
        dump(log_, cycle);
}
