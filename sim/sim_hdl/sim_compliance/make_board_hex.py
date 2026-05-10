#!/usr/bin/env python3
"""
Convert a sparse objcopy-generated Verilog hex file into a 1024-word FPGA image.

The output contains exactly one 32-bit word per line so Quartus does not warn
about sparse input. The final four words carry metadata for the board viewer:

  mem[1020] = 0x53494730  ("SIG0")
  mem[1021] = begin_signature word index
  mem[1022] = end_signature word index (exclusive)
  mem[1023] = signature length in words
"""

from __future__ import annotations

import argparse
from pathlib import Path

MEM_WORDS = 1024
META_BASE = MEM_WORDS - 4
META_MAGIC = 0x53494730


def load_sparse_hex(path: Path) -> list[int]:
    mem = [0] * MEM_WORDS
    cursor = 0

    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("@"):
            cursor = int(line[1:], 16)
            continue

        for token in line.split():
            if cursor >= MEM_WORDS:
                raise ValueError(f"{path}: word index {cursor} exceeds {MEM_WORDS - 1}")
            mem[cursor] = int(token, 16) & 0xFFFFFFFF
            cursor += 1

    return mem


def write_dense_hex(path: Path, mem: list[int]) -> None:
    with path.open("w", encoding="ascii") as f:
        for word in mem:
            f.write(f"{word:08X}\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--sig-begin", required=True, type=int)
    parser.add_argument("--sig-end", required=True, type=int)
    args = parser.parse_args()

    sig_begin = args.sig_begin
    sig_end = args.sig_end
    sig_len = sig_end - sig_begin

    if not (0 <= sig_begin <= sig_end <= META_BASE):
        raise ValueError(
            f"signature range [{sig_begin}, {sig_end}) overlaps reserved metadata words"
        )

    mem = load_sparse_hex(args.input)
    mem[META_BASE + 0] = META_MAGIC
    mem[META_BASE + 1] = sig_begin
    mem[META_BASE + 2] = sig_end
    mem[META_BASE + 3] = sig_len
    write_dense_hex(args.output, mem)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
