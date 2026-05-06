/**
 * @brief 4-stage pipelined FP multiply unit (FMUL.S).
 *
 * Stage 1: extract fields, compute sign/exponent, split 24x24 into four 12x12
 *          partial products.
 * Stage 2: accumulate the four partial products into the full 48-bit mantissa.
 * Stage 3: normalize (one-bit shift check), pack IEEE 754 result.
 * Stage 4: hold result until CDB arbiter grants a broadcast slot.
 * When stage 4 is occupied and not granted the entire pipeline freezes.
 * Normalized operands only; truncate rounding; no NaN/Inf/denormal handling.
 *
 * @param clk/rst_n/flush_i Standard control.
 * @param valid_i/tag_i/rs1_i/rs2_i Issue interface from RS.
 * @param cdb_grant_i CDB arbiter granted this FU this cycle.
 * @param fu_ready_o FU can accept a new instruction this cycle.
 * @param cdb_valid_o/cdb_tag_o/cdb_result_o Result for CDB broadcast.
 */
module fp_mul(clk, rst_n, flush_i,
              valid_i, tag_i, rs1_i, rs2_i,
              cdb_grant_i, fu_ready_o,
              cdb_valid_o, cdb_tag_o, cdb_result_o);
    import rv32if_pkg::*;

    input logic clk;
    input logic rst_n;
    input logic flush_i;

    input logic valid_i;
    input logic [TAG_W-1:0] tag_i;
    input logic [DATA_W-1:0] rs1_i;
    input logic [DATA_W-1:0] rs2_i;

    input logic cdb_grant_i;
    output logic fu_ready_o;

    output logic cdb_valid_o;
    output logic [TAG_W-1:0] cdb_tag_o;
    output logic [DATA_W-1:0] cdb_result_o;

    logic advance;

    // ----- Stage 1 registers: partial products + sign/exponent -----
    logic s1_valid, s1_zero, s1_sign;
    logic [TAG_W-1:0] s1_tag;
    logic [9:0] s1_exp;
    logic [23:0] s1_hh, s1_hl, s1_lh, s1_ll; // four 12x12 partial products

    // ----- Stage 2 registers: full 48-bit mantissa product -----
    logic  s2_valid, s2_zero, s2_sign;
    logic [TAG_W-1:0] s2_tag;
    logic [9:0]  s2_exp;
    logic [47:0] s2_product;

    // ----- Stage 3 registers: packed IEEE 754 result -----
    logic s3_valid;
    logic [TAG_W-1:0] s3_tag;
    logic [DATA_W-1:0] s3_result;

    // ----- Stage 4 registers: CDB hold -----
    logic s4_valid;
    logic [TAG_W-1:0] s4_tag;
    logic [DATA_W-1:0] s4_result;

    // -------------------------------------------------------------------------
    // Combinational: stage-1 inputs (split-multiply prep)
    // -------------------------------------------------------------------------
    logic c1_sign, c1_zero;
    logic [9:0]  c1_exp;
    logic [23:0] c1_hh, c1_hl, c1_lh, c1_ll;

    always_comb begin
        logic [7:0]  ea, eb;
        logic [23:0] ma, mb;
        ea = rs1_i[30:23]; ma = {1'b1, rs1_i[22:0]};
        eb = rs2_i[30:23]; mb = {1'b1, rs2_i[22:0]};

        c1_sign = rs1_i[31] ^ rs2_i[31];
        c1_zero = (ea == 8'd0) | (eb == 8'd0);
        c1_exp  = {2'b0, ea} + {2'b0, eb} - 10'd127;

        // Split 24-bit mantissas into high (bits 23:12) and low (bits 11:0)
        c1_hh = ma[23:12] * mb[23:12]; // contributes to product bits [47:24]
        c1_hl = ma[23:12] * mb[11:0];  // contributes to product bits [35:12]
        c1_lh = ma[11:0] * mb[23:12]; // contributes to product bits [35:12]
        c1_ll = ma[11:0] * mb[11:0];  // contributes to product bits [23:0]
    end

    // -------------------------------------------------------------------------
    // Combinational: stage-2 inputs (accumulate partial products)
    // -------------------------------------------------------------------------
    logic [47:0] c2_product;

    always_comb begin 
        c2_product = {s1_hh, 24'b0}          // bits [47:24]
                   + {12'b0, s1_hl, 12'b0}   // bits [35:12]
                   + {12'b0, s1_lh, 12'b0}   // bits [35:12]
                   + {24'b0, s1_ll};          // bits [23:0]
    end 

    // -------------------------------------------------------------------------
    // Combinational: stage-3 inputs (normalize and pack)
    // -------------------------------------------------------------------------
    logic [DATA_W-1:0] c3_result;

    always_comb begin
        logic [9:0]  er;
        logic [22:0] mant;
        if (s2_zero | (s2_product == 48'h0)) begin
            c3_result = 32'h0;
        end else begin
            er = s2_exp;
            if (s2_product[47]) begin
                er = s2_exp + 10'd1;
                mant = s2_product[46:24];
            end else begin
                mant = s2_product[45:23];
            end
            if (er[9] | (er == 10'd0))  c3_result = 32'h0;
            else if (er > 10'd254)  c3_result = {s2_sign, 8'hFE, 23'h7FFFFF};
            else c3_result = {s2_sign, er[7:0], mant};
        end
    end

    // -------------------------------------------------------------------------
    // Pipeline control and registers
    // -------------------------------------------------------------------------
    assign advance = ~s4_valid | cdb_grant_i;
    assign fu_ready_o = advance;
    assign cdb_valid_o = s4_valid;
    assign cdb_tag_o = s4_tag;
    assign cdb_result_o = s4_result;

    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n || flush_i) begin
            s1_valid <= 1'b0; s1_tag <= '0; s1_zero <= 1'b0; s1_sign <= 1'b0;
            s1_exp <= '0; s1_hh <= '0; s1_hl <= '0;
            s1_lh <= '0; s1_ll <= '0;
            s2_valid <= 1'b0; s2_tag <= '0; s2_zero <= 1'b0; s2_sign <= 1'b0;
            s2_exp <= '0; s2_product <= '0;
            s3_valid <= 1'b0; s3_tag <= '0; s3_result <= '0;
            s4_valid <= 1'b0; s4_tag <= '0; s4_result <= '0;
        end else if (advance) begin
            // Stage 4 <- Stage 3
            s4_valid <= s3_valid;
            s4_tag <= s3_tag;
            s4_result <= s3_result;

            // Stage 3 <- Stage 2 (normalize and pack)
            s3_valid <= s2_valid;
            s3_tag <= s2_tag;
            s3_result <= c3_result;

            // Stage 2 <- Stage 1 (accumulate partial products)
            s2_valid <= s1_valid;
            s2_tag <= s1_tag;
            s2_sign <= s1_sign;
            s2_exp <= s1_exp;
            s2_zero <= s1_zero;
            s2_product <= c2_product;

            // Stage 1 <- Input (split multiply)
            s1_valid <= valid_i;
            s1_tag <= tag_i;
            s1_sign <= c1_sign;
            s1_exp <= c1_exp;
            s1_zero <= c1_zero;
            s1_hh <= c1_hh;
            s1_hl <= c1_hl;
            s1_lh <= c1_lh;
            s1_ll <= c1_ll;
        end
    end

endmodule : fp_mul
