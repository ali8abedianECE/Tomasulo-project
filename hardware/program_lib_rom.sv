/**
 * @brief Program library ROM for the DE1-SoC top level.
 *
 * In synthesis this uses an inferred ROM backed by `program_lib.mif`, so
 * Quartus maps the program library into block memory instead of LAB logic.
 * Simulation falls back to a plain memory array loaded from `program_lib.hex`.
 */
module program_lib_rom(clk, program_i, word_i, data_o);
    import rv32if_pkg::*;

    localparam int NUM_PROGRAMS = 44;
    localparam int TOTAL_WORDS = 45056;
    localparam int ROM_DEPTH = 65536;
    localparam int LIB_ADDR_W = $clog2(ROM_DEPTH);

    input  logic clk;
    input  logic [5:0] program_i;
    input  logic [$clog2(MEM_SIZE)-1:0] word_i;
    output logic [DATA_W-1:0] data_o;

    logic [LIB_ADDR_W-1:0] rom_addr;
    (* ramstyle = "M10K", ram_init_file = "program_lib.mif" *)
    logic [DATA_W-1:0] rom [0:ROM_DEPTH-1];

    always_comb begin
        if (program_i < NUM_PROGRAMS[5:0])
            rom_addr = (program_i * MEM_SIZE) + word_i;
        else
            rom_addr = '0;
    end

    always_ff @(posedge clk) begin
        if (program_i < NUM_PROGRAMS[5:0])
            data_o <= rom[rom_addr];
        else
            data_o <= '0;
    end
endmodule : program_lib_rom