/**
 * @brief Top-level Tomasulo out-of-order pipeline (RV32IF).
 *
 * Wires: IQ, dispatch, ROB, RAT, regfile, 6 RSes, ALU, branch unit, fp_add,
 * fp_mul, fp_div, fp_cvt, LSB, CDB, commit_unit.
 *
 * ALU and branch results are latched here (those units have no CDB backpressure)
 * and held until the round-robin CDB arbiter grants them a slot.
 *
 * @param clk/rst_n Standard control.
 * @param fetch_valid_i/fetch_instr_i Decoded instruction from the fetch stage.
 * @param iq_full_o IQ full - stall fetch.
 * @param flush_o/redirect_pc_o Misprediction flush and restart PC.
 * @param mem_* Data memory ports (connect to data_mem in cpu.sv).
 */
module tomasulo_core(
    clk, rst_n,
    fetch_valid_i, fetch_instr_i, iq_full_o,
    flush_o, redirect_pc_o,
    mem_rd_addr_o, mem_rd_data_i,
    mem_wr_en_o, mem_wr_addr_o, mem_wr_data_o
);
    import rv32if_pkg::*;

    input  logic        clk;
    input  logic        rst_n;

    input  logic        fetch_valid_i;
    input  instr_t      fetch_instr_i;
    output logic        iq_full_o;

    output logic        flush_o;
    output logic [PC_W-1:0] redirect_pc_o;

    output logic [PC_W-1:0]   mem_rd_addr_o;
    input  logic [DATA_W-1:0] mem_rd_data_i;
    output logic               mem_wr_en_o;
    output logic [PC_W-1:0]   mem_wr_addr_o;
    output logic [DATA_W-1:0] mem_wr_data_o;

    // -------------------------------------------------------------------------
    // Global signals
    // -------------------------------------------------------------------------
    cdb_t              cdb_w;
    logic [NUM_FU-1:0] fu_grant_w;
    logic              flush_w;

    assign flush_o = flush_w;

    // -------------------------------------------------------------------------
    // Instruction Queue
    // -------------------------------------------------------------------------
    logic   iq_valid_w, iq_pop_w;
    instr_t iq_instr_w;

    instr_queue u_iq(
        .clk(clk), .rst_n(rst_n), .flush_i(flush_w),
        .push_en_i(fetch_valid_i & ~iq_full_o),
        .push_instr_i(fetch_instr_i), .full_o(iq_full_o),
        .pop_en_i(iq_pop_w), .instr_o(iq_instr_w), .valid_o(iq_valid_w)
    );

    // -------------------------------------------------------------------------
    // ROB
    // -------------------------------------------------------------------------
    logic         rob_full_w, commit_en_w;
    logic [TAG_W-1:0] rob_alloc_tag_w, rob_head_tag_w;
    logic         rob_commit_valid_w;
    rob_entry_t   rob_commit_entry_w;
    logic         rob_alloc_en_w;
    instr_t       rob_alloc_instr_w;

    logic         br_res_valid_w, br_res_taken_w;
    logic [TAG_W-1:0] br_res_tag_w;
    logic [PC_W-1:0]  br_res_target_w;

    // The ROB head tag (used by commit_unit) is alloc_tag_o from the previous
    // cycle when head == tail-1; simpler to track externally via a head register.
    // commit_unit only needs commit_tag_i = current head index. Since rob_unit
    // exposes alloc_tag_o = tail (not head), we track head separately.
    logic [TAG_W-1:0] rob_head_reg;
    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n || flush_w) rob_head_reg <= '0;
        else if (commit_en_w && rob_commit_valid_w) rob_head_reg <= rob_head_reg + 1;
    end

    rob_unit u_rob(
        .clk(clk), .rst_n(rst_n), .flush_i(flush_w),
        .alloc_en_i(rob_alloc_en_w), .alloc_instr_i(rob_alloc_instr_w),
        .alloc_tag_o(rob_alloc_tag_w), .full_o(rob_full_w),
        .cdb_i(cdb_w),
        .br_valid_i(br_res_valid_w), .br_tag_i(br_res_tag_w),
        .br_taken_i(br_res_taken_w), .br_target_i(br_res_target_w),
        .commit_en_i(commit_en_w),
        .commit_valid_o(rob_commit_valid_w), .commit_entry_o(rob_commit_entry_w)
    );

    // -------------------------------------------------------------------------
    // RAT
    // -------------------------------------------------------------------------
    logic [ARCH_W-1:0] x_rs1_addr_w, x_rs2_addr_w, f_rs1_addr_w, f_rs2_addr_w;
    logic [TAG_W-1:0]  x_rs1_tag_w,  x_rs2_tag_w,  f_rs1_tag_w,  f_rs2_tag_w;
    logic              x_rs1_valid_w, x_rs2_valid_w, f_rs1_valid_w, f_rs2_valid_w;
    logic              x_map_en_w,  f_map_en_w;
    logic [ARCH_W-1:0] x_map_addr_w, f_map_addr_w;
    logic [TAG_W-1:0]  x_map_tag_w,  f_map_tag_w;
    logic              x_commit_en_w, f_commit_en_w;
    logic [ARCH_W-1:0] x_commit_addr_w, f_commit_addr_w;
    logic [TAG_W-1:0]  x_commit_tag_w,  f_commit_tag_w;

    rat_table u_rat(
        .clk(clk), .rst_n(rst_n), .flush_i(flush_w),
        .x_rs1_addr_i(x_rs1_addr_w), .x_rs1_tag_o(x_rs1_tag_w), .x_rs1_valid_o(x_rs1_valid_w),
        .x_rs2_addr_i(x_rs2_addr_w), .x_rs2_tag_o(x_rs2_tag_w), .x_rs2_valid_o(x_rs2_valid_w),
        .f_rs1_addr_i(f_rs1_addr_w), .f_rs1_tag_o(f_rs1_tag_w), .f_rs1_valid_o(f_rs1_valid_w),
        .f_rs2_addr_i(f_rs2_addr_w), .f_rs2_tag_o(f_rs2_tag_w), .f_rs2_valid_o(f_rs2_valid_w),
        .x_map_en_i(x_map_en_w), .x_map_addr_i(x_map_addr_w), .x_map_tag_i(x_map_tag_w),
        .f_map_en_i(f_map_en_w), .f_map_addr_i(f_map_addr_w), .f_map_tag_i(f_map_tag_w),
        .x_commit_en_i(x_commit_en_w), .x_commit_addr_i(x_commit_addr_w), .x_commit_tag_i(x_commit_tag_w),
        .f_commit_en_i(f_commit_en_w), .f_commit_addr_i(f_commit_addr_w), .f_commit_tag_i(f_commit_tag_w)
    );

    // -------------------------------------------------------------------------
    // Register File
    // -------------------------------------------------------------------------
    logic [DATA_W-1:0] x_rs1_val_w, x_rs2_val_w, f_rs1_val_w, f_rs2_val_w;
    logic              x_wr_en_w,   f_wr_en_w;
    logic [ARCH_W-1:0] x_wr_addr_w, f_wr_addr_w;
    logic [DATA_W-1:0] x_wr_val_w,  f_wr_val_w;

    regfile u_rf(
        .clk(clk), .rst_n(rst_n),
        .x_rs1_addr_i(x_rs1_addr_w), .x_rs1_val_o(x_rs1_val_w),
        .x_rs2_addr_i(x_rs2_addr_w), .x_rs2_val_o(x_rs2_val_w),
        .x_wr_en_i(x_wr_en_w), .x_wr_addr_i(x_wr_addr_w), .x_wr_val_i(x_wr_val_w),
        .f_rs1_addr_i(f_rs1_addr_w), .f_rs1_val_o(f_rs1_val_w),
        .f_rs2_addr_i(f_rs2_addr_w), .f_rs2_val_o(f_rs2_val_w),
        .f_wr_en_i(f_wr_en_w), .f_wr_addr_i(f_wr_addr_w), .f_wr_val_i(f_wr_val_w)
    );

    // -------------------------------------------------------------------------
    // Dispatch
    // -------------------------------------------------------------------------
    logic      alu_disp_valid_w,    br_disp_valid_w;
    logic      fp_add_disp_valid_w, fp_mul_disp_valid_w, fp_div_disp_valid_w;
    logic      lsb_disp_valid_w,    fp_cvt_disp_valid_w;
    rs_entry_t alu_disp_entry_w,    br_disp_entry_w;
    rs_entry_t fp_add_disp_entry_w, fp_mul_disp_entry_w, fp_div_disp_entry_w;
    rs_entry_t lsb_disp_entry_w,    fp_cvt_disp_entry_w;

    logic alu_rs_full_w,    br_rs_full_w;
    logic fp_add_rs_full_w, fp_mul_rs_full_w, fp_div_rs_full_w;
    logic lsb_ready_w,      fp_cvt_rs_full_w;

    dispatch u_dispatch(
        .iq_valid_i(iq_valid_w), .iq_instr_i(iq_instr_w), .iq_rd_en_o(iq_pop_w),
        .rob_full_i(rob_full_w), .rob_alloc_en_o(rob_alloc_en_w),
        .rob_alloc_instr_o(rob_alloc_instr_w), .rob_alloc_tag_i(rob_alloc_tag_w),
        .x_rs1_addr_o(x_rs1_addr_w), .x_rs1_tag_i(x_rs1_tag_w), .x_rs1_valid_i(x_rs1_valid_w),
        .x_rs2_addr_o(x_rs2_addr_w), .x_rs2_tag_i(x_rs2_tag_w), .x_rs2_valid_i(x_rs2_valid_w),
        .f_rs1_addr_o(f_rs1_addr_w), .f_rs1_tag_i(f_rs1_tag_w), .f_rs1_valid_i(f_rs1_valid_w),
        .f_rs2_addr_o(f_rs2_addr_w), .f_rs2_tag_i(f_rs2_tag_w), .f_rs2_valid_i(f_rs2_valid_w),
        .x_map_en_o(x_map_en_w), .x_map_addr_o(x_map_addr_w), .x_map_tag_o(x_map_tag_w),
        .f_map_en_o(f_map_en_w), .f_map_addr_o(f_map_addr_w), .f_map_tag_o(f_map_tag_w),
        .x_rs1_val_i(x_rs1_val_w), .x_rs2_val_i(x_rs2_val_w),
        .f_rs1_val_i(f_rs1_val_w), .f_rs2_val_i(f_rs2_val_w),
        .alu_valid_o(alu_disp_valid_w),     .alu_full_i(alu_rs_full_w),     .alu_entry_o(alu_disp_entry_w),
        .br_valid_o(br_disp_valid_w),        .br_full_i(br_rs_full_w),        .br_entry_o(br_disp_entry_w),
        .fp_add_valid_o(fp_add_disp_valid_w),.fp_add_full_i(fp_add_rs_full_w),.fp_add_entry_o(fp_add_disp_entry_w),
        .fp_mul_valid_o(fp_mul_disp_valid_w),.fp_mul_full_i(fp_mul_rs_full_w),.fp_mul_entry_o(fp_mul_disp_entry_w),
        .fp_div_valid_o(fp_div_disp_valid_w),.fp_div_full_i(fp_div_rs_full_w),.fp_div_entry_o(fp_div_disp_entry_w),
        .lsb_valid_o(lsb_disp_valid_w),      .lsb_full_i(~lsb_ready_w),       .lsb_entry_o(lsb_disp_entry_w),
        .fp_cvt_valid_o(fp_cvt_disp_valid_w),.fp_cvt_full_i(fp_cvt_rs_full_w),.fp_cvt_entry_o(fp_cvt_disp_entry_w)
    );

    // -------------------------------------------------------------------------
    // Reservation Stations
    // -------------------------------------------------------------------------
    logic      alu_issue_valid_w,    br_issue_valid_w;
    logic      fp_add_issue_valid_w, fp_mul_issue_valid_w;
    logic      fp_div_issue_valid_w, fp_cvt_issue_valid_w;
    rs_entry_t alu_issue_entry_w,    br_issue_entry_w;
    rs_entry_t fp_add_issue_entry_w, fp_mul_issue_entry_w;
    rs_entry_t fp_div_issue_entry_w, fp_cvt_issue_entry_w;

    logic alu_rs_fu_ready_w, br_rs_fu_ready_w;
    logic fp_add_fu_ready_w, fp_mul_fu_ready_w, fp_div_fu_ready_w, fp_cvt_fu_ready_w;

    reservation_station #(.SIZE(RS_ALU_SIZE)) u_rs_alu(
        .clk(clk), .rst_n(rst_n), .flush_i(flush_w),
        .dispatch_valid_i(alu_disp_valid_w), .dispatch_entry_i(alu_disp_entry_w),
        .full_o(alu_rs_full_w), .cdb_i(cdb_w),
        .issue_valid_o(alu_issue_valid_w), .issue_entry_o(alu_issue_entry_w),
        .fu_ready_i(alu_rs_fu_ready_w)
    );

    reservation_station #(.SIZE(RS_BRANCH_SIZE)) u_rs_br(
        .clk(clk), .rst_n(rst_n), .flush_i(flush_w),
        .dispatch_valid_i(br_disp_valid_w), .dispatch_entry_i(br_disp_entry_w),
        .full_o(br_rs_full_w), .cdb_i(cdb_w),
        .issue_valid_o(br_issue_valid_w), .issue_entry_o(br_issue_entry_w),
        .fu_ready_i(br_rs_fu_ready_w)
    );

    reservation_station #(.SIZE(RS_FP_ADDSUB_SIZE)) u_rs_fp_add(
        .clk(clk), .rst_n(rst_n), .flush_i(flush_w),
        .dispatch_valid_i(fp_add_disp_valid_w), .dispatch_entry_i(fp_add_disp_entry_w),
        .full_o(fp_add_rs_full_w), .cdb_i(cdb_w),
        .issue_valid_o(fp_add_issue_valid_w), .issue_entry_o(fp_add_issue_entry_w),
        .fu_ready_i(fp_add_fu_ready_w)
    );

    reservation_station #(.SIZE(RS_FP_MUL_SIZE)) u_rs_fp_mul(
        .clk(clk), .rst_n(rst_n), .flush_i(flush_w),
        .dispatch_valid_i(fp_mul_disp_valid_w), .dispatch_entry_i(fp_mul_disp_entry_w),
        .full_o(fp_mul_rs_full_w), .cdb_i(cdb_w),
        .issue_valid_o(fp_mul_issue_valid_w), .issue_entry_o(fp_mul_issue_entry_w),
        .fu_ready_i(fp_mul_fu_ready_w)
    );

    reservation_station #(.SIZE(RS_FP_DIV_SIZE)) u_rs_fp_div(
        .clk(clk), .rst_n(rst_n), .flush_i(flush_w),
        .dispatch_valid_i(fp_div_disp_valid_w), .dispatch_entry_i(fp_div_disp_entry_w),
        .full_o(fp_div_rs_full_w), .cdb_i(cdb_w),
        .issue_valid_o(fp_div_issue_valid_w), .issue_entry_o(fp_div_issue_entry_w),
        .fu_ready_i(fp_div_fu_ready_w)
    );

    reservation_station #(.SIZE(RS_FP_CVT_SIZE)) u_rs_fp_cvt(
        .clk(clk), .rst_n(rst_n), .flush_i(flush_w),
        .dispatch_valid_i(fp_cvt_disp_valid_w), .dispatch_entry_i(fp_cvt_disp_entry_w),
        .full_o(fp_cvt_rs_full_w), .cdb_i(cdb_w),
        .issue_valid_o(fp_cvt_issue_valid_w), .issue_entry_o(fp_cvt_issue_entry_w),
        .fu_ready_i(fp_cvt_fu_ready_w)
    );

    // -------------------------------------------------------------------------
    // ALU + result latch (holds until CDB slot 0 is granted)
    // -------------------------------------------------------------------------
    logic          alu_valid_o;
    logic [TAG_W-1:0]  alu_tag_o;
    logic [DATA_W-1:0] alu_result_o;

    alu_int u_alu(
        .clk(clk), .rst_n(rst_n),
        .op_i(alu_issue_entry_w.op), .valid_i(alu_issue_valid_w),
        .tag_i(alu_issue_entry_w.rob_tag),
        .rs1_i(alu_issue_entry_w.rs1_val), .rs2_i(alu_issue_entry_w.rs2_val),
        .imm_i(alu_issue_entry_w.imm),
        .valid_o(alu_valid_o), .tag_o(alu_tag_o), .result_o(alu_result_o)
    );

    cdb_t alu_cdb;
    assign alu_rs_fu_ready_w = ~alu_cdb.valid | fu_grant_w[0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n || flush_w)
            alu_cdb <= '{valid: 1'b0, tag: '0, value: '0};
        else begin
            if (fu_grant_w[0])         alu_cdb.valid <= 1'b0;
            else if (alu_valid_o) begin
                alu_cdb <= '{valid: 1'b1, tag: alu_tag_o, value: alu_result_o};
            end
        end
    end

    // -------------------------------------------------------------------------
    // Branch unit + result latch
    // -------------------------------------------------------------------------
    logic          br_valid_o, br_taken_o;
    logic [TAG_W-1:0]  br_tag_o;
    logic [PC_W-1:0]   br_target_o;

    // Delay op/pc by 1 cycle (branch_unit is registered) to compute PC+4
    opcode_e     br_op_d;
    logic [PC_W-1:0] br_pc_d;
    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin br_op_d <= OP_NOP; br_pc_d <= '0; end
        else        begin br_op_d <= br_issue_entry_w.op; br_pc_d <= br_issue_entry_w.pc; end
    end

    branch_unit u_br(
        .clk(clk), .rst_n(rst_n),
        .valid_i(br_issue_valid_w), .op_i(br_issue_entry_w.op),
        .tag_i(br_issue_entry_w.rob_tag),
        .rs1_i(br_issue_entry_w.rs1_val), .rs2_i(br_issue_entry_w.rs2_val),
        .imm_i(br_issue_entry_w.imm), .pc_i(br_issue_entry_w.pc),
        .valid_o(br_valid_o), .tag_o(br_tag_o),
        .target_o(br_target_o), .taken_o(br_taken_o)
    );

    assign br_res_valid_w  = br_valid_o;
    assign br_res_tag_w    = br_tag_o;
    assign br_res_taken_w  = br_taken_o;
    assign br_res_target_w = br_target_o;

    // CDB value: PC+4 (return address) for JAL/JALR; target for branches.
    wire [DATA_W-1:0] br_cdb_val =
        ((br_op_d == OP_JAL) || (br_op_d == OP_JALR)) ? (br_pc_d + 32'd4) : br_target_o;

    cdb_t br_cdb;
    assign br_rs_fu_ready_w = ~br_cdb.valid | fu_grant_w[1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n || flush_w)
            br_cdb <= '{valid: 1'b0, tag: '0, value: '0};
        else begin
            if (fu_grant_w[1])        br_cdb.valid <= 1'b0;
            else if (br_valid_o) begin
                br_cdb <= '{valid: 1'b1, tag: br_tag_o, value: br_cdb_val};
            end
        end
    end

    // -------------------------------------------------------------------------
    // FP add (FU 2)
    // -------------------------------------------------------------------------
    logic          fp_add_cdb_valid_w;
    logic [TAG_W-1:0]  fp_add_cdb_tag_w;
    logic [DATA_W-1:0] fp_add_cdb_result_w;

    fp_add u_fp_add(
        .clk(clk), .rst_n(rst_n), .flush_i(flush_w),
        .valid_i(fp_add_issue_valid_w), .op_i(fp_add_issue_entry_w.op),
        .tag_i(fp_add_issue_entry_w.rob_tag),
        .rs1_i(fp_add_issue_entry_w.rs1_val), .rs2_i(fp_add_issue_entry_w.rs2_val),
        .cdb_grant_i(fu_grant_w[2]), .fu_ready_o(fp_add_fu_ready_w),
        .cdb_valid_o(fp_add_cdb_valid_w), .cdb_tag_o(fp_add_cdb_tag_w),
        .cdb_result_o(fp_add_cdb_result_w)
    );

    // -------------------------------------------------------------------------
    // FP mul (FU 3)
    // -------------------------------------------------------------------------
    logic          fp_mul_cdb_valid_w;
    logic [TAG_W-1:0]  fp_mul_cdb_tag_w;
    logic [DATA_W-1:0] fp_mul_cdb_result_w;

    fp_mul u_fp_mul(
        .clk(clk), .rst_n(rst_n), .flush_i(flush_w),
        .valid_i(fp_mul_issue_valid_w),
        .tag_i(fp_mul_issue_entry_w.rob_tag),
        .rs1_i(fp_mul_issue_entry_w.rs1_val), .rs2_i(fp_mul_issue_entry_w.rs2_val),
        .cdb_grant_i(fu_grant_w[3]), .fu_ready_o(fp_mul_fu_ready_w),
        .cdb_valid_o(fp_mul_cdb_valid_w), .cdb_tag_o(fp_mul_cdb_tag_w),
        .cdb_result_o(fp_mul_cdb_result_w)
    );

    // -------------------------------------------------------------------------
    // FP div (FU 4)
    // -------------------------------------------------------------------------
    logic          fp_div_cdb_valid_w;
    logic [TAG_W-1:0]  fp_div_cdb_tag_w;
    logic [DATA_W-1:0] fp_div_cdb_result_w;

    fp_div u_fp_div(
        .clk(clk), .rst_n(rst_n), .flush_i(flush_w),
        .valid_i(fp_div_issue_valid_w),
        .tag_i(fp_div_issue_entry_w.rob_tag),
        .rs1_i(fp_div_issue_entry_w.rs1_val), .rs2_i(fp_div_issue_entry_w.rs2_val),
        .cdb_grant_i(fu_grant_w[4]), .fu_ready_o(fp_div_fu_ready_w),
        .cdb_valid_o(fp_div_cdb_valid_w), .cdb_tag_o(fp_div_cdb_tag_w),
        .cdb_result_o(fp_div_cdb_result_w)
    );

    // -------------------------------------------------------------------------
    // Load/Store Buffer (RS+FU combined, FU 5)
    // -------------------------------------------------------------------------
    logic          lsb_cdb_valid_w;
    logic [TAG_W-1:0]  lsb_cdb_tag_w;
    logic [DATA_W-1:0] lsb_cdb_value_w;
    logic          store_commit_w;
    logic [TAG_W-1:0]  store_commit_tag_w;

    load_store_buffer u_lsb(
        .clk(clk), .rst_n(rst_n), .flush_i(flush_w),
        .issue_valid_i(lsb_disp_valid_w), .issue_entry_i(lsb_disp_entry_w),
        .fu_ready_o(lsb_ready_w),
        .cdb_i(cdb_w),
        .mem_rd_addr_o(mem_rd_addr_o), .mem_rd_data_i(mem_rd_data_i),
        .mem_wr_en_o(mem_wr_en_o), .mem_wr_addr_o(mem_wr_addr_o),
        .mem_wr_data_o(mem_wr_data_o),
        .store_commit_i(store_commit_w), .store_commit_tag_i(store_commit_tag_w),
        .cdb_valid_o(lsb_cdb_valid_w), .cdb_tag_o(lsb_cdb_tag_w),
        .cdb_value_o(lsb_cdb_value_w)
    );

    // -------------------------------------------------------------------------
    // FP cvt (FU 6)
    // -------------------------------------------------------------------------
    logic          fp_cvt_cdb_valid_w;
    logic [TAG_W-1:0]  fp_cvt_cdb_tag_w;
    logic [DATA_W-1:0] fp_cvt_cdb_result_w;

    fp_cvt u_fp_cvt(
        .clk(clk), .rst_n(rst_n), .flush_i(flush_w),
        .valid_i(fp_cvt_issue_valid_w), .op_i(fp_cvt_issue_entry_w.op),
        .tag_i(fp_cvt_issue_entry_w.rob_tag),
        .rs1_i(fp_cvt_issue_entry_w.rs1_val),
        .cdb_grant_i(fu_grant_w[6]), .fu_ready_o(fp_cvt_fu_ready_w),
        .cdb_valid_o(fp_cvt_cdb_valid_w), .cdb_tag_o(fp_cvt_cdb_tag_w),
        .cdb_result_o(fp_cvt_cdb_result_w)
    );

    // -------------------------------------------------------------------------
    // CDB arbiter
    // -------------------------------------------------------------------------
    cdb_t fu_results [NUM_FU];
    assign fu_results[0] = alu_cdb;
    assign fu_results[1] = br_cdb;
    assign fu_results[2] = '{valid: fp_add_cdb_valid_w, tag: fp_add_cdb_tag_w, value: fp_add_cdb_result_w};
    assign fu_results[3] = '{valid: fp_mul_cdb_valid_w, tag: fp_mul_cdb_tag_w, value: fp_mul_cdb_result_w};
    assign fu_results[4] = '{valid: fp_div_cdb_valid_w, tag: fp_div_cdb_tag_w, value: fp_div_cdb_result_w};
    assign fu_results[5] = '{valid: lsb_cdb_valid_w,    tag: lsb_cdb_tag_w,    value: lsb_cdb_value_w};
    assign fu_results[6] = '{valid: fp_cvt_cdb_valid_w, tag: fp_cvt_cdb_tag_w, value: fp_cvt_cdb_result_w};

    cdb u_cdb(
        .clk(clk), .rst_n(rst_n),
        .fu_results_i(fu_results),
        .cdb_o(cdb_w), .fu_grant_o(fu_grant_w)
    );

    // -------------------------------------------------------------------------
    // Commit unit
    // -------------------------------------------------------------------------
    commit_unit u_commit(
        .commit_valid_i(rob_commit_valid_w),
        .commit_entry_i(rob_commit_entry_w),
        .commit_tag_i(rob_head_reg),
        .commit_en_o(commit_en_w),
        .x_wr_en_o(x_wr_en_w),       .x_wr_addr_o(x_wr_addr_w),       .x_wr_val_o(x_wr_val_w),
        .f_wr_en_o(f_wr_en_w),        .f_wr_addr_o(f_wr_addr_w),        .f_wr_val_o(f_wr_val_w),
        .x_commit_en_o(x_commit_en_w),.x_commit_addr_o(x_commit_addr_w),.x_commit_tag_o(x_commit_tag_w),
        .f_commit_en_o(f_commit_en_w),.f_commit_addr_o(f_commit_addr_w),.f_commit_tag_o(f_commit_tag_w),
        .flush_o(flush_w), .redirect_pc_o(redirect_pc_o),
        .store_commit_o(store_commit_w), .store_commit_tag_o(store_commit_tag_w)
    );

endmodule : tomasulo_core
