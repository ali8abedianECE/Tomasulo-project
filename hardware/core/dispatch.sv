/**
 * @brief Combinational dispatch unit - routes IQ head to the correct RS each cycle.
 *
 * Reads the RAT to resolve source operands: if a register is in-flight the RS
 * entry carries the ROB tag to snoop; if ready the register file value is
 * captured directly. Allocates a ROB slot and writes one rs_entry_t to the
 * target RS. Updates the RAT destination mapping with the new ROB tag.
 * Stalls (no pop, no alloc) when the ROB or target RS is full.
 *
 * @param iq_valid_i / iq_instr_i Instruction at the head of the IQ.
 * @param iq_rd_en_o Pop signal - dequeues the instruction when dispatch succeeds.
 * @param rob_full_i / rob_alloc_en_o / rob_alloc_instr_o / rob_alloc_tag_i ROB allocation.
 * @param x_rsf_rs* RAT lookup outputs and regfile values for rs1/rs2.
 * @param x_mapf_map* RAT write port to map rd to the new ROB tag.
 * @param *_valid_o / *_full_i / *_entry_o Per-RS dispatch interface.
 */
module dispatch(// Instruction Queue interface
                iq_valid_i, iq_instr_i, iq_rd_en_o,

                // ROB interface allocation
                rob_full_i, rob_alloc_en_o, rob_alloc_instr_o, rob_alloc_tag_i,

                // RAT lookup for source registers
                x_rs1_addr_o, x_rs1_tag_i, x_rs1_valid_i,
                x_rs2_addr_o, x_rs2_tag_i, x_rs2_valid_i,
                f_rs1_addr_o, f_rs1_tag_i, f_rs1_valid_i,
                f_rs2_addr_o, f_rs2_tag_i, f_rs2_valid_i,

                // RAT mapping for destination register on dispatch
                x_map_en_o, x_map_addr_o, x_map_tag_o,
                f_map_en_o, f_map_addr_o, f_map_tag_o,

                // Regfile read interface for source operands
                x_rs1_val_i, x_rs2_val_i,
                f_rs1_val_i, f_rs2_val_i,

                // Output to reservation stations
                alu_valid_o, alu_full_i, alu_entry_o,
                br_valid_o, br_full_i, br_entry_o,
                fp_add_valid_o, fp_add_full_i, fp_add_entry_o,
                fp_mul_valid_o, fp_mul_full_i, fp_mul_entry_o,
                fp_div_valid_o, fp_div_full_i, fp_div_entry_o,
                lsb_valid_o, lsb_full_i, lsb_entry_o,
                fp_cvt_valid_o, fp_cvt_full_i, fp_cvt_entry_o
                );
    import rv32if_pkg::*;

    // Instruction queue
    input logic iq_valid_i;
    input instr_t iq_instr_i;
    output logic iq_rd_en_o;

    // ROB allocation
    input logic rob_full_i;
    output logic rob_alloc_en_o;
    output instr_t rob_alloc_instr_o;
    input logic [TAG_W-1:0] rob_alloc_tag_i;

    // RAT source lookups
    output logic [ARCH_W-1:0] x_rs1_addr_o;
    input logic [TAG_W-1:0]  x_rs1_tag_i;
    input logic x_rs1_valid_i;

    output logic [ARCH_W-1:0] x_rs2_addr_o;
    input logic [TAG_W-1:0]  x_rs2_tag_i;
    input logic x_rs2_valid_i;

    output logic [ARCH_W-1:0] f_rs1_addr_o;
    input logic [TAG_W-1:0]  f_rs1_tag_i;
    input logic f_rs1_valid_i;

    output logic [ARCH_W-1:0] f_rs2_addr_o;
    input logic [TAG_W-1:0]  f_rs2_tag_i;
    input logic f_rs2_valid_i;

    // RAT destination mapping
    output logic x_map_en_o;
    output logic [ARCH_W-1:0] x_map_addr_o;
    output logic [TAG_W-1:0] x_map_tag_o;

    output logic f_map_en_o;
    output logic [ARCH_W-1:0] f_map_addr_o;
    output logic [TAG_W-1:0] f_map_tag_o;

    // Regfile values
    input logic [DATA_W-1:0] x_rs1_val_i;
    input logic [DATA_W-1:0] x_rs2_val_i;
    input logic [DATA_W-1:0] f_rs1_val_i;
    input logic [DATA_W-1:0] f_rs2_val_i;

    // Reservation station interfaces
    output logic alu_valid_o;
    input logic alu_full_i;
    output rs_entry_t alu_entry_o;

    output logic br_valid_o;
    input logic br_full_i;
    output rs_entry_t br_entry_o;

    output logic fp_add_valid_o;
    input logic fp_add_full_i;
    output rs_entry_t fp_add_entry_o;

    output logic fp_mul_valid_o;
    input logic fp_mul_full_i;
    output rs_entry_t fp_mul_entry_o;

    output logic fp_div_valid_o;
    input logic fp_div_full_i;
    output rs_entry_t fp_div_entry_o;

    output logic lsb_valid_o;
    input logic lsb_full_i;
    output rs_entry_t lsb_entry_o;

    output logic fp_cvt_valid_o;
    input logic fp_cvt_full_i;
    output rs_entry_t fp_cvt_entry_o;

    // RAT address outputs are pure wires to the instruction's rs1/rs2 fields
    assign x_rs1_addr_o = iq_instr_i.rs1;
    assign x_rs2_addr_o = iq_instr_i.rs2;
    assign f_rs1_addr_o = iq_instr_i.rs1;
    assign f_rs2_addr_o = iq_instr_i.rs2;

    rs_entry_t entry; ///< Dispatch entry built from current IQ head.
    logic target_full; ///< Full flag of the RS targeted by current instruction.

    // Determine which RS the current instruction targets
    always_comb begin
        if (iq_instr_i.op inside {OP_ADD, OP_SUB, OP_AND, OP_OR,  OP_XOR,
                                   OP_SLL, OP_SRL, OP_SRA,
                                   OP_ADDI, OP_ANDI, OP_ORI, OP_XORI,
                                   OP_SLLI, OP_SRLI, OP_LUI, OP_NOP, OP_HALT})
            target_full = alu_full_i;
        else if (iq_instr_i.op inside {OP_BEQ, OP_BNE, OP_BLT, OP_BGE, OP_JAL, OP_JALR})
            target_full = br_full_i;
        else if (iq_instr_i.op inside {OP_FADD_S, OP_FSUB_S})
            target_full = fp_add_full_i;
        else if (iq_instr_i.op == OP_FMUL_S)
            target_full = fp_mul_full_i;
        else if (iq_instr_i.op == OP_FDIV_S)
            target_full = fp_div_full_i;
        else if (iq_instr_i.op inside {OP_LW, OP_SW, OP_FLW, OP_FSW})
            target_full = lsb_full_i;
        else if (iq_instr_i.op inside {OP_FCVT_W_S, OP_FCVT_S_W})
            target_full = fp_cvt_full_i;
        else
            target_full = 1'b0;
    end

    always_comb begin
        // --- DEFAULTS ---
        iq_rd_en_o = 1'b0;
        rob_alloc_en_o = 1'b0;
        rob_alloc_instr_o = '0;
        x_map_en_o = 1'b0; x_map_addr_o = '0; x_map_tag_o = '0;
        f_map_en_o = 1'b0; f_map_addr_o = '0; f_map_tag_o = '0;
        alu_valid_o = 1'b0; alu_entry_o = '0;
        br_valid_o = 1'b0; br_entry_o = '0;
        fp_add_valid_o = 1'b0; fp_add_entry_o = '0;
        fp_mul_valid_o = 1'b0; fp_mul_entry_o = '0;
        fp_div_valid_o = 1'b0; fp_div_entry_o = '0;
        lsb_valid_o = 1'b0; lsb_entry_o = '0;
        fp_cvt_valid_o = 1'b0; fp_cvt_entry_o = '0;

        // --- BUILD ENTRY ---
        entry.op = iq_instr_i.op;
        entry.rob_tag = rob_alloc_tag_i;
        entry.imm = iq_instr_i.imm;
        entry.pc = iq_instr_i.pc;

        // rs1: pick INT or FP RAT/regfile based on rs1_fp flag
        if (iq_instr_i.rs1_fp) begin
            entry.rs1_ready = ~f_rs1_valid_i;
            entry.rs1_val = f_rs1_val_i;
            entry.rs1_tag = f_rs1_tag_i;
        end else begin
            entry.rs1_ready = ~x_rs1_valid_i;
            entry.rs1_val = x_rs1_val_i;
            entry.rs1_tag = x_rs1_tag_i;
        end

        // rs2: pick INT or FP RAT/regfile based on rs2_fp flag
        if (iq_instr_i.rs2_fp) begin
            entry.rs2_ready = ~f_rs2_valid_i;
            entry.rs2_val = f_rs2_val_i;
            entry.rs2_tag = f_rs2_tag_i;
        end else begin
            entry.rs2_ready = ~x_rs2_valid_i;
            entry.rs2_val = x_rs2_val_i;
            entry.rs2_tag = x_rs2_tag_i;
        end

        // --- DISPATCH ---
        if (iq_valid_i && ~rob_full_i && ~target_full) begin
            iq_rd_en_o = 1'b1;
            rob_alloc_en_o = 1'b1;
            rob_alloc_instr_o = iq_instr_i;

            // Route to correct RS
            if (iq_instr_i.op inside {OP_ADD, OP_SUB, OP_AND, OP_OR,  OP_XOR,
                                       OP_SLL, OP_SRL, OP_SRA,
                                       OP_ADDI, OP_ANDI, OP_ORI, OP_XORI,
                                       OP_SLLI, OP_SRLI, OP_LUI, OP_NOP, OP_HALT}) begin
                alu_valid_o = 1'b1;
                alu_entry_o = entry;
            end else if (iq_instr_i.op inside {OP_BEQ, OP_BNE, OP_BLT, OP_BGE, OP_JAL, OP_JALR}) begin
                br_valid_o = 1'b1;
                br_entry_o = entry;
            end else if (iq_instr_i.op inside {OP_FADD_S, OP_FSUB_S}) begin
                fp_add_valid_o = 1'b1;
                fp_add_entry_o = entry;
            end else if (iq_instr_i.op == OP_FMUL_S) begin
                fp_mul_valid_o = 1'b1;
                fp_mul_entry_o = entry;
            end else if (iq_instr_i.op == OP_FDIV_S) begin
                fp_div_valid_o = 1'b1;
                fp_div_entry_o = entry;
            end else if (iq_instr_i.op inside {OP_LW, OP_SW, OP_FLW, OP_FSW}) begin
                lsb_valid_o = 1'b1;
                lsb_entry_o = entry;
            end else if (iq_instr_i.op inside {OP_FCVT_W_S, OP_FCVT_S_W}) begin
                fp_cvt_valid_o = 1'b1;
                fp_cvt_entry_o = entry;
            end

            // --- UPDATE RAT ---
            if (iq_instr_i.rd_valid && ~iq_instr_i.rd_fp) begin
                x_map_en_o  = 1'b1;
                x_map_addr_o = iq_instr_i.rd;
                x_map_tag_o = rob_alloc_tag_i;
            end else if (iq_instr_i.rd_valid && iq_instr_i.rd_fp) begin
                f_map_en_o  = 1'b1;
                f_map_addr_o = iq_instr_i.rd;
                f_map_tag_o = rob_alloc_tag_i;
            end
        end
    end

endmodule : dispatch
