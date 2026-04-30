#include "load_store_buffer.h"
#include "dispatch_utils.h"
#include <cassert>
#include <iomanip>

/**
 * @brief Construct a LoadStoreBuffer with the given number of slots.
 *
 * @param[in] size Total number of LSB entries (must be >= 1).
 */
LoadStoreBuffer::LoadStoreBuffer(int size)
    : size_(size), head_(0), tail_(0), count_(0) {
    assert(size >= 1);
    entries_.resize(size_);
}


/**
 * @brief Enqueue a load or store instruction into the next free LSB slot.
 *
 * Resolves the base address register and, for stores, the data register
 * from the RAT, register file, or ROB at issue time.
 *
 * @param[in] instr   Decoded load/store instruction to enqueue.
 * @param[in] rob_tag ROB slot allocated for this instruction.
 * @param[in] rat     Current register-renaming table for operand lookup.
 * @param[in] rf      Architectural register file for operand lookup.
 * @param[in] rob     ROB used to forward already-computed but uncommitted values.
 *
 * @return @c true if the entry was enqueued; @c false if the LSB is full.
 */
bool LoadStoreBuffer::issue(const Instruction&            instr,
                             int                           rob_tag,
                             const RegisterRemappingTable& rat,
                             const RegisterFile&           rf,
                             const ReorderBuffer&          rob) {
    if (full()) return false;
    LSBEntry& e   = entries_[tail_];
    e.state       = LSBState::WAITING;
    e.op          = instr.op;
    e.rob_tag     = rob_tag;
    e.imm         = instr.imm;
    e.rd_fp       = instr.rd_fp;
    e.cycles_rem  = 0;
    e.result      = 0;
    e.pc          = instr.pc;
    /* rs1 = base address register (always integer) */
    resolve_operand(instr.rs1, false, rat, rf, rob, e.vj, e.qj);
    /* rs2 = store data register (only for SW/FSW); rs2_fp tells which file */
    resolve_operand(instr.rs2, instr.rs2_fp, rat, rf, rob, e.vk, e.qk);
    tail_  = (tail_ + 1) % size_;
    ++count_;
    return true;
}


/**
 * @brief Capture CDB results into waiting LSB entries.
 *
 * Clears qj/qk tags and latches forwarded values for entries whose
 * operands are satisfied by this cycle's broadcast.
 *
 * @param[in] cdb Common Data Bus carrying results from this cycle.
 */
void LoadStoreBuffer::snoop(const CommonDataBus& cdb) {
    for (const auto& res : cdb.results()) {
        for (int i = 0; i < count_; ++i) {
            LSBEntry& e = entries_[phys(i)];
            if (e.state == LSBState::IDLE || e.state == LSBState::DONE) continue;
            if (e.qj == res.rob_tag) { e.vj = res.value; e.qj = -1; }
            if (e.qk == res.rob_tag) { e.vk = res.value; e.qk = -1; }
        }
    }
}


/**
 * @brief Advance all LSB entries by one cycle.
 *
 * Four ordered passes each tick:
 * 1. WAITING → ADDR_READY when the base register (qj) is resolved.
 * 2. ADDR_READY store → DONE when the store data register (qk) is also resolved.
 * 3. ADDR_READY load → EXECUTING or DONE (with store-to-load forwarding and
 *    memory-order safety checks against earlier unresolved stores).
 * 4. Decrement EXECUTING load countdowns; perform the memory read when done.
 *
 * @param[in,out] mem Word-addressed memory image used for load execution.
 */
void LoadStoreBuffer::tick(std::vector<uint32_t>& mem) {
    /* Pass 1: WAITING → ADDR_READY when base register (qj) resolved. */
    for (int i = 0; i < count_; ++i) {
        LSBEntry& e = entries_[phys(i)];
        if (e.state != LSBState::WAITING || e.qj != -1) continue;
        e.eff_addr = static_cast<uint32_t>(static_cast<int32_t>(e.vj) + e.imm);
        e.state    = LSBState::ADDR_READY;
    }
    /* Pass 2: ADDR_READY store → DONE when store data (qk) also resolved. */
    for (int i = 0; i < count_; ++i) {
        LSBEntry& e = entries_[phys(i)];
        if (e.state != LSBState::ADDR_READY || !is_store(e.op) || e.qk != -1) continue;
        e.state = LSBState::DONE;
    }
    /* Pass 3: ADDR_READY load → EXECUTING or DONE.
     * Block if any earlier unresolved store exists, or if an earlier store
     * to the same address is not yet DONE. Forward from DONE stores. */
    for (int i = 0; i < count_; ++i) {
        LSBEntry& e = entries_[phys(i)];
        if (e.state != LSBState::ADDR_READY || !is_load(e.op)) continue;
        bool blocked  = false;
        int  fwd_slot = -1;
        for (int j = 0; j < i; ++j) {
            const LSBEntry& older = entries_[phys(j)];
            if (!is_store(older.op)) continue;
            if (older.state == LSBState::WAITING) { blocked = true; fwd_slot = -1; break; }
            if (older.eff_addr != e.eff_addr) continue;
            if (older.state == LSBState::DONE)
                fwd_slot = j;  /* keep scanning for the most recent aliasing DONE store */
            else
                { blocked = true; fwd_slot = -1; break; }
        }
        if (blocked) continue;
        if (fwd_slot >= 0) {
            e.result = entries_[phys(fwd_slot)].vk;
            e.state  = LSBState::DONE;
            continue;
        }
        int lat = latency_of(e.op);
        if (lat <= 1) {
            uint32_t wa = e.eff_addr >> 2;
            e.result = (wa < static_cast<uint32_t>(mem.size())) ? mem[wa] : 0u;
            e.state  = LSBState::DONE;
        } else {
            e.cycles_rem = lat - 1;
            e.state      = LSBState::EXECUTING;
        }
    }
    /* Pass 4: Decrement EXECUTING loads; mark DONE when counter hits zero. */
    for (int i = 0; i < count_; ++i) {
        LSBEntry& e = entries_[phys(i)];
        if (e.state != LSBState::EXECUTING) continue;
        if (--e.cycles_rem == 0) {
            uint32_t wa = e.eff_addr >> 2;
            e.result = (wa < static_cast<uint32_t>(mem.size())) ? mem[wa] : 0u;
            e.state  = LSBState::DONE;
        }
    }
}


/**
 * @brief Check whether the head LSB entry is a completed load ready to broadcast.
 *
 * @return @c true if the LSB is non-empty, the head entry is in the DONE state,
 *         and the head entry is a load operation.
 */
bool LoadStoreBuffer::has_load_result() const {
    if (empty()) return false;
    const LSBEntry& h = entries_[head_];
    return h.state == LSBState::DONE && is_load(h.op);
}


/**
 * @brief Remove and return the head load entry for CDB broadcast.
 *
 * @return A copy of the completed LSBEntry. The slot is cleared and the
 *         head pointer advanced.
 *
 * @throws Assertion failure if called when has_load_result() is false.
 */
LSBEntry LoadStoreBuffer::pop_load_result() {
    assert(has_load_result());
    LSBEntry out    = entries_[head_];
    entries_[head_] = LSBEntry{};
    head_  = (head_ + 1) % size_;
    --count_;
    return out;
}


/**
 * @brief Check whether the head LSB entry is a completed store ready to retire.
 *
 * @return @c true if the LSB is non-empty, the head entry is DONE, and it is
 *         a store operation.
 */
bool LoadStoreBuffer::can_commit_store() const {
    if (empty()) return false;
    const LSBEntry& h = entries_[head_];
    return h.state == LSBState::DONE && is_store(h.op);
}


/**
 * @brief Write the head store entry to memory and retire it from the LSB.
 *
 * Called by the commit unit when a store reaches the head of the ROB.
 * The effective address must already be computed and the data register resolved.
 *
 * @param[in,out] mem Word-addressed memory image to write the store data into.
 *
 * @throws Assertion failure if called when can_commit_store() is false.
 */
void LoadStoreBuffer::commit_store(std::vector<uint32_t>& mem) {
    assert(can_commit_store());
    LSBEntry& h  = entries_[head_];
    uint32_t  wa = h.eff_addr >> 2;
    if (wa < static_cast<uint32_t>(mem.size()))
        mem[wa] = h.vk;
    entries_[head_] = LSBEntry{};
    head_  = (head_ + 1) % size_;
    --count_;
}


/**
 * @brief Notify the ROB of any stores that have reached the DONE state.
 *
 * Marks the corresponding ROB entries as DONE (result = 0) so the commit
 * unit can retire them in program order.
 *
 * @param[in,out] rob Reorder buffer to update.
 */
void LoadStoreBuffer::update_rob(ReorderBuffer& rob) const {
    for (int i = 0; i < count_; ++i) {
        const LSBEntry& e = entries_[phys(i)];
        if (is_store(e.op) && e.state == LSBState::DONE &&
                rob.peek(e.rob_tag).state == ROBState::IN_FLIGHT)
            rob.write_result(e.rob_tag, 0u);
    }
}


/** @brief Return @c true if every LSB slot is occupied. */
bool LoadStoreBuffer::full()  const { return count_ == size_; }


/** @brief Return @c true if no LSB slots are occupied. */
bool LoadStoreBuffer::empty() const { return count_ == 0; }


/**
 * @brief Reset all LSB entries and pointers to their initial state.
 *
 * Called on a branch misprediction flush to discard all pending memory operations.
 */
void LoadStoreBuffer::flush() {
    entries_.assign(size_, LSBEntry{});
    head_  = 0;
    tail_  = 0;
    count_ = 0;
}


static const char* lsb_state_str(LSBState s) {
    switch (s) {
        case LSBState::IDLE:       return "IDLE";
        case LSBState::WAITING:    return "WAIT";
        case LSBState::ADDR_READY: return "ARDY";
        case LSBState::EXECUTING:  return "EXEC";
        case LSBState::DONE:       return "DONE";
        default:                   return "?";
    }
}

/**
 * @brief Print a human-readable snapshot of all non-idle LSB entries.
 *
 * @param[in,out] os    Output stream to write to.
 * @param[in]     cycle Current simulation cycle number (for the header line).
 */
void LoadStoreBuffer::dump(std::ostream& os, int cycle) const {
    os << "[LSB  cycle=" << std::setw(4) << cycle << "]"
       << " head=" << head_ << " tail=" << tail_
       << " count=" << count_ << "/" << size_ << "\n";
    for (int i = 0; i < count_; ++i) {
        const LSBEntry& e = entries_[phys(i)];
        os << "  [" << std::setw(2) << phys(i) << "] "
           << lsb_state_str(e.state) << " " << opcode_name(e.op)
           << " ROB=" << e.rob_tag;
        if (e.qj != -1) os << " qj=ROB" << e.qj;
        else            os << " vj=0x" << std::hex << e.vj << std::dec;
        if (is_store(e.op)) {
            if (e.qk != -1) os << " qk=ROB" << e.qk;
            else            os << " vk=0x" << std::hex << e.vk << std::dec;
        }
        if (e.state != LSBState::IDLE && e.state != LSBState::WAITING)
            os << " addr=0x" << std::hex << e.eff_addr << std::dec;
        if (e.cycles_rem > 0) os << " rem=" << e.cycles_rem;
        os << " PC=0x" << std::hex << std::setw(4) << std::setfill('0')
           << e.pc << std::dec << std::setfill(' ') << "\n";
    }
}



void LoadStoreBuffer::open_log(const std::string& path) {}


void LoadStoreBuffer::log_cycle(int cycle) {}
