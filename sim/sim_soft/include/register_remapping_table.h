#pragma once
#include "config.h"
#include <fstream>
#include <ostream>
#include <string>

/*
 * RegisterRemappingTable (RAT) — maps architectural registers to in-flight ROB entries.
 *
 * Two separate tables mirror the two register files:
 *   int_rat_[0..31]  for x0-x31
 *   fp_rat_ [0..31]  for f0-f31
 *
 * Each entry is a RATEntry:
 *   valid=false  → value is committed, read from RegisterFile
 *   valid=true   → value is in-flight; rob_tag is the ROB index to wait on
 *
 * Key operations:
 *   map()    — called at dispatch: record that rd will be written by rob_tag
 *   lookup() — called at dispatch: find where rs1/rs2 values come from
 *   commit() — called at commit: clear entry only if rob_tag still matches
 *              (a later instruction may have re-mapped the same register)
 *   flush()  — called on branch misprediction: invalidate all entries
 */
struct RATEntry {
    bool valid   = false;  /* true = value pending in ROB    */
    int  rob_tag = -1;     /* ROB index, valid only when valid=true */
};

class RegisterRemappingTable {
public:
    RegisterRemappingTable();

    /* Returns current mapping; valid=false means value is in the register file. */
    RATEntry lookup(int reg_idx, bool fp) const;

    /* Record that reg_idx is being written by rob_tag. x0 is silently ignored. */
    void map(int reg_idx, bool fp, int rob_tag);

    /* At commit: clear the entry only if it still belongs to rob_tag. */
    void commit(int reg_idx, bool fp, int rob_tag);

    /* Invalidate all entries — used on branch misprediction recovery. */
    void flush();

    void dump(std::ostream& os, int cycle) const;
    void open_log(const std::string& path);
    void log_cycle(int cycle);

private:
    RATEntry      int_rat_[NUM_INT_REGS];
    RATEntry      fp_rat_[NUM_FP_REGS];
    std::ofstream log_;
};
