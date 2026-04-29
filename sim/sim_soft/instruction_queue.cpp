#include "instruction_queue.h"
#include <cassert>
#include <iomanip>

/**
 * @brief Construct an InstructionQueue with the given fetch buffer capacity.
 *
 * @param[in] capacity Maximum number of instructions held in the fetch buffer.
 */
InstructionQueue::InstructionQueue(int capacity) : capacity_(capacity), pc_(0) {
    assert(capacity >= 1);
}


/**
 * @brief Load a new program and reset the fetch state.
 *
 * Stamps each instruction with its byte-addressed PC (index × 4) and
 * clears the fetch buffer so execution begins at PC 0.
 *
 * @param[in] prog Flat list of decoded instructions in program order.
 */
void InstructionQueue::load_program(const std::vector<Instruction>& prog) {
    program_ = prog;
    /* stamp each instruction with its byte address */
    for (int i = 0; i < static_cast<int>(program_.size()); ++i)
        program_[i].pc = static_cast<uint32_t>(i) * 4;
    pc_ = 0;
    buffer_.clear();
}


/**
 * @brief Advance the fetch stage by one cycle.
 *
 * Fetches one instruction from the program into the buffer if the program
 * has not been fully fetched and the buffer is not at capacity.
 */
void InstructionQueue::tick() {
    if (pc_ < static_cast<int>(program_.size()) && static_cast<int>(buffer_.size()) < capacity_) {
        buffer_.push_back(program_[pc_++]);
    }
}


/**
 * @brief Check whether an instruction is available for dispatch.
 *
 * @return @c true if the fetch buffer is non-empty.
 */
bool InstructionQueue::can_dispatch() const {
    return !buffer_.empty();
}


/**
 * @brief Return a const reference to the next instruction without consuming it.
 *
 * @return Const reference to the front of the fetch buffer.
 */
const Instruction& InstructionQueue::peek() const {
    assert(can_dispatch());
    return buffer_.front();
}


/**
 * @brief Remove and return the next instruction from the fetch buffer.
 *
 * @return The front instruction; the buffer shrinks by one entry.
 */
Instruction InstructionQueue::dispatch() {
    assert(can_dispatch());
    Instruction front = buffer_.front();
    buffer_.pop_front();
    return front;
}


/**
 * @brief Check whether the entire program has been fetched and dispatched.
 *
 * @return @c true when all instructions have been consumed from the buffer
 *         and no more remain to be fetched from the program.
 */
bool InstructionQueue::done() const {}


/**
 * @brief Redirect fetch to a new PC, discarding any buffered instructions.
 *
 * Used after a branch commit to resume fetching at the correct target.
 *
 * @param[in] byte_pc Byte-addressed target PC to fetch from next.
 */
void InstructionQueue::seek(uint32_t byte_pc) {}


/**
 * @brief Print a human-readable snapshot of the fetch buffer.
 *
 * @param[in,out] os    Output stream to write to.
 * @param[in]     cycle Current simulation cycle number (for the header line).
 */
void InstructionQueue::dump(std::ostream& os, int cycle) const {}



void InstructionQueue::open_log(const std::string& path) {}


void InstructionQueue::log_cycle(int cycle) {}
