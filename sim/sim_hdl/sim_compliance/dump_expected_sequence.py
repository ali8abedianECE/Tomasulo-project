#!/usr/bin/env python3
"""
Generate a plain-text playback file for the board review mode.

This script supports two related outputs:

1. Expected replay sequence from a compliance reference file.
   This is what the board *should* show after the test runs.

2. Raw signature contents from a dense .board.hex image.
   This is mainly useful for debugging image generation, not correctness,
   because the pre-run signature region is usually filled with placeholders.

The default and most useful path is to provide both:
  --board-hex <test.board.hex>
  --reference <test.reference_output>

That lets the script use the embedded SIG0 metadata to recover the signature
base address, then pair each expected value with the word index and byte
address the board review will walk through.
"""

from __future__ import annotations

import argparse
from pathlib import Path

MEM_WORDS = 1024
META_MAGIC = 0x53494730
META_BASE = MEM_WORDS - 4


def load_dense_hex(path: Path) -> list[int]:
    lines = [line.strip() for line in path.read_text().splitlines() if line.strip()]
    if len(lines) != MEM_WORDS:
        raise ValueError(f"{path}: expected {MEM_WORDS} words, found {len(lines)}")
    return [int(line, 16) & 0xFFFFFFFF for line in lines]


def read_metadata(mem: list[int]) -> tuple[int, int, int]:
    magic = mem[META_BASE + 0]
    begin_word = mem[META_BASE + 1]
    end_word = mem[META_BASE + 2]
    sig_len = mem[META_BASE + 3]

    if magic != META_MAGIC:
        raise ValueError(
            f"missing SIG0 metadata: expected 0x{META_MAGIC:08X}, found 0x{magic:08X}"
        )
    if not (0 <= begin_word <= end_word <= META_BASE):
        raise ValueError(f"invalid signature range [{begin_word}, {end_word})")
    if sig_len != (end_word - begin_word):
        raise ValueError(
            f"metadata length mismatch: len={sig_len}, range={end_word - begin_word}"
        )

    return begin_word, end_word, sig_len


def extract_signature(mem: list[int]) -> list[int]:
    begin_word, end_word, _sig_len = read_metadata(mem)
    return mem[begin_word:end_word]


def load_reference(path: Path) -> list[int]:
    words: list[int] = []
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line:
            continue
        words.append(int(line, 16) & 0xFFFFFFFF)
    return words


def write_sequence(path: Path, begin_word: int, words: list[int]) -> None:
    with path.open("w", encoding="ascii") as f:
        for offset, word in enumerate(words):
            word_idx = begin_word + offset
            byte_addr = word_idx * 4
            f.write(f"{word_idx:04X} {byte_addr:08X} {word:08X}\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--board-hex", type=Path, help="Dense .board.hex file")
    parser.add_argument(
        "--reference",
        type=Path,
        help="Compliance reference_output file with expected signature words",
    )
    parser.add_argument("--output", required=True, type=Path, help="Output .expected.txt file")
    args = parser.parse_args()

    if args.board_hex is None and args.reference is None:
        raise ValueError("provide at least --board-hex or --reference")

    begin_word = 0
    board_words: list[int] | None = None

    if args.board_hex is not None:
        mem = load_dense_hex(args.board_hex)
        begin_word, _end_word, _sig_len = read_metadata(mem)
        board_words = extract_signature(mem)

    if args.reference is not None:
        words = load_reference(args.reference)
    else:
        assert board_words is not None
        words = board_words

    write_sequence(args.output, begin_word, words)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
