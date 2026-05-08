/**
 * Compliance testbench for the Tomasulo RV32I core.
 *
 * Loads a test hex into both instruction and data memories, runs until
 * OP_HALT retires, then dumps the signature word range to a file for
 * comparison against the reference output.
 *
 * Plus arguments:
 *   +HEX=<path>       Hex file produced by: riscv32-unknown-elf-objcopy -O verilog
 *   +SIG_BEGIN=<int>  First word index of the signature region
 *   +SIG_END=<int>    One-past-last word index of the signature region
 *   +SIG_OUT=<path>   Output file for the signature dump
 */
module sim_compliance;
    import rv32if_pkg::*;

    // -----------------------------------------------------------------------
    // Clock + reset
    // -----------------------------------------------------------------------
    logic clk  = 1'b0;
    logic rst_n;
    always #5 clk = ~clk;   // 100 MHz

    // -----------------------------------------------------------------------
    // Fetch stage (mirrors cpu.sv)
    // -----------------------------------------------------------------------
    logic [DATA_W-1:0] instr_raw;
    logic [PC_W-1:0]   mem_rd_addr, mem_wr_addr;
    logic [DATA_W-1:0] mem_rd_data, mem_wr_data;
    logic              mem_wr_en;
    logic [3:0]        mem_wr_be;
    logic              iq_full, flush;
    logic [PC_W-1:0]   redirect_pc;

    logic [PC_W-1:0] fetch_pc   = '0;
    logic [PC_W-1:0] fetch_pc_d = '0;
    logic            fetch_valid = 1'b0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            fetch_pc    <= '0;
            fetch_pc_d  <= '0;
            fetch_valid <= 1'b0;
        end else if (flush) begin
            fetch_pc    <= redirect_pc;
            fetch_pc_d  <= redirect_pc;
            fetch_valid <= 1'b0;
        end else begin
            fetch_valid <= 1'b1;
            if (!iq_full) begin
                fetch_pc   <= fetch_pc + 4;
                fetch_pc_d <= fetch_pc;
            end
        end
    end

    // Combinational read avoids Icarus scheduling race where instr_mem's
    // always_ff would see the post-update fetch_pc at the same posedge.
    assign instr_raw = u_imem.mem[fetch_pc_d[11:2]];

    // -----------------------------------------------------------------------
    // Memory + core
    // -----------------------------------------------------------------------
    instr_mem #(.FILENAME("")) u_imem(
        .clk(clk), .pc_i(fetch_pc),
        .instr_o(),
        .write_en_i(1'b0), .write_addr_i('0), .write_data_i('0)
    );

    data_mem #(.FILENAME("")) u_dmem(
        .clk(clk),
        .rd_addr_i(mem_rd_addr), .rd_data_o(mem_rd_data),
        .wr_en_i(mem_wr_en), .wr_be_i(mem_wr_be),
        .wr_addr_i(mem_wr_addr), .wr_data_i(mem_wr_data)
    );

    tomasulo_core u_core(
        .clk(clk), .rst_n(rst_n),
        .fetch_valid_i(fetch_valid & ~iq_full),
        .fetch_raw_i(instr_raw),
        .fetch_pc_i(fetch_pc_d),
        .iq_full_o(iq_full),
        .flush_o(flush), .redirect_pc_o(redirect_pc),
        .mem_rd_addr_o(mem_rd_addr), .mem_rd_data_i(mem_rd_data),
        .mem_wr_en_o(mem_wr_en), .mem_wr_be_o(mem_wr_be),
        .mem_wr_addr_o(mem_wr_addr), .mem_wr_data_o(mem_wr_data)
    );

    // -----------------------------------------------------------------------
    // HALT detection via commit unit
    // -----------------------------------------------------------------------
    logic halted = 1'b0;
    always_ff @(posedge clk) begin
        if (u_core.u_commit.commit_valid_i &&
            u_core.u_commit.commit_entry_i.op == OP_HALT)
            halted <= 1'b1;
    end

    // -----------------------------------------------------------------------
    // Simulation control
    // -----------------------------------------------------------------------
    string  hex_file, sig_out;
    integer sig_begin, sig_end;
    integer sig_fd, cycle_cnt;

    initial begin
        if (!$value$plusargs("HEX=%s", hex_file))  hex_file  = "program.hex";
        if (!$value$plusargs("SIG_OUT=%s",sig_out))   sig_out   = "out.sig";
        if (!$value$plusargs("SIG_BEGIN=%d", sig_begin)) sig_begin = 256;
        if (!$value$plusargs("SIG_END=%d",sig_end))   sig_end   = 512;

        for (int i = 0; i < MEM_SIZE; i++) u_dmem.mem[i] = '0;
        $display("[tb] loading hex: %s", hex_file);
        $readmemh(hex_file, u_imem.mem);
        $readmemh(hex_file, u_dmem.mem);
        $display("[tb] hex loaded, entering reset");

        rst_n = 1'b0;
        $display("[tb] rst_n=0, waiting for 4 clk edges...");
        repeat(4) @(posedge clk);
        $display("[tb] reset done, rst_n=1");
        rst_n = 1'b1;

        cycle_cnt = 0;
        while (!halted && cycle_cnt < 100_000) begin
            @(posedge clk);
            cycle_cnt++;
            if (cycle_cnt % 1000 == 0) $display("[tb] cycle %0d", cycle_cnt);
            begin
                if (u_core.iq_pop_w)
                    $display("[D] cyc=%0d dispatch op=%0d pc=%08x tag=%0d raw_iq_imm=%08x rs1=%0d",
                             cycle_cnt, u_core.iq_instr_w.op,
                             u_core.iq_instr_w.pc, u_core.rob_alloc_tag_w,
                             u_core.iq_instr_w.imm, u_core.iq_instr_w.rs1);
                if (fetch_valid & ~iq_full)
                    $display("[F] cyc=%0d fetch raw=%08x pc_d=%08x fetch_pc=%08x mem_direct=%08x",
                             cycle_cnt, instr_raw, fetch_pc_d, fetch_pc,
                             u_imem.mem[fetch_pc_d >> 2]);
                if (u_core.cdb_w.valid)
                    $display("[C] cyc=%0d CDB tag=%0d val=%08x", cycle_cnt,
                             u_core.cdb_w.tag, u_core.cdb_w.value);
                if (u_core.rob_commit_valid_w)
                    $display("[R] cyc=%0d COMMIT op=%0d pc=%08x", cycle_cnt,
                             u_core.rob_commit_entry_w.op,
                             u_core.rob_commit_entry_w.pc);
            end
        end

        if (!halted)
            $display("TIMEOUT: %s did not halt within %0d cycles", hex_file, cycle_cnt);

        repeat(20) @(posedge clk);   // drain pipeline

        sig_fd = $fopen(sig_out, "w");
        for (int i = sig_begin; i < sig_end; i++)
            $fdisplay(sig_fd, "%08x", u_dmem.mem[i]);
        $fclose(sig_fd);

        $finish;
    end

endmodule : sim_compliance
