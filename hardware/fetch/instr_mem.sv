/**
 * @brief Synchronous instruction memory (ROM).
 *
 * MEM_SIZE x 32-bit word array initialized from a hex file at simulation
 * start. PC is a byte address - the two LSBs are dropped to form the word
 * index. Output is registered (one-cycle read latency). Write port is
 * present for testbench loading only; tie write_en_i low in normal use.
 *
 * @param FILENAME Path to the hex file loaded by $readmemh at sim start.
 * @param clk Rising-edge clock.
 * @param pc_i Byte address from the fetch stage.
 * @param instr_o Registered 32-bit instruction word.
 * @param write_en_i Testbench write enable.
 * @param write_addr_i Testbench write address (word-addressed).
 * @param write_data_i Testbench write data.
 */
module instr_mem #(parameter FILENAME = "data.txt")
                 (clk,
                  pc_i, instr_o,
                  write_en_i, write_addr_i, write_data_i);
    import rv32if_pkg::*;

    localparam ADDR_W = $clog2(MEM_SIZE);

    input logic clk;
    input logic [PC_W-1:0] pc_i;
    output logic [DATA_W-1:0] instr_o;

    input logic write_en_i;
    input logic [ADDR_W-1:0] write_addr_i;
    input logic [DATA_W-1:0] write_data_i;

    logic [DATA_W-1:0] mem [MEM_SIZE];

    initial if (FILENAME != "") $readmemh(FILENAME, mem);

    always_ff @(posedge clk) begin
        if (write_en_i)
            mem[write_addr_i] <= write_data_i;
        instr_o <= mem[pc_i[ADDR_W+1:2]];
    end

endmodule : instr_mem
