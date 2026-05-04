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
                commit_valid_o, commit_entry_o
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
    input logic commit_en_i; ///< Enable signal for committing the head entry of the ROB.
    output logic commit_valid_o; ///< Indicates that the head entry of the ROB is valid and can be committed.
    output rob_entry_t commit_entry_o; ///< Tag of the head entry being committed.

    rob_entry_t entries [ROB_SIZE]; ///< Array of ROB entries, each containing information about an instruction in flight.
    logic [TAG_W-1:0] head; ///< Pointer to the head of the ROB, indicating the next entry to be committed.
    logic [TAG_W-1:0] tail; ///< Pointer to the tail of the ROB, indicating where the next instruction will be allocated.
    logic [TAG_W:0] count; ///< Count of the number of valid entries currently in the ROB.

    always_comb begin 
        alloc_tag_o = tail; // The tag for the new entry is the current tail index
        full_o = (count == ROB_SIZE); // ROB is full when count reaches its maximum
        commit_valid_o = (entries[head].state == ROB_DONE); 
        commit_entry_o = entries[head];
    end 

    always_ff @(posedge clk or negedge rst_n) begin 
        if(~rst_n) begin 
            head <= '0;
            tail <= '0;
            count <= '0;
            entries <= '{default: '0}; // Invalidate all entries on reset
        end else if(flush_i) begin 
            head <= 0;
            tail <= 0;
            count <= 0;
            entries <= '{default: '0}; // Invalidate all entries on flush
        end else begin 
            // Common Data Bus update logic
            if(cdb_i.valid) begin 
                if(entries[cdb_i.tag].state == ROB_IN_FLIGHT) begin 
                    entries[cdb_i.tag].result <= cdb_i.value; // Update result for the entry when result is broadcast on CDB
                    entries[cdb_i.tag].state <= ROB_DONE; // Mark entry as done when result is broadcast on CDB
                end
            end 

            // Branch resolution logic
            if(br_valid_i) begin 
                if(entries[br_tag_i].is_branch) begin 
                    entries[br_tag_i].branch_taken <= br_taken_i; // Update branch outcome
                    entries[br_tag_i].branch_target <= br_target_i; // Update branch target
                    entries[br_tag_i].state <= ROB_DONE; // Mark entry as done when branch is resolved
                end
            end

            // Dispatch logic
            if(alloc_en_i && ~full_o) begin 
                entries[tail].state <= ROB_IN_FLIGHT; // Mark new entry as in-flight
                entries[tail].op <= alloc_instr_i.op; // Store opcode of the allocated instruction
                entries[tail].rd <= alloc_instr_i.rd; // Store destination register of the allocated instruction
                entries[tail].rd_fp <= alloc_instr_i.rd_fp; // Store whether destination register is FP
                entries[tail].rd_valid <= alloc_instr_i.rd_valid; // Store whether the instruction writes to a register
                entries[tail].pc <= alloc_instr_i.pc; // Store program counter of the allocated instruction
                entries[tail].is_branch <= is_branch_op(alloc_instr_i.op) || is_jump_op(alloc_instr_i.op); // Determine if the instruction is a branch
                entries[tail].result <= '0;
                entries[tail].branch_taken <= 1'b0;
                entries[tail].branch_target <= '0;

                tail <= tail + 1; // Move tail pointer to the next entry
            end

            // Commit logic
            if(commit_en_i && commit_valid_o) begin 
                entries[head].state <= ROB_IDLE; // Mark head entry as idle after commit
                head <= head + 1; // Move head pointer to the next entry
            end

            count <= count + (alloc_en_i & ~full_o) - (commit_en_i & commit_valid_o);/// Update count based on allocations and commits; increment on allocation if not full, decrement on commit if valid ensuers that count accurately reflects the number of valid entries in the ROB
        end 
    end 

endmodule : rob_unit