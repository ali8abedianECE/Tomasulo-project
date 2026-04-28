#pragma once
#include "instruction.h"
#include <deque>
#include <fstream>
#include <ostream>
#include <string>
#include <vector>

/*
 * InstructionQueue — in-order fetch buffer between instruction memory and dispatch.
 *
 * Each cycle tick() pulls the next instruction from the loaded program into
 * the buffer if capacity allows. Dispatch calls can_dispatch() then dispatch()
 * to pop the front entry and send it downstream.
 *
 *   [front/oldest] <- dispatch        fetch -> [back/newest]
 *
 * program_ is indexed by PC >> 2 (word address).
 * Capacity defaults to IQ_CAPACITY from config.h.
 */
class InstructionQueue {
public:
    explicit InstructionQueue(int capacity = IQ_CAPACITY);
    void load_program(const std::vector<Instruction>& prog);
    /* Fetch next instruction into buffer if space allows. */
    void tick();
    bool can_dispatch() const;
    /* Inspect front instruction without removing it. Only call when can_dispatch(). */
    const Instruction& peek() const;
    /* Pop and return front instruction. Only call when can_dispatch(). */
    Instruction dispatch();
    /* True once all instructions fetched and buffer empty. */
    bool done() const;
    /* Clear buffer and seek to byte_pc (used after a branch commits). */
    void seek(uint32_t byte_pc);
    void dump(std::ostream& os, int cycle) const;
    /* Open (or create) a log file. Call once before the clock loop. */
    void open_log(const std::string& path);
    /* Append a one-line state snapshot for this cycle to the log file. */
    void log_cycle(int cycle);

private:
    int                      capacity_;
    std::vector<Instruction> program_;  /* full program, index = PC >> 2 */
    int                      pc_;       /* index of next instruction to fetch */
    std::deque<Instruction>  buffer_;
    std::ofstream            log_;      /* cycle-trace output file            */
};
