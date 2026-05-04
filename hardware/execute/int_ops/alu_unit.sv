
/* 
 * @brief ALU unit for integer operations (ADD, SUB, AND, OR, XOR, shifts, ADDI variants).
 * Based upon the opcode and input operands, performs the appropriate computation and produces the result.
 * 
 * Supported operations:
 * - OP_ADD: result_o = rs1_i + rs2_i
 * - OP_SUB: result_o = rs1_i - rs2_i
 * - OP_AND: result_o = rs1_i & rs2_i
 * - OP_OR: result_o = rs1_i | rs2_i
 * - OP_XOR: result_o = rs1_i ^ rs2_i
 * - OP_SLL: result_o = rs1_i << (rs2_i[4:0]) // Shift left logical
 * - OP_SRL: result_o = rs1_i >> (rs2_i[4:0]) // Shift right logical
 * - OP_SRA: result_o = rs1_i >>> (rs2_i[4:0]) // Shift right arithmetic
 * - OP_ADDI: result_o = rs1_i + imm_i
 * - OP_ANDI: result_o = rs1_i & imm_i
 * - OP_ORI: result_o = rs1_i | imm_i
 * - OP_XORI: result_o = rs1_i ^ imm_i
 * - OP_SLLI: result_o = rs1_i << (imm_i[4:0]) // Shift left logical immediate
 * - OP_SRLI: result_o = rs1_i >> (imm_i[4:0]) // Shift right logical immediate
 */
module alu_int(clk, rst_n, 
           op_i, valid_i, 
           tag_i, 
           rs1_i, rs2_i, imm_i,
           valid_o, 
           tag_o, result_o);
    import rv32if_pkg::*;

    input logic clk; ///< Clock signal for synchronizing the ALU operations.
    input logic rst_n; ///< Active-low reset signal.

    input opcode_e op_i; ///< Operation code indicating which ALU operation to perform.

    input logic valid_i; ///< Indicates that the input operands and opcode are valid and can be processed.

    input logic [TAG_W-1:0] tag_i; ///< Tag for tracking the instruction or operation associated with the inputs.

    input logic [DATA_W-1:0] rs1_i; ///< First source operand (register value).
    input logic [DATA_W-1:0] rs2_i; ///< Second source operand (register value).
    input logic [DATA_W-1:0] imm_i; ///< Immediate value for operations that require it (e.g., ADDI).

    output logic valid_o; ///< Indicates that the output result is valid and can be consumed by downstream stages.
    output logic [TAG_W-1:0] tag_o; ///< Tag for tracking the instruction or operation associated with the output result.

    output logic [DATA_W-1:0] result_o; ///< Result of the ALU operation.

    logic [DATA_W-1:0] result_next; ///< Next value of the result, computed combinationally based on the opcode and inputs.

    always_comb begin
        case(op_i) 
            ///< R-type operations
            OP_ADD: result_next = rs1_i + rs2_i;
            OP_SUB: result_next = rs1_i - rs2_i;
            OP_AND: result_next = rs1_i & rs2_i;
            OP_OR: result_next = rs1_i | rs2_i;
            OP_XOR: result_next = rs1_i ^ rs2_i;
            OP_SLL: result_next = rs1_i << rs2_i[4:0];
            OP_SRL: result_next = rs1_i >> rs2_i[4:0];
            OP_SRA: result_next = $signed(rs1_i) >>> rs2_i[4:0]; // arithmetic shift right using signed shift operator

            ///< I-type operations
            OP_ADDI: result_next = rs1_i + imm_i;
            OP_ANDI: result_next = rs1_i & imm_i;
            OP_ORI: result_next = rs1_i | imm_i;
            OP_XORI: result_next = rs1_i ^ imm_i;
            OP_SLLI: result_next = rs1_i << imm_i[4:0];
            OP_SRLI: result_next = rs1_i >> imm_i[4:0];

            ///< U-type operations (LUI)
            OP_LUI: result_next = imm_i; //Assumed imm_i is already shifted left by 12 in decode stage
            default: result_next = {DATA_W{1'b0}}; // Default case for unsupported opcodes
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
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

endmodule
