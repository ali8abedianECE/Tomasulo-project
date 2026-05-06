/**
 * @brief Combinational in-order retirement unit.
 *
 * Each cycle reads the ROB head entry and, if it is ROB_DONE, drives all
 * retirement signals: writes the result to the architectural register file,
 * clears the RAT mapping (tag-matched), and pulses commit_en_o to advance
 * the ROB head. For branch instructions a predict-not-taken policy is used:
 * if the branch resolved as taken, flush_o fires and redirect_pc_o carries
 * the resolved target so the fetch stage can restart from the correct PC.
 *
 * @param commit_valid_i Head ROB entry is ROB_DONE and ready to retire.
 * @param commit_entry_i Full rob_entry_t from the ROB head.
 * @param commit_tag_i ROB tag (head index) used to match the RAT entry.
 * @param commit_en_o Tells the ROB to advance its head pointer.
 * @param x_wr_f_wr_* Integer/FP register file write port.
 * @param x_commit_*f_commit_* RAT clear port - clears mapping if tag matches.
 * @param flush_o High for one cycle on branch misprediction.
 * @param redirect_pc_o Correct PC to restart fetch from on flush.
 */
module commit_unit(
                    commit_valid_i, commit_entry_i, commit_tag_i,
                    commit_en_o,

                    // Integer reg file commit interface
                    x_wr_en_o, x_wr_addr_o, x_wr_val_o,

                    // FP reg file commit interface
                    f_wr_en_o, f_wr_addr_o, f_wr_val_o,

                    // RAT clear (INT)
                    x_commit_en_o, x_commit_addr_o, x_commit_tag_o,

                    // RAT clear (FP)
                    f_commit_en_o, f_commit_addr_o, f_commit_tag_o,

                    // Branch misprediction interface
                    flush_o, redirect_pc_o,

                    // Store commit pulse to LSB
                    store_commit_o, store_commit_tag_o
                    );
    import rv32if_pkg::*;

    input logic commit_valid_i; ///< Indicates that the head entry of the ROB is valid and can be committed.
    input rob_entry_t commit_entry_i; ///< Full ROB head entry to retire.
    input logic [TAG_W-1:0] commit_tag_i; ///< ROB tag (head index) of the committing entry.

    output logic commit_en_o; ///< Pulses high to tell ROB to advance its head.

    // Integer reg file commit interface
    output logic x_wr_en_o; ///< Write enable signal for the integer register file.
    output logic [ARCH_W-1:0] x_wr_addr_o; ///< Destination register address for integer write.
    output logic [DATA_W-1:0] x_wr_val_o; ///< Value to write to the integer register file.

    // FP reg file commit interface
    output logic f_wr_en_o; ///< Write enable signal for the floating-point register file.
    output logic [ARCH_W-1:0] f_wr_addr_o; ///< Destination register address for FP write.
    output logic [DATA_W-1:0] f_wr_val_o; ///< Value to write to the floating-point register file.

    // RAT clear (INT)
    output logic x_commit_en_o; ///< Enable signal for clearing integer RAT mapping.
    output logic [ARCH_W-1:0] x_commit_addr_o; ///< Integer register address to clear in RAT.
    output logic [TAG_W-1:0] x_commit_tag_o; ///< Tag to match before clearing integer RAT entry.

    // RAT clear (FP)
    output logic f_commit_en_o; ///< Enable signal for clearing FP RAT mapping.
    output logic [ARCH_W-1:0] f_commit_addr_o; ///< FP register address to clear in RAT.
    output logic [TAG_W-1:0] f_commit_tag_o; ///< Tag to match before clearing FP RAT entry.

    // Branch misprediction interface
    output logic flush_o; ///< Flush the pipeline on branch misprediction (predict not-taken).
    output logic [PC_W-1:0] redirect_pc_o; ///< Redirect PC to resolved branch target on flush.

    // Store commit pulse to LSB
    output logic store_commit_o; ///< Pulses high when a store instruction retires.
    output logic [TAG_W-1:0] store_commit_tag_o; ///< ROB tag of the retiring store.

    always_comb begin
        commit_en_o = commit_valid_i;

        // defaults
        x_wr_en_o = 1'b0; 
        x_wr_addr_o = '0; 
        x_wr_val_o = '0;

        f_wr_en_o = 1'b0; 
        f_wr_addr_o = '0; 
        f_wr_val_o = '0;

        x_commit_en_o = 1'b0; 
        x_commit_addr_o = '0; 
        x_commit_tag_o = '0;

        f_commit_en_o = 1'b0; 
        f_commit_addr_o = '0; 
        f_commit_tag_o = '0;

        flush_o = 1'b0;
        redirect_pc_o = '0;
        store_commit_o = commit_valid_i & is_store_op(commit_entry_i.op);
        store_commit_tag_o = commit_tag_i;
        if (commit_valid_i) begin
            // write to integer regfile and clear INT RAT mapping
            if (commit_entry_i.rd_valid && ~commit_entry_i.rd_fp) begin
                x_wr_en_o = 1'b1;
                x_wr_addr_o = commit_entry_i.rd;
                x_wr_val_o = commit_entry_i.result;
                x_commit_en_o = 1'b1;
                x_commit_addr_o = commit_entry_i.rd;
                x_commit_tag_o = commit_tag_i;
            end

            // write to FP regfile and clear FP RAT mapping
            if (commit_entry_i.rd_valid && commit_entry_i.rd_fp) begin
                f_wr_en_o = 1'b1;
                f_wr_addr_o = commit_entry_i.rd;
                f_wr_val_o = commit_entry_i.result;
                f_commit_en_o = 1'b1;
                f_commit_addr_o = commit_entry_i.rd;
                f_commit_tag_o = commit_tag_i;
            end

            // flush on misprediction: predict not-taken, so flush when branch is taken
            if (commit_entry_i.is_branch && commit_entry_i.branch_taken) begin
                flush_o = 1'b1;
                redirect_pc_o = commit_entry_i.branch_target;
            end
        end
    end

endmodule : commit_unit
