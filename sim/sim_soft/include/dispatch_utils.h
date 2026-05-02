#pragma once
#include "regfile.h"
#include "register_remapping_table.h"
#include "reorder_buffer.h"
#include "utils.h"

/**
 * @brief Resolve a source register at dispatch time using the Tomasulo forwarding chain.
 *
 * Checks RAT -> ROB forwarding -> RegisterFile in that priority order:
 *   1. If the register has no RAT entry, reads the committed value from the register file.
 *   2. If renamed and the producing ROB entry is already DONE, forwards the result directly.
 *   3. If renamed and the ROB entry is still IN_FLIGHT, records the dependency tag in @p out_q.
 *
 * @param[in]  reg_idx  Architectural register index (0-31), or -1 for unused operands.
 * @param[in]  fp       True to look up f0-f31 (FP file); false for x0-x31 (integer file).
 * @param[in]  rat      Current register renaming table.
 * @param[in]  rf       Committed architectural register file.
 * @param[in]  rob      In-flight reorder buffer (used for result forwarding).
 * @param[out] out_val  Resolved operand bits; valid only when @p out_q == -1.
 * @param[out] out_q    ROB tag the operand is waiting on; -1 means @p out_val is ready.
 */
inline void resolve_operand(int reg_idx, bool fp,
                             const RegisterRemappingTable& rat,
                             const RegisterFile&           rf,
                             const ReorderBuffer&          rob,
                             uint32_t& out_val, int& out_q) {
    if (reg_idx < 0) { out_val = 0; out_q = -1; return; }
    RATEntry re = rat.lookup(reg_idx, fp);
    if (!re.valid) {
        out_val = fp ? float_to_bits(rf.read_fp(reg_idx))
                     : static_cast<uint32_t>(rf.read_int(reg_idx));
        out_q = -1;
    } else {
        const ROBEntry& rob_e = rob.peek(re.rob_tag);
        if (rob_e.state == ROBState::DONE) { out_val = rob_e.result; out_q = -1; }
        else                               { out_q = re.rob_tag; }
    }
}
