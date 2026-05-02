#pragma once
#include "instruction.h"
#include <deque>
#include <fstream>
#include <ostream>
#include <string>
#include <vector>

/**
 * @brief In-order fetch buffer that sits between instruction memory and dispatch.
 *
 * Each cycle tick() pulls up to IQ_FETCH_WIDTH instructions from the loaded program
 * into the buffer if capacity allows.  Dispatch calls can_dispatch() then dispatch()
 * to pop the front entry and send it downstream to an RS or LSB slot.
 *
 * Buffer layout:
 * @code
 *   [front/oldest] <- dispatch        fetch -> [back/newest]
 * @endcode
 *
 * The program is indexed by word address (PC >> 2).
 * Buffer capacity defaults to IQ_CAPACITY from config.h.
 */
class InstructionQueue {
public:
    /**
     * @brief Construct an instruction queue with the given fetch buffer capacity.
     * @param[in] capacity  Maximum number of instructions the buffer can hold.
     */
    explicit InstructionQueue(int capacity = IQ_CAPACITY);

    /**
     * @brief Load a decoded program into the queue.
     * @param[in] prog  Vector of decoded instructions; index maps to word address.
     */
    void load_program(const std::vector<Instruction>& prog);

    /** @brief Fetch up to IQ_FETCH_WIDTH instructions from the program into the buffer. */
    void tick();

    /**
     * @brief Return true if the buffer has at least one instruction ready to dispatch.
     * @return True when the front of the buffer is available.
     */
    bool can_dispatch() const;

    /**
     * @brief Inspect the front instruction without removing it.
     *
     * Only call when can_dispatch() returns true.
     *
     * @return Const reference to the next instruction to be dispatched.
     */
    const Instruction& peek() const;

    /**
     * @brief Pop and return the front instruction.
     *
     * Only call when can_dispatch() returns true.
     *
     * @return The oldest buffered instruction.
     */
    Instruction dispatch();

    /**
     * @brief Return true once all instructions have been fetched and the buffer is empty.
     * @return True when the program counter is past the last instruction and the buffer is empty.
     */
    bool done() const;

    /**
     * @brief Flush the buffer and seek to a new fetch address.
     *
     * Called after a branch commits so fetching resumes at the correct target.
     *
     * @param[in] byte_pc  Byte address of the next instruction to fetch.
     */
    void seek(uint32_t byte_pc);

    /** @brief Print current queue state to @p os annotated with @p cycle. */
    void dump(std::ostream& os, int cycle) const;

    /** @brief Open (or create) the cycle-trace log file at @p path. */
    void open_log(const std::string& path);

    /** @brief Append a one-line state snapshot for @p cycle to the log file. */
    void log_cycle(int cycle);

private:
    int                      capacity_;
    std::vector<Instruction> program_;  ///< Full program; index = PC >> 2.
    int                      pc_;       ///< Word index of the next instruction to fetch.
    std::deque<Instruction>  buffer_;
    std::ofstream            log_;
};
