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
 * @brief Lifecycle states for a load/store buffer entry.
 *
 * Transitions: IDLE -> WAITING -> ADDR_READY -> EXECUTING -> DONE
 */
enum class LSBState : uint8_t {
    IDLE,        ///< Slot is free.
    WAITING,     ///< Base-register or store-data operand not yet available.
    ADDR_READY,  ///< Effective address computed; load may execute, store waits to commit.
    EXECUTING,   ///< Load is accessing memory (counting down the latency).
    DONE         ///< Load result ready for CDB, or store addr+data ready for commit.
};

/**
 * @brief One entry in the load/store buffer.
 */
struct LSBEntry {
    LSBState state      = LSBState::IDLE;
    Opcode   op         = Opcode::NOP;
    int      rob_tag    = -1;
    uint32_t vj         = 0;     ///< Base register value; valid when qj == -1.
    uint32_t vk         = 0;     ///< Store data value; valid when qk == -1.
    int      qj         = -1;    ///< ROB tag base register is waiting on.
    int      qk         = -1;    ///< ROB tag store data is waiting on.
    int32_t  imm        = 0;
    bool     rd_fp      = false; ///< True if the load destination is an FP register.
    uint32_t eff_addr   = 0;     ///< Effective byte address = vj + imm.
    int      cycles_rem = 0;     ///< Remaining execution cycles for loads.
    uint32_t result     = 0;     ///< Loaded value; valid when state == DONE (loads only).
    uint32_t pc         = 0;
};

/**
 * @brief Load/store buffer — ordered queue for all memory operations.
 *
 * Implemented as a circular buffer so program order is preserved.  Only load and
 * store instructions go here; ALU ops go to the ReservationStation.
 *
 * Memory ordering:
 *   A load may execute once its address is known AND every earlier store in the
 *   LSB either has a known non-aliasing address or can forward its data directly.
 *   Stores never write memory here — commit_store() is called by the CommitUnit
 *   when the store reaches the ROB head, preserving in-order memory writes.
 */
class LoadStoreBuffer {
public:
    /**
     * @brief Construct a load/store buffer with @p size entries.
     * @param[in] size  Maximum number of in-flight memory ops.
     */
    explicit LoadStoreBuffer(int size = LSB_SIZE);

    /**
     * @brief Dispatch a load or store into a free slot, resolving operands from RAT/RF/ROB.
     * @param[in] instr    Decoded instruction (LW, SW, FLW, or FSW).
     * @param[in] rob_tag  ROB slot allocated for this instruction.
     * @param[in] rat      Current register renaming table.
     * @param[in] rf       Committed register file (fallback when RAT has no entry).
     * @param[in] rob      In-flight ROB (for value forwarding from DONE entries).
     * @return             True if the instruction was accepted; false if the buffer is full.
     */
    bool issue(const Instruction&            instr,
               int                           rob_tag,
               const RegisterRemappingTable& rat,
               const RegisterFile&           rf,
               const ReorderBuffer&          rob);

    /**
     * @brief Capture matching CDB results into waiting entries.
     *
     * Must be called before tick() so that newly arrived operands are visible
     * when addresses and aliasing are evaluated this cycle.
     *
     * @param[in] cdb  Common data bus carrying results broadcast this cycle.
     */
    void snoop(const CommonDataBus& cdb);

    /**
     * @brief Advance one cycle.
     *
     * For each entry in program order:
     *   - Compute the effective address for WAITING entries whose base register is resolved.
     *   - Check load aliasing against all earlier stores; execute eligible loads.
     *   - Decrement cycles_rem for EXECUTING loads; mark DONE when it reaches zero.
     *
     * @param[in,out] mem  Word-addressed data memory (read by loads).
     */
    void tick(std::vector<uint32_t>& mem);

    /**
     * @brief Return true if the head entry is a completed load result ready for the CDB.
     * @return True when the oldest entry is a DONE load.
     */
    bool has_load_result() const;

    /**
     * @brief Remove and return the head load entry.
     *
     * Only call when has_load_result() returns true.
     *
     * @return The completed LSBEntry with result filled in.
     */
    LSBEntry pop_load_result();

    /**
     * @brief Return true if the head entry is a store that is ready to commit.
     * @return True when the oldest entry is a DONE store (address and data both known).
     */
    bool can_commit_store() const;

    /**
     * @brief Write the head store to memory and free its slot.
     *
     * Only call when can_commit_store() returns true.
     *
     * @param[in,out] mem  Word-addressed data memory (the store word is written here).
     */
    void commit_store(std::vector<uint32_t>& mem);

    /** @brief Return true if all slots are occupied. */
    bool full()  const;

    /** @brief Return true if no slots are occupied. */
    bool empty() const;

    /** @brief Flush all entries.  Called on branch misprediction recovery. */
    void flush();

    /**
     * @brief Mark DONE stores in the ROB so the CommitUnit can retire them.
     *
     * Guards against double-write by checking ROBState::IN_FLIGHT first.
     *
     * @param[in,out] rob  Reorder buffer to update.
     */
    void update_rob(ReorderBuffer& rob) const;

    /** @brief Print current LSB state to @p os annotated with @p cycle. */
    void dump(std::ostream& os, int cycle) const;

    /** @brief Open (or create) the cycle-trace log file at @p path. */
    void open_log(const std::string& path);

    /** @brief Append a one-line state snapshot for @p cycle to the log file. */
    void log_cycle(int cycle);

private:
    int                   size_;
    int                   head_;
    int                   tail_;
    int                   count_;
    std::vector<LSBEntry> entries_;
    std::ofstream         log_;

    /** @brief Convert a logical (program-order) index to a physical array index. */
    int phys(int logical) const { return (head_ + logical) % size_; }
};
