/**
 * @brief Dual-bank architectural register file (RV32IF).
 *
 * Holds 32×32-bit integer registers (x0–x31) and 32×32-bit FP registers
 * (f0–f31). Reads are combinational; writes are synchronous on the rising
 * edge. x0 is hardwired to zero - writes to it are silently ignored.
 *
 * @param clk Rising-edge clock.
 * @param rst_n Active-low reset; clears all registers to 0.
 * @param x_rs1_addr_i Integer read port 1 address (rs1).
 * @param x_rs1_val_o Integer read port 1 data.
 * @param x_rs2_addr_i Integer read port 2 address (rs2).
 * @param x_rs2_val_o Integer read port 2 data.
 * @param x_wr_en_i Integer write enable (commit unit asserts on retirement).
 * @param x_wr_addr_i Integer write address; writes to 0 are ignored.
 * @param x_wr_val_i Integer write data.
 * @param f_rs1_addr_i FP read port 1 address.
 * @param f_rs1_val_o FP read port 1 data.
 * @param f_rs2_addr_i FP read port 2 address.
 * @param f_rs2_val_o FP read port 2 data.
 * @param f_wr_en_i FP write enable.
 * @param f_wr_addr_i FP write address.
 * @param f_wr_val_i FP write data (raw bits).
 */
module regfile(clk, rst_n,
                // Integer reg file interface
                x_rs1_addr_i, x_rs1_val_o,
                x_rs2_addr_i, x_rs2_val_o,
                x_wr_en_i, x_wr_addr_i, x_wr_val_i,
                /// Floating point regs interface
                f_rs1_addr_i, f_rs1_val_o,
                f_rs2_addr_i, f_rs2_val_o,
                f_wr_en_i, f_wr_addr_i, f_wr_val_i);
    import rv32if_pkg::*;

    input logic clk; ///< Clock signal for synchronizing register file operations.
    input logic rst_n; ///< Active-low reset signal.

    // Integer register file interface
    input logic [ARCH_W-1:0] x_rs1_addr_i; ///< Address of the first source register for integer operations.
    output logic [DATA_W-1:0] x_rs1_val_o; ///< Value read from the first source register for integer operations.

    input logic [ARCH_W-1:0] x_rs2_addr_i; ///< Address of the second source register for integer operations.
    output logic [DATA_W-1:0] x_rs2_val_o; ///< Value read from the second source register for integer operations.

    input logic x_wr_en_i; ///< Write enable signal for the integer register file.
    input logic [ARCH_W-1:0] x_wr_addr_i; ///< Address of the destination register for integer write operations.
    input logic [DATA_W-1:0] x_wr_val_i; ///< Value to be written to the integer register file when write enable is active.

    // Floating point register file interface
    input logic [ARCH_W-1:0] f_rs1_addr_i; ///< Address of the first source register for floating-point operations.
    output logic [DATA_W-1:0] f_rs1_val_o; ///< Value read from the first source register for floating-point operations.

    input logic [ARCH_W-1:0] f_rs2_addr_i; ///< Address of the second source register for floating-point operations.
    output logic [DATA_W-1:0] f_rs2_val_o; ///< Value read from the second source register for floating-point operations.

    input logic f_wr_en_i; ///< Write enable signal for the floating-point register file.
    input logic [ARCH_W-1:0] f_wr_addr_i; ///< Address of the destination register for floating-point write operations.
    input logic [DATA_W-1:0] f_wr_val_i; ///< Value to be written to the floating-point register file when write enable is active.

    logic [DATA_W-1:0] int_regs [NUM_INT_REGS]; 
    logic [DATA_W-1:0] fp_regs [NUM_FP_REGS];

    always_ff @(posedge clk or negedge rst_n) begin 
        if(~rst_n) begin 
            int_regs <= '{default: {DATA_W{1'b0}}}; // Reset integer registers to 0
            fp_regs <= '{default: {DATA_W{1'b0}}}; // Reset floating-point registers to 0
        end else begin
            if(x_wr_en_i) begin 
                if(x_wr_addr_i != 0) begin // Register x0 is hardwired to zero in RISC-V
                    int_regs[x_wr_addr_i] <= x_wr_val_i; // Write to integer register file
                end
            end

            if(f_wr_en_i) begin 
                fp_regs[f_wr_addr_i] <= f_wr_val_i; // Write to floating-point register file
            end
        end
    end 

    always_comb begin 
        x_rs1_val_o = int_regs[x_rs1_addr_i]; // Read from integer register file
        x_rs2_val_o = int_regs[x_rs2_addr_i]; // Read from integer register file

        f_rs1_val_o = fp_regs[f_rs1_addr_i]; // Read from floating-point register file
        f_rs2_val_o = fp_regs[f_rs2_addr_i]; // Read from floating-point register file
    end 

endmodule : regfile

