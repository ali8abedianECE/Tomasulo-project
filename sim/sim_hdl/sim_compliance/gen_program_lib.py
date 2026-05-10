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


def round_up_pow2(n: int) -> int:
    if n <= 1:
        return 1
    return 1 << (n - 1).bit_length()


def load_words(path: Path) -> list[str]:
    words = [line.strip().upper() for line in path.read_text().splitlines() if line.strip()]
    if len(words) != NUM_WORDS_PER_PROGRAM:
        raise ValueError(f"{path} has {len(words)} words, expected {NUM_WORDS_PER_PROGRAM}")
    return words


def write_hex(path: Path, words: list[str]) -> None:
    path.write_text("\n".join(words) + "\n", encoding="ascii")


def write_mif(path: Path, words: list[str], depth: int) -> None:
    lines = [
        f"DEPTH = {depth};",
        "WIDTH = 32;",
        "ADDRESS_RADIX = UNS;",
        "DATA_RADIX = HEX;",
        "CONTENT BEGIN",
    ]
    for idx, word in enumerate(words):
        lines.append(f"    {idx} : {word};")
    if len(words) < depth:
        lines.append(f"    [{len(words)}..{depth - 1}] : 00000000;")
    lines.append("END;")
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def write_sv(path: Path, num_programs: int, total_words: int, depth: int) -> None:
    text = f"""/**
 * @brief Program library ROM for the DE1-SoC top level.
 *
 * In synthesis this uses an inferred ROM backed by `program_lib.mif`, so
 * Quartus maps the program library into block memory instead of LAB logic.
 * Simulation falls back to a plain memory array loaded from `program_lib.hex`.
 */
`ifdef SYNTHESIS
module program_lib_rom(clk, program_i, word_i, data_o);
    import rv32if_pkg::*;

    localparam int NUM_PROGRAMS = {num_programs};
    localparam int TOTAL_WORDS = {total_words};
    localparam int ROM_DEPTH = {depth};
    localparam int LIB_ADDR_W = $clog2(ROM_DEPTH);

    input  logic clk;
    input  logic [5:0] program_i;
    input  logic [$clog2(MEM_SIZE)-1:0] word_i;
    output logic [DATA_W-1:0] data_o;

    logic [LIB_ADDR_W-1:0] rom_addr;
    (* ramstyle = "M10K", ram_init_file = "program_lib.mif" *)
    logic [DATA_W-1:0] rom [0:ROM_DEPTH-1];

    always_comb begin
        if (program_i < NUM_PROGRAMS[5:0])
            rom_addr = (program_i * MEM_SIZE) + word_i;
        else
            rom_addr = '0;
    end

    always_ff @(posedge clk) begin
        if (program_i < NUM_PROGRAMS[5:0])
            data_o <= rom[rom_addr];
        else
            data_o <= '0;
    end
endmodule : program_lib_rom
`else
module program_lib_rom(clk, program_i, word_i, data_o);
    import rv32if_pkg::*;

    localparam int NUM_PROGRAMS = {num_programs};
    localparam int TOTAL_WORDS = {total_words};
    localparam int ROM_DEPTH = {depth};
    localparam int LIB_ADDR_W = $clog2(ROM_DEPTH);

    input  logic clk;
    input  logic [5:0] program_i;
    input  logic [$clog2(MEM_SIZE)-1:0] word_i;
    output logic [DATA_W-1:0] data_o;

    logic [LIB_ADDR_W-1:0] rom_addr;
    logic [DATA_W-1:0] rom [0:ROM_DEPTH-1];

    always_comb begin
        if (program_i < NUM_PROGRAMS[5:0])
            rom_addr = (program_i * MEM_SIZE) + word_i;
        else
            rom_addr = '0;
    end

    initial begin
        $readmemh("hardware/program_lib.hex", rom);
    end

    always_ff @(posedge clk) begin
        if (program_i < NUM_PROGRAMS[5:0])
            data_o <= rom[rom_addr];
        else
            data_o <= '0;
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

    depth = round_up_pow2(len(all_words))
    padded_words = all_words + (["00000000"] * (depth - len(all_words)))

    args.hex_out.parent.mkdir(parents=True, exist_ok=True)
    args.mif_out.parent.mkdir(parents=True, exist_ok=True)
    write_hex(args.hex_out, padded_words)
    write_mif(args.mif_out, all_words, depth)
    write_sv(args.sv_out, len(board_hexes), len(all_words), depth)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
