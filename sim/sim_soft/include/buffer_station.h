#pragma once
#include <cassert>
#include <cstdint>
#include <fstream>
#include <ostream>
#include <string>
#include <vector>

/**
 * @brief One stage slot in a BufferStation pipeline.
 */
struct BufSlot {
    bool     valid   = false;  ///< True when this stage holds a valid result.
    int      rob_tag = -1;     ///< ROB index of the instruction in this stage.
    uint32_t value   = 0;      ///< Result bits; valid only when @c valid is true.
};

/**
 * @brief Generic N-stage pipeline shift register that models a pipelined functional unit.
 *
 * Each tick() shifts all occupied slots one step toward the output end.
 * @c stages_[0] is the input staging area; @c stages_[depth_] is the output.
 *
 * Two throughput modes:
 *   - @c pipelined=true  — accepts one new op every cycle regardless of occupancy.
 *   - @c pipelined=false — rejects new ops while any stage is occupied (throughput = 1/N).
 *
 * Caller sequence each cycle:
 *   1. if has_output(): pop_output() and broadcast result on the CDB.
 *   2. accept() new work if any reservation station entry is ready.
 *   3. tick() to advance all stages by one step.
 */
class BufferStation {
public:
    /**
     * @brief Construct a buffer station with the given pipeline depth and pipelining mode.
     * @param[in] depth      Number of pipeline stages (latency in cycles).
     * @param[in] pipelined  True for full throughput; false for non-pipelined stall behaviour.
     */
    explicit BufferStation(int depth, bool pipelined);

    /**
     * @brief Insert an operation at the input stage.
     * @param[in] rob_tag  ROB index of the instruction starting execution.
     * @param[in] value    Computed result bits.
     * @return             True if the op was accepted; false if the unit cannot accept this cycle.
     */
    bool accept(int rob_tag, uint32_t value);

    /** @brief Advance all stages one step toward the output end. */
    void tick();

    /**
     * @brief Return true if the output stage holds a completed result.
     * @return True when a result is ready to be broadcast on the CDB.
     */
    bool has_output() const;

    /**
     * @brief Remove and return the output-stage slot.
     *
     * Only call when has_output() returns true.
     *
     * @return The completed BufSlot with valid=true, rob_tag, and value set.
     */
    BufSlot pop_output();

    /**
     * @brief Return true if any stage is currently occupied.
     *
     * Used by non-pipelined units to decide whether to accept new work.
     *
     * @return True if at least one stage holds a valid entry.
     */
    bool busy() const;

    /** @brief Print current stage state to @p os annotated with @p cycle. */
    void dump(std::ostream& os, int cycle) const;

    /** @brief Open (or create) the cycle-trace log file at @p path. */
    void open_log(const std::string& path);

    /** @brief Append a one-line state snapshot for @p cycle to the log file. */
    void log_cycle(int cycle);

private:
    int                  depth_;
    bool                 pipelined_;
    std::vector<BufSlot> stages_;   ///< [0] = input staging area … [depth_] = output.
    std::ofstream        log_;
};
