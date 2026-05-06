# Compliance test runner for the Tomasulo RV32I HDL simulator.
#
# Supported simulators (auto-detected, or set SIM= to override):
#   SIM=wine_vsim  ModelSim ASE via Wine  (auto-detected from MODELSIM_DIR)
#   SIM=vsim       Native ModelSim/QuestaSim on PATH
#   SIM=iverilog   Icarus Verilog         (brew install icarus-verilog)
#
# Usage:
#   make fetch        Download rv32i test sources and references from GitHub
#   make all          Build, simulate, and compare all rv32i tests
#   make I-ADD-01     Run a single test
#   make clean        Remove generated files
#
# Override toolchain prefix if needed:
#   make I-ADD-01 RISCV_PREFIX=riscv32-unknown-elf-

SHELL := bash
SUITE  := rv32i
SRCDIR := $(SUITE)/src
REFDIR := $(SUITE)/references
OUTDIR := work

RISCV_PREFIX ?= riscv64-unknown-elf-
CC      := $(RISCV_PREFIX)gcc
OBJCOPY := $(RISCV_PREFIX)objcopy
NM      := $(RISCV_PREFIX)nm

HW_ROOT := ../../../hardware

# ModelSim ASE installed under Downloads/modelsim_ase
MODELSIM_DIR ?= $(HOME)/Downloads/modelsim_ase/win32aloem
WINE_VLIB    := wine $(MODELSIM_DIR)/vlib.exe
WINE_VLOG    := wine $(MODELSIM_DIR)/vlog.exe
WINE_VSIM    := wine $(MODELSIM_DIR)/vsim.exe

# Separate directory for ModelSim's compiled library so it doesn't
# conflict with our work/ output directory (ELFs, hexes, sigs).
MLIB := msim_lib

CFLAGS := -march=rv32i -mabi=ilp32 -static -nostdlib -nostartfiles \
          -I macros -T link.ld

# Wine converts Unix paths: prefix with Z: and flip slashes
winpath = $(shell echo "$(abspath $(1))" | sed 's|^/|Z:/|; s|/|\\\\|g')

# Detect OS so we can choose the right backend on Windows vs Mac/Linux
ifeq ($(OS),Windows_NT)
  ON_WINDOWS := 1
else
  ON_WINDOWS :=
endif

# Auto-detect simulator if SIM not set
ifeq ($(origin SIM),undefined)
  ifdef ON_WINDOWS
    # Windows (Git Bash / Cygwin): call vlog.exe/vsim.exe directly
    SIM := win_vsim
  else ifneq ($(wildcard $(MODELSIM_DIR)/vsim.exe),)
    # Mac/Linux: Wine wrapper for the win32 ModelSim ASE download
    SIM := wine_vsim
  else ifneq ($(shell command -v vsim 2>/dev/null),)
    SIM := vsim
  else ifneq ($(shell command -v iverilog 2>/dev/null),)
    SIM := iverilog
  else
    SIM := none
  endif
endif

TESTS := $(basename $(notdir $(wildcard $(SRCDIR)/I-*.S)))

.PHONY: all fetch clean check-sim $(TESTS)

all: fetch check-sim $(addprefix $(OUTDIR)/,$(addsuffix .pass,$(TESTS)))

check-sim:
	@if [ "$(SIM)" = "none" ]; then \
	    echo "ERROR: No simulator found. Options:"; \
	    echo "  Mac   - ModelSim via Wine : $(MODELSIM_DIR)/vsim.exe (auto-detected)"; \
	    echo "  Mac   - Icarus Verilog    : brew install icarus-verilog"; \
	    echo "  Win   - ModelSim native   : runs automatically in Git Bash"; \
	    echo "  Linux - native vsim       : add vsim to PATH"; \
	    exit 1; \
	fi
	@echo "Using simulator: $(SIM)"

# -----------------------------------------------------------------------
# Fetch test sources and reference outputs from lowRISC/riscv-compliance
# -----------------------------------------------------------------------
fetch:
	@echo "Fetching $(SUITE) tests..."
	@mkdir -p $(SRCDIR) $(REFDIR)
	@for f in $$(gh api repos/lowRISC/riscv-compliance/contents/riscv-test-suite/$(SUITE)/src \
	              --jq '.[].name' 2>/dev/null); do \
	    gh api repos/lowRISC/riscv-compliance/contents/riscv-test-suite/$(SUITE)/src/$$f \
	        --jq '.content' | base64 -d > $(SRCDIR)/$$f ; \
	done
	@for f in $$(gh api repos/lowRISC/riscv-compliance/contents/riscv-test-suite/$(SUITE)/references \
	              --jq '.[].name' 2>/dev/null); do \
	    gh api repos/lowRISC/riscv-compliance/contents/riscv-test-suite/$(SUITE)/references/$$f \
	        --jq '.content' | base64 -d > $(REFDIR)/$$f ; \
	done
	@echo "Done."

# -----------------------------------------------------------------------
# Compile: .S -> ELF -> hex (32-bit word-addressed Verilog format)
# -----------------------------------------------------------------------
$(OUTDIR)/%.elf: $(SRCDIR)/%.S | $(OUTDIR)
	$(CC) $(CFLAGS) -o $@ $<

$(OUTDIR)/%.hex: $(OUTDIR)/%.elf
	$(OBJCOPY) -O verilog --verilog-data-width=4 $< $@

# Extract begin_signature / end_signature word indices from the ELF symbol table
$(OUTDIR)/%.sig_range: $(OUTDIR)/%.elf
	@begin_byte=$$($(NM) $< | awk '/begin_signature/{print $$1}'); \
	 end_byte=$$($(NM)   $< | awk '/end_signature/{print $$1}'); \
	 echo "$$(( 16#$$begin_byte / 4 )) $$(( 16#$$end_byte / 4 ))" > $@

# -----------------------------------------------------------------------
# Source list (shared by all simulator backends)
# -----------------------------------------------------------------------
SV_SOURCES := \
    $(HW_ROOT)/pkg/rv32if_pkg.sv \
    $(HW_ROOT)/fetch/instr_mem.sv \
    $(HW_ROOT)/fetch/instr_queue.sv \
    $(HW_ROOT)/execute/lsb/data_mem.sv \
    $(HW_ROOT)/execute/lsb/load_store_buffer.sv \
    $(HW_ROOT)/execute/int_ops/alu_unit.sv \
    $(HW_ROOT)/execute/int_ops/branch_unit.sv \
    $(HW_ROOT)/execute/fp_ops/fp_add.sv \
    $(HW_ROOT)/execute/fp_ops/fp_mul.sv \
    $(HW_ROOT)/execute/fp_ops/fp_div.sv \
    $(HW_ROOT)/execute/fp_ops/fp_cvt.sv \
    $(HW_ROOT)/execute/fp_ops/fp_round.sv \
    $(HW_ROOT)/execute/reservation_station.sv \
    $(HW_ROOT)/core/arbiter.sv \
    $(HW_ROOT)/core/cdb.sv \
    $(HW_ROOT)/core/regfile.sv \
    $(HW_ROOT)/core/rat.sv \
    $(HW_ROOT)/core/rob.sv \
    $(HW_ROOT)/core/dispatch.sv \
    $(HW_ROOT)/core/commit_unit.sv \
    $(HW_ROOT)/core/tomasulo_core.sv \
    sim_compliance.sv

# Windows-style source list for Wine
WIN_SV_SOURCES = $(foreach f,$(SV_SOURCES),$(call winpath,$(f)))

# -----------------------------------------------------------------------
# Simulate: ModelSim ASE via Wine
#   Step 1: vlog.exe compiles all SV into ./work library
#   Step 2: vsim.exe runs sim_compliance in batch mode
# -----------------------------------------------------------------------
define run_wine_vsim
	@echo "  [wine/modelsim] simulating $*..."
	@mkdir -p $(MLIB)
	@$(WINE_VLIB) $(call winpath,$(MLIB)/work) >> $(OUTDIR)/$*.log 2>&1 || true
	@$(WINE_VLOG) -sv \
	    -work $(call winpath,$(MLIB)/work) \
	    +incdir+$(call winpath,$(HW_ROOT)/pkg) \
	    $(WIN_SV_SOURCES) \
	    > $(OUTDIR)/$*.log 2>&1 || \
	    (echo "  [vlog] FAILED -- see $(OUTDIR)/$*.log"; cat $(OUTDIR)/$*.log; exit 1)
	@$(WINE_VSIM) -c \
	    -lib $(call winpath,$(MLIB)) \
	    work.sim_compliance \
	    "+HEX=$(call winpath,$(OUTDIR)/$*.hex)" \
	    "+SIG_BEGIN=$(word 1,$(RANGE))" \
	    "+SIG_END=$(word 2,$(RANGE))" \
	    "+SIG_OUT=$(call winpath,$(OUTDIR)/$*.sig)" \
	    -do "run -all; quit" \
	    >> $(OUTDIR)/$*.log 2>&1 || \
	    (echo "  [vsim] FAILED -- see $(OUTDIR)/$*.log"; cat $(OUTDIR)/$*.log; exit 1)
endef

# -----------------------------------------------------------------------
# Simulate: ModelSim ASE on Windows (Git Bash) -- call exe directly
# -----------------------------------------------------------------------
define run_win_vsim
	@echo "  [win/modelsim] simulating $*..."
	@mkdir -p $(MLIB)
	@$(MODELSIM_DIR)/vlib.exe $(MLIB)/work >> $(OUTDIR)/$*.log 2>&1 || true
	@$(MODELSIM_DIR)/vlog.exe -sv \
	    -work $(MLIB)/work \
	    +incdir+$(HW_ROOT)/pkg \
	    $(SV_SOURCES) \
	    > $(OUTDIR)/$*.log 2>&1 || \
	    (echo "  [vlog] FAILED -- see $(OUTDIR)/$*.log"; cat $(OUTDIR)/$*.log; exit 1)
	@$(MODELSIM_DIR)/vsim.exe -c \
	    -lib $(MLIB) \
	    work.sim_compliance \
	    "+HEX=$(OUTDIR)/$*.hex" \
	    "+SIG_BEGIN=$(word 1,$(RANGE))" \
	    "+SIG_END=$(word 2,$(RANGE))" \
	    "+SIG_OUT=$(OUTDIR)/$*.sig" \
	    -do "run -all; quit" \
	    >> $(OUTDIR)/$*.log 2>&1 || \
	    (echo "  [vsim] FAILED -- see $(OUTDIR)/$*.log"; cat $(OUTDIR)/$*.log; exit 1)
endef

# -----------------------------------------------------------------------
# Simulate: native ModelSim / QuestaSim
# -----------------------------------------------------------------------
define run_vsim
	@echo "  [vsim] simulating $*..."
	@vsim -c -quiet \
	    -do "vlog -sv +incdir+$(HW_ROOT)/pkg $(SV_SOURCES); \
	         vsim -c work.sim_compliance \
	              +HEX=$(OUTDIR)/$*.hex \
	              +SIG_BEGIN=$(word 1,$(RANGE)) \
	              +SIG_END=$(word 2,$(RANGE)) \
	              +SIG_OUT=$(OUTDIR)/$*.sig \
	              -do 'run -all; quit'; \
	         quit -f" > $(OUTDIR)/$*.log 2>&1 || \
	    (echo "  [vsim] FAILED -- see $(OUTDIR)/$*.log"; cat $(OUTDIR)/$*.log; exit 1)
endef

# -----------------------------------------------------------------------
# Simulate: Icarus Verilog
# -----------------------------------------------------------------------
define run_iverilog
	@echo "  [iverilog] simulating $*..."
	@iverilog -g2012 \
	    -I $(HW_ROOT)/pkg \
	    -o $(OUTDIR)/$*.vvp \
	    $(SV_SOURCES) \
	    > $(OUTDIR)/$*.log 2>&1 || \
	    (echo "  [iverilog] compile FAILED -- see $(OUTDIR)/$*.log"; cat $(OUTDIR)/$*.log; exit 1)
	@vvp $(OUTDIR)/$*.vvp \
	    +HEX=$(OUTDIR)/$*.hex \
	    +SIG_BEGIN=$(word 1,$(RANGE)) \
	    +SIG_END=$(word 2,$(RANGE)) \
	    +SIG_OUT=$(OUTDIR)/$*.sig \
	    >> $(OUTDIR)/$*.log 2>&1 || \
	    (echo "  [iverilog] sim FAILED -- see $(OUTDIR)/$*.log"; cat $(OUTDIR)/$*.log; exit 1)
endef

# -----------------------------------------------------------------------
# Unified simulate rule
# -----------------------------------------------------------------------
$(OUTDIR)/%.sig: $(OUTDIR)/%.hex $(OUTDIR)/%.sig_range sim_compliance.sv
	$(eval RANGE := $(shell cat $(OUTDIR)/$*.sig_range))
	$(if $(filter wine_vsim,$(SIM)),$(call run_wine_vsim),\
	$(if $(filter win_vsim,$(SIM)),$(call run_win_vsim),\
	$(if $(filter vsim,$(SIM)),$(call run_vsim),\
	$(if $(filter iverilog,$(SIM)),$(call run_iverilog),\
	$(error No simulator: set SIM=wine_vsim, win_vsim, vsim, or iverilog)))))

# -----------------------------------------------------------------------
# Compare: signature vs reference output
# -----------------------------------------------------------------------
$(OUTDIR)/%.pass: $(OUTDIR)/%.sig $(REFDIR)/%.reference_output
	@if diff -b $< $(REFDIR)/$*.reference_output > /dev/null 2>&1; then \
	    echo "PASS: $*"; touch $@; \
	else \
	    echo "FAIL: $*"; \
	    diff $< $(REFDIR)/$*.reference_output | head -20; \
	    exit 1; \
	fi

$(OUTDIR):
	mkdir -p $@

clean:
	rm -rf $(OUTDIR) $(MLIB) transcript vsim.wlf modelsim.ini

# Single-test shortcut:  make I-ADD-01
$(TESTS): %: $(OUTDIR)/%.pass
