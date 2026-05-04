module dispatch(clk, rst_n, flush_i,
                
                // Instruction Queue interface
                iq_valid_i, iq_instr_i, iq_rd_en_o, 

                // ROB interface allocation
                rob_full_i, rob_alloc_en_o, rob_alloc_instr_o, rob_alloc_tag_i,

                // RAT mapping for destination registers
                x_rs1_addr_o, x_rs1_tag_i, x_rs1_valid_i,
                x_rs2_addr_o, x_rs2_tag_i, x_rs2_valid_i,
                f_rs1_addr_o, f_rs1_tag_i, f_rs1_valid_i,
                f_rs2_addr_o, f_rs2_tag_i, f_rs2_valid_i,

                // RAT mapping for destination registers on dispatch
                x_map_en_o, x_map_addr_o, x_map_tag_o,
                f_map_en_o, f_map_addr_o, f_map_tag_o,

                // regfile read interface for source operands
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

endmodule : dispatch