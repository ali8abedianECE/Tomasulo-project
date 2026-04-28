#pragma once
#include "common_data_bus.h"
#include "instruction.h"
#include "regfile.h"
#include "register_remapping_table.h"
#include "reorder_buffer.h"
#include <cstdint>
#include <fstream>
#include <ostream>
#include <string>
#include <vector>

/*
 * LoadStoreBuffer (LSB) — ordered queue for all memory operations.
 *
 * Implemented as a circular buffer (same layout as ROB) so program order
 * is preserved. Only load/store instructions go here; ALU ops go to the RS.
 *
 * Entry state machine:
 *   IDLE       → slot is free
 *   WAITING    → base-register or store-data operand not yet available
 *   ADDR_READY → effective address computed; load may execute, store waits
 *   EXECUTING  → load is accessing memory (counting down LAT_INT_LS / LAT_FP_LS)
 *   DONE       → load result ready for CDB  |  store addr+data ready for commit
 *
 * Memory ordering:
 *   A load may execute once its address is known AND every earlier store in the
 *   LSB either has a known non-aliasing address, or can forward its data directly.
 *   Stores never write memory here — commit_store() is called by the commit unit
 *   when the store reaches the ROB head, preserving in-order memory writes.
 */
enum class LSBState : uint8_t {
    IDLE,
    WAITING,
    ADDR_READY,
    EXECUTING,
    DONE
};

struct LSBEntry {
    LSBState state     = LSBState::IDLE;
    Opcode   op        = Opcode::NOP;
    int      rob_tag   = -1;
    uint32_t vj        = 0;     /* base register value (valid when qj==-1)  */
    uint32_t vk        = 0;     /* store data value    (valid when qk==-1)  */
    int      qj        = -1;    /* ROB tag base reg is waiting on            */
    int      qk        = -1;    /* ROB tag store data is waiting on          */
    int32_t  imm       = 0;
    bool     rd_fp     = false; /* load destination in f-reg file            */
    uint32_t eff_addr  = 0;     /* byte address = vj + imm                  */
    int      cycles_rem = 0;
    uint32_t result    = 0;     /* loaded value; valid when DONE (loads only) */
    uint32_t pc        = 0;
};

class LoadStoreBuffer {
public:
    explicit LoadStoreBuffer(int size = LSB_SIZE);

    /* Dispatch a load/store into a free slot, resolving operands from RAT/RF/ROB. */
    bool issue(const Instruction&            instr,
               int                           rob_tag,
               const RegisterRemappingTable& rat,
               const RegisterFile&           rf,
               const ReorderBuffer&          rob);

    /* Capture matching CDB results into waiting entries. Call before tick(). */
    void snoop(const CommonDataBus& cdb);

    /*
     * Advance one cycle:
     *   - Compute effective addresses for WAITING entries whose qj is resolved.
     *   - Check load aliasing against earlier stores; execute eligible loads.
     *   - Decrement cycles_rem for EXECUTING loads; mark DONE when zero.
     */
    void tick(std::vector<uint32_t>& mem);

    /* True if the head entry is a DONE load (result ready for CDB). */
    bool has_load_result() const;

    /* Remove and return the head load entry. Only call when has_load_result(). */
    LSBEntry pop_load_result();

    /* True if the head entry is a DONE store (addr and data ready to commit). */
    bool can_commit_store() const;

    /* Write the head store to memory and free the slot. */
    void commit_store(std::vector<uint32_t>& mem);

    bool full()  const;
    bool empty() const;

    /* Flush all entries (branch misprediction recovery). */
    void flush();

    /* Mark DONE stores in the ROB so the commit unit can retire them.
     * Guards against double-write by checking ROBState::IN_FLIGHT first. */
    void update_rob(ReorderBuffer& rob) const;

    void dump(std::ostream& os, int cycle) const;
    void open_log(const std::string& path);
    void log_cycle(int cycle);

private:
    int                   size_;
    int                   head_;
    int                   tail_;
    int                   count_;
    std::vector<LSBEntry> entries_;
    std::ofstream         log_;

    /* Logical index → physical array index. */
    int phys(int logical) const { return (head_ + logical) % size_; }
};
