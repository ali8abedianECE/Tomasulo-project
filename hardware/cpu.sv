/**
 * @brief DE1-SoC top-level for the RV32IF Tomasulo processor.
 *
 * Instantiates instr_mem, data_mem, and tomasulo_core. Adds a 1-cycle
 * fetch stage (PC register + decode). The 32-bit cycle counter is shown
 * on HEX5..HEX0 as six hex digits. KEY[0] is active-low reset.
 *
 * HEX display: HEX5:HEX4 = cycle_count[23:16],
 *              HEX3:HEX2 = cycle_count[15:8],
 *              HEX1:HEX0 = cycle_count[7:0].
 * LEDR[9] = halted (OP_HALT retired), LEDR[8] = flush active.
 */
module cpu(CLOCK_50, KEY, SW, LEDR, HEX0, HEX1, HEX2, HEX3, HEX4, HEX5);
    import rv32if_pkg::*;

    input  logic        CLOCK_50;
    input  logic [3:0]  KEY;
    input  logic [9:0]  SW;
    output logic [9:0]  LEDR;
    output logic [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;

    logic clk, rst_n;
    assign clk   = CLOCK_50;
    assign rst_n = KEY[0];   // KEY[0] active-low

    // -------------------------------------------------------------------------
    // Decode: raw 32-bit instruction -> instr_t
    // -------------------------------------------------------------------------
    function automatic instr_t decode(input logic [31:0] raw, input logic [PC_W-1:0] pc);
        logic [6:0] opcode, funct7;
        logic [2:0] funct3;
        logic [4:0] rd, rs1, rs2;
        instr_t     d;
        begin
            opcode = raw[6:0]; rd = raw[11:7]; funct3 = raw[14:12];
            rs1 = raw[19:15];  rs2 = raw[24:20]; funct7 = raw[31:25];

            d = '{op: OP_NOP, rd: '0, rs1: '0, rs2: '0, imm: '0,
                  rd_fp: 1'b0, rs1_fp: 1'b0, rs2_fp: 1'b0, rd_valid: 1'b0, pc: pc};

            case (opcode)
                7'h33: begin // R-type INT
                    d.rd = rd; d.rs1 = rs1; d.rs2 = rs2; d.rd_valid = 1'b1;
                    case ({funct7[5], funct3})
                        4'b0_000: d.op = OP_ADD;  4'b1_000: d.op = OP_SUB;
                        4'b0_111: d.op = OP_AND;  4'b0_110: d.op = OP_OR;
                        4'b0_100: d.op = OP_XOR;  4'b0_001: d.op = OP_SLL;
                        4'b0_101: d.op = OP_SRL;  4'b1_101: d.op = OP_SRA;
                        default:  d.op = OP_NOP;
                    endcase
                end
                7'h13: begin // I-type INT
                    d.rd = rd; d.rs1 = rs1; d.rd_valid = 1'b1;
                    d.imm = {{20{raw[31]}}, raw[31:20]};
                    case (funct3)
                        3'b000: d.op = OP_ADDI; 3'b111: d.op = OP_ANDI;
                        3'b110: d.op = OP_ORI;  3'b100: d.op = OP_XORI;
                        3'b001: d.op = OP_SLLI; 3'b101: d.op = OP_SRLI;
                        default: d.op = OP_NOP;
                    endcase
                end
                7'h03: begin // LW
                    if (funct3 == 3'b010) begin
                        d.op = OP_LW; d.rd = rd; d.rs1 = rs1; d.rd_valid = 1'b1;
                        d.imm = {{20{raw[31]}}, raw[31:20]};
                    end
                end
                7'h23: begin // SW
                    if (funct3 == 3'b010) begin
                        d.op = OP_SW; d.rs1 = rs1; d.rs2 = rs2;
                        d.imm = {{20{raw[31]}}, raw[31:25], raw[11:7]};
                    end
                end
                7'h63: begin // branches
                    d.rs1 = rs1; d.rs2 = rs2;
                    d.imm = {{19{raw[31]}}, raw[31], raw[7], raw[30:25], raw[11:8], 1'b0};
                    case (funct3)
                        3'b000: d.op = OP_BEQ; 3'b001: d.op = OP_BNE;
                        3'b100: d.op = OP_BLT; 3'b101: d.op = OP_BGE;
                        default: d.op = OP_NOP;
                    endcase
                end
                7'h6F: begin // JAL
                    d.op = OP_JAL; d.rd = rd; d.rd_valid = 1'b1;
                    d.imm = {{11{raw[31]}}, raw[31], raw[19:12], raw[20], raw[30:21], 1'b0};
                end
                7'h67: begin // JALR
                    if (funct3 == 3'b000) begin
                        d.op = OP_JALR; d.rd = rd; d.rs1 = rs1; d.rd_valid = 1'b1;
                        d.imm = {{20{raw[31]}}, raw[31:20]};
                    end
                end
                7'h37: begin // LUI
                    d.op = OP_LUI; d.rd = rd; d.rd_valid = 1'b1;
                    d.imm = {raw[31:12], 12'b0};
                end
                7'h07: begin // FLW
                    if (funct3 == 3'b010) begin
                        d.op = OP_FLW; d.rd = rd; d.rs1 = rs1;
                        d.rd_valid = 1'b1; d.rd_fp = 1'b1;
                        d.imm = {{20{raw[31]}}, raw[31:20]};
                    end
                end
                7'h27: begin // FSW
                    if (funct3 == 3'b010) begin
                        d.op = OP_FSW; d.rs1 = rs1; d.rs2 = rs2; d.rs2_fp = 1'b1;
                        d.imm = {{20{raw[31]}}, raw[31:25], raw[11:7]};
                    end
                end
                7'h53: begin // FP arithmetic / conversion
                    case (funct7)
                        7'b0000000: begin d.op=OP_FADD_S; d.rd=rd; d.rs1=rs1; d.rs2=rs2; d.rd_valid=1'b1; d.rd_fp=1'b1; d.rs1_fp=1'b1; d.rs2_fp=1'b1; end
                        7'b0000100: begin d.op=OP_FSUB_S; d.rd=rd; d.rs1=rs1; d.rs2=rs2; d.rd_valid=1'b1; d.rd_fp=1'b1; d.rs1_fp=1'b1; d.rs2_fp=1'b1; end
                        7'b0001000: begin d.op=OP_FMUL_S; d.rd=rd; d.rs1=rs1; d.rs2=rs2; d.rd_valid=1'b1; d.rd_fp=1'b1; d.rs1_fp=1'b1; d.rs2_fp=1'b1; end
                        7'b0001100: begin d.op=OP_FDIV_S; d.rd=rd; d.rs1=rs1; d.rs2=rs2; d.rd_valid=1'b1; d.rd_fp=1'b1; d.rs1_fp=1'b1; d.rs2_fp=1'b1; end
                        7'b1100000: begin d.op=OP_FCVT_W_S; d.rd=rd; d.rs1=rs1; d.rd_valid=1'b1; d.rs1_fp=1'b1; end
                        7'b1101000: begin d.op=OP_FCVT_S_W; d.rd=rd; d.rs1=rs1; d.rd_valid=1'b1; d.rd_fp=1'b1; end
                        default: d.op = OP_NOP;
                    endcase
                end
                7'h73: d.op = OP_HALT; // ECALL / EBREAK -> HALT
                default: d.op = OP_NOP;
            endcase
            decode = d;
        end
    endfunction

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
    logic [PC_W-1:0]   mem_rd_addr, mem_wr_addr;
    logic [DATA_W-1:0] mem_rd_data, mem_wr_data;
    logic              mem_wr_en;

    instr_mem #(.FILENAME("program.hex")) u_imem(
        .clk(clk), .pc_i(fetch_pc),
        .instr_o(instr_raw),
        .write_en_i(1'b0), .write_addr_i('0), .write_data_i('0)
    );

    data_mem #(.FILENAME("")) u_dmem(
        .clk(clk),
        .rd_addr_i(mem_rd_addr), .rd_data_o(mem_rd_data),
        .wr_en_i(mem_wr_en), .wr_addr_i(mem_wr_addr), .wr_data_i(mem_wr_data)
    );

    // -------------------------------------------------------------------------
    // Fetch stage: PC register + 1-cycle bubble after flush
    // -------------------------------------------------------------------------
    logic [PC_W-1:0] fetch_pc;   // sent to instr_mem this cycle
    logic [PC_W-1:0] fetch_pc_d; // PC of the instruction now on instr_mem output
    logic            fetch_valid; // instr_mem output is valid to push into IQ
    logic            iq_full;
    logic            flush;
    logic [PC_W-1:0] redirect_pc;

    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            fetch_pc    <= '0;
            fetch_pc_d  <= '0;
            fetch_valid <= 1'b0;
        end else if (flush) begin
            fetch_pc    <= redirect_pc;
            fetch_pc_d  <= redirect_pc;
            fetch_valid <= 1'b0;  // 1-cycle bubble: discard next instr_mem output
        end else begin
            fetch_valid <= 1'b1;
            if (!iq_full) begin
                fetch_pc   <= fetch_pc + 4;
                fetch_pc_d <= fetch_pc;
            end
        end
    end

    instr_t fetch_instr;
    always_comb fetch_instr = decode(instr_raw, fetch_pc_d);

    // -------------------------------------------------------------------------
    // Tomasulo core
    // -------------------------------------------------------------------------
    tomasulo_core u_core(
        .clk(clk), .rst_n(rst_n),
        .fetch_valid_i(fetch_valid & ~iq_full),
        .fetch_instr_i(fetch_instr),
        .iq_full_o(iq_full),
        .flush_o(flush), .redirect_pc_o(redirect_pc),
        .mem_rd_addr_o(mem_rd_addr), .mem_rd_data_i(mem_rd_data),
        .mem_wr_en_o(mem_wr_en), .mem_wr_addr_o(mem_wr_addr),
        .mem_wr_data_o(mem_wr_data)
    );

    // -------------------------------------------------------------------------
    // Cycle counter
    // -------------------------------------------------------------------------
    logic [31:0] cycle_count;
    logic        halted;

    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            cycle_count <= '0;
            halted      <= 1'b0;
        end else begin
            cycle_count <= cycle_count + 32'd1;
        end
    end

    // -------------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------------
    assign LEDR[8]   = flush;
    assign LEDR[9]   = 1'b0;
    assign LEDR[7:0] = cycle_count[7:0];

    assign HEX0 = hex_digit(cycle_count[3:0]);
    assign HEX1 = hex_digit(cycle_count[7:4]);
    assign HEX2 = hex_digit(cycle_count[11:8]);
    assign HEX3 = hex_digit(cycle_count[15:12]);
    assign HEX4 = hex_digit(cycle_count[19:16]);
    assign HEX5 = hex_digit(cycle_count[23:20]);

endmodule : cpu
