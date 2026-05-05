/**
 * @brief In-order load/store buffer.
 *
 * LSB_SIZE-entry FIFO. Snoops the CDB to capture operands. Processes the
 * head entry each cycle in order: loads send their address to data_mem and
 * broadcast the result one cycle later; stores fire their memory write when
 * commit_unit signals in-order retirement. Un-retired stores whose operands
 * are ready broadcast their ROB tag on the CDB (value=0) so the ROB can mark
 * them ROB_DONE and allow commit.
 *
 * @param clk/rst_n/flush_i Standard control.
 * @param issue_valid_i/issue_entry_i/fu_ready_o RS issue interface.
 * @param cdb_i CDB snoop for operand capture.
 * @param mem_rd_addr_o/mem_rd_data_i/mem_wr_en_o/mem_wr_addr_o/mem_wr_data_o Data memory.
 * @param store_commit_i/store_commit_tag_i Commit pulse + tag from commit_unit.
 * @param cdb_valid_o/cdb_tag_o/cdb_value_o CDB broadcast (load result or store-ready).
 */
module load_store_buffer(clk, rst_n, flush_i,
                         issue_valid_i, issue_entry_i, fu_ready_o,
                         cdb_i,
                         mem_rd_addr_o, mem_rd_data_i,
                         mem_wr_en_o, mem_wr_addr_o, mem_wr_data_o,
                         store_commit_i, store_commit_tag_i,
                         cdb_valid_o, cdb_tag_o, cdb_value_o);
    import rv32if_pkg::*;

    localparam PTR_W = $clog2(LSB_SIZE);

    input logic clk;
    input logic rst_n;
    input logic flush_i;

    input logic issue_valid_i;
    input rs_entry_t issue_entry_i;
    output logic fu_ready_o;

    input cdb_t cdb_i;

    output logic [PC_W-1:0] mem_rd_addr_o;
    input logic [DATA_W-1:0] mem_rd_data_i;
    output logic mem_wr_en_o;
    output logic [PC_W-1:0] mem_wr_addr_o;
    output logic [DATA_W-1:0] mem_wr_data_o;

    input logic store_commit_i;
    input logic [TAG_W-1:0] store_commit_tag_i;

    output logic cdb_valid_o;
    output logic [TAG_W-1:0] cdb_tag_o;
    output logic [DATA_W-1:0] cdb_value_o;

    rs_entry_t entries [LSB_SIZE];
    logic [LSB_SIZE-1:0] valid;
    logic [LSB_SIZE-1:0] store_notified; ///< Store operands already broadcast on CDB.

    logic [PTR_W-1:0] head, tail;
    logic [PTR_W:0] count;

    logic load_pending;
    logic [TAG_W-1:0] load_pending_tag;

    logic full;
    logic head_ready;
    logic head_is_load, head_is_store;
    logic [DATA_W-1:0] head_addr;
    logic do_pop;

    // Priority chain: first valid, ready, un-notified store
    logic [LSB_SIZE-1:0] store_ready_vec;
    logic [PTR_W-1:0] store_chain [LSB_SIZE];
    logic [PTR_W-1:0] store_notify_idx;
    logic any_store_ready;

    genvar i;
    generate
        for (i = 0; i < LSB_SIZE; i++) begin : gen_store_ready
            assign store_ready_vec[i] = valid[i] & is_store_op(entries[i].op) &
                                        entries[i].rs1_ready & entries[i].rs2_ready &
                                        ~store_notified[i];
        end
        assign store_chain[LSB_SIZE-1] = PTR_W'(LSB_SIZE-1);
        for (i = 0; i < LSB_SIZE-1; i++) begin : gen_store_chain
            assign store_chain[i] = store_ready_vec[i] ? PTR_W'(i) : store_chain[i+1];
        end
    endgenerate

    assign any_store_ready  = |store_ready_vec;
    assign store_notify_idx = store_chain[0];

    assign full = (count == (PTR_W+1)'(LSB_SIZE));
    assign fu_ready_o = ~full;
    assign head_ready = entries[head].rs1_ready & entries[head].rs2_ready;
    assign head_is_load = is_load_op(entries[head].op);
    assign head_is_store = is_store_op(entries[head].op);
    assign head_addr = entries[head].rs1_val + entries[head].imm;

    assign do_pop = (valid[head] & ~load_pending & head_is_load & head_ready) |
                   (valid[head] & head_is_store & store_commit_i &
                    (entries[head].rob_tag == store_commit_tag_i));

    assign mem_rd_addr_o = head_addr;
    assign mem_wr_en_o   = valid[head] & head_is_store & store_commit_i &
                           (entries[head].rob_tag == store_commit_tag_i);
    assign mem_wr_addr_o = head_addr;
    assign mem_wr_data_o = entries[head].rs2_val;

    // Load result has priority over store-ready notification
    assign cdb_valid_o = load_pending | any_store_ready;
    assign cdb_tag_o = load_pending ? load_pending_tag : entries[store_notify_idx].rob_tag;
    assign cdb_value_o = load_pending ? mem_rd_data_i    : '0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n || flush_i) begin
            valid <= '0;
            store_notified <= '0;
            head <= '0;
            tail <= '0;
            count <= '0;
            load_pending <= 1'b0;
            load_pending_tag <= '0;
            for (int j = 0; j < LSB_SIZE; j++) entries[j] <= '0;
        end else begin
            load_pending <= 1'b0;

            // Mark store as notified when CDB fires for it
            if (~load_pending & any_store_ready)
                store_notified[store_notify_idx] <= 1'b1;

            // CDB snoop: capture arriving operands
            if (cdb_i.valid) begin
                for (int j = 0; j < LSB_SIZE; j++) begin
                    if (valid[j]) begin
                        if (~entries[j].rs1_ready & (entries[j].rs1_tag == cdb_i.tag)) begin
                            entries[j].rs1_ready <= 1'b1;
                            entries[j].rs1_val <= cdb_i.value;
                        end
                        if (~entries[j].rs2_ready & (entries[j].rs2_tag == cdb_i.tag)) begin
                            entries[j].rs2_ready <= 1'b1;
                            entries[j].rs2_val <= cdb_i.value;
                        end
                    end
                end
            end

            // Head: issue load (address drives mem_rd_addr_o combinationally)
            if (valid[head] & ~load_pending & head_is_load & head_ready) begin
                load_pending <= 1'b1;
                load_pending_tag <= entries[head].rob_tag;
                valid[head] <= 1'b0;
                store_notified[head] <= 1'b0;
                head <= head + 1;
            end

            // Head: commit store (wr_en fires combinationally via mem_wr_en_o)
            if (valid[head] & head_is_store & store_commit_i &
                (entries[head].rob_tag == store_commit_tag_i)) begin
                valid[head] <= 1'b0;
                store_notified[head] <= 1'b0;
                head <= head + 1;
            end

            // Push new entry
            if (issue_valid_i & ~full) begin
                entries[tail] <= issue_entry_i;
                valid[tail] <= 1'b1;
                store_notified[tail] <= 1'b0;
                tail <= tail + 1;
            end

            count <= count + (issue_valid_i & ~full) - do_pop;
        end
    end

endmodule : load_store_buffer
