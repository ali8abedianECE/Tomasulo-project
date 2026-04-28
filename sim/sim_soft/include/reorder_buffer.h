#pragma once
#include "instruction.h"
#include <cstdint>
#include <fstream>
#include <ostream>
#include <string>
#include <vector>

/*
 * ReorderBuffer (ROB) — tracks all in-flight instructions in program order.
 *
 * Implemented as a circular buffer of ROB_SIZE entries (from config.h).
 * The ROB tag returned by allocate() is the stable array index and is used
 * everywhere else (RAT, RS, CDB) to identify an in-flight instruction.
 *
 * Circular layout:
 *   head_ → oldest entry (next to commit)
 *   tail_ → next free slot
 *
 * State machine per entry:
 *   IDLE      → slot is free
 *   IN_FLIGHT → dispatched; result not yet available
 *   DONE      → result written by CDB; waiting for in-order commit
 *
 * Result is stored as uint32_t bits.  The commit unit reads rd_fp to decide
 * whether to reinterpret as int32_t (write_int) or float (write_fp).
 */
enum class ROBState : uint8_t {
    IDLE,
    IN_FLIGHT,
    DONE
};

struct ROBEntry {
    ROBState state  = ROBState::IDLE;
    Opcode   op     = Opcode::NOP;
    int      rd     = -1;     /* dest register index, -1 = no writeback */
    bool     rd_fp  = false;  /* dest lives in f0-f31                   */
    uint32_t result = 0;      /* result bits; valid only when DONE       */
    uint32_t pc     = 0;      /* instruction PC for trace output         */
};

class ReorderBuffer {
public:
    explicit ReorderBuffer(int size = ROB_SIZE);

    /* Allocate a slot for a newly dispatched instruction.
     * Returns the ROB tag (index) or -1 if full. */
    int allocate(const Instruction& instr);

    /* Called by the CDB when an execution unit finishes.
     * Stores result bits and marks the entry DONE. */
    void write_result(int rob_tag, uint32_t result);

    /* True if the head entry is DONE and safe to commit. */
    bool head_ready() const;

    /* Remove and return the head entry.  Only call when head_ready(). */
    ROBEntry commit();

    /* Read an entry by tag (used for operand forwarding — check state first). */
    const ROBEntry& peek(int rob_tag) const;

    bool full()  const;
    bool empty() const;

    /* Index of the oldest entry (used by CommitUnit to pass to RAT::commit). */
    int head_tag() const;

    /* Flush all entries on branch misprediction recovery. */
    void flush();

    void dump(std::ostream& os, int cycle) const;
    void open_log(const std::string& path);
    void log_cycle(int cycle);

private:
    int                   size_;
    int                   head_;    /* index of oldest entry     */
    int                   tail_;    /* index of next free slot   */
    int                   count_;   /* number of valid entries   */
    std::vector<ROBEntry> entries_;
    std::ofstream         log_;
};
