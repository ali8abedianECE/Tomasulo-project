/**
 * @brief Combinational IEEE 754 rounding unit.
 *
 * Accepts a pre-truncated mantissa, three rounding bits (guard, round, sticky),
 * and a RISC-V rounding mode, and produces the correctly-rounded IEEE 754
 * single-precision result.
 *
 * Rounding modes (rm_i encoding matches RISC-V fcsr.frm):
 *   000 RNE - Round to Nearest, ties to Even
 *   001 RTZ - Round toward Zero (truncate; same as the default FU behavior)
 *   010 RDN - Round Down (toward -infinity)
 *   011 RUP - Round Up   (toward +infinity)
 *   100 RMM - Round to Nearest, ties to Max Magnitude
 *
 * Mantissa overflow after rounding (1.frac + ulp -> 10.000) is handled by
 * incrementing the exponent; exponent overflow saturates to max-finite rather
 * than producing infinity.
 *
 * @param sign_i    Sign bit of the result.
 * @param exp_i     Biased exponent of the truncated result (before rounding).
 * @param mant_i    23-bit fractional mantissa (truncated, hidden bit excluded).
 * @param guard_i   First bit dropped during truncation.
 * @param round_i   Second bit dropped during truncation.
 * @param sticky_i  OR of all bits beyond guard and round.
 * @param rm_i      3-bit RISC-V rounding mode.
 * @param result_o  Rounded 32-bit IEEE 754 result.
 */
module fp_round(sign_i, exp_i, mant_i, guard_i, round_i, sticky_i, rm_i, result_o);
    import rv32if_pkg::*;

    input  logic        sign_i;
    input  logic [7:0]  exp_i;
    input  logic [22:0] mant_i;
    input  logic        guard_i;
    input  logic        round_i;
    input  logic        sticky_i;
    input  logic [2:0]  rm_i;
    output logic [DATA_W-1:0] result_o;

    // -------------------------------------------------------------------------
    // Round-up decision
    // -------------------------------------------------------------------------
    logic round_up;

    always_comb begin
        case (rm_i)
            3'b000:  round_up = guard_i & (round_i | sticky_i | mant_i[0]); // RNE
            3'b001:  round_up = 1'b0;                                        // RTZ
            3'b010:  round_up = sign_i  & (guard_i | round_i | sticky_i);   // RDN
            3'b011:  round_up = ~sign_i & (guard_i | round_i | sticky_i);   // RUP
            3'b100:  round_up = guard_i;                                     // RMM
            default: round_up = 1'b0;
        endcase
    end

    // -------------------------------------------------------------------------
    // Apply rounding and repack
    // -------------------------------------------------------------------------
    logic [23:0] mant_inc;
    logic [8:0]  exp_out;

    always_comb begin
        mant_inc = {1'b0, mant_i} + {23'h0, round_up};

        if (mant_inc[23])
            exp_out = {1'b0, exp_i} + 9'd1;  // carry into exponent
        else
            exp_out = {1'b0, exp_i};

        if (exp_out == 9'd0 || exp_out[8])
            result_o = 32'h0;                           // underflow -> zero
        else if (exp_out > 9'd254)
            result_o = {sign_i, 8'hFE, 23'h7FFFFF};    // overflow -> max finite
        else
            result_o = {sign_i, exp_out[7:0], mant_inc[22:0]};
    end

endmodule : fp_round
