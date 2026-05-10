/**
 * @brief DE1-SoC top-level for the RV32IF Tomasulo processor.
 *
 * Instantiates instr_mem, data_mem, and tomasulo_core. Adds a 1-cycle
 * fetch stage (PC register + decode). The 32-bit cycle counter is shown
 * on HEX5..HEX0 as six hex digits until HALT retires. KEY[0] is active-low reset.
 *
 * HEX display: HEX5:HEX4 = cycle_count[23:16],
 *              HEX3:HEX2 = cycle_count[15:8],
 *              HEX1:HEX0 = cycle_count[7:0].
 * When KEY[1] is pressed after HALT, HEX5..HEX0 instead show the low 24 bits
 * of the selected data-memory word at address {SW[8:0], 2'b00}.
 * LEDR[9] = halted (OP_HALT retired), LEDR[8:0] = SW[8:0].
 */
module cpu(CLOCK_50, KEY, SW, LEDR, HEX0, HEX1, HEX2, HEX3, HEX4, HEX5);
    import rv32if_pkg::*;

    input logic CLOCK_50;
    input logic [3:0] KEY;
    input logic [9:0] SW;
    output logic [9:0] LEDR;
    output logic [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;

    logic clk, rst_n;
    assign clk = CLOCK_50;
    assign rst_n = KEY[0];   // KEY[0] active-low

    // -------------------------------------------------------------------------
    // Seven-segment helper
    // -------------------------------------------------------------------------
    function automatic logic [6:0] hex_digit(input logic [3:0] n);
        case (n)
            4'h0: hex_digit = 7'b1000000; 4'h1: hex_digit = 7'b1111001;
            4'h2: hex_digit = 7'b0100100; 4'h3: hex_digit = 7'b0110000;
            4'h4: hex_digit = 7'b0011001; 4'h5: hex_digit = 7'b0010010;
            4'h6: hex_digit = 7'b0000010; 4'h7: hex_digit = 7'b1111000;
            4'h8: hex_digit = 7'b0000000; 4'h9: hex_digit = 7'b0010000;
            4'hA: hex_digit = 7'b0001000; 4'hB: hex_digit = 7'b0000011;
            4'hC: hex_digit = 7'b1000110; 4'hD: hex_digit = 7'b0100001;
            4'hE: hex_digit = 7'b0000110; 4'hF: hex_digit = 7'b0001110;
            default: hex_digit = 7'b1111111;
        endcase
    endfunction

    // -------------------------------------------------------------------------
    // Memory
    // -------------------------------------------------------------------------
    logic [DATA_W-1:0] instr_raw;
    logic [PC_W-1:0] mem_rd_addr_core, mem_rd_addr, mem_wr_addr;
    logic [DATA_W-1:0] mem_rd_data, mem_wr_data;
    logic mem_wr_en;
    logic [3:0] mem_wr_be;
    logic mem_view_en;
    logic [PC_W-1:0] mem_view_addr;
    logic [23:0] hex_display_value;

    instr_mem #(.FILENAME("program.hex")) u_imem(
        .clk(clk), .pc_i(fetch_pc),
        .instr_o(instr_raw),
        .write_en_i(1'b0), .write_addr_i('0), .write_data_i('0)
    );

    data_mem #(.FILENAME("program.hex")) u_dmem(
        .clk(clk),
        .rd_addr_i(mem_rd_addr), .rd_data_o(mem_rd_data),
        .wr_en_i(mem_wr_en), .wr_be_i(mem_wr_be),
        .wr_addr_i(mem_wr_addr), .wr_data_i(mem_wr_data)
    );

    // -------------------------------------------------------------------------
    // Fetch stage: PC register + 1-cycle bubble after flush
    // -------------------------------------------------------------------------
    logic [PC_W-1:0] fetch_pc; // sent to instr_mem this cycle
    logic [PC_W-1:0] fetch_pc_d; // PC of the instruction now on instr_mem output
    logic fetch_valid; // instr_mem output is valid to push into IQ
    logic iq_full;
    logic flush;
    logic [PC_W-1:0] redirect_pc;

    always_ff @(posedge clk) begin
        if (~rst_n) begin
            fetch_pc <= '0;
            fetch_pc_d <= '0;
            fetch_valid <= 1'b0;
        end else if (flush) begin
            fetch_pc <= redirect_pc;
            fetch_pc_d <= redirect_pc;
            fetch_valid <= 1'b0;  // 1-cycle bubble: discard next instr_mem output
        end else begin
            fetch_valid <= 1'b1;
            if (!iq_full) begin
                fetch_pc <= fetch_pc + 4;
                fetch_pc_d <= fetch_pc;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Tomasulo core
    // -------------------------------------------------------------------------
    tomasulo_core u_core(
        .clk(clk), .rst_n(rst_n),
        .fetch_valid_i(fetch_valid & ~iq_full),
        .fetch_raw_i(instr_raw),
        .fetch_pc_i(fetch_pc_d),
        .iq_full_o(iq_full),
        .flush_o(flush), .redirect_pc_o(redirect_pc),
        .halted_o(halted_core),
        .mem_rd_addr_o(mem_rd_addr_core), .mem_rd_data_i(mem_rd_data),
        .mem_wr_en_o(mem_wr_en), .mem_wr_be_o(mem_wr_be), .mem_wr_addr_o(mem_wr_addr),
        .mem_wr_data_o(mem_wr_data)
    );

    // -------------------------------------------------------------------------
    // Cycle counter
    // -------------------------------------------------------------------------
    logic [31:0] cycle_count;
    logic        halted, halted_core;

    assign mem_view_en = halted & ~KEY[1];
    assign mem_view_addr = {{(PC_W-11){1'b0}}, SW[8:0], 2'b00};
    assign mem_rd_addr = mem_view_en ? mem_view_addr : mem_rd_addr_core;
    assign hex_display_value = mem_view_en ? mem_rd_data[23:0] : cycle_count[23:0];

    always_ff @(posedge clk) begin
        if (~rst_n) begin
            cycle_count <= '0;
            halted <= 1'b0;
        end else begin
            if (halted_core) begin
                halted <= 1'b1;
            end

            if (!(halted || halted_core)) begin
                cycle_count <= cycle_count + 32'd1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------------
    assign LEDR[9] = halted;
    assign LEDR[8:0] = SW[8:0];

    assign HEX0 = hex_digit(hex_display_value[3:0]);
    assign HEX1 = hex_digit(hex_display_value[7:4]);
    assign HEX2 = hex_digit(hex_display_value[11:8]);
    assign HEX3 = hex_digit(hex_display_value[15:12]);
    assign HEX4 = hex_digit(hex_display_value[19:16]);
    assign HEX5 = hex_digit(hex_display_value[23:20]);

endmodule : cpu
