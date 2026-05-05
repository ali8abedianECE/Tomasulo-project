/**
 * @brief Parameterized reservation station for one functional unit class.
 *
 * Holds up to SIZE in-flight instructions waiting for their operands.
 * Each cycle: the CDB is snooped to capture arriving values, dispatch writes
 * one new entry to the first free slot, and the first slot with both operands
 * ready is issued to the functional unit (when fu_ready_i is high).
 *
 * Priority: lowest slot index wins for both dispatch and issue.
 * CDB captures take effect the cycle AFTER the broadcast (registered).
 *
 * @param SIZE Number of slots (set per RS type via parameter override).
 * @param clk Rising-edge clock.
 * @param rst_n Active-low async reset.
 * @param flush_i Synchronous flush - clears all slots.
 * @param dispatch_valid_i / dispatch_entry_i New entry from dispatch unit.
 * @param full_o All slots occupied - dispatch must stall.
 * @param cdb_i CDB broadcast - captured into matching slots.
 * @param issue_valid_o An entry with both operands ready is being issued.
 * @param issue_entry_o The rs_entry_t being issued to the functional unit.
 * @param fu_ready_i FU can accept a new instruction this cycle.
 */
module reservation_station(clk, rst_n, flush_i,
                            dispatch_valid_i, dispatch_entry_i,
                            full_o,
                            cdb_i,
                            issue_valid_o, issue_entry_o,
                            fu_ready_i
                            );
    import rv32if_pkg::*;
    parameter SIZE = 4;

    input logic clk;
    input logic rst_n;
    input logic flush_i;

    input logic dispatch_valid_i;
    input rs_entry_t dispatch_entry_i;
    output logic full_o;

    input cdb_t cdb_i;

    output logic issue_valid_o;
    output rs_entry_t issue_entry_o;
    input logic fu_ready_i;

    localparam IDX_W = $clog2(SIZE);

    logic [SIZE-1:0] busy;       ///< Slot occupied flags.
    rs_entry_t slots [SIZE]; ///< Slot data.

    logic [SIZE-1:0] ready_vec;   ///< busy AND rs1_ready AND rs2_ready per slot.
    logic [IDX_W-1:0] issue_idx;   ///< Lowest-index ready slot.
    logic [IDX_W-1:0] dispatch_idx; ///< Lowest-index free slot.
    logic [IDX_W-1:0] issue_chain[SIZE]; ///< Priority chain for issue.
    logic [IDX_W-1:0] dispatch_chain[SIZE]; ///< Priority chain for dispatch.

    assign full_o = &busy;
    assign issue_valid_o = (|ready_vec) && fu_ready_i;
    assign issue_entry_o = slots[issue_idx];
    assign issue_idx = issue_chain[0];
    assign dispatch_idx = dispatch_chain[0];

    // Ready vector and priority chains via genvar
    genvar i;
    generate
        for (i = 0; i < SIZE; i++) begin : gen_ready
            assign ready_vec[i] = busy[i] && slots[i].rs1_ready && slots[i].rs2_ready;
        end

        // Issue: lowest ready slot (chain from high to low, slot 0 wins)
        assign issue_chain[SIZE-1] = IDX_W'(SIZE-1);
        for (i = 0; i < SIZE-1; i++) begin : gen_issue_chain
            assign issue_chain[i] = ready_vec[i] ? IDX_W'(i) : issue_chain[i+1];
        end

        // Dispatch: lowest free slot
        assign dispatch_chain[SIZE-1] = IDX_W'(SIZE-1);
        for (i = 0; i < SIZE-1; i++) begin : gen_dispatch_chain
            assign dispatch_chain[i] = ~busy[i] ? IDX_W'(i) : dispatch_chain[i+1];
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n || flush_i) begin
            busy <= '0;
            for (int j = 0; j < SIZE; j++) slots[j] <= '0;
        end else begin
            // CDB snoop: capture arriving values into waiting slots
            if (cdb_i.valid) begin
                for (int j = 0; j < SIZE; j++) begin
                    if (busy[j]) begin
                        if (!slots[j].rs1_ready && slots[j].rs1_tag == cdb_i.tag) begin
                            slots[j].rs1_ready <= 1'b1;
                            slots[j].rs1_val <= cdb_i.value;
                        end
                        if (!slots[j].rs2_ready && slots[j].rs2_tag == cdb_i.tag) begin
                            slots[j].rs2_ready <= 1'b1;
                            slots[j].rs2_val <= cdb_i.value;
                        end
                    end
                end
            end

            // Dispatch: write new entry into first free slot
            if (dispatch_valid_i && !full_o) begin
                slots[dispatch_idx] <= dispatch_entry_i;
                busy[dispatch_idx]  <= 1'b1;
            end

            // Issue: clear the issued slot
            if (issue_valid_o) begin
                busy[issue_idx] <= 1'b0;
            end
        end
    end

endmodule : reservation_station
