module commit_unit(
                    commit_valid_i, commit_entry_i, 
                    commit_en_o, 

                    // Integer reg file commit interface
                    x_wr_en_o, x_wr_addr_o, x_wr_val_o,

                    // FP reg file commit interface
                    f_wr_en_o, f_wr_addr_o, f_wr_val_o

                    // RAT clear (INT)
                    x_commit_en_o, x_commit_addr_o, x_commit_tag_o,

                    // RAT clear (FP)
                    f_commit_en_o, f_commit_addr_o, f_commit_tag_o,

                    // Branch misprediction interface
                    flush_o, redirect_pc_o
                    ); 
    import rv32if_pkg::*;

    input logic commit_valid_i; ///< Indicates that the head entry of the ROB is valid and can be committed.
    input rob_entry_t commit_entry_i; ///< Tag of the head entry being committed.

    output logic commit_en_o; ///< Enable signal for committing the head entry of the ROB.

    // Integer reg file commit interface
    output logic x_wr_en_o; ///< Write enable signal for the integer register file.
    output logic [ARCH_W-1:0] x_wr_addr_o; ///< Address of the destination register for integer write operations.
    output logic [DATA_W-1:0] x_wr_val_o; ///< Value to be written to the integer register file when write enable is active.

    // FP reg file commit interface
    output logic f_wr_en_o; ///< Write enable signal for the floating-point register file.
    output logic [ARCH_W-1:0] f_wr_addr_o; ///< Address of the destination register for floating-point write operations.
    output logic [DATA_W-1:0] f_wr_val_o; ///< Value to be written to the floating-point register file when write enable is active.

    // RAT clear (INT)
    output logic x_commit_en_o; ///< Enable signal for committing an integer register mapping.
    output logic [ARCH_W-1:0] x_commit_addr_o; ///< Address of the integer register to be committed.
    output logic [TAG_W-1:0] x_commit_tag_o; ///< Tag associated with the integer register mapping to be committed.

    // RAT clear (FP)
    output logic f_commit_en_o; ///< Enable signal for committing a floating-point register mapping.
    output logic [ARCH_W-1:0] f_commit_addr_o; ///< Address of the floating-point register to be committed.
    output logic [TAG_W-1:0] f_commit_tag_o; ///< Tag associated with the floating-point register mapping to be committed.

    // Branch misprediction interface
    output logic flush_o; ///< Signal to flush the pipeline, typically on branch misprediction or exception.
    output logic [PC_W-1:0] redirect_pc_o; ///< Target address for redirecting the program counter on branch misprediction.

    

endmodule : commit_unit