#include "instruction.h"
#include <cassert>
#include <iomanip>

InstructionQueue::InstructionQueue(int capacity)
    : capacity_(capacity), pc_(0) {
    assert(capacity >= 1);
}

void InstructionQueue::load_program(const std::vector<Instruction>& prog) {
    program_ = prog;
    /* stamp each instruction with its byte address */
    for (int i = 0; i < static_cast<int>(program_.size()); ++i)
        program_[i].pc = static_cast<uint32_t>(i) * 4;
    pc_ = 0;
    buffer_.clear();
}

void InstructionQueue::tick() {
    if (pc_ < static_cast<int>(program_.size()) &&
        static_cast<int>(buffer_.size()) < capacity_) {
        buffer_.push_back(program_[pc_++]);
    }
}

bool InstructionQueue::can_dispatch() const {
    return !buffer_.empty();
}

Instruction InstructionQueue::dispatch() {
    assert(can_dispatch());
    Instruction front = buffer_.front();
    buffer_.pop_front();
    return front;
}

bool InstructionQueue::done() const {
    return pc_ >= static_cast<int>(program_.size()) && buffer_.empty();
}

void InstructionQueue::dump(std::ostream& os, int cycle) const {
    os << "[IQ  cycle=" << std::setw(4) << cycle << "] "
       << "fetched=" << pc_
       << " buf=" << buffer_.size() << "/" << capacity_;
    for (const auto& instr : buffer_)
        os << "  [PC=0x" << std::hex << std::setw(4) << std::setfill('0')
           << instr.pc << " " << opcode_name(instr.op) << "]"
           << std::dec << std::setfill(' ');
    os << "\n";
}
