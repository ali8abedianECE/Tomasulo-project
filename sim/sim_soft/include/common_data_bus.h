#pragma once
#include <cstdint>
#include <fstream>
#include <ostream>
#include <string>
#include <vector>

/**
 * @brief One result broadcast on the CDB in a single cycle.
 */
struct CDBResult {
    int      rob_tag;  ///< ROB index of the instruction that produced this value.
    uint32_t value;    ///< Result bits — reinterpreted as int32_t or float at writeback.
};

/**
 * @brief Common Data Bus — result broadcast bus for Tomasulo's algorithm.
 *
 * When an execution unit finishes it calls broadcast(rob_tag, value).
 * At the end of the same cycle every listening unit (RS entries, ROB)
 * calls results() and captures any value whose tag matches a pending operand.
 * flush() is then called once to clear the bus for the next cycle.
 *
 * Multiple results can land on the CDB in one cycle because pipelined FUs
 * (e.g. FMUL, FADD) may all complete simultaneously.  Each RS entry scans
 * the full results list rather than checking a single slot.
 *
 * Values are stored as @c uint32_t bits.  The consumer uses the corresponding
 * ROBEntry::rd_fp flag to reinterpret as int32_t (integer) or float (FP) at writeback.
 */
class CommonDataBus {
public:
    CommonDataBus();

    /**
     * @brief Post a completed result to the bus.
     *
     * Called by a functional unit or the LSB when execution finishes.
     *
     * @param[in] rob_tag  ROB index of the completing instruction.
     * @param[in] value    Result bits to broadcast.
     */
    void broadcast(int rob_tag, uint32_t value);

    /**
     * @brief Return true if at least one result is pending this cycle.
     * @return True when results() is non-empty.
     */
    bool has_results() const;

    /**
     * @brief Return all pending results for this cycle.
     *
     * RS entries, the ROB, and the LSB snoop this list each cycle to capture
     * operands whose tags match.
     *
     * @return Const reference to the list of CDBResult entries posted this cycle.
     */
    const std::vector<CDBResult>& results() const;

    /**
     * @brief Clear all pending results.
     *
     * Must be called exactly once per cycle, after all units have snooped the bus.
     */
    void flush();

    /** @brief Print pending CDB results to @p os annotated with @p cycle. */
    void dump(std::ostream& os, int cycle) const;

    /** @brief Open (or create) the cycle-trace log file at @p path. */
    void open_log(const std::string& path);

    /** @brief Append a one-line state snapshot for @p cycle to the log file. */
    void log_cycle(int cycle);

private:
    std::vector<CDBResult> pending_;  ///< Results posted this cycle, not yet flushed.
    std::ofstream          log_;
};
