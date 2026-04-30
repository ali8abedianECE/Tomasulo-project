#include "commit_unit.h"
#include <cassert>
#include <iomanip>

/**
 * @brief Attempt to retire the oldest ROB entry for this cycle.
 *
 * Handles all commit cases in program order: HALT, branches (sets next_pc),
 * stores (delegates to LSB), and register-writing instructions (updates rf + RAT).
 *
 * @param[in,out] rob     Reorder buffer to commit from.
 * @param[in,out] rf      Architectural register file to write results into.
 * @param[in,out] rat     Register-renaming table to release the committed mapping.
 * @param[in,out] lsb     Load/store buffer used to finalise store commits.
 * @param[in,out] mem     Word-addressed memory image (passed through to lsb).
 * @param[out]    next_pc Set to the resolved branch target when a branch commits.
 * @param[out]    halted  Set to @c true when a HALT instruction commits.
 *
 * @return @c true if an instruction was committed this cycle; @c false if the
 *         ROB head is not yet ready.
 */
bool CommitUnit::tick(ReorderBuffer& rob, RegisterFile& rf,
                      RegisterRemappingTable& rat,
                      LoadStoreBuffer& lsb, std::vector<uint32_t>& mem,
                      uint32_t& next_pc, bool& halted) {
    last_ = CommitRecord{};
    if (!rob.head_ready()) return false;

    int      rob_tag = rob.head_tag();
    ROBEntry entry   = rob.commit();

    last_.valid  = true;
    last_.op     = entry.op;
    last_.rd     = entry.rd;
    last_.rd_fp  = entry.rd_fp;
    last_.result = entry.result;
    last_.pc     = entry.pc;

    if (entry.op == Opcode::HALT) { halted = true; return true; }

    if (is_branch(entry.op)) {
        /* result holds the resolved target PC from execute_op() */
        next_pc = entry.result;
        return true;
    }

    if (is_store(entry.op)) {
        assert(lsb.can_commit_store());
        lsb.commit_store(mem);
        return true;
    }

    if (entry.rd >= 0) {
        if (entry.rd_fp)
            rf.write_fp(entry.rd, bits_to_float(entry.result));
        else
            rf.write_int(entry.rd, static_cast<int32_t>(entry.result));
        rat.commit(entry.rd, entry.rd_fp, rob_tag);
    }
    return true;
}


/**
 * @brief Print the instruction committed in the most recent tick, or "idle".
 *
 * @param[in,out] os    Output stream to write to.
 * @param[in]     cycle Current simulation cycle number (for the header line).
 */
void CommitUnit::dump(std::ostream& os, int cycle) const {
    os << "[CU   cycle=" << std::setw(4) << cycle << "]";
    if (!last_.valid) { os << " idle\n"; return; }
    os << " COMMIT " << opcode_name(last_.op)
       << " PC=0x" << std::hex << std::setw(4) << std::setfill('0')
       << last_.pc << std::dec << std::setfill(' ');
    if (last_.rd >= 0)
        os << " " << (last_.rd_fp ? "f" : "x") << last_.rd
           << "=0x" << std::hex << last_.result << std::dec;
    os << "\n";
}



void CommitUnit::open_log(const std::string& path) {
    log_.open(path, std::ios::out | std::ios::trunc);
}


void CommitUnit::log_cycle(int cycle) {}
