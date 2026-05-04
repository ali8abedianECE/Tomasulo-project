/**
 * @brief Register Alias Table (RAT) for integer and FP register files.
 *
 * Tracks in-flight register writes during out-of-order execution. Each
 * architectural register has a {valid, tag} pair. When an instruction is
 * dispatched, its destination register is mapped to a new ROB tag (valid=1).
 * Source register lookups return the current tag so the RS can snoop the CDB.
 * At commit, the entry is cleared only if the stored tag still matches the
 * committing instruction — a newer dispatch to the same register leaves its
 * mapping intact. Flush (branch misprediction / exception) invalidates all
 * entries synchronously.
 *
 * Priority: map wins over commit when both target the same register in the
 * same cycle (map block is evaluated after commit in the always_ff body).
 *
 * @param clk Rising-edge clock.
 * @param rst_n Active-low async reset.
 * @param flush_i Synchronous flush — clears all valid bits and tags.
 * @param x_rs1_addr_i / x_rs2_addr_i Integer source register addresses (combinational lookup).
 * @param x_rs1_tag_o / x_rs1_valid_o Tag and valid for integer rs1.
 * @param x_rs2_tag_o / x_rs2_valid_o Tag and valid for integer rs2.
 * @param f_rs1_addr_i / f_rs2_addr_i FP source register addresses (combinational lookup).
 * @param f_rs1_tag_o / f_rs1_valid_o Tag and valid for FP rs1.
 * @param f_rs2_tag_o / f_rs2_valid_o Tag and valid for FP rs2.
 * @param x_map_en_i / x_map_addr_i / x_map_tag_i Integer dispatch mapping (writes ignored for x0).
 * @param f_map_en_i / f_map_addr_i / f_map_tag_i FP dispatch mapping.
 * @param x_commit_en_i / x_commit_addr_i / x_commit_tag_i Integer commit — clears entry if tag matches.
 * @param f_commit_en_i / f_commit_addr_i / f_commit_tag_i FP commit — clears entry if tag matches.
 */
module rat_table(clk, rst_n, flush_i,
                 //Dispatch lookup for source registers INT
                x_rs1_addr_i, x_rs1_tag_o, x_rs1_valid_o,
                x_rs2_addr_i, x_rs2_tag_o, x_rs2_valid_o,

                //Dispatch lookup for source registers FP
                f_rs1_addr_i, f_rs1_tag_o, f_rs1_valid_o,
                f_rs2_addr_i, f_rs2_tag_o, f_rs2_valid_o,

                //Mapping for int destination register
                x_map_en_i, x_map_addr_i, x_map_tag_i,

                //Mapping for FP destination register
                f_map_en_i, f_map_addr_i, f_map_tag_i, 

                //Commit interface for INT register file   
                x_commit_en_i, x_commit_addr_i, x_commit_tag_i,

                //Commit interface for FP register file
                f_commit_en_i, f_commit_addr_i, f_commit_tag_i                 
                );
    import rv32if_pkg::*;

    input logic clk; ///< Clock signal for synchronizing RAT operations.
    input logic rst_n; ///< Active-low reset signal.
    input logic flush_i; ///< Signal to flush the RAT, typically on branch misprediction or exception.

    // Dispatch lookup for source registers INT
    input logic [ARCH_W-1:0] x_rs1_addr_i; ///< Address of the first source register for integer operations.
    output logic [TAG_W-1:0] x_rs1_tag_o; ///< Tag associated with the first source register for integer operations.
    output logic x_rs1_valid_o; ///< Valid signal indicating if the tag for the first source register is valid.

    input logic [ARCH_W-1:0] x_rs2_addr_i; ///< Address of the second source register for integer operations.
    output logic [TAG_W-1:0] x_rs2_tag_o; ///< Tag associated with the second source register for integer operations.
    output logic x_rs2_valid_o; ///< Valid signal indicating if the tag for the second source register is valid.

    // Dispatch lookup for source registers FP
    input logic [ARCH_W-1:0] f_rs1_addr_i; ///< Address of the first source register for floating-point operations.
    output logic [TAG_W-1:0] f_rs1_tag_o; ///< Tag associated with the first source register for floating-point operations.
    output logic f_rs1_valid_o; ///< Valid signal indicating if the tag for the first source register is valid.

    input logic [ARCH_W-1:0] f_rs2_addr_i; ///< Address of the second source register for floating-point operations.
    output logic [TAG_W-1:0] f_rs2_tag_o; ///< Tag associated with the second source register for floating-point operations.
    output logic f_rs2_valid_o; ///< Valid signal indicating if the tag for the second source register is valid.

    // Mapping for int destination register
    input logic x_map_en_i; ///< Enable signal for mapping an integer destination register.
    input logic [ARCH_W-1:0] x_map_addr_i; ///< Address of the integer destination register to be mapped.
    input logic [TAG_W-1:0] x_map_tag_i; ///< Tag to be associated with the mapped integer destination register.

    // Mapping for FP destination register
    input logic f_map_en_i; ///< Enable signal for mapping a floating-point destination register.
    input logic [ARCH_W-1:0] f_map_addr_i; ///< Address of the floating-point destination register to be mapped.
    input logic [TAG_W-1:0] f_map_tag_i; ///< Tag to be associated with the mapped floating-point destination register.

    // Commit interface for INT register file
    input logic x_commit_en_i; ///< Enable signal for committing an integer register mapping.
    input logic [ARCH_W-1:0] x_commit_addr_i; ///< Address of the integer register to be committed.
    input logic [TAG_W-1:0] x_commit_tag_i; ///< Tag associated with the integer register mapping to be committed.

    // Commit interface for FP register file
    input logic f_commit_en_i; ///< Enable signal for committing a floating-point register mapping.
    input logic [ARCH_W-1:0] f_commit_addr_i; ///< Address of the floating-point register to be committed.
    input logic [TAG_W-1:0] f_commit_tag_i; ///< Tag associated with the floating-point register mapping to be committed.

    logic [NUM_INT_REGS-1:0] x_valid; ///< Valid bits for integer register mappings.
    logic [TAG_W-1:0] x_tags [NUM_INT_REGS]; ///< Tags for integer register mappings.

    logic [NUM_FP_REGS-1:0] f_valid; ///< Valid bits for floating-point register mappings.
    logic [TAG_W-1:0] f_tags [NUM_FP_REGS]; ///< Tags for floating-point register mappings.

    // logic for dispatch lookup
    assign x_rs1_tag_o = x_tags[x_rs1_addr_i];
    assign x_rs1_valid_o = x_valid[x_rs1_addr_i];

    assign x_rs2_tag_o = x_tags[x_rs2_addr_i];
    assign x_rs2_valid_o = x_valid[x_rs2_addr_i];

    assign f_rs1_tag_o = f_tags[f_rs1_addr_i];
    assign f_rs1_valid_o = f_valid[f_rs1_addr_i];

    assign f_rs2_tag_o = f_tags[f_rs2_addr_i];
    assign f_rs2_valid_o = f_valid[f_rs2_addr_i];

    // logic for mapping and committing
    always_ff @(posedge clk or negedge rst_n) begin 
        if(~rst_n || flush_i) begin 
            x_valid <= {NUM_INT_REGS{1'b0}}; // Invalidate all integer register mappings on reset or flush
            f_valid <= {NUM_FP_REGS{1'b0}}; // Invalidate all floating-point register mappings on reset or flush

            x_tags <= '{default: {TAG_W{1'b0}}}; // Clear all integer register tags on reset or flush
            f_tags <= '{default: {TAG_W{1'b0}}}; // Clear all floating-point register tags on reset or flush
        end else begin  

            // update on commit FIRST - this ensures that if an instruction is dispatched and committed in the same cycle. 
            if(x_commit_en_i) begin 
                if(x_valid[x_commit_addr_i] && x_tags[x_commit_addr_i] == x_commit_tag_i) begin 
                    x_valid[x_commit_addr_i] <= 1'b0; // Clear valid bit for the committed integer register
                    x_tags[x_commit_addr_i] <= {TAG_W{1'b0}}; // Clear tag for the committed integer register
                end
            end

            if(f_commit_en_i) begin 
                if(f_valid[f_commit_addr_i] && f_tags[f_commit_addr_i] == f_commit_tag_i) begin 
                    f_valid[f_commit_addr_i] <= 1'b0; // Clear valid bit for the committed floating-point register
                    f_tags[f_commit_addr_i] <= {TAG_W{1'b0}}; // Clear tag for the committed floating-point register
                end
            end

            // update map on dispatch
            if(x_map_en_i && x_map_addr_i != '0) begin 
                x_valid[x_map_addr_i] <= 1'b1; // Set valid bit for the mapped integer register
                x_tags[x_map_addr_i] <= x_map_tag_i; // Update tag for the mapped integer register
            end

            if(f_map_en_i) begin 
                f_valid[f_map_addr_i] <= 1'b1; // Set valid bit for the mapped floating-point register
                f_tags[f_map_addr_i] <= f_map_tag_i; // Update tag for the mapped floating-point register
            end
             
        end 
    end 

endmodule : rat_table

