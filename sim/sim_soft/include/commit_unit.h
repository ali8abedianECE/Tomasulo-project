#pragma once
#include "load_store_buffer.h"
#include "regfile.h"
#include "register_remapping_table.h"
#include "reorder_buffer.h"
#include "utils.h"
#include <cstdint>
#include <fstream>
#include <ostream>
#include <string>
#include <vector>

/*
 * CommitRecord — snapshot of the last retired instruction for trace output.
 */
struct CommitRecord {
    bool     valid   = false;
    Opcode   op      = Opcode::NOP;
    int      rd      = -1;
    bool     rd_fp   = false;
    uint32_t result  = 0;
    uint32_t pc      = 0;
};

/*
 * CommitUnit — retires the ROB head in program order each cycle.
 *
 * On each tick():
 *   - If ROB head is not DONE → returns false (stall).
 *   - Store: pops LSB head and writes to memory.
 *   - Branch: sets next_pc to the resolved target PC.
 *   - ALU/Load: writes result to RegisterFile, clears RAT entry.
 *   - HALT: sets halted = true.
 *
 * next_pc is only meaningful when tick() returns true and is_branch(last().op).
 * Callers should check last().op after each tick() to determine what committed.
 */
class CommitUnit {
public:
    bool tick(ReorderBuffer&          rob,
              RegisterFile&           rf,
              RegisterRemappingTable& rat,
              LoadStoreBuffer&        lsb,
              std::vector<uint32_t>&  mem,
              uint32_t&               next_pc,
              bool&                   halted);

    /* Last committed instruction; valid=false if nothing committed this cycle. */
    const CommitRecord& last() const { return last_; }

    void dump(std::ostream& os, int cycle) const;
    void open_log(const std::string& path);
    void log_cycle(int cycle);

private:
    CommitRecord  last_;
    std::ofstream log_;
};
