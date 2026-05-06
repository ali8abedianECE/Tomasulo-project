# RV32I Compliance Tests — Tomasulo HDL

This directory runs the [lowRISC riscv-compliance](https://github.com/lowRISC/riscv-compliance) rv32i test suite against the Tomasulo out-of-order processor RTL using ModelSim.

## How it works

Each compliance test is a RISC-V assembly file that:
1. Executes a sequence of instructions exercising one opcode
2. Stores results into a **signature** memory region (`begin_signature` to `end_signature`)
3. Halts with `ecall` (opcode `0x73`), which our decoder maps to `OP_HALT`

The Makefile compiles each `.S` file to a flat hex image, loads it into both instruction and data memories in the RTL simulator, runs until HALT, dumps the signature words to a `.sig` file, then diffs against the golden `reference_output`.

### Memory layout

```
0x0000 - 0x03FF   .text   (code, 1 KB  — instruction memory word indices 0-255)
0x0400 - 0x0FFF   .data   (signature + variables, 3 KB — data memory word indices 256-1023)
```

Both memories (`instr_mem` and `data_mem`) load from the same hex file since data labels are assembled into the flat binary image alongside the code.

### Custom compliance macros (`macros/`)

| Macro | What it does |
|---|---|
| `RVTEST_CODE_BEGIN` | `.section .text.init`, defines `_start` |
| `RVTEST_CODE_END` | Emits `ecall` to halt the core |
| `RVTEST_DATA_BEGIN` | Opens `.data` section, places `begin_signature` label |
| `RVTEST_DATA_END` | Places `end_signature` label, closes section |
| `RVTEST_IO_*` | No-ops (bare metal, no console) |

---

## Prerequisites

### 1. RISC-V toolchain

Install via Homebrew (one-time, takes a few minutes):

```bash
brew tap riscv-software-src/riscv
brew install riscv-gnu-toolchain
```

This gives you `riscv64-unknown-elf-gcc`. The Makefile uses it with `-march=rv32i -mabi=ilp32` to produce rv32i binaries.

Verify:
```bash
riscv64-unknown-elf-gcc --version
```

### 2. ModelSim ASE

The Makefile auto-detects which platform you are on:

| Platform | What it does |
|---|---|
| **Mac** (Wine) | Detects `~/Downloads/modelsim_ase/win32aloem/vsim.exe` and runs it via `wine` |
| **Windows** (Git Bash) | Calls `vsim.exe` / `vlog.exe` directly (no Wine needed) |
| **Linux** | Expects native `vsim` on PATH |

On Mac the ModelSim ASE download should be at `~/Downloads/modelsim_ase/`. Override the path if yours differs:
```bash
make I-ADD-01 MODELSIM_DIR=/path/to/modelsim_ase/win32aloem
```

On Windows (Git Bash), make sure `MODELSIM_DIR` points to the `win32aloem` folder:
```bash
make I-ADD-01 MODELSIM_DIR="C:/intelFPGA/modelsim_ase/win32aloem"
```

### 3. GitHub CLI (`gh`)

Used by `make fetch` to download test sources. Install:
```bash
brew install gh
gh auth login
```

---

## Running tests

### First time: fetch test sources

```bash
cd sim/sim_hdl/sim_compliance
make fetch
```

This downloads all 48 rv32i `.S` files and their `reference_output` files from GitHub into `rv32i/src/` and `rv32i/references/`.

### Run a single test

```bash
make I-ADD-01
```

Output:
```
PASS: I-ADD-01
```

### Run all rv32i tests

```bash
make all
```

### What gets generated (in `work/`)

| File | Description |
|---|---|
| `I-ADD-01.elf` | Linked ELF binary |
| `I-ADD-01.hex` | Verilog hex image loaded by `$readmemh` |
| `I-ADD-01.sig_range` | Word indices of begin/end signature (from ELF symbol table) |
| `I-ADD-01.sig` | Signature words dumped by the RTL sim |
| `I-ADD-01.pass` | Stamp file created when diff passes |

### Clean up

```bash
make clean
```

---

## Debugging a failure

If a test prints `FAIL`, the Makefile shows the first 20 lines of the diff between the actual signature and the reference output. To dig deeper:

```bash
# Look at the compiled instructions
riscv64-unknown-elf-objdump -d work/I-ADD-01.elf

# Compare signature vs reference side by side
diff work/I-ADD-01.sig rv32i/references/I-ADD-01.reference_output

# Re-run the sim manually with waveform dumping
# (edit sim_compliance.sv to add $dumpvars, then rerun vsim interactively)
```

---

## Directory structure

```
sim_compliance/
  macros/
    compliance_io.h       no-op IO macros
    compliance_test.h     RVTEST_* macros for this target
  rv32i/
    src/                  .S test files (from make fetch)
    references/           golden reference_output files (from make fetch)
  work/                   generated ELFs, hexes, signatures (gitignored)
  link.ld                 linker script
  sim_compliance.sv       RTL testbench
  Makefile                build + simulate + compare flow
```
