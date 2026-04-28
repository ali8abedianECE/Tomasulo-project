#include "reorder_buffer.h"
#include <cassert>
#include <iomanip>

/**
 * @brief Construct a ReorderBuffer with the given number of slots.
 *
 * @param[in] size Total number of ROB entries (must be >= 1).
 */
ReorderBuffer::ReorderBuffer(int size)
    : size_(size), head_(0), tail_(0), count_(0) {
    assert(size >= 1);
    entries_.resize(size_);
}


/**
 * @brief Allocate the next free ROB slot for an in-flight instruction.
 *
 * @param[in] instr Instruction being dispatched.
 *
 * @return Index of the newly allocated ROB entry, or -1 if the ROB is full.
 */
int ReorderBuffer::allocate(const Instruction& instr) {
    if (full()) return -1;
    int tag = tail_;
    ROBEntry& e = entries_[tag];
    e.state  = ROBState::IN_FLIGHT;
    e.op     = instr.op;
    e.rd     = instr.rd;
    e.rd_fp  = instr.rd_fp;
    e.result = 0;
    e.pc     = instr.pc;
    tail_    = (tail_ + 1) % size_;
    ++count_;
    return tag;
}


/**
 * @brief Record the computed result for a completed ROB entry and mark it DONE.
 *
 * @param[in] rob_tag Index of the ROB entry to update.
 * @param[in] result  Computed 32-bit result value.
 */
void ReorderBuffer::write_result(int rob_tag, uint32_t result) {
    assert(rob_tag >= 0 && rob_tag < size_);
    assert(entries_[rob_tag].state == ROBState::IN_FLIGHT);
    entries_[rob_tag].result = result;
    entries_[rob_tag].state  = ROBState::DONE;
}


/**
 * @brief Check whether the oldest ROB entry is ready to commit.
 *
 * @return @c true if the ROB is non-empty and the head entry is in the DONE state.
 */
bool ReorderBuffer::head_ready() const {
    return !empty() && entries_[head_].state == ROBState::DONE;
}


/**
 * @brief Retire the head ROB entry and advance the head pointer.
 *
 * Caller must verify head_ready() before calling.
 *
 * @return A copy of the committed ROBEntry containing the result and metadata.
 */
ROBEntry ReorderBuffer::commit() {
    assert(head_ready());
    ROBEntry entry   = entries_[head_];
    entries_[head_]  = ROBEntry{};   /* reset to IDLE */
    head_            = (head_ + 1) % size_;
    --count_;
    return entry;
}


/**
 * @brief Read-only access to any ROB entry by tag.
 *
 * @param[in] rob_tag Index of the ROB entry to inspect.
 *
 * @return Const reference to the requested ROBEntry.
 */
const ROBEntry& ReorderBuffer::peek(int rob_tag) const {
    assert(rob_tag >= 0 && rob_tag < size_);
    return entries_[rob_tag];
}


/** @brief Return @c true if every ROB slot is occupied. */
bool ReorderBuffer::full()  const { return count_ == size_; }


/** @brief Return @c true if no ROB slots are occupied. */
bool ReorderBuffer::empty() const { return count_ == 0; }


/**
 * @brief Return the ROB index of the oldest in-flight entry.
 *
 * @return Head index (0 … size-1). Must not be called on an empty ROB.
 */
int  ReorderBuffer::head_tag() const {}


/**
 * @brief Reset all ROB entries and pointers to their initial state.
 *
 * Called on a branch misprediction flush to discard all in-flight work.
 */
void ReorderBuffer::flush() {}


static const char* rob_state_str(ROBState s) {
    switch (s) {
        case ROBState::IDLE:      return "IDLE";
        case ROBState::IN_FLIGHT: return "INFLT";
        case ROBState::DONE:      return "DONE";
        default:                  return "?";
    }
}

/**
 * @brief Print a human-readable snapshot of all non-idle ROB entries.
 *
 * @param[in,out] os    Output stream to write to.
 * @param[in]     cycle Current simulation cycle number (for the header line).
 */
void ReorderBuffer::dump(std::ostream& os, int cycle) const {}



void ReorderBuffer::open_log(const std::string& path) {}


void ReorderBuffer::log_cycle(int cycle) {}
