/**
 * @brief Synchronous data memory (SRAM model).
 *
 * MEM_SIZE x 32-bit word array. Byte addresses on both ports; two LSBs are
 * dropped to form the word index. Write takes effect on the rising edge;
 * read data is registered (one-cycle latency). Optionally pre-loaded from
 * a hex file for simulation.
 *
 * @param FILENAME Optional hex file loaded by $readmemh at sim start.
 * @param clk Rising-edge clock.
 * @param rd_addr_i Byte address for load.
 * @param rd_data_o Registered 32-bit load result.
 * @param wr_en_i Store enable.
 * @param wr_addr_i Byte address for store.
 * @param wr_data_i 32-bit value to write.
 */
module data_mem #(parameter FILENAME = "")
                (clk,
                 rd_addr_i, rd_data_o,
                 wr_en_i, wr_addr_i, wr_data_i);
    import rv32if_pkg::*;

    localparam ADDR_W = $clog2(MEM_SIZE);

    input logic clk;
    input logic [PC_W-1:0] rd_addr_i;
    output logic [DATA_W-1:0] rd_data_o;

    input logic wr_en_i;
    input logic [PC_W-1:0] wr_addr_i;
    input logic [DATA_W-1:0] wr_data_i;

    logic [DATA_W-1:0] mem [MEM_SIZE];

    initial if (FILENAME != "") $readmemh(FILENAME, mem);

    always_ff @(posedge clk) begin
        if (wr_en_i)
            mem[wr_addr_i[ADDR_W+1:2]] <= wr_data_i;
        rd_data_o <= mem[rd_addr_i[ADDR_W+1:2]];
    end

endmodule : data_mem
