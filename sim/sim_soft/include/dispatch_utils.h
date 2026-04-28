#pragma once
#include "regfile.h"
#include "register_remapping_table.h"
#include "reorder_buffer.h"
#include "utils.h"

/*
 * Shared operand resolution for dispatch into RS and LSB.
 * Checks RAT → ROB forwarding → RegisterFile in that order.
 * out_q == -1 means the value is ready in out_val.
 * out_q >= 0  means we are waiting on that ROB tag.
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
