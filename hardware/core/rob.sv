/**
 * @brief ROB_SIZE-entry circular reorder buffer for in-order retirement.
 *
 * Instructions allocate a slot (tag = tail index) at dispatch and retire in order
 * from the head. Results arrive out of order via the CDB; branch taken/target arrive
 * via the br_ port. An entry becomes ROB_DONE when its result is written, and is
 * retired only when it reaches the head. A (TAG_W+1)-bit count distinguishes full
 * from empty when head == tail. Flush clears all entries synchronously.
 *
 * @param clk Rising-edge clock.
 * @param rst_n Active-low async reset.
 * @param flush_i Synchronous flush.
 * @param alloc_en_i / alloc_instr_i Dispatch allocation request and instruction.
 * @param alloc_tag_o Assigned ROB tag (tail index).
 * @param full_o Stall dispatch when all ROB_SIZE slots are occupied.
 * @param cdb_i CDB broadcast - writes result and sets ROB_DONE on tag match.
 * @param br_valid_i / br_tag_i / br_taken_i / br_target_i Branch resolution.
 * @param commit_en_i Commit unit acknowledges retirement, advances head.
 * @param commit_valid_o Head entry is ROB_DONE and ready to retire.
 * @param commit_entry_o Full head entry for the commit unit to consume.
 */
module rob_unit(clk, rst_n, flush_i,

                // Dispatch interface
                alloc_en_i, alloc_instr_i,
                alloc_tag_o, full_o,

                // CDB interface
                cdb_i,

                // Branch resolution interface
                br_valid_i, br_tag_i, br_taken_i, br_target_i,

                // Commit interface
                commit_en_i,
                commit_valid_o, commit_entry_o,

                // Lookup by tag (for dispatch ROB forwarding)
                lookup1_tag_i, lookup1_done_o, lookup1_val_o,
                lookup2_tag_i, lookup2_done_o, lookup2_val_o
                );
    import rv32if_pkg::*;

    input logic clk; ///< Clock signal for synchronizing ROB operations.
    input logic rst_n; ///< Active-low reset signal.
    input logic flush_i; ///< Signal to flush the ROB, typically on branch misprediction or exception.

    // Dispatch interface
    input logic alloc_en_i; ///< Enable signal for allocating a new entry in the ROB.
    input instr_t alloc_instr_i; ///< Instruction information for the new entry being allocated in the ROB.

    output logic [TAG_W-1:0] alloc_tag_o; ///< Tag assigned to the newly allocated ROB entry.
    output logic full_o; ///< Signal indicating that the ROB is full and cannot accept new entries.

    // CDB interface
    input cdb_t cdb_i; ///< Common Data Bus input for receiving results from execution units.

    // Branch resolution interface
    input logic br_valid_i; ///< Indicates that the branch resolution information is valid.
    input logic [TAG_W-1:0] br_tag_i; ///< Tag associated with the branch instruction being resolved.
    input logic br_taken_i; ///< Indicates whether the branch was taken (1) or not taken (0).
    input logic [PC_W-1:0] br_target_i; ///< Target address for the branch instruction being resolved.

    // Commit interface
    input logic commit_en_i;
    output logic commit_valid_o;
    output rob_entry_t commit_entry_o;

    // Lookup by tag (combinational, for dispatch forwarding)
    input  logic [TAG_W-1:0]   lookup1_tag_i;
    output logic               lookup1_done_o;
    output logic [DATA_W-1:0]  lookup1_val_o;

    input  logic [TAG_W-1:0]   lookup2_tag_i;
    output logic               lookup2_done_o;
    output logic [DATA_W-1:0]  lookup2_val_o;

    rob_entry_t entries [ROB_SIZE];
    logic [TAG_W-1:0] head; ///< Pointer to the head of the ROB, indicating the next entry to be committed.
    logic [TAG_W-1:0] tail; ///< Pointer to the tail of the ROB, indicating where the next instruction will be allocated.
    logic [TAG_W:0] count; ///< Count of the number of valid entries currently in the ROB.

    rob_entry_t head_entry_w;
    assign head_entry_w = entries[head];

    rob_entry_t lookup1_entry_w, lookup2_entry_w;
    assign lookup1_entry_w = entries[lookup1_tag_i];
    assign lookup2_entry_w = entries[lookup2_tag_i];

    always_comb begin
        alloc_tag_o    = tail;
        full_o         = (count == ROB_SIZE);
        commit_valid_o = (head_entry_w.state == ROB_DONE);
        commit_entry_o = head_entry_w;
        lookup1_done_o = (lookup1_entry_w.state == ROB_DONE);
        lookup1_val_o  = lookup1_entry_w.result;
        lookup2_done_o = (lookup2_entry_w.state == ROB_DONE);
        lookup2_val_o  = lookup2_entry_w.result;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            head  <= '0;
            tail  <= '0;
            count <= '0;
            for (int i = 0; i < ROB_SIZE; i++) entries[i] <= '0;
        end else if (flush_i) begin
            head  <= 0;
            tail  <= 0;
            count <= 0;
            for (int i = 0; i < ROB_SIZE; i++) entries[i] <= '0;
        end else begin
            // CDB update: copy entry, check state, modify fields, write back whole struct
            if (cdb_i.valid) begin
                rob_entry_t cdb_e;
                cdb_e = entries[cdb_i.tag];
                if (cdb_e.state == ROB_IN_FLIGHT) begin
                    cdb_e.result = cdb_i.value;
                    cdb_e.state  = ROB_DONE;
                    entries[cdb_i.tag] <= cdb_e;
                end
            end

            // Branch resolution
            if (br_valid_i) begin
                rob_entry_t br_e;
                br_e = entries[br_tag_i];
                if (br_e.is_branch) begin
                    br_e.branch_taken  = br_taken_i;
                    br_e.branch_target = br_target_i;
                    br_e.state         = ROB_DONE;
                    entries[br_tag_i] <= br_e;
                end
            end

            // Dispatch: build a fresh entry and write it whole
            if (alloc_en_i && ~full_o) begin
                rob_entry_t new_e;
                new_e.state         = ROB_IN_FLIGHT;
                new_e.op            = alloc_instr_i.op;
                new_e.rd            = alloc_instr_i.rd;
                new_e.rd_fp         = alloc_instr_i.rd_fp;
                new_e.rd_valid      = alloc_instr_i.rd_valid;
                new_e.pc            = alloc_instr_i.pc;
                new_e.is_branch     = is_branch_op(alloc_instr_i.op) || is_jump_op(alloc_instr_i.op);
                new_e.result        = '0;
                new_e.branch_taken  = 1'b0;
                new_e.branch_target = '0;
                entries[tail] <= new_e;
                tail <= tail + 1;
            end

            // Commit: copy entry, clear state, write back whole struct
            if (commit_en_i && commit_valid_o) begin
                rob_entry_t commit_e;
                commit_e       = entries[head];
                commit_e.state = ROB_IDLE;
                entries[head] <= commit_e;
                head <= head + 1;
            end

            count <= count + (alloc_en_i & ~full_o) - (commit_en_i & commit_valid_o);
        end
    end

endmodule : rob_unit