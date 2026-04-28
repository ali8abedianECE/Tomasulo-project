#include "regfile.h"
#include <cassert>
#include <iomanip>

RegisterFile::RegisterFile() {
    for (int i = 0; i < NUM_INT_REGS; ++i) int_regs_[i] = 0;
    for (int i = 0; i < NUM_FP_REGS;  ++i) fp_regs_[i]  = 0.0f;
}

int32_t RegisterFile::read_int(int idx) const {
    assert(idx >= 0 && idx < NUM_INT_REGS);
    return int_regs_[idx];
}

void RegisterFile::write_int(int idx, int32_t val) {
    assert(idx >= 0 && idx < NUM_INT_REGS);
    if (idx == 0) return;  /* x0 hardwired to 0 */
    int_regs_[idx] = val;
}

float RegisterFile::read_fp(int idx) const {
    assert(idx >= 0 && idx < NUM_FP_REGS);
    return fp_regs_[idx];
}

void RegisterFile::write_fp(int idx, float val) {
    assert(idx >= 0 && idx < NUM_FP_REGS);
    fp_regs_[idx] = val;
}

void RegisterFile::dump(std::ostream& os, int cycle) const {
    os << "[RF   cycle=" << std::setw(4) << cycle << "]\n";
    os << "  INT:";
    for (int i = 0; i < NUM_INT_REGS; ++i)
        os << " x" << i << "=" << int_regs_[i];
    os << "\n  FP: ";
    for (int i = 0; i < NUM_FP_REGS; ++i)
        os << " f" << i << "=" << fp_regs_[i];
    os << "\n";
}

void RegisterFile::open_log(const std::string& path) {
    log_.open(path, std::ios::out | std::ios::trunc);
}

void RegisterFile::log_cycle(int cycle) {
    if (log_.is_open())
        dump(log_, cycle);
}
