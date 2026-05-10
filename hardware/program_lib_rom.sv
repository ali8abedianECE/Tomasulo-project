/**
 * @brief Program library ROM for the DE1-SoC top level.
 *
 * In synthesis this instantiates an Intel `altsyncram` ROM backed by
 * `hardware/quartus/program_lib.mif`, so Quartus maps the program library into
 * block memory instead of LAB logic. Simulation falls back to a plain memory
 * array loaded from `program_lib.hex`.
 */
module program_lib_rom(program_i, word_i, data_o);
    import rv32if_pkg::*;

    localparam int NUM_PROGRAMS = 44;
    localparam int TOTAL_WORDS = 45056;
    localparam int LIB_ADDR_W = $clog2(TOTAL_WORDS);

    input  logic [5:0] program_i;
    input  logic [$clog2(MEM_SIZE)-1:0] word_i;
    output logic [DATA_W-1:0] data_o;

    logic [LIB_ADDR_W-1:0] rom_addr;

    always_comb begin
        if (program_i < NUM_PROGRAMS[5:0])
            rom_addr = (program_i * MEM_SIZE) + word_i;
        else
            rom_addr = '0;
    end

`ifdef SYNTHESIS
    wire [DATA_W-1:0] rom_q;

    altsyncram #(
        .operation_mode("ROM"),
        .width_a(DATA_W),
        .widthad_a(LIB_ADDR_W),
        .numwords_a(TOTAL_WORDS),
        .outdata_reg_a("UNREGISTERED"),
        .address_aclr_a("NONE"),
        .outdata_aclr_a("NONE"),
        .indata_aclr_a("NONE"),
        .wrcontrol_aclr_a("NONE"),
        .init_file("program_lib.mif"),
        .intended_device_family("Cyclone V")
    ) u_rom (
        .clock0(1'b1),
        .address_a(rom_addr),
        .q_a(rom_q),
        .aclr0(1'b0),
        .aclr1(1'b0),
        .address_b('0),
        .addressstall_a(1'b0),
        .addressstall_b(1'b0),
        .byteena_a(1'b1),
        .byteena_b(1'b1),
        .clock1(1'b1),
        .clocken0(1'b1),
        .clocken1(1'b1),
        .clocken2(1'b1),
        .clocken3(1'b1),
        .data_a('0),
        .data_b('0),
        .eccstatus(),
        .q_b(),
        .rden_a(1'b1),
        .rden_b(1'b1),
        .wren_a(1'b0),
        .wren_b(1'b0)
    );

    always_comb data_o = rom_q;
`else
    logic [DATA_W-1:0] rom [0:TOTAL_WORDS-1];
    integer i;

    initial begin
        for (i = 0; i < TOTAL_WORDS; i = i + 1)
            rom[i] = '0;
        $readmemh("hardware/program_lib.hex", rom);
    end

    always_comb begin
        if (program_i < NUM_PROGRAMS[5:0])
            data_o = rom[rom_addr];
        else
            data_o = '0;
    end
`endif

endmodule : program_lib_rom
