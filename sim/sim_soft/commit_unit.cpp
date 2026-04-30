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
                      uint32_t& next_pc, bool& halted) {}


/**
 * @brief Print the instruction committed in the most recent tick, or "idle".
 *
 * @param[in,out] os    Output stream to write to.
 * @param[in]     cycle Current simulation cycle number (for the header line).
 */
void CommitUnit::dump(std::ostream& os, int cycle) const {}



void CommitUnit::open_log(const std::string& path) {}


void CommitUnit::log_cycle(int cycle) {}
