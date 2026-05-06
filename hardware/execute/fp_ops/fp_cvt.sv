/**
 * @brief 2-stage pipelined FP conversion unit (FCVT.W.S, FCVT.S.W).
 *
 * Stage 1 computes the result combinationally; stage 2 holds it until the
 * CDB arbiter grants a broadcast slot. When stage 2 is occupied and not
 * granted, fu_ready_o deasserts and the pipeline freezes.
 * Normalized operands only; truncation rounding; no NaN/Inf/denormal handling.
 *
 * FCVT.W.S: rs1_i is IEEE 754 float, result is signed int32.
 * FCVT.S.W: rs1_i is signed int32, result is IEEE 754 float.
 *
 * @param clk/rst_n/flush_i Standard control.
 * @param valid_i/op_i/tag_i/rs1_i Issue interface from RS.
 * @param cdb_grant_i CDB arbiter granted this FU this cycle.
 * @param fu_ready_o FU can accept a new instruction this cycle.
 * @param cdb_valid_o/cdb_tag_o/cdb_result_o Result for CDB broadcast.
 */
module fp_cvt(clk, rst_n, flush_i,
              valid_i, op_i, tag_i, rs1_i,
              cdb_grant_i, fu_ready_o,
              cdb_valid_o, cdb_tag_o, cdb_result_o);
    import rv32if_pkg::*;

    input logic clk;
    input logic rst_n;
    input logic flush_i;

    input logic valid_i;
    input opcode_e op_i;
    input logic [TAG_W-1:0] tag_i;
    input logic [DATA_W-1:0] rs1_i;

    input logic cdb_grant_i;
    output logic fu_ready_o;

    output logic cdb_valid_o;
    output logic [TAG_W-1:0] cdb_tag_o;
    output logic [DATA_W-1:0] cdb_result_o;

    // -------------------------------------------------------------------------
    // FCVT.W.S: IEEE 754 float -> signed int32 (truncation toward zero).
    //
    // Works directly with biased exponent fe to avoid signed arithmetic:
    //   fe < 127        -> |x| < 1.0, result = 0
    //   fe >= 158       -> |x| >= 2^31, saturate
    //   otherwise       -> exponent in [0,30], shift mantissa
    // -------------------------------------------------------------------------
    function automatic logic [31:0] fp_to_int(input logic [31:0] f);
        logic        fs;
        logic [7:0]  fe;
        logic [23:0] fmant;
        logic [4:0]  exp_u;
        logic [31:0] mag;
        logic [4:0]  sh;
        begin
            fs    = f[31];
            fe    = f[30:23];
            fmant = {1'b1, f[22:0]};

            if (fe == 8'd0) begin
                fp_to_int = 32'd0;
            end else if (fe < 8'd127) begin
                fp_to_int = 32'd0;
            end else if (fe >= 8'd158) begin
                fp_to_int = fs ? 32'h80000000 : 32'h7FFFFFFF;
            end else begin
                exp_u = 5'(fe - 8'd127);
                if (exp_u >= 5'd23) begin
                    sh  = exp_u - 5'd23;
                    mag = {8'h0, fmant} << sh;
                end else begin
                    sh  = 5'd23 - exp_u;
                    mag = {8'h0, fmant} >> sh;
                end
                fp_to_int = fs ? (~mag + 32'd1) : mag;
            end
        end
    endfunction

    // -------------------------------------------------------------------------
    // FCVT.S.W: signed int32 -> IEEE 754 float (truncation rounding).
    //
    // Finds the highest set bit of the magnitude with a last-wins for-loop,
    // shifts the magnitude left so the leading 1 lands at bit 31, then
    // extracts bits [30:8] as the 23-bit fractional mantissa field.
    // -------------------------------------------------------------------------
    function automatic logic [31:0] int_to_fp(input logic [31:0] x);
        logic        xs;
        logic [31:0] mag;
        logic [4:0]  pos;
        logic [4:0]  sh;
        logic [31:0] norm;
        logic [7:0]  fe;
        begin
            if (x == 32'd0) begin
                int_to_fp = 32'h0;
            end else begin
                xs  = x[31];
                mag = xs ? (~x + 32'd1) : x;

                pos = 5'd0;
                for (int i = 0; i < 32; i++)
                    if (mag[i]) pos = 5'(i);

                sh   = 5'd31 - pos;
                norm = mag << sh;
                fe   = 8'(8'd127 + {3'b0, pos});

                int_to_fp = {xs, fe, norm[30:8]};
            end
        end
    endfunction

    // -------------------------------------------------------------------------
    // Combinational dispatch
    // -------------------------------------------------------------------------
    logic [DATA_W-1:0] compute_result;

    always_comb begin
        if (op_i == OP_FCVT_W_S)
            compute_result = fp_to_int(rs1_i);
        else
            compute_result = int_to_fp(rs1_i);
    end

    // -------------------------------------------------------------------------
    // 2-stage pipeline with CDB backpressure
    // -------------------------------------------------------------------------
    logic advance;

    logic s1_valid;
    logic [TAG_W-1:0] s1_tag;
    logic [DATA_W-1:0] s1_result;

    logic s2_valid;
    logic [TAG_W-1:0] s2_tag;
    logic [DATA_W-1:0] s2_result;

    assign advance    = ~s2_valid | cdb_grant_i;
    assign fu_ready_o = advance;
    assign cdb_valid_o  = s2_valid;
    assign cdb_tag_o    = s2_tag;
    assign cdb_result_o = s2_result;

    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n || flush_i) begin
            s1_valid <= 1'b0; s1_tag <= '0; s1_result <= '0;
            s2_valid <= 1'b0; s2_tag <= '0; s2_result <= '0;
        end else if (advance) begin
            s2_valid  <= s1_valid;
            s2_tag    <= s1_tag;
            s2_result <= s1_result;
            s1_valid  <= valid_i;
            s1_tag    <= tag_i;
            s1_result <= valid_i ? compute_result : '0;
        end
    end

endmodule : fp_cvt
