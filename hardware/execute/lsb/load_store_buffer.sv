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
                         mem_wr_en_o, mem_wr_be_o, mem_wr_addr_o, mem_wr_data_o,
                         store_commit_i, store_commit_tag_i,
                         cdb_grant_i,
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
    output logic [3:0] mem_wr_be_o;
    output logic [PC_W-1:0] mem_wr_addr_o;
    output logic [DATA_W-1:0] mem_wr_data_o;

    input logic store_commit_i;
    input logic [TAG_W-1:0] store_commit_tag_i;
    input logic cdb_grant_i;

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
    opcode_e load_pending_op;
    logic [1:0] load_pending_byte_sel;
    logic [PC_W-1:0] load_pending_addr_r; ///< Saved load address; keeps mem_rd_addr stable until CDB grant.

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

    // Iverilog 13 crashes on unpacked_array[index].member.
    // Wire intermediaries let us do whole-struct reads, then member-access on a scalar.
    rs_entry_t head_entry_w;
    assign head_entry_w = entries[head];

    rs_entry_t sni_entry_w;
    assign sni_entry_w = entries[store_notify_idx];

    genvar i;
    generate
        for (i = 0; i < LSB_SIZE; i++) begin : gen_store_ready
            rs_entry_t entry_w;
            assign entry_w = entries[i];
            assign store_ready_vec[i] = valid[i] & is_store_op(entry_w.op) &
                                        entry_w.rs1_ready & entry_w.rs2_ready &
                                        ~store_notified[i];
        end
        assign store_chain[LSB_SIZE-1] = PTR_W'(LSB_SIZE-1);
        for (i = 0; i < LSB_SIZE-1; i++) begin : gen_store_chain
            assign store_chain[i] = store_ready_vec[i] ? PTR_W'(i) : store_chain[i+1];
        end
    endgenerate

    assign any_store_ready  = |store_ready_vec;
    assign store_notify_idx = store_chain[0];

    assign full          = (count == (PTR_W+1)'(LSB_SIZE));
    assign fu_ready_o    = ~full;
    assign head_ready    = head_entry_w.rs1_ready & head_entry_w.rs2_ready;
    assign head_is_load  = is_load_op(head_entry_w.op);
    assign head_is_store = is_store_op(head_entry_w.op);
    assign head_addr     = head_entry_w.rs1_val + head_entry_w.imm;

    assign do_pop = (valid[head] & ~load_pending & head_is_load & head_ready) |
                   (valid[head] & head_is_store & store_commit_i &
                    (head_entry_w.rob_tag == store_commit_tag_i));

    // Byte-enable computation for stores
    logic [3:0] store_be;
    always_comb begin
        case (head_entry_w.op)
            OP_SB:   store_be = 4'b0001 << head_addr[1:0];
            OP_SH:   store_be = head_addr[1] ? 4'b1100 : 4'b0011;
            default: store_be = 4'b1111; // SW, FSW
        endcase
    end

    // Store write data: rotate byte/halfword to correct lane
    logic [DATA_W-1:0] store_wdata;
    always_comb begin
        case (head_entry_w.op)
            OP_SB:   store_wdata = {4{head_entry_w.rs2_val[7:0]}};
            OP_SH:   store_wdata = {2{head_entry_w.rs2_val[15:0]}};
            default: store_wdata = head_entry_w.rs2_val;
        endcase
    end

    // Sub-word load result extraction
    logic [DATA_W-1:0] load_result;
    always_comb begin
        case (load_pending_op)
            OP_LB: begin
                case (load_pending_byte_sel)
                    2'd0: load_result = {{24{mem_rd_data_i[7]}},  mem_rd_data_i[7:0]};
                    2'd1: load_result = {{24{mem_rd_data_i[15]}}, mem_rd_data_i[15:8]};
                    2'd2: load_result = {{24{mem_rd_data_i[23]}}, mem_rd_data_i[23:16]};
                    default: load_result = {{24{mem_rd_data_i[31]}}, mem_rd_data_i[31:24]};
                endcase
            end
            OP_LBU: begin
                case (load_pending_byte_sel)
                    2'd0: load_result = {24'd0, mem_rd_data_i[7:0]};
                    2'd1: load_result = {24'd0, mem_rd_data_i[15:8]};
                    2'd2: load_result = {24'd0, mem_rd_data_i[23:16]};
                    default: load_result = {24'd0, mem_rd_data_i[31:24]};
                endcase
            end
            OP_LH:  load_result = load_pending_byte_sel[1] ?
                        {{16{mem_rd_data_i[31]}}, mem_rd_data_i[31:16]} :
                        {{16{mem_rd_data_i[15]}}, mem_rd_data_i[15:0]};
            OP_LHU: load_result = load_pending_byte_sel[1] ?
                        {16'd0, mem_rd_data_i[31:16]} :
                        {16'd0, mem_rd_data_i[15:0]};
            default: load_result = mem_rd_data_i; // LW, FLW
        endcase
    end

    assign mem_rd_addr_o = load_pending ? load_pending_addr_r : head_addr;
    assign mem_wr_en_o   = valid[head] & head_is_store & store_commit_i &
                           (head_entry_w.rob_tag == store_commit_tag_i);
    assign mem_wr_be_o   = store_be;
    assign mem_wr_addr_o = head_addr;
    assign mem_wr_data_o = store_wdata;

    assign cdb_valid_o = load_pending | any_store_ready;
    assign cdb_tag_o   = load_pending ? load_pending_tag : sni_entry_w.rob_tag;
    assign cdb_value_o = load_pending ? load_result      : '0;

    always_ff @(posedge clk) begin
        if (~rst_n) begin
            valid <= '0;
            store_notified <= '0;
            head <= '0;
            tail <= '0;
            count <= '0;
            load_pending <= 1'b0;
            load_pending_tag <= '0;
            load_pending_op <= OP_LW;
            load_pending_byte_sel <= '0;
            load_pending_addr_r <= '0;
            for (int j = 0; j < LSB_SIZE; j++) entries[j] <= '0;
        end else if (flush_i) begin 
            valid <= '0;
            store_notified <= '0;
            head <= '0;
            tail <= '0;
            count <= '0;
            load_pending <= 1'b0;
            load_pending_tag <= '0;
            load_pending_op <= OP_LW;
            load_pending_byte_sel <= '0;
            load_pending_addr_r <= '0;
            for (int j = 0; j < LSB_SIZE; j++) entries[j] <= '0;
        end else begin
            // Hold load_pending until the CDB arbiter grants the LSB.
            // Without this, the load result is lost if the CDB is busy the
            // cycle after the load fires (data_mem result is registered,
            // valid only while mem_rd_addr_o is stable).
            load_pending <= load_pending & ~cdb_grant_i;

            // Mark store as notified only when CDB arbiter grants the LSB
            if (~load_pending & any_store_ready & cdb_grant_i)
                store_notified[store_notify_idx] <= 1'b1;

            // CDB snoop: copy each entry to a local, update fields, write back whole struct
            for (int j = 0; j < LSB_SIZE; j++) begin
                rs_entry_t ej, upd;
                ej  = entries[j];
                upd = ej;
                if (valid[j] && cdb_i.valid) begin
                    if (~ej.rs1_ready & (ej.rs1_tag == cdb_i.tag)) begin
                        upd.rs1_ready = 1'b1;
                        upd.rs1_val   = cdb_i.value;
                    end
                    if (~ej.rs2_ready & (ej.rs2_tag == cdb_i.tag)) begin
                        upd.rs2_ready = 1'b1;
                        upd.rs2_val   = cdb_i.value;
                    end
                end
                entries[j] <= upd;
            end

            // Head: issue load (head_entry_w provides combinational member access)
            if (valid[head] & ~load_pending & head_is_load & head_ready) begin
                load_pending <= 1'b1;
                load_pending_tag <= head_entry_w.rob_tag;
                load_pending_op <= head_entry_w.op;
                load_pending_byte_sel <= head_addr[1:0];
                load_pending_addr_r <= head_addr;
                valid[head] <= 1'b0;
                store_notified[head] <= 1'b0;
                head <= head + 1;
            end

            // Head: commit store
            if (valid[head] & head_is_store & store_commit_i &
                (head_entry_w.rob_tag == store_commit_tag_i)) begin
                valid[head] <= 1'b0;
                store_notified[head] <= 1'b0;
                head <= head + 1;
            end

            // Push new entry (overrides CDB loop write for that slot)
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
