#!/usr/bin/env python3
"""
Generate a synthesizable multi-program ROM module for the FPGA top level.

The generated RTL uses nested `case` statements instead of aggregate array
initializers so older simulators and synthesis tools can parse it reliably.
"""

from __future__ import annotations

import argparse
from pathlib import Path


def load_words(path: Path) -> list[str]:
    words = [line.strip() for line in path.read_text().splitlines() if line.strip()]
    if len(words) != 1024:
        raise ValueError(f"{path} has {len(words)} words, expected 1024")
    return words


def emit_program_case(program_id: int, program_name: str, words: list[str]) -> str:
    lines = [f"            6'd{program_id}: begin // {program_name}",
             "                case (word_i)"]
    for idx, word in enumerate(words):
        lines.append(f"                    10'd{idx}: data_o = 32'h{word};")
    lines.extend([
        "                    default: data_o = '0;",
        "                endcase",
        "            end",
    ])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-dir", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    board_hexes = sorted(args.build_dir.glob("I-*.board.hex"))
    if not board_hexes:
        raise ValueError(f"no board hexes found in {args.build_dir}")

    header = """/**
 * @brief Synthesizable program library ROM for the DE1-SoC top level.
 *
 * Auto-generated from the compliance suite board images. Each program image is
 * exactly 1024 words and includes the signature metadata header in words
 * 1020..1023.
 */
module program_lib_rom(program_i, word_i, data_o);
    import rv32if_pkg::*;

    input  logic [5:0] program_i;
    input  logic [$clog2(MEM_SIZE)-1:0] word_i;
    output logic [DATA_W-1:0] data_o;

    // Program IDs:
{program_comments}

    always_comb begin
        data_o = '0;
        case (program_i)
{program_cases}
            default: data_o = '0;
        endcase
    end

endmodule : program_lib_rom
"""

    program_comments = []
    program_cases = []
    for idx, hex_path in enumerate(board_hexes):
        name = hex_path.stem.removesuffix(".board")
        program_comments.append(f"    //   {idx:2d} -> {name}")
        program_cases.append(emit_program_case(idx, name, load_words(hex_path)))

    text = header.format(
        program_comments="\n".join(program_comments),
        program_cases="\n".join(program_cases),
    )
    args.output.write_text(text, encoding="ascii")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
