#pragma once
#include "config.h"
#include <cstdint>
#include <fstream>
#include <ostream>
#include <string>

/*
 * RegisterFile — architectural register state, written only at commit.
 *
 * Two separate banks:
 *   int_regs_[0..31]  x0-x31  int32_t   x0 hardwired to 0 (writes ignored)
 *   fp_regs_ [0..31]  f0-f31  float     single-precision (RV32F)
 *
 * During execution operand values come from the ROB/CDB, not here.
 * The register file is the ground truth only after an instruction commits.
 */
class RegisterFile {
public:
    RegisterFile();

    /* Integer register access (x0-x31). Write to x0 is silently ignored. */
    int32_t read_int(int idx) const;
    void    write_int(int idx, int32_t val);

    /* FP register access (f0-f31). */
    float   read_fp(int idx) const;
    void    write_fp(int idx, float val);

    void dump(std::ostream& os, int cycle) const;
    void open_log(const std::string& path);
    void log_cycle(int cycle);

private:
    int32_t       int_regs_[NUM_INT_REGS];  /* x0-x31, x0 kept at 0 */
    float         fp_regs_[NUM_FP_REGS];   /* f0-f31                 */
    std::ofstream log_;
};
