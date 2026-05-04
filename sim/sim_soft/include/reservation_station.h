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

/**
 * @brief One entry in a reservation station.
 *
 * Operand fields:
 *   - @c vj / @c vk  - source values as uint32_t bits (ready when qj/qk == -1).
 *   - @c qj / @c qk  - ROB tag we are waiting on (-1 means the value is in vj/vk).
 *
 * Implicit entry states:
 *   - !busy                              - IDLE
 *   - busy && (qj != -1 || qk != -1)    - WAITING (operand(s) not yet available)
 *   - busy && qj == -1 && qk == -1
 *          && cycles_rem == 0           - READY (waiting for FU to pick it up)
 *   - busy && qj == -1 && qk == -1
 *          && cycles_rem > 0            - EXECUTING
 *   - busy && done                       - DONE (result ready for the CDB)
 */
struct RSEntry {
    bool     busy       = false;
    Opcode   op         = Opcode::NOP;
    int      rob_tag    = -1;   ///< ROB slot this instruction writes to.
    uint32_t vj         = 0;    ///< Source 1 value bits; valid when qj == -1.
    uint32_t vk         = 0;    ///< Source 2 value bits; valid when qk == -1.
    int      qj         = -1;   ///< ROB tag source 1 is waiting on.
    int      qk         = -1;   ///< ROB tag source 2 is waiting on.
    int32_t  imm        = 0;    ///< Sign-extended immediate operand.
    bool     rd_fp      = false;
    bool     done       = false;
    int      cycles_rem = 0;    ///< Cycles remaining until the result is ready.
    uint32_t result     = 0;    ///< Computed value; valid when done == true.
    uint32_t pc         = 0;
};

/**
 * @brief Reservation station - holds dispatched instructions waiting for operands.
 *
 * One instance is created per functional unit group (e.g. integer ALU, FP ALU).
 * Load/store ops go to the LoadStoreBuffer instead.
 *
 * Caller ordering each cycle:
 *   1. snoop(cdb)              - capture newly available operands.
 *   2. tick()                  - start READY entries, decrement counters, mark DONE.
 *   3. while has_result(): cdb.broadcast(pop_result())  - post results to the bus.
 *   4. cdb.flush()             - clear the bus after all units have posted.
 */
class ReservationStation {
public:
    /**
     * @brief Construct a reservation station with @p size slots.
     * @param[in] size  Number of RS entries for this functional unit group.
     */
    explicit ReservationStation(int size);

    /**
     * @brief Dispatch an instruction into a free slot.
     *
     * Resolves vj/vk from the RAT, ROB forwarding, and RegisterFile at dispatch time.
     *
     * @param[in] instr    Decoded instruction to queue.
     * @param[in] rob_tag  ROB slot allocated for this instruction.
     * @param[in] rat      Current register renaming table.
     * @param[in] rf       Committed register file (fallback when RAT has no entry).
     * @param[in] rob      In-flight ROB (for value forwarding from DONE entries).
     * @return             True if the instruction was accepted; false if all slots are full.
     */
    bool issue(const Instruction&           instr,
               int                          rob_tag,
               const RegisterRemappingTable& rat,
               const RegisterFile&           rf,
               const ReorderBuffer&          rob);

    /**
     * @brief Capture matching CDB results into waiting entries.
     *
     * Must be called before tick() each cycle so that operands resolved this
     * cycle are visible when READY entries are selected for execution.
     *
     * @param[in] cdb  Common data bus carrying results broadcast this cycle.
     */
    void snoop(const CommonDataBus& cdb);

    /**
     * @brief Advance one cycle.
     *
     * For each entry:
     *   - READY entries: start executing (set cycles_rem = latency_of(op)).
     *     Non-pipelined FUs block if another entry with the same op is EXECUTING.
     *   - EXECUTING entries: decrement cycles_rem; mark done when it reaches zero.
     */
    void tick();

    /**
     * @brief Return true if any entry has a completed result ready for the CDB.
     * @return True when at least one entry has done == true.
     */
    bool has_result() const;

    /**
     * @brief Remove and return a completed entry, freeing its slot.
     *
     * Only call when has_result() returns true.
     *
     * @return The done RSEntry with result and rob_tag filled in.
     */
    RSEntry pop_result();

    /** @brief Return true if all slots are occupied. */
    bool full()  const;

    /** @brief Return true if no slots are occupied. */
    bool empty() const;

    /** @brief Flush all entries.  Called on branch misprediction recovery. */
    void flush();

    /** @brief Print current RS state to @p os annotated with @p cycle. */
    void dump(std::ostream& os, int cycle) const;

    /** @brief Open (or create) the cycle-trace log file at @p path. */
    void open_log(const std::string& path);

    /** @brief Append a one-line state snapshot for @p cycle to the log file. */
    void log_cycle(int cycle);

private:
    int                  size_;
    int                  count_;
    std::vector<RSEntry> entries_;
    std::ofstream        log_;
};
