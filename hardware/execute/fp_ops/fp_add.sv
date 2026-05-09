/**
 * @brief 2-stage pipelined FP add/subtract unit (FADD.S, FSUB.S).
 *
 * Stage 1 computes the IEEE 754 result combinationally; stage 2 holds it
 * until the CDB arbiter grants a broadcast slot. When stage 2 is occupied
 * and not granted, fu_ready_o deasserts and the pipeline freezes.
 * Normalized operands only; truncate rounding; no NaN/Inf/denormal handling.
 *
 * @param clk/rst_n/flush_i Standard control.
 * @param valid_i/op_i/tag_i/rs1_i/rs2_i Issue interface from RS.
 * @param cdb_grant_i CDB arbiter granted this FU this cycle.
 * @param fu_ready_o FU can accept a new instruction this cycle.
 * @param cdb_valid_o/cdb_tag_o/cdb_result_o Result for CDB broadcast.
 */
module fp_add(clk, rst_n, flush_i,
              valid_i, op_i, tag_i, rs1_i, rs2_i,
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
    input logic [DATA_W-1:0] rs2_i;

    input logic cdb_grant_i;
    output logic fu_ready_o;

    output logic cdb_valid_o;
    output logic [TAG_W-1:0] cdb_tag_o;
    output logic [DATA_W-1:0] cdb_result_o;

    // -------------------------------------------------------------------------
    // IEEE 754 single-precision add/subtract (normalized numbers, truncation).
    //
    // Representation: a = (-1)^sa * 1.ma * 2^(ea-127)
    // Guard bits: 2 bits appended to the 24-bit extended mantissa -> 26-bit xa/xb
    // Sum: 27 bits to catch the carry-out.
    // Normalization: barrel-shift so the leading 1 lands at bit 25 of the 26-bit
    // result mantissa, then extract bits [24:2] as the 23-bit fractional field.
    // -------------------------------------------------------------------------
    function automatic logic [31:0] fp_add_core(
        input logic [31:0] a,
        input logic [31:0] b,
        input logic subtract
    );
        logic sa, sb, sr;
        logic [7:0]  ea, eb, er, ediff, sh;
        logic [23:0] ma, mb;
        logic [25:0] xa, xb, norm;
        logic [26:0] s;
        logic [4:0] lop;

        begin
            sa = a[31]; ea = a[30:23]; ma = {1'b1, a[22:0]};
            sb = b[31] ^ subtract;
            eb = b[30:23]; mb = {1'b1, b[22:0]};

            if (ea == 8'd0 && eb == 8'd0) begin
                fp_add_core = 32'h0;
            end else if (ea == 8'd0) begin
                fp_add_core = {sb, b[30:0]};
            end else if (eb == 8'd0) begin
                fp_add_core = a;
            end else begin
                // Swap so ea >= eb (simplifies alignment)
                if (eb > ea) begin
                    {sa, sb} = {sb, sa};
                    {ea, eb} = {eb, ea};
                    {ma, mb} = {mb, ma};
                end

                ediff = ea - eb;
                xa = {ma, 2'b00};
                xb = (ediff > 8'd25) ? 26'h0 : ({mb, 2'b00} >> ediff[4:0]);
                er = ea;

                // Add or subtract
                if (sa == sb) begin
                    s = {1'b0, xa} + {1'b0, xb};
                    sr = sa;
                end else if (xa >= xb) begin
                    s = {1'b0, xa} - {1'b0, xb};
                    sr = sa;
                end else begin
                    s = {1'b0, xb} - {1'b0, xa};
                    sr = sb;
                end

                if (s == 27'h0) begin
                    fp_add_core = 32'h0;
                end else if (s[26]) begin
                    // Carry: implicit 1 shifted to bit 26; extract bits 25:3
                    er = er + 8'd1;
                    fp_add_core = {sr, er, s[25:3]};
                end else begin
                    // Find highest set bit in s[25:0] (last assignment wins)
                    lop = 5'd0;
                    for (int i = 0; i < 26; i++)
                        if (s[i]) lop = 5'(i);

                    sh = 8'd25 - {3'b0, lop};
                    norm = s[25:0] << sh[4:0];

                    if (er > sh) begin
                        er = er - sh;
                        fp_add_core = {sr, er, norm[24:2]};
                    end else begin
                        fp_add_core = 32'h0;  // exponent underflow
                    end
                end
            end
        end
    endfunction

    logic [DATA_W-1:0] compute_result;
    logic advance;

    logic s1_valid;
    logic [TAG_W-1:0] s1_tag;
    logic [DATA_W-1:0] s1_result;

    logic s2_valid;
    logic [TAG_W-1:0] s2_tag;
    logic [DATA_W-1:0] s2_result;

    always_comb begin
        compute_result = fp_add_core(rs1_i, rs2_i, op_i == OP_FSUB_S);
    end 
    
    assign advance = ~s2_valid | cdb_grant_i;
    assign fu_ready_o = advance;
    assign cdb_valid_o = s2_valid;
    assign cdb_tag_o = s2_tag;
    assign cdb_result_o = s2_result;

    always_ff @(posedge clk) begin
        if (~rst_n) begin
            s1_valid <= 1'b0; s1_tag <= '0; s1_result <= '0;
            s2_valid <= 1'b0; s2_tag <= '0; s2_result <= '0;
        end else if (flush_i) begin 
            s1_valid <= 1'b0; s1_tag <= '0; s1_result <= '0;
            s2_valid <= 1'b0; s2_tag <= '0; s2_result <= '0;
        end else if (advance) begin
            s2_valid <= s1_valid;
            s2_tag <= s1_tag;
            s2_result <= s1_result;
            s1_valid <= valid_i;
            s1_tag <= tag_i;
            s1_result <= valid_i ? compute_result : '0;
        end
    end

endmodule : fp_add
