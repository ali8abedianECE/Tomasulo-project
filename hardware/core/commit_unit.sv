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

endmodule : commit_unit