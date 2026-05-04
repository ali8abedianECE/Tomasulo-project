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

    logic [NUM_FU-1:0]              valid_vec;   ///< Valid bits packed from fu_results_i.
    logic [NUM_FU-1:0]              grant_vec;   ///< 1-hot grant from arbiter.
    logic [NUM_FU-1:0]              base;        ///< 1-hot start: slot after last_grant.
    logic [NUM_FU-1:0]              last_grant;  ///< 1-hot last winner (registered).
    logic [$clog2(NUM_FU)-1:0]      grant_idx;   ///< Binary index of winning FU.
    logic                           grant_valid; ///< At least one FU has a result.

    assign valid_vec   = {fu_results_i[6].valid, fu_results_i[5].valid,
                          fu_results_i[4].valid, fu_results_i[3].valid,
                          fu_results_i[2].valid, fu_results_i[1].valid,
                          fu_results_i[0].valid};
    assign base        = {last_grant[NUM_FU-2:0], last_grant[NUM_FU-1]};
    assign fu_grant_o  = grant_vec;
    assign grant_valid = |grant_vec;

    // 1-hot to binary: only one term contributes since grant_vec is 1-hot
    assign grant_idx = ({3{grant_vec[6]}} & 3'd6) |
                       ({3{grant_vec[5]}} & 3'd5) |
                       ({3{grant_vec[4]}} & 3'd4) |
                       ({3{grant_vec[3]}} & 3'd3) |
                       ({3{grant_vec[2]}} & 3'd2) |
                       ({3{grant_vec[1]}} & 3'd1) |
                       ({3{grant_vec[0]}} & 3'd0);

    arbiter #(.WIDTH(NUM_FU)) u_arb(.req(valid_vec), .grant(grant_vec), .base(base));

    always_comb begin
        cdb_o = '{valid: 1'b0, tag: '0, value: '0};
        if (grant_valid)
            cdb_o = fu_results_i[grant_idx];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) last_grant <= {{NUM_FU-1{1'b0}}, 1'b1};
        else if (|grant_vec) last_grant <= grant_vec;
    end

endmodule : cdb
