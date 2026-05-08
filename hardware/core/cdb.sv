/**
 * @brief Round-robin Common Data Bus arbiter for NUM_FU functional units.
 *
 * Each cycle at most one result is broadcast. last_grant (1-hot) tracks the
 * previous winner; base rotates it left by one to give the next start point.
 * The arbiter finds the first valid input at or after base (wrapping). The
 * winning result is broadcast combinationally on cdb_o.
 *
 * FU index mapping:
 *   0 - Integer ALU
 *   1 - Branch unit
 *   2 - FP add/sub
 *   3 - FP mul
 *   4 - FP div
 *   5 - Load (LSB)
 *   6 - FP convert
 *
 * @param clk Rising-edge clock.
 * @param rst_n Active-low async reset.
 * @param fu_results_i One cdb_t per functional unit.
 * @param cdb_o Winning result broadcast to ROB and all RS entries.
 * @param fu_grant_o 1-hot grant vector - each FU clears its result register when its bit fires.
 */
module cdb(clk, rst_n, fu_results_i, cdb_o, fu_grant_o);
    import rv32if_pkg::*;

    input logic clk;
    input logic rst_n;
    input cdb_t fu_results_i [NUM_FU]; ///< Results from each functional unit.
    output cdb_t cdb_o;  ///< Winning broadcast this cycle.
    output logic [NUM_FU-1:0] fu_grant_o; ///< 1-hot: tells each FU it was served this cycle.

    localparam IDX_W = $clog2(NUM_FU);

    logic [NUM_FU-1:0] valid_vec;           ///< Valid bits packed from fu_results_i.
    logic [NUM_FU-1:0] grant_vec;           ///< 1-hot grant from arbiter.
    logic [NUM_FU-1:0] base;                ///< 1-hot start: slot after last_grant.
    logic [NUM_FU-1:0] last_grant;          ///< 1-hot last winner (registered).
    logic [IDX_W-1:0]  grant_idx;           ///< Binary index of winning FU.
    logic              grant_valid;         ///< At least one FU has a result.
    logic [IDX_W-1:0]  idx_terms   [NUM_FU]; ///< Per-FU masked index (non-zero only for winner).
    logic [IDX_W-1:0]  idx_reduce  [NUM_FU]; ///< Prefix-OR chain; last entry is grant_idx.

    assign base        = {last_grant[NUM_FU-2:0], last_grant[NUM_FU-1]};
    assign fu_grant_o  = grant_vec;
    assign grant_valid = |grant_vec;

    // 1-hot to binary via genvar: mask each slot's index, then prefix-OR reduce
    // Use a per-slot wire to avoid iverilog crash on fu_results_i[i].valid (array[i].member).
    genvar i;
    generate
        for (i = 0; i < NUM_FU; i++) begin : gen_terms
            cdb_t fu_i_w;
            assign fu_i_w      = fu_results_i[i];
            assign valid_vec[i] = fu_i_w.valid;
            assign idx_terms[i] = {IDX_W{grant_vec[i]}} & IDX_W'(i);
        end

        assign idx_reduce[0] = idx_terms[0];
        for (i = 1; i < NUM_FU; i++) begin : gen_reduce
            assign idx_reduce[i] = idx_reduce[i-1] | idx_terms[i];
        end
    endgenerate

    assign grant_idx = idx_reduce[NUM_FU-1];

    arbiter #(.WIDTH(NUM_FU)) u_arb(.req(valid_vec), .grant(grant_vec), .base(base));

    always_comb begin
        cdb_o.valid = 1'b0;
        cdb_o.tag   = '0;
        cdb_o.value = '0;
        if (grant_valid)
            cdb_o = fu_results_i[grant_idx];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) last_grant <= {{NUM_FU-1{1'b0}}, 1'b1};
        else if (|grant_vec) last_grant <= grant_vec;
    end

endmodule : cdb
