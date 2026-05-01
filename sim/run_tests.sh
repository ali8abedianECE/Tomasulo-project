#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAKE_DIR="$SCRIPT_DIR/sim_soft/make"
SIM="$MAKE_DIR/tomasulo_sim"
TEST_DIR="$SCRIPT_DIR/test_sim"

make -C "$MAKE_DIR" -j"$(nproc 2>/dev/null || sysctl -n hw.logicalcpu)" --no-print-directory

for asm in "$TEST_DIR"/*/program.asm; do
    test_dir="$(dirname "$asm")"
    test_name="$(basename "$test_dir")"
    echo "Running $test_name..."
    "$SIM" "$asm" "$test_dir/"
done
