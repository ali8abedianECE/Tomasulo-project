/**
 * @brief IQ_DEPTH-entry instruction queue FIFO between fetch and dispatch.
 *
 * Circular buffer of instr_t entries. Fetch pushes decoded instructions;
 * dispatch pops one per cycle when it can accept. Both push and pop may
 * occur in the same cycle - count stays the same. Flush clears the queue
 * synchronously (branch misprediction or exception).
 *
 * @param clk Rising-edge clock.
 * @param rst_n Active-low async reset.
 * @param flush_i Synchronous flush - empties the queue.
 * @param push_en_i Fetch is writing a new instruction.
 * @param push_instr_i Instruction to enqueue.
 * @param full_o Queue is full - fetch must stall.
 * @param pop_en_i Dispatch is consuming the head instruction.
 * @param instr_o Head instruction (combinational).
 * @param valid_o Queue is non-empty - head instruction is valid.
 */
module instr_queue(clk, rst_n, flush_i,
                   push_en_i, push_instr_i, full_o,
                   pop_en_i, instr_o, valid_o);
    import rv32if_pkg::*;

    input logic clk;
    input logic rst_n;
    input logic flush_i;

    input logic push_en_i;
    input instr_t push_instr_i;
    output logic full_o;

    input logic pop_en_i;
    output instr_t instr_o;
    output logic valid_o;

    localparam PTR_W = $clog2(IQ_DEPTH);

    instr_t entries [IQ_DEPTH];
    logic [PTR_W-1:0] head;
    logic [PTR_W-1:0] tail;
    logic [PTR_W:0] count;

    assign full_o  = (count == IQ_DEPTH);
    assign valid_o = (count != 0);
    assign instr_o = entries[head];

    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n || flush_i) begin
            head <= '0;
            tail <= '0;
            count <= '0;
        end else begin
            if (push_en_i && !full_o) begin
                entries[tail] <= push_instr_i;
                tail <= tail + 1;
            end

            if (pop_en_i && valid_o) begin
                head <= head + 1;
            end

            count <= count + (push_en_i & ~full_o) - (pop_en_i & valid_o);
        end
    end

endmodule : instr_queue
