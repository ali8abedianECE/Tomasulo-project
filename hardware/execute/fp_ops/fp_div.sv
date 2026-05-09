/**
 * @brief Unpipelined FP divide unit (FDIV.S), 8-cycle restoring division.
 *
 * State machine: IDLE -> DIVIDE (cnt 0..6) -> DONE.
 * Processes 3 quotient bits per cycle; 7 cycles of iteration after the first
 * 3-bit step in IDLE, giving 24 quotient bits total.
 * fu_ready_o is asserted only in IDLE. The unit stalls in DONE until the CDB
 * arbiter grants a broadcast slot.
 * Normalized operands only; truncation rounding; no NaN/Inf/denormal handling.
 *
 * @param clk/rst_n/flush_i Standard control.
 * @param valid_i/tag_i/rs1_i/rs2_i Issue interface from RS.
 * @param cdb_grant_i CDB arbiter granted this FU this cycle.
 * @param fu_ready_o FU can accept a new instruction this cycle.
 * @param cdb_valid_o/cdb_tag_o/cdb_result_o Result for CDB broadcast.
 */
module fp_div(clk, rst_n, flush_i,
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

    // -------------------------------------------------------------------------
    // State machine
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] { IDLE, DIVIDE, DONE } state_e;
    state_e state;

    // Divider registers
    logic [TAG_W-1:0] s_tag;
    logic s_sign;
    logic [9:0] s_exp;
    logic [23:0] s_dv;      // divisor mantissa (1.frac)
    logic [23:0] s_preg;    // partial remainder
    logic [23:0] s_sreg;    // remaining dividend bits (shift register)
    logic [23:0] s_qreg;    // accumulated quotient bits
    logic [2:0] s_cnt;     // iteration counter (0..6 = 7 iterations after first)

    // -------------------------------------------------------------------------
    // 3-bit restoring division step (combinational, unrolled)
    // Takes current partial remainder p, shift register s, divisor dv.
    // Returns next p, s, and 3 quotient bits q[2:1:0] (MSB first).
    //
    // Two identical copies (div3_step / div3_idle) exist because iverilog has a
    // bug where two always_comb blocks calling the *same* automatic task share
    // sensitivity-list state, causing an infinite delta-cycle loop.  Using
    // separate task symbols eliminates the interference.
    //
    // Shift ops replace {p[22:0],s[23]} / {s[22:0],1'b0} to avoid iverilog's
    // "sorry: constant selects" adding local p/s to the always_comb sensitivity.
    // Explicit if/else avoids reading qbits[N] back after writing it.
    // -------------------------------------------------------------------------
    task automatic div3_step(
        input  logic [23:0] p_in,
        input  logic [23:0] s_in,
        input  logic [23:0] dv,
        output logic [23:0] p_out,
        output logic [23:0] s_out,
        output logic [2:0]  qbits
    );
        logic [23:0] p, s;
        begin
            p = p_in; s = s_in;
            p = (p << 1) | (s >> 23); s = s << 1;
            if (p >= dv) begin qbits[2] = 1'b1; p = p - dv; end
            else              qbits[2] = 1'b0;
            p = (p << 1) | (s >> 23); s = s << 1;
            if (p >= dv) begin qbits[1] = 1'b1; p = p - dv; end
            else              qbits[1] = 1'b0;
            p = (p << 1) | (s >> 23); s = s << 1;
            if (p >= dv) begin qbits[0] = 1'b1; p = p - dv; end
            else              qbits[0] = 1'b0;
            p_out = p;
            s_out = s;
        end
    endtask

    task automatic div3_idle(
        input  logic [23:0] p_in,
        input  logic [23:0] s_in,
        input  logic [23:0] dv,
        output logic [23:0] p_out,
        output logic [23:0] s_out,
        output logic [2:0]  qbits
    );
        logic [23:0] p, s;
        begin
            p = p_in; s = s_in;
            p = (p << 1) | (s >> 23); s = s << 1;
            if (p >= dv) begin qbits[2] = 1'b1; p = p - dv; end
            else              qbits[2] = 1'b0;
            p = (p << 1) | (s >> 23); s = s << 1;
            if (p >= dv) begin qbits[1] = 1'b1; p = p - dv; end
            else              qbits[1] = 1'b0;
            p = (p << 1) | (s >> 23); s = s << 1;
            if (p >= dv) begin qbits[0] = 1'b1; p = p - dv; end
            else              qbits[0] = 1'b0;
            p_out = p;
            s_out = s;
        end
    endtask

    // -------------------------------------------------------------------------
    // Combinational: next-step outputs from current registers (used in DIVIDE)
    // -------------------------------------------------------------------------
    logic [23:0] c_preg, c_sreg;
    logic [2:0]  c_qbits;

    always_comb begin
        div3_step(s_preg, s_sreg, s_dv, c_preg, c_sreg, c_qbits);
    end

    // -------------------------------------------------------------------------
    // Result packing from 24-bit quotient
    // -------------------------------------------------------------------------
    logic [DATA_W-1:0] c_result;
    // Local vars with bit-select reads inside always_comb trigger iverilog
    // "sorry: constant selects" -- locals get added to sensitivity and
    // re-init to X each evaluation, causing an infinite delta-cycle loop.
    // Fix: inline the expressions directly using module-level signals.
    always_comb begin
        if (s_exp[9] | (s_exp == 10'd0)) begin
            c_result = 32'h0;
        end else if (s_exp > 10'd254) begin
            c_result = {s_sign, 8'hFE, 23'h7FFFFF};
        end else if (s_qreg[23]) begin
            c_result = {s_sign, s_exp[7:0], s_qreg[22:0]};
        end else if (s_exp > 10'd1) begin
            // Leading bit is 0: shift mantissa left, decrement exponent.
            // s_exp in [2,254] so s_exp[7:0]-1 never borrows into bit 8.
            c_result = {s_sign, s_exp[7:0] - 8'd1, {s_qreg[21:0], 1'b0}};
        end else begin
            c_result = 32'h0;
        end
    end

    // -------------------------------------------------------------------------
    // Combinational: IDLE-entry precompute from rs1_i/rs2_i
    // -------------------------------------------------------------------------
    logic        c_idle_sign;
    logic [9:0]  c_idle_exp;
    logic [23:0] c_idle_dv, c_idle_preg, c_idle_sreg;
    logic [23:0] c_idle_qreg;

    always_comb begin
        logic [7:0]  ea, eb;
        logic [23:0] ma, mb, p0, s0;
        logic [2:0]  qb0;
        ea = rs1_i[30:23]; ma = {1'b1, rs1_i[22:0]};
        eb = rs2_i[30:23]; mb = {1'b1, rs2_i[22:0]};
        c_idle_sign = rs1_i[31] ^ rs2_i[31];
        c_idle_exp  = {2'b0, ea} - {2'b0, eb} + 10'd127;
        c_idle_dv   = mb;
        div3_idle(24'h0, ma, mb, p0, s0, qb0);
        c_idle_preg = p0;
        c_idle_sreg = s0;
        c_idle_qreg = {21'h0, qb0};
    end

    // -------------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------------
    assign fu_ready_o = (state == IDLE);
    assign cdb_valid_o = (state == DONE);
    assign cdb_tag_o = s_tag;
    assign cdb_result_o = c_result;

    // -------------------------------------------------------------------------
    // State machine and datapath registers
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (~rst_n) begin
            state <= IDLE;
            s_tag <= '0;
            s_sign <= 1'b0;
            s_exp <= '0;
            s_dv <= '0;
            s_preg <= '0;
            s_sreg <= '0;
            s_qreg <= '0;
            s_cnt <= '0;
        end else if (flush_i) begin 
            state <= IDLE;
            s_tag <= '0;
            s_sign <= 1'b0;
            s_exp <= '0;
            s_dv <= '0;
            s_preg <= '0;
            s_sreg <= '0;
            s_qreg <= '0;
            s_cnt <= '0;
        end else begin
            case (state)
                IDLE: begin
                    if (valid_i) begin
                        s_tag  <= tag_i;
                        s_sign <= c_idle_sign;
                        s_exp  <= c_idle_exp;
                        s_dv   <= c_idle_dv;
                        s_preg <= c_idle_preg;
                        s_sreg <= c_idle_sreg;
                        s_qreg <= c_idle_qreg;
                        s_cnt  <= 3'd0;
                        state  <= DIVIDE;
                    end
                end

                DIVIDE: begin
                    s_preg <= c_preg;
                    s_sreg <= c_sreg;
                    s_qreg <= {s_qreg[20:0], c_qbits};
                    if (s_cnt == 3'd6) begin
                        state <= DONE;
                    end else begin
                        s_cnt <= s_cnt + 3'd1;
                    end
                end

                DONE: begin
                    if (cdb_grant_i)
                        state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule : fp_div
