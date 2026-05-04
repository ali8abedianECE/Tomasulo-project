#pragma once
#include "config.h"
#include <fstream>
#include <ostream>
#include <string>

/**
 * @brief One entry in the register renaming table.
 *
 * @c valid=false means the architectural register holds a committed value; read from RegisterFile.\n
 * @c valid=true  means the next value is being produced by the ROB entry at @c rob_tag.
 */
struct RATEntry {
    bool valid   = false;  ///< True when the register has an in-flight producer.
    int  rob_tag = -1;     ///< ROB index of the producing instruction; valid only when valid=true.
};

/**
 * @brief Register renaming table - maps architectural registers to in-flight ROB entries.
 *
 * Two separate tables mirror the two register files:
 *   - @c int_rat_[0..31]  for x0-x31
 *   - @c fp_rat_ [0..31]  for f0-f31
 *
 * Key operations:
 *   - map()    - called at dispatch: record that @c rd will be written by @c rob_tag.
 *   - lookup() - called at dispatch: find where rs1/rs2 values come from.
 *   - commit() - called at commit: clear the entry only if @c rob_tag still matches
 *                (a later dispatch may have re-mapped the same register).
 *   - flush()  - called on branch misprediction: invalidate all entries.
 */
class RegisterRemappingTable {
public:
    RegisterRemappingTable();

    /**
     * @brief Look up the current mapping for an architectural register.
     * @param[in] reg_idx  Register index (0-31).
     * @param[in] fp       True to query the FP table (f0-f31); false for integer (x0-x31).
     * @return             RATEntry with valid=false if the value is committed, or
     *                     valid=true and the producing rob_tag if still in-flight.
     */
    RATEntry lookup(int reg_idx, bool fp) const;

    /**
     * @brief Record that @p reg_idx is being written by the instruction at @p rob_tag.
     *
     * Writes to x0 are silently ignored.
     *
     * @param[in] reg_idx  Destination register index (0-31).
     * @param[in] fp       True for the FP file; false for the integer file.
     * @param[in] rob_tag  ROB slot of the producing instruction.
     */
    void map(int reg_idx, bool fp, int rob_tag);

    /**
     * @brief Clear the RAT entry for @p reg_idx only if it still belongs to @p rob_tag.
     *
     * The guard prevents clearing a newer mapping when the same register is written
     * by multiple in-flight instructions.
     *
     * @param[in] reg_idx  Register being committed.
     * @param[in] fp       True for the FP file; false for the integer file.
     * @param[in] rob_tag  ROB tag of the instruction that just committed.
     */
    void commit(int reg_idx, bool fp, int rob_tag);

    /**
     * @brief Invalidate all RAT entries.
     *
     * Called on branch misprediction recovery after the ROB and RS are flushed.
     * All subsequent register reads fall through to the committed register file.
     */
    void flush();

    /** @brief Print current RAT state to @p os annotated with @p cycle. */
    void dump(std::ostream& os, int cycle) const;

    /** @brief Open (or create) the cycle-trace log file at @p path. */
    void open_log(const std::string& path);

    /** @brief Append a one-line state snapshot for @p cycle to the log file. */
    void log_cycle(int cycle);

private:
    RATEntry      int_rat_[NUM_INT_REGS];
    RATEntry      fp_rat_[NUM_FP_REGS];
    std::ofstream log_;
};
