#!/usr/bin/env python3
"""
Generate the synthesized program-library assets for the FPGA top level.

Outputs:
  - hardware/program_lib_rom.sv     Quartus ROM wrapper with simulation fallback
  - hardware/program_lib.hex        Dense hex image for simulation fallback
  - hardware/quartus/program_lib.mif  Quartus memory-init file
"""

from __future__ import annotations

import argparse
from pathlib import Path

NUM_WORDS_PER_PROGRAM = 1024


def load_words(path: Path) -> list[str]:
    words = [line.strip().upper() for line in path.read_text().splitlines() if line.strip()]
    if len(words) != NUM_WORDS_PER_PROGRAM:
        raise ValueError(f"{path} has {len(words)} words, expected {NUM_WORDS_PER_PROGRAM}")
    return words


def write_hex(path: Path, words: list[str]) -> None:
    path.write_text("\n".join(words) + "\n", encoding="ascii")


def write_mif(path: Path, words: list[str]) -> None:
    lines = [
        f"DEPTH = {len(words)};",
        "WIDTH = 32;",
        "ADDRESS_RADIX = UNS;",
        "DATA_RADIX = HEX;",
        "CONTENT BEGIN",
    ]
    for idx, word in enumerate(words):
        lines.append(f"    {idx} : {word};")
    lines.append("END;")
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def write_sv(path: Path, num_programs: int, total_words: int) -> None:
    text = f"""/**
 * @brief Program library ROM for the DE1-SoC top level.
 *
 * In synthesis this instantiates an Intel `altsyncram` ROM backed by
 * `hardware/quartus/program_lib.mif`, so Quartus maps the program library into
 * block memory instead of LAB logic. Simulation falls back to a plain memory
 * array loaded from `program_lib.hex`.
 */
`ifdef SYNTHESIS
module program_lib_rom(program_i, word_i, data_o);
    import rv32if_pkg::*;

    localparam int NUM_PROGRAMS = {num_programs};
    localparam int TOTAL_WORDS = {total_words};
    localparam int LIB_ADDR_W = $clog2(TOTAL_WORDS);

    input  logic [5:0] program_i;
    input  logic [$clog2(MEM_SIZE)-1:0] word_i;
    output logic [DATA_W-1:0] data_o;

    logic [LIB_ADDR_W-1:0] rom_addr;

    always_comb begin
        if (program_i < NUM_PROGRAMS[5:0])
            rom_addr = (program_i * MEM_SIZE) + word_i;
        else
            rom_addr = '0;
    end

    wire [DATA_W-1:0] rom_q;

    altsyncram #(
        .operation_mode("ROM"),
        .width_a(DATA_W),
        .widthad_a(LIB_ADDR_W),
        .numwords_a(TOTAL_WORDS),
        .outdata_reg_a("UNREGISTERED"),
        .address_aclr_a("NONE"),
        .outdata_aclr_a("NONE"),
        .indata_aclr_a("NONE"),
        .wrcontrol_aclr_a("NONE"),
        .init_file("program_lib.mif"),
        .intended_device_family("Cyclone V")
    ) u_rom (
        .clock0(1'b1),
        .address_a(rom_addr),
        .q_a(rom_q),
        .aclr0(1'b0),
        .aclr1(1'b0),
        .address_b('0),
        .addressstall_a(1'b0),
        .addressstall_b(1'b0),
        .byteena_a(1'b1),
        .byteena_b(1'b1),
        .clock1(1'b1),
        .clocken0(1'b1),
        .clocken1(1'b1),
        .clocken2(1'b1),
        .clocken3(1'b1),
        .data_a('0),
        .data_b('0),
        .eccstatus(),
        .q_b(),
        .rden_a(1'b1),
        .rden_b(1'b1),
        .wren_a(1'b0),
        .wren_b(1'b0)
    );

    always_comb data_o = rom_q;
endmodule : program_lib_rom
`else
module program_lib_rom(program_i, word_i, data_o);
    import rv32if_pkg::*;

    localparam int NUM_PROGRAMS = {num_programs};
    localparam int TOTAL_WORDS = {total_words};
    localparam int LIB_ADDR_W = $clog2(TOTAL_WORDS);

    input  logic [5:0] program_i;
    input  logic [$clog2(MEM_SIZE)-1:0] word_i;
    output logic [DATA_W-1:0] data_o;

    logic [LIB_ADDR_W-1:0] rom_addr;
    logic [DATA_W-1:0] rom [0:TOTAL_WORDS-1];

    always_comb begin
        if (program_i < NUM_PROGRAMS[5:0])
            rom_addr = (program_i * MEM_SIZE) + word_i;
        else
            rom_addr = '0;
    end

    initial begin
        $readmemh("hardware/program_lib.hex", rom);
    end

    always_comb begin
        if (program_i < NUM_PROGRAMS[5:0])
            data_o = rom[rom_addr];
        else
            data_o = '0;
    end

endmodule : program_lib_rom
`endif
"""
    path.write_text(text, encoding="ascii")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-dir", required=True, type=Path)
    parser.add_argument("--sv-out", required=True, type=Path)
    parser.add_argument("--hex-out", required=True, type=Path)
    parser.add_argument("--mif-out", required=True, type=Path)
    args = parser.parse_args()

    board_hexes = sorted(args.build_dir.glob("I-*.board.hex"))
    if not board_hexes:
        raise ValueError(f"no board hexes found in {args.build_dir}")

    all_words: list[str] = []
    for hex_path in board_hexes:
        all_words.extend(load_words(hex_path))

    args.hex_out.parent.mkdir(parents=True, exist_ok=True)
    args.mif_out.parent.mkdir(parents=True, exist_ok=True)
    write_hex(args.hex_out, all_words)
    write_mif(args.mif_out, all_words)
    write_sv(args.sv_out, len(board_hexes), len(all_words))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
