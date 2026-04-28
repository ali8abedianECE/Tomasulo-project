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
 * ReservationStation — holds dispatched instructions waiting for operands.
 *
 * One instance is created per functional unit type (e.g. integer ALU, FP ALU).
 * Load/store ops go to the LoadStoreBuffer instead.
 *
 * Entry state is implicit:
 *   !busy                              → IDLE
 *   busy && (qj!=-1 || qk!=-1)        → WAITING  (operand(s) not yet available)
 *   busy && qj==-1 && qk==-1
 *        && cycles_rem==0             → READY    (waiting for FU to pick it up)
 *   busy && qj==-1 && qk==-1
 *        && cycles_rem>0              → EXECUTING
 *   busy && done                       → DONE     (result ready for CDB)
 *
 * Operand fields:
 *   vj / vk   — source values as uint32_t bits (ready when qj/qk == -1)
 *   qj / qk   — ROB tag we are waiting on     (-1 = value is in vj/vk)
 *
 * Caller ordering each cycle:
 *   1. snoop(cdb)   — capture newly available operands
 *   2. tick()       — start READY entries, decrement counters, mark DONE
 *   3. while has_result(): cdb.broadcast(pop_result())
 *   4. cdb.flush()
 */
struct RSEntry {
    bool     busy       = false;
    Opcode   op         = Opcode::NOP;
    int      rob_tag    = -1;   /* ROB slot this writes to              */
    uint32_t vj         = 0;    /* src1 value bits (valid when qj==-1)  */
    uint32_t vk         = 0;    /* src2 value bits (valid when qk==-1)  */
    int      qj         = -1;   /* ROB tag src1 is waiting on           */
    int      qk         = -1;   /* ROB tag src2 is waiting on           */
    int32_t  imm        = 0;    /* sign-extended immediate               */
    bool     rd_fp      = false;
    bool     done       = false;
    int      cycles_rem = 0;    /* cycles left until result is ready     */
    uint32_t result     = 0;    /* computed value, valid when done=true  */
    uint32_t pc         = 0;
};

class ReservationStation {
public:
    explicit ReservationStation(int size);

    /*
     * Dispatch an instruction into a free slot.
     * Resolves vj/vk from RAT + RegisterFile + ROB (forwarding).
     * Returns false if all slots are full.
     */
    bool issue(const Instruction&           instr,
               int                          rob_tag,
               const RegisterRemappingTable& rat,
               const RegisterFile&           rf,
               const ReorderBuffer&          rob);

    /* Capture matching CDB results into waiting entries. Call before tick(). */
    void snoop(const CommonDataBus& cdb);

    /*
     * Advance one cycle:
     *   - READY entries: start executing (set cycles_rem = latency_of(op)).
     *     Non-pipelined FUs block if another entry with the same op is EXECUTING.
     *   - EXECUTING entries: decrement cycles_rem; mark done when it hits 0.
     */
    void tick();

    /* True if any entry has done=true. */
    bool has_result() const;

    /* Remove and return a done entry, freeing the slot. */
    RSEntry pop_result();

    bool full()  const;
    bool empty() const;

    /* Flush all entries (branch misprediction recovery). */
    void flush();

    void dump(std::ostream& os, int cycle) const;
    void open_log(const std::string& path);
    void log_cycle(int cycle);

private:
    int                  size_;
    int                  count_;
    std::vector<RSEntry> entries_;
    std::ofstream        log_;
};
