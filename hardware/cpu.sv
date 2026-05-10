/**
 * @brief DE1-SoC top-level for the RV32IF Tomasulo processor.
 *
 * The board build does not rely on `initial`-time memory contents. Instead,
 * KEY[0] reloads the program selected by SW[5:0] from a synthesized program
 * library ROM into the writable instruction and data memories. Each program
 * image includes a signature metadata header in data-memory words 1020..1023.
 *
 * Runtime behavior:
 *   - SW[5:0] select one of the 44 supported compliance programs.
 *   - KEY[0] reloads the selected program and restarts the CPU.
 *   - HEX5..HEX0 show the cycle counter while the test is running.
 *   - After HALT, setting SW[9] enters review mode:
 *       KEY[1] marks current signature word correct and advances.
 *       KEY[2] moves back one signature word.
 *       KEY[3] marks current signature word wrong and advances.
 *     The current signature word is shown on HEX5..HEX0, and LEDR[6:0]
 *     show the running correct-count.
 */
module cpu(CLOCK_50, KEY, SW, LEDR, HEX0, HEX1, HEX2, HEX3, HEX4, HEX5);
    import rv32if_pkg::*;

    localparam int ADDR_W = $clog2(MEM_SIZE);
    localparam int PROG_SEL_W = 6;
    localparam int NUM_PROGRAMS = 44;
    localparam int META_BEGIN_WORD = MEM_SIZE - 3;
    localparam int META_END_WORD = MEM_SIZE - 2;
    localparam int META_COUNT_WORD = MEM_SIZE - 1;
    localparam int REVIEW_MAX = 64;

    localparam logic [1:0] MARK_UNKNOWN = 2'b00;
    localparam logic [1:0] MARK_CORRECT = 2'b01;
    localparam logic [1:0] MARK_WRONG   = 2'b10;

    input logic CLOCK_50;
    input logic [3:0] KEY;
    input logic [9:0] SW;
    output logic [9:0] LEDR;
    output logic [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;

    logic clk, rst_n, rst_btn_n, rst_sync_ff1;
    logic core_rst_n;

    logic [DATA_W-1:0] instr_raw;
    logic [PC_W-1:0] mem_rd_addr_core, mem_rd_addr_mux;
    logic [PC_W-1:0] mem_wr_addr_core, dmem_wr_addr;
    logic [DATA_W-1:0] mem_rd_data;
    logic [DATA_W-1:0] mem_wr_data_core, dmem_wr_data;
    logic mem_wr_en_core, dmem_wr_en;
    logic [3:0] mem_wr_be_core, dmem_wr_be;

    logic imem_wr_en;
    logic [ADDR_W-1:0] imem_wr_addr;
    logic [DATA_W-1:0] imem_wr_data;

    logic [PC_W-1:0] fetch_pc;
    logic [PC_W-1:0] fetch_pc_d;
    logic fetch_valid;
    logic iq_full;
    logic flush;
    logic [PC_W-1:0] redirect_pc;

    logic [31:0] cycle_count;
    logic halted, halted_core;

    logic [PROG_SEL_W-1:0] active_program;
    logic loading;
    logic [ADDR_W:0] load_fetch_idx;
    logic [ADDR_W-1:0] load_write_idx;
    logic load_data_valid;
    logic [15:0] lib_word_addr;
    logic [DATA_W-1:0] lib_word_data;

    logic [ADDR_W-1:0] sig_begin_word;
    logic [ADDR_W-1:0] sig_end_word;
    logic [ADDR_W-1:0] sig_word_count;

    logic review_mode, review_mode_d;
    logic [ADDR_W-1:0] review_index;
    logic [ADDR_W-1:0] review_word_idx;
    logic [PC_W-1:0] review_addr;
    logic [6:0] review_correct_count;
    logic [5:0] review_slot;
    logic [1:0] review_marks [0:REVIEW_MAX-1];
    logic key1_prev, key2_prev, key3_prev;
    logic key1_press, key2_press, key3_press;

    logic [23:0] hex_display_value;
    integer review_i;

    assign clk = CLOCK_50;
    assign rst_btn_n = KEY[0];
    assign core_rst_n = rst_n & ~loading;

    assign review_mode = halted & SW[9];
    assign review_slot = review_index[5:0];
    assign review_word_idx = sig_begin_word + review_index;
    assign review_addr = {{(PC_W-ADDR_W-2){1'b0}}, review_word_idx, 2'b00};

    assign key1_press = key1_prev & ~KEY[1];
    assign key2_press = key2_prev & ~KEY[2];
    assign key3_press = key3_prev & ~KEY[3];

    assign imem_wr_en = load_data_valid;
    assign imem_wr_addr = load_write_idx;
    assign imem_wr_data = lib_word_data;

    assign dmem_wr_en = load_data_valid ? 1'b1 : mem_wr_en_core;
    assign dmem_wr_be = load_data_valid ? 4'b1111 : mem_wr_be_core;
    assign dmem_wr_addr = load_data_valid
        ? {{(PC_W-ADDR_W-2){1'b0}}, load_write_idx, 2'b00}
        : mem_wr_addr_core;
    assign dmem_wr_data = load_data_valid ? lib_word_data : mem_wr_data_core;

    assign mem_rd_addr_mux = loading ? '0 : (review_mode ? review_addr : mem_rd_addr_core);

    always_comb begin
        if (loading)
            hex_display_value = {8'h00, active_program, load_write_idx};
        else if (review_mode)
            hex_display_value = mem_rd_data[23:0];
        else
            hex_display_value = cycle_count[23:0];
    end

    // Asynchronous assert, synchronous deassert reset synchronizer.
    always_ff @(posedge clk or negedge rst_btn_n) begin
        if (~rst_btn_n) begin
            rst_sync_ff1 <= 1'b0;
            rst_n <= 1'b0;
        end else begin
            rst_sync_ff1 <= 1'b1;
            rst_n <= rst_sync_ff1;
        end
    end

    function automatic logic [PROG_SEL_W-1:0] clamp_program_sel(input logic [PROG_SEL_W-1:0] raw_sel);
        if (raw_sel < NUM_PROGRAMS[PROG_SEL_W-1:0])
            clamp_program_sel = raw_sel;
        else
            clamp_program_sel = '0;
    endfunction

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

    main_rom1 u_prog_lib(
        .address(lib_word_addr),
        .clock(clk),
        .q(lib_word_data)
    );

    assign lib_word_addr = {active_program, load_fetch_idx[ADDR_W-1:0]};

    instr_mem #(.FILENAME("")) u_imem(
        .clk(clk),
        .pc_i(fetch_pc),
        .instr_o(instr_raw),
        .write_en_i(imem_wr_en),
        .write_addr_i(imem_wr_addr),
        .write_data_i(imem_wr_data)
    );

    data_mem #(.FILENAME("")) u_dmem(
        .clk(clk),
        .rd_addr_i(mem_rd_addr_mux),
        .rd_data_o(mem_rd_data),
        .wr_en_i(dmem_wr_en),
        .wr_be_i(dmem_wr_be),
        .wr_addr_i(dmem_wr_addr),
        .wr_data_i(dmem_wr_data)
    );

    always_ff @(posedge clk) begin
        if (~rst_n) begin
            active_program <= clamp_program_sel(SW[5:0]);
            loading <= 1'b1;
            load_fetch_idx <= '0;
            load_write_idx <= '0;
            load_data_valid <= 1'b0;
            sig_begin_word <= '0;
            sig_end_word <= '0;
            sig_word_count <= '0;
        end else if (loading) begin
            if (load_data_valid && (load_write_idx == META_BEGIN_WORD[ADDR_W-1:0]))
                sig_begin_word <= lib_word_data[ADDR_W-1:0];
            if (load_data_valid && (load_write_idx == META_END_WORD[ADDR_W-1:0]))
                sig_end_word <= lib_word_data[ADDR_W-1:0];
            if (load_data_valid && (load_write_idx == META_COUNT_WORD[ADDR_W-1:0]))
                sig_word_count <= lib_word_data[ADDR_W-1:0];

            if (!load_data_valid) begin
                load_data_valid <= 1'b1;
                load_write_idx <= '0;
                load_fetch_idx <= {{ADDR_W{1'b0}}, 1'b1};
            end else if (load_fetch_idx < MEM_SIZE) begin
                load_write_idx <= load_fetch_idx[ADDR_W-1:0];
                load_fetch_idx <= load_fetch_idx + 1'b1;
            end else begin
                loading <= 1'b0;
                load_data_valid <= 1'b0;
                load_fetch_idx <= '0;
                load_write_idx <= '0;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (~core_rst_n) begin
            fetch_pc <= '0;
            fetch_pc_d <= '0;
            fetch_valid <= 1'b0;
        end else if (flush) begin
            fetch_pc <= redirect_pc;
            fetch_pc_d <= redirect_pc;
            fetch_valid <= 1'b0;
        end else begin
            fetch_valid <= 1'b1;
            if (!iq_full) begin
                fetch_pc <= fetch_pc + 4;
                fetch_pc_d <= fetch_pc;
            end
        end
    end

    tomasulo_core u_core(
        .clk(clk),
        .rst_n(core_rst_n),
        .fetch_valid_i(fetch_valid & ~iq_full),
        .fetch_raw_i(instr_raw),
        .fetch_pc_i(fetch_pc_d),
        .iq_full_o(iq_full),
        .flush_o(flush),
        .redirect_pc_o(redirect_pc),
        .halted_o(halted_core),
        .mem_rd_addr_o(mem_rd_addr_core),
        .mem_rd_data_i(mem_rd_data),
        .mem_wr_en_o(mem_wr_en_core),
        .mem_wr_be_o(mem_wr_be_core),
        .mem_wr_addr_o(mem_wr_addr_core),
        .mem_wr_data_o(mem_wr_data_core)
    );

    always_ff @(posedge clk) begin
        if (~core_rst_n) begin
            cycle_count <= '0;
            halted <= 1'b0;
        end else begin
            if (halted_core)
                halted <= 1'b1;

            if (!(halted || halted_core))
                cycle_count <= cycle_count + 32'd1;
        end
    end

    always_ff @(posedge clk) begin
        if (~rst_n) begin
            key1_prev <= 1'b1;
            key2_prev <= 1'b1;
            key3_prev <= 1'b1;
        end else begin
            key1_prev <= KEY[1];
            key2_prev <= KEY[2];
            key3_prev <= KEY[3];
        end
    end

    always_ff @(posedge clk) begin
        if (~core_rst_n) begin
            review_index <= '0;
            review_mode_d <= 1'b0;
            review_correct_count <= '0;
            for (review_i = 0; review_i < REVIEW_MAX; review_i = review_i + 1)
                review_marks[review_i] <= MARK_UNKNOWN;
        end else begin
            review_mode_d <= review_mode;

            if (~review_mode_d & review_mode)
                review_index <= '0;

            if (review_mode && (sig_word_count != '0)) begin
                if (key1_press) begin
                    if (review_marks[review_slot] != MARK_CORRECT)
                        review_correct_count <= review_correct_count + 1'b1;
                    review_marks[review_slot] <= MARK_CORRECT;

                    if ((review_index + 1'b1) < sig_word_count)
                        review_index <= review_index + 1'b1;
                end else if (key2_press) begin
                    if (review_index != '0)
                        review_index <= review_index - 1'b1;
                end else if (key3_press) begin
                    if (review_marks[review_slot] == MARK_CORRECT)
                        review_correct_count <= review_correct_count - 1'b1;
                    review_marks[review_slot] <= MARK_WRONG;

                    if ((review_index + 1'b1) < sig_word_count)
                        review_index <= review_index + 1'b1;
                end
            end
        end
    end

    assign LEDR[9] = halted;
    assign LEDR[8] = loading;
    assign LEDR[7] = review_mode;
    assign LEDR[6:0] = review_mode ? review_correct_count : {1'b0, active_program};

    assign HEX0 = hex_digit(hex_display_value[3:0]);
    assign HEX1 = hex_digit(hex_display_value[7:4]);
    assign HEX2 = hex_digit(hex_display_value[11:8]);
    assign HEX3 = hex_digit(hex_display_value[15:12]);
    assign HEX4 = hex_digit(hex_display_value[19:16]);
    assign HEX5 = hex_digit(hex_display_value[23:20]);

endmodule : cpu
