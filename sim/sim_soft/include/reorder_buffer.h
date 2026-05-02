#pragma once
#include "instruction.h"
#include <cstdint>
#include <fstream>
#include <ostream>
#include <string>
#include <vector>

/**
 * @brief Lifecycle states for a reorder buffer entry.
 */
enum class ROBState : uint8_t {
    IDLE,       ///< Slot is free and available for allocation.
    IN_FLIGHT,  ///< Instruction dispatched; result not yet available.
    DONE        ///< Result written by the CDB; waiting for in-order commit.
};

/**
 * @brief One entry in the reorder buffer.
 *
 * The result is stored as @c uint32_t bits.  The CommitUnit reads @c rd_fp to
 * decide whether to call write_int() or write_fp() on the register file.
 */
struct ROBEntry {
    ROBState state  = ROBState::IDLE;
    Opcode   op     = Opcode::NOP;
    int      rd     = -1;     ///< Destination register index; -1 = no writeback.
    bool     rd_fp  = false;  ///< True if @c rd lives in the FP register file.
    uint32_t result = 0;      ///< Result bits; valid only when state == DONE.
    uint32_t pc     = 0;      ///< Instruction byte address, for trace output.
};

/**
 * @brief Reorder buffer — tracks all in-flight instructions in program order.
 *
 * Implemented as a circular buffer of ROB_SIZE entries (from config.h).
 * The ROB tag returned by allocate() is the stable array index and is used
 * everywhere else (RAT, RS, CDB, LSB) to identify an in-flight instruction.
 *
 * Circular layout:
 *   @c head_ points to the oldest entry (next to commit).\n
 *   @c tail_ points to the next free slot.
 */
class ReorderBuffer {
public:
    /**
     * @brief Construct a reorder buffer with @p size entries.
     * @param[in] size  Number of ROB slots.
     */
    explicit ReorderBuffer(int size = ROB_SIZE);

    /**
     * @brief Allocate a slot for a newly dispatched instruction.
     * @param[in] instr  Decoded instruction being dispatched.
     * @return           ROB tag (array index) for this instruction, or -1 if full.
     */
    int allocate(const Instruction& instr);

    /**
     * @brief Record the result of a completed instruction.
     *
     * Called by the CDB when an execution unit finishes.
     * Stores the result bits and transitions the entry to DONE.
     *
     * @param[in] rob_tag  ROB index of the completing instruction.
     * @param[in] result   Result bits to store.
     */
    void write_result(int rob_tag, uint32_t result);

    /**
     * @brief Return true if the oldest entry is DONE and safe to commit.
     * @return True when the head entry can be retired this cycle.
     */
    bool head_ready() const;

    /**
     * @brief Remove and return the head entry.
     *
     * Only call when head_ready() returns true.
     *
     * @return The committed ROBEntry (state will be DONE).
     */
    ROBEntry commit();

    /**
     * @brief Read an entry by tag without removing it.
     *
     * Used at dispatch for operand forwarding — callers check the entry state
     * before using the result.
     *
     * @param[in] rob_tag  ROB index to inspect.
     * @return             Const reference to the entry at @p rob_tag.
     */
    const ROBEntry& peek(int rob_tag) const;

    /** @brief Return true if all ROB slots are occupied. */
    bool full()  const;

    /** @brief Return true if no ROB slots are occupied. */
    bool empty() const;

    /**
     * @brief Return the array index of the oldest in-flight entry.
     *
     * Used by CommitUnit to pass the correct tag to RAT::commit().
     *
     * @return Head slot index.
     */
    int head_tag() const;

    /**
     * @brief Flush all entries.
     *
     * Called on branch misprediction recovery.  Resets head, tail, and count.
     */
    void flush();

    /** @brief Print current ROB state to @p os annotated with @p cycle. */
    void dump(std::ostream& os, int cycle) const;

    /** @brief Open (or create) the cycle-trace log file at @p path. */
    void open_log(const std::string& path);

    /** @brief Append a one-line state snapshot for @p cycle to the log file. */
    void log_cycle(int cycle);

private:
    int                   size_;
    int                   head_;     ///< Index of the oldest entry.
    int                   tail_;     ///< Index of the next free slot.
    int                   count_;    ///< Number of valid entries.
    std::vector<ROBEntry> entries_;
    std::ofstream         log_;
};
