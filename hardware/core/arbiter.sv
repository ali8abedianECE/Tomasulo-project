/**
 * @brief Combinational round-robin arbiter.
 *
 * Uses the double-width trick: duplicates req, subtracts base, finds the
 * first set bit at or after base, then folds back to WIDTH bits.
 * base must be a 1-hot vector pointing to the slot after last_grant.
 *
 * @param req   1-hot or multi-hot request vector.
 * @param grant 1-hot grant output - lowest set bit at or after base wins.
 * @param base  1-hot start position for this round (next after last winner).
 */
module arbiter(req, grant, base);

    parameter WIDTH = 16;

    input logic [WIDTH-1:0] req;
    output logic [WIDTH-1:0] grant;
    input logic [WIDTH-1:0] base;

    logic [2*WIDTH-1:0] double_req;
    logic [2*WIDTH-1:0] double_grant;

    assign double_req = {req, req};
    assign double_grant = double_req & ~(double_req - base);
    assign grant = double_grant[WIDTH-1:0] | double_grant[2*WIDTH-1:WIDTH];

endmodule : arbiter
