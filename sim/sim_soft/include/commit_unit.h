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

/**
 * @brief Snapshot of the last instruction retired this cycle, used for trace output.
 */
struct CommitRecord {
    bool     valid   = false;          ///< True when an instruction committed this cycle.
    Opcode   op      = Opcode::NOP;    ///< Opcode of the committed instruction.
    int      rd      = -1;             ///< Destination register index; -1 = no writeback.
    bool     rd_fp   = false;          ///< True if @c rd lives in the FP register file.
    uint32_t result  = 0;              ///< Value written to @c rd (or store data for SW/FSW).
    uint32_t pc      = 0;              ///< Byte address of the committed instruction.
};

/**
 * @brief Commit unit — retires the ROB head in program order each cycle.
 *
 * On each tick():
 *   - If the ROB head is not DONE, returns false (stall, nothing commits).
 *   - Store (SW/FSW): pops the LSB head and writes the value to memory.
 *   - Branch (BEQ/BNE/BLT/BGE): sets @p next_pc to the resolved branch target.
 *   - ALU / Load: writes the result to the RegisterFile and clears the RAT entry.
 *   - HALT: sets @p halted to true.
 *
 * @p next_pc is only meaningful when tick() returns true and is_branch(last().op) is true.
 * Callers should check last().op after each tick() to determine what committed.
 */
class CommitUnit {
public:
    /**
     * @brief Attempt to retire the ROB head.
     *
     * @param[in,out] rob      Reorder buffer; head is popped when ready.
     * @param[in,out] rf       Register file; written when an ALU/load commits.
     * @param[in,out] rat      Renaming table; entry cleared when a register commits.
     * @param[in,out] lsb      Load/store buffer; head store popped and written to memory.
     * @param[in,out] mem      Data memory array (word-addressed).
     * @param[out]    next_pc  Branch target PC; valid only when the committed op is a branch.
     * @param[out]    halted   Set to true when a HALT instruction commits.
     * @return                 True if an instruction was committed this cycle; false if stalled.
     */
    bool tick(ReorderBuffer&          rob,
              RegisterFile&           rf,
              RegisterRemappingTable& rat,
              LoadStoreBuffer&        lsb,
              std::vector<uint32_t>&  mem,
              uint32_t&               next_pc,
              bool&                   halted);

    /**
     * @brief Return the record for the last committed instruction.
     * @return CommitRecord with valid=false if nothing committed this cycle.
     */
    const CommitRecord& last() const { return last_; }

    /** @brief Print last commit record to @p os annotated with @p cycle. */
    void dump(std::ostream& os, int cycle) const;

    /** @brief Open (or create) the cycle-trace log file at @p path. */
    void open_log(const std::string& path);

    /** @brief Append a one-line state snapshot for @p cycle to the log file. */
    void log_cycle(int cycle);

private:
    CommitRecord  last_;
    std::ofstream log_;
};
