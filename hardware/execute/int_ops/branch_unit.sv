/**
 * @brief 1-cycle branch and jump unit (BEQ, BNE, BLT, BGE, JAL, JALR).
 *
 * Resolves the next PC and taken flag. target_o goes to the CDB; the commit
 * unit redirects the IQ and writes the JAL/JALR return address at retirement.
 *
 * @param clk Rising-edge clock.
 * @param rst_n Active-low reset.
 * @param valid_i Operands ready; this entry wins issue.
 * @param op_i Opcode - OP_BEQ/BNE/BLT/BGE/JAL/JALR.
 * @param tag_i ROB tag echoed to CDB.
 * @param rs1_i Condition LHS / JALR base address.
 * @param rs2_i Condition RHS (unused for JAL/JALR).
 * @param imm_i Sign-extended branch/jump offset.
 * @param pc_i Byte address of this instruction.
 * @param valid_o High for one cycle when outputs are valid.
 * @param tag_o ROB tag forwarded alongside the result.
 * @param target_o Resolved next PC (target if taken, PC+4 if not).
 * @param taken_o 1 = taken or unconditional jump; 0 = not taken.
 */
module branch_unit(clk, rst_n,
                    valid_i, op_i, tag_i, 
                    rs1_i, rs2_i, imm_i, pc_i,
                    valid_o, tag_o, target_o, taken_o);
    import rv32if_pkg::*;

    input logic clk; ///< Clock signal for synchronizing the branch unit operations.
    input logic rst_n; ///< Active-low reset signal.

    input logic valid_i; ///< Indicates that the input operands and opcode are valid and can be processed.
    input opcode_e op_i; ///< Operation code indicating which branch operation to perform.
    input logic [TAG_W-1:0] tag_i; ///< Tag for tracking the instruction or operation associated with the inputs.

    input logic [DATA_W-1:0] rs1_i; ///< First source operand (register value). 
    input logic [DATA_W-1:0] rs2_i; ///< Second source operand (register value).
    input logic [DATA_W-1:0] imm_i; ///< Immediate value for branch target calculation.

    input logic [PC_W-1:0] pc_i; ///< Program counter of the current instruction, used for calculating branch target.

    output logic valid_o; ///< Indicates that the output branch decision is valid and can be consumed by downstream stages.
    output logic [TAG_W-1:0] tag_o; ///< Tag for tracking the instruction or operation associated with the output result.
    output logic [PC_W-1:0] target_o; ///< Calculated branch target address.
    output logic taken_o; ///< Indicates whether the branch is taken (1) or not taken (0).

    logic [PC_W-1:0] target_next; ///< Next value of the branch target, computed combinationally based on the opcode and inputs.
    logic taken_next; ///< Next value of the branch taken signal, computed combinationally based on the opcode and inputs.
    
    always_comb begin
        case(op_i)
            OP_BEQ:  taken_next = (rs1_i == rs2_i);
            OP_BNE:  taken_next = (rs1_i != rs2_i);
            OP_BLT:  taken_next = ($signed(rs1_i) < $signed(rs2_i));
            OP_BGE:  taken_next = ($signed(rs1_i) >= $signed(rs2_i));
            OP_BLTU: taken_next = (rs1_i < rs2_i);
            OP_BGEU: taken_next = (rs1_i >= rs2_i);
            OP_JAL, OP_JALR: taken_next = 1'b1;
            default: taken_next = 1'b0;
        endcase
    end

    always_comb begin
        case(op_i)
            OP_BEQ, OP_BNE, OP_BLT, OP_BGE, OP_BLTU, OP_BGEU, OP_JAL:
                target_next = taken_next ? pc_i + imm_i : pc_i + 4;

            OP_JALR: target_next = (rs1_i + imm_i) & ~1; // Register-indirect target, ensure LSB is zero

            default: target_next = '0; // Not a branch instruction
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin 
        if(~rst_n) begin 
            valid_o <= 1'b0;
            tag_o <= '0;
            target_o <= '0;
            taken_o <= 1'b0;
        end else if(valid_i) begin 
            valid_o <= 1'b1; // Output is valid when input is valid
            tag_o <= tag_i; // Tag can be assigned based on the instruction tracking mechanism (e.g., ROB index)
            target_o <= target_next; // Update target output with the calculated target
            taken_o <= taken_next; // Update taken output with the calculated taken signal
        end else begin 
            valid_o <= 1'b0; // Output is not valid when input is not valid
            tag_o <= '0;
            target_o <= '0;
            taken_o <= 1'b0;
        end 
    end

endmodule : branch_unit