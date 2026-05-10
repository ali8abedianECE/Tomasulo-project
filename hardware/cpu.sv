/**
 * @brief DE1-SoC top-level for the RV32IF Tomasulo processor.
 *
 * Runtime behavior:
 *   - Before reset/reload:
 *       SW[5:0] select one of the supported compliance programs.
 *
 *   - Press KEY[0]:
 *       Reloads selected program from main_rom1 into instruction/data memory
 *       and restarts the CPU.
 *
 *   - While loading:
 *       HEX5..HEX0 show lib_word_data[23:0].
 *       This is intentional debug: for program 0 you should see values like
 *       000293, F00F93, 000813, ...
 *
 *   - While running:
 *       HEX5..HEX0 show cycle_count[23:0].
 *
 *   - After HALT:
 *       LEDR[9] = halted.
 *
 *   - Review mode:
 *       Set SW[9] = 1.
 *       SW[5:0] select the signature word index directly.
 *       SW[8] selects which 24-bit window is displayed:
 *           0 = bits [23:0]
 *           1 = bits [31:8]
 *
 * Debug LEDs:
 *   LEDR[9] = halted
 *   LEDR[8] = loading
 *   LEDR[7] = review_mode
 *   LEDR[6] = selected review entry valid
 *   LEDR[5:0] = active_program while running, review index while reviewing
 */

module cpu(CLOCK_50, KEY, SW, LEDR, HEX0, HEX1, HEX2, HEX3, HEX4, HEX5);
    import rv32if_pkg::*;

    localparam int ADDR_W      = $clog2(MEM_SIZE);
    localparam int PROG_SEL_W  = 6;
    localparam int NUM_PROGRAMS = 44;
    localparam int LIB_ADDR_W  = PROG_SEL_W + ADDR_W;

    localparam logic [ADDR_W-1:0] META_BEGIN_WORD = MEM_SIZE - 3;
    localparam logic [ADDR_W-1:0] META_END_WORD   = MEM_SIZE - 2;
    localparam logic [ADDR_W-1:0] META_COUNT_WORD = MEM_SIZE - 1;
    localparam logic [ADDR_W-1:0] LAST_WORD       = MEM_SIZE - 1;

    input  logic CLOCK_50;
    input  logic [3:0] KEY;
    input  logic [9:0] SW;

    output logic [9:0] LEDR;
    output logic [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;

    // -------------------------------------------------------------------------
    // Clock/reset
    // -------------------------------------------------------------------------
    logic clk;
    logic rst_n;
    logic rst_btn_n;
    logic rst_sync_ff1;
    logic core_rst_n;

    assign clk       = CLOCK_50;
    assign rst_btn_n = KEY[0];

    // CPU core is held in reset while RAMs are being loaded.
    assign core_rst_n = rst_n & ~loading;

    // Asynchronous assert, synchronous deassert reset synchronizer.
    always_ff @(posedge clk or negedge rst_btn_n) begin
        if (~rst_btn_n) begin
            rst_sync_ff1 <= 1'b0;
            rst_n        <= 1'b0;
        end else begin
            rst_sync_ff1 <= 1'b1;
            rst_n        <= rst_sync_ff1;
        end
    end

    // -------------------------------------------------------------------------
    // Seven-segment helper
    // -------------------------------------------------------------------------
    function automatic logic [6:0] hex_digit(input logic [3:0] n);
        begin
            case (n)
                4'h0: hex_digit = 7'b1000000;
                4'h1: hex_digit = 7'b1111001;
                4'h2: hex_digit = 7'b0100100;
                4'h3: hex_digit = 7'b0110000;
                4'h4: hex_digit = 7'b0011001;
                4'h5: hex_digit = 7'b0010010;
                4'h6: hex_digit = 7'b0000010;
                4'h7: hex_digit = 7'b1111000;
                4'h8: hex_digit = 7'b0000000;
                4'h9: hex_digit = 7'b0010000;
                4'hA: hex_digit = 7'b0001000;
                4'hB: hex_digit = 7'b0000011;
                4'hC: hex_digit = 7'b1000110;
                4'hD: hex_digit = 7'b0100001;
                4'hE: hex_digit = 7'b0000110;
                4'hF: hex_digit = 7'b0001110;
                default: hex_digit = 7'b1111111;
            endcase
        end
    endfunction

    // Convert word index to byte address.
    function automatic logic [PC_W-1:0] word_to_byte_addr(
        input logic [ADDR_W-1:0] word_idx
    );
        logic [PC_W-1:0] addr;
        begin
            addr = '0;
            addr[ADDR_W+1:2] = word_idx;
            word_to_byte_addr = addr;
        end
    endfunction

    function automatic logic [PROG_SEL_W-1:0] clamp_program_sel(
        input logic [PROG_SEL_W-1:0] raw_sel
    );
        begin
            if (raw_sel < NUM_PROGRAMS)
                clamp_program_sel = raw_sel;
            else
                clamp_program_sel = '0;
        end
    endfunction

    // -------------------------------------------------------------------------
    // Program ROM library
    // -------------------------------------------------------------------------
    logic [PROG_SEL_W-1:0] active_program;

    logic [LIB_ADDR_W-1:0] lib_word_addr;
    logic [DATA_W-1:0]     lib_word_data;

    // Loader state.
    //
    // load_req_word:
    //   Word address currently being requested from main_rom1.
    //
    // load_data_word:
    //   Word index corresponding to lib_word_data on the current write cycle.
    //
    // load_data_valid:
    //   High when lib_word_data should be written into instruction/data memory.
    //
    // This assumes main_rom1 has unregistered output but synchronous address/M10K
    // behavior: request word N, then word N is usable on the next clock edge.
    logic loading;
    logic [ADDR_W-1:0] load_req_word;
    logic [ADDR_W-1:0] load_data_word;
    logic load_data_valid;
    logic load_wr_en;

    assign load_wr_en = loading & load_data_valid;

    // main_rom1 stores each program as MEM_SIZE words:
    // address = {program_id, word_index}
    assign lib_word_addr = {active_program, load_req_word};

    main_rom1 u_prog_lib (
        .address(lib_word_addr),
        .clock  (clk),
        .q      (lib_word_data)
    );

    // -------------------------------------------------------------------------
    // Instruction/data memory wiring
    // -------------------------------------------------------------------------
    logic [DATA_W-1:0] instr_raw;

    logic [PC_W-1:0]   mem_rd_addr_core;
    logic [PC_W-1:0]   mem_rd_addr_mux;
    logic [DATA_W-1:0] mem_rd_data;

    logic [PC_W-1:0]   mem_wr_addr_core;
    logic [DATA_W-1:0] mem_wr_data_core;
    logic              mem_wr_en_core;
    logic [3:0]        mem_wr_be_core;

    logic [PC_W-1:0]   dmem_wr_addr;
    logic [DATA_W-1:0] dmem_wr_data;
    logic              dmem_wr_en;
    logic [3:0]        dmem_wr_be;

    logic              imem_wr_en;
    logic [ADDR_W-1:0] imem_wr_addr;
    logic [DATA_W-1:0] imem_wr_data;

    assign imem_wr_en   = load_wr_en;
    assign imem_wr_addr = load_data_word;
    assign imem_wr_data = lib_word_data;

    assign dmem_wr_en = load_wr_en ? 1'b1 : mem_wr_en_core;
    assign dmem_wr_be = load_wr_en ? 4'b1111 : mem_wr_be_core;

    assign dmem_wr_addr = load_wr_en
        ? word_to_byte_addr(load_data_word)
        : mem_wr_addr_core;

    assign dmem_wr_data = load_wr_en
        ? lib_word_data
        : mem_wr_data_core;

    instr_mem #(.FILENAME("")) u_imem (
        .clk          (clk),
        .pc_i         (fetch_pc),
        .instr_o      (instr_raw),
        .write_en_i   (imem_wr_en),
        .write_addr_i (imem_wr_addr),
        .write_data_i (imem_wr_data)
    );

    data_mem #(.FILENAME("")) u_dmem (
        .clk       (clk),
        .rd_addr_i (mem_rd_addr_mux),
        .rd_data_o (mem_rd_data),
        .wr_en_i   (dmem_wr_en),
        .wr_be_i   (dmem_wr_be),
        .wr_addr_i (dmem_wr_addr),
        .wr_data_i (dmem_wr_data)
    );

    // -------------------------------------------------------------------------
    // Signature metadata/review mode
    // -------------------------------------------------------------------------
    logic [ADDR_W-1:0] sig_begin_word;
    logic [ADDR_W-1:0] sig_end_word;
    logic [ADDR_W-1:0] sig_word_count;

    logic review_mode;
    logic review_active_entry;
    logic [ADDR_W-1:0] review_index_sw;
    logic [ADDR_W-1:0] review_word_idx;
    logic [PC_W-1:0] review_addr;
    logic [DATA_W-1:0] review_data_word;

    logic [15:0] sig_count_display;
    assign sig_count_display = {{(16-ADDR_W){1'b0}}, sig_word_count};

    assign review_mode = halted & SW[9];

    // In review mode, SW[5:0] directly chooses the signature word.
    assign review_index_sw = {{(ADDR_W-PROG_SEL_W){1'b0}}, SW[5:0]};

    assign review_active_entry = review_mode && (review_index_sw < sig_word_count);
    assign review_word_idx     = sig_begin_word + review_index_sw;
    assign review_addr         = word_to_byte_addr(review_word_idx);

    // Data memory read address mux:
    //   - During loading: dummy address 0
    //   - During review: selected signature word
    //   - Otherwise: CPU data memory read address
    assign mem_rd_addr_mux = loading
        ? '0
        : (review_active_entry ? review_addr : mem_rd_addr_core);

    // -------------------------------------------------------------------------
    // Loader FSM
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (~rst_n) begin
            active_program  <= clamp_program_sel(SW[5:0]);

            loading         <= 1'b1;
            load_req_word   <= '0;
            load_data_word  <= '0;
            load_data_valid <= 1'b0;

            sig_begin_word  <= '0;
            sig_end_word    <= '0;
            sig_word_count  <= '0;

        end else if (loading) begin
            // Capture metadata from the word currently being written.
            if (load_data_valid && (load_data_word == META_BEGIN_WORD))
                sig_begin_word <= lib_word_data[ADDR_W-1:0];

            if (load_data_valid && (load_data_word == META_END_WORD))
                sig_end_word <= lib_word_data[ADDR_W-1:0];

            if (load_data_valid && (load_data_word == META_COUNT_WORD))
                sig_word_count <= lib_word_data[ADDR_W-1:0];

            if (!load_data_valid) begin
                // First valid ROM word will be word 0.
                // Next request is word 1.
                load_data_valid <= 1'b1;
                load_data_word  <= '0;
                load_req_word   <= {{(ADDR_W-1){1'b0}}, 1'b1};

            end else if (load_data_word == LAST_WORD) begin
                // Final word has just been written on this clock edge.
                loading         <= 1'b0;
                load_data_valid <= 1'b0;
                load_req_word   <= '0;
                load_data_word  <= '0;

            end else begin
                // Current lib_word_data was for load_data_word.
                // Next cycle's valid data corresponds to load_req_word.
                load_data_word <= load_req_word;

                // Request the next word, but never wrap to zero while finishing.
                if (load_req_word != LAST_WORD)
                    load_req_word <= load_req_word + 1'b1;
                else
                    load_req_word <= load_req_word;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Fetch stage
    // -------------------------------------------------------------------------
    logic [PC_W-1:0] fetch_pc;
    logic [PC_W-1:0] fetch_pc_d;
    logic fetch_valid;
    logic iq_full;
    logic flush;
    logic [PC_W-1:0] redirect_pc;

    always_ff @(posedge clk) begin
        if (~core_rst_n) begin
            fetch_pc    <= '0;
            fetch_pc_d  <= '0;
            fetch_valid <= 1'b0;
        end else if (flush) begin
            fetch_pc    <= redirect_pc;
            fetch_pc_d  <= redirect_pc;
            fetch_valid <= 1'b0;
        end else begin
            fetch_valid <= 1'b1;

            if (!iq_full) begin
                fetch_pc   <= fetch_pc + 4;
                fetch_pc_d <= fetch_pc;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Tomasulo core
    // -------------------------------------------------------------------------
    logic halted;
    logic halted_core;

    tomasulo_core u_core (
        .clk           (clk),
        .rst_n         (core_rst_n),

        .fetch_valid_i (fetch_valid & ~iq_full),
        .fetch_raw_i   (instr_raw),
        .fetch_pc_i    (fetch_pc_d),
        .iq_full_o     (iq_full),

        .flush_o       (flush),
        .redirect_pc_o (redirect_pc),

        .halted_o      (halted_core),

        .mem_rd_addr_o (mem_rd_addr_core),
        .mem_rd_data_i (mem_rd_data),

        .mem_wr_en_o   (mem_wr_en_core),
        .mem_wr_be_o   (mem_wr_be_core),
        .mem_wr_addr_o (mem_wr_addr_core),
        .mem_wr_data_o (mem_wr_data_core)
    );

    // -------------------------------------------------------------------------
    // Cycle counter and halt latch
    // -------------------------------------------------------------------------
    logic [31:0] cycle_count;

    always_ff @(posedge clk) begin
        if (~core_rst_n) begin
            cycle_count <= '0;
            halted      <= 1'b0;
        end else begin
            if (halted_core)
                halted <= 1'b1;

            if (!(halted || halted_core))
                cycle_count <= cycle_count + 32'd1;
        end
    end

    // -------------------------------------------------------------------------
    // Review data capture
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (~core_rst_n) begin
            review_data_word <= '0;
        end else if (review_mode && review_active_entry) begin
            review_data_word <= mem_rd_data;
        end
    end

    // -------------------------------------------------------------------------
    // HEX display mux
    // -------------------------------------------------------------------------
    logic [23:0] hex_display_value;

    always_comb begin
        if (loading) begin
            // Debug ROM data directly.
            // Program 0 should show changing values, not all zeros.
            hex_display_value = lib_word_data[23:0];

        end else if (review_mode && review_active_entry) begin
            // Show selected signature word.
            hex_display_value = SW[8] ? review_data_word[31:8] : review_data_word[23:0];

        end else if (review_mode && !review_active_entry) begin
            // Invalid review index or sig_word_count == 0.
            // Shows EE + count.
            hex_display_value = {8'hEE, sig_count_display};

        end else begin
            // Normal running display.
            hex_display_value = cycle_count[23:0];
        end
    end

    // -------------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------------
    assign LEDR[9]   = halted;
    assign LEDR[8]   = loading;
    assign LEDR[7]   = review_mode;
    assign LEDR[6]   = review_active_entry;
    assign LEDR[5:0] = review_mode ? SW[5:0] : active_program;

    assign HEX0 = hex_digit(hex_display_value[3:0]);
    assign HEX1 = hex_digit(hex_display_value[7:4]);
    assign HEX2 = hex_digit(hex_display_value[11:8]);
    assign HEX3 = hex_digit(hex_display_value[15:12]);
    assign HEX4 = hex_digit(hex_display_value[19:16]);
    assign HEX5 = hex_digit(hex_display_value[23:20]);

endmodule : cpu