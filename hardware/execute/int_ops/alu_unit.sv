
/**
 * @brief 1-cycle integer ALU (ADD/SUB/AND/OR/XOR/SLL/SRL/SRA, I-type variants, LUI).
 *
 * Combinatorially computes result_next then registers it on the rising edge.
 * result_o and tag_o are valid the cycle after valid_i is asserted.
 *
 * @param clk Rising-edge clock.
 * @param rst_n Active-low reset.
 * @param valid_i Operands ready; this entry wins issue.
 * @param op_i Opcode - OP_ADD/SUB/AND/OR/XOR/SLL/SRL/SRA/ADDI/ANDI/ORI/XORI/SLLI/SRLI/LUI.
 * @param tag_i ROB tag echoed to CDB.
 * @param rs1_i Source register 1.
 * @param rs2_i Source register 2 (R-type only).
 * @param imm_i Sign-extended immediate (I-type / LUI pre-shifted by decode).
 * @param valid_o High for one cycle when result_o is valid.
 * @param tag_o ROB tag forwarded alongside the result.
 * @param result_o Computed 32-bit result.
 */
module alu_int(clk, rst_n,
           op_i, valid_i,
           tag_i, pc_i,
           rs1_i, rs2_i, imm_i,
           valid_o,
           tag_o, result_o);
    import rv32if_pkg::*;

    input logic clk;
    input logic rst_n;
    input opcode_e op_i;
    input logic valid_i;
    input logic [TAG_W-1:0] tag_i;
    input logic [PC_W-1:0] pc_i;
    input logic [DATA_W-1:0] rs1_i;
    input logic [DATA_W-1:0] rs2_i;
    input logic [DATA_W-1:0] imm_i;
    output logic valid_o;
    output logic [TAG_W-1:0] tag_o;
    output logic [DATA_W-1:0] result_o;

    logic [DATA_W-1:0] result_next;

    always_comb begin
        case(op_i)
            OP_ADD:  result_next = rs1_i + rs2_i;
            OP_SUB:  result_next = rs1_i - rs2_i;
            OP_AND:  result_next = rs1_i & rs2_i;
            OP_OR:   result_next = rs1_i | rs2_i;
            OP_XOR:  result_next = rs1_i ^ rs2_i;
            OP_SLL:  result_next = rs1_i << rs2_i[4:0];
            OP_SRL:  result_next = rs1_i >> rs2_i[4:0];
            OP_SRA:  result_next = $signed(rs1_i) >>> rs2_i[4:0];
            OP_SLT:  result_next = ($signed(rs1_i) < $signed(rs2_i)) ? 32'd1 : 32'd0;
            OP_SLTU: result_next = (rs1_i < rs2_i) ? 32'd1 : 32'd0;

            OP_ADDI:  result_next = rs1_i + imm_i;
            OP_ANDI:  result_next = rs1_i & imm_i;
            OP_ORI:   result_next = rs1_i | imm_i;
            OP_XORI:  result_next = rs1_i ^ imm_i;
            OP_SLLI:  result_next = rs1_i << imm_i[4:0];
            OP_SRLI:  result_next = rs1_i >> imm_i[4:0];
            OP_SRAI:  result_next = $signed(rs1_i) >>> imm_i[4:0];
            OP_SLTI:  result_next = ($signed(rs1_i) < $signed(imm_i)) ? 32'd1 : 32'd0;
            OP_SLTIU: result_next = (rs1_i < imm_i) ? 32'd1 : 32'd0;

            OP_LUI:   result_next = imm_i;
            OP_AUIPC: result_next = pc_i + imm_i;
            default:  result_next = '0;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            result_o <= 0;
            valid_o <= 0;
            tag_o <= 0;
        end else if (valid_i) begin
            result_o <= result_next; // Update the output result with the computed value
            valid_o <= 1; // Indicate that the output is valid
            tag_o <= tag_i; // Forward the input tag to the output for tracking
        end else begin
            valid_o <= 0; // If input is not valid, output is not valid
        end
    end

endmodule : alu_int
