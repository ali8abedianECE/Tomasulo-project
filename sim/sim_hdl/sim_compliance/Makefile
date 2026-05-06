# Compliance test runner for the Tomasulo RV32I HDL simulator.
#
# Supported simulators (auto-detected, or set SIM= to override):
#   SIM=wine_vsim  ModelSim ASE via Wine  (auto-detected from MODELSIM_DIR)
#   SIM=win_vsim   ModelSim ASE on Windows Git Bash (no Wine)
#   SIM=vsim       Native ModelSim/QuestaSim on PATH
#   SIM=iverilog   Icarus Verilog  (brew install icarus-verilog)
#
# Usage:
#   make fetch        Download rv32i test sources and references from GitHub
#   make all          Build, simulate, and compare all rv32i tests
#   make I-ADD-01     Run a single test
#   make clean        Remove generated files

SHELL := bash
SUITE  := rv32i
SRCDIR := $(SUITE)/src
REFDIR := $(SUITE)/references

# ELFs, hexes, sigs go here (NOT named "work" -- ModelSim owns that name)
OUTDIR := build

RISCV_PREFIX ?= riscv64-unknown-elf-
CC      := $(RISCV_PREFIX)gcc
OBJCOPY := $(RISCV_PREFIX)objcopy
NM      := $(RISCV_PREFIX)nm

HW_ROOT := ../../../hardware

# ModelSim ASE installed under ~/Downloads/modelsim_ase
MODELSIM_DIR ?= $(HOME)/Downloads/modelsim_ase/win32aloem
WINE_VLIB    := wine $(MODELSIM_DIR)/vlib.exe
WINE_VLOG    := wine $(MODELSIM_DIR)/vlog.exe
WINE_VSIM    := wine $(MODELSIM_DIR)/vsim.exe

CFLAGS := -march=rv32i -mabi=ilp32 -static -nostdlib -nostartfiles \
          -I macros -T link.ld

# Convert a Unix path to a Wine Windows path (Z:\ prefix, backslashes)
# Double backslashes are intentional: shell reduces \\ -> \ when the result
# is used unquoted in a recipe command, giving the single \ that Windows needs.
winpath = $(shell echo "$(abspath $(1))" | sed 's|^/|Z:/|; s|/|\\\\|g')

# Same conversion but with forward slashes -- safe to embed in INI files
# without any shell quoting gymnastics.
winpath_fwd = $(shell echo "$(abspath $(1))" | sed 's|^/|Z:/|')

# Detect OS
ifeq ($(OS),Windows_NT)
  ON_WINDOWS := 1
else
  ON_WINDOWS :=
endif

# Auto-detect simulator
ifeq ($(origin SIM),undefined)
  ifdef ON_WINDOWS
    SIM := win_vsim
  else ifneq ($(wildcard $(MODELSIM_DIR)/vsim.exe),)
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
	    echo "  Win   - ModelSim native   : detected automatically in Git Bash"; \
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

WIN_SV_SOURCES = $(foreach f,$(SV_SOURCES),$(call winpath,$(f)))

# -----------------------------------------------------------------------
# ModelSim ASE via Wine (Mac)
#
# ModelSim owns the "work" directory in the current folder.
# Our outputs (ELFs, hexes, sigs) live in build/ to avoid the name clash.
# -----------------------------------------------------------------------
define run_wine_vsim
	@echo "  [wine/modelsim] simulating $*..."
	@printf '[Library]\nwork = %s\n[vsim]\nLicense = nomgc nomti\n' \
	    '$(call winpath_fwd,$(CURDIR)/work)' > $(MODELSIM_DIR)/modelsim.ini
	@$(WINE_VLIB) $(call winpath,$(CURDIR)/work) >> $(OUTDIR)/$*.log 2>&1 || true
	@$(WINE_VLOG) -sv \
	    +incdir+$(call winpath,$(HW_ROOT)/pkg) \
	    $(WIN_SV_SOURCES) \
	    > $(OUTDIR)/$*.log 2>&1 || \
	    (echo "  [vlog] FAILED -- see $(OUTDIR)/$*.log"; cat $(OUTDIR)/$*.log; exit 1)
	@$(WINE_VSIM) -c \
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
# ModelSim ASE on Windows (Git Bash) -- call exe directly, no Wine
# -----------------------------------------------------------------------
define run_win_vsim
	@echo "  [win/modelsim] simulating $*..."
	@printf '[Library]\nwork = work\n[vsim]\nLicense = nomgc nomti\n' > modelsim.ini
	@$(MODELSIM_DIR)/vlib.exe work >> $(OUTDIR)/$*.log 2>&1 || true
	@$(MODELSIM_DIR)/vlog.exe -sv \
	    +incdir+$(HW_ROOT)/pkg \
	    $(SV_SOURCES) \
	    > $(OUTDIR)/$*.log 2>&1 || \
	    (echo "  [vlog] FAILED -- see $(OUTDIR)/$*.log"; cat $(OUTDIR)/$*.log; exit 1)
	@$(MODELSIM_DIR)/vsim.exe -c \
	    -modelsimini modelsim.ini \
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
# Native ModelSim / QuestaSim
# -----------------------------------------------------------------------
define run_vsim
	@echo "  [vsim] simulating $*..."
	@vlib work >> $(OUTDIR)/$*.log 2>&1 || true
	@vlog -sv +incdir+$(HW_ROOT)/pkg $(SV_SOURCES) \
	    > $(OUTDIR)/$*.log 2>&1 || \
	    (echo "  [vlog] FAILED -- see $(OUTDIR)/$*.log"; cat $(OUTDIR)/$*.log; exit 1)
	@vsim -c work.sim_compliance \
	    +HEX=$(OUTDIR)/$*.hex \
	    +SIG_BEGIN=$(word 1,$(RANGE)) \
	    +SIG_END=$(word 2,$(RANGE)) \
	    +SIG_OUT=$(OUTDIR)/$*.sig \
	    -do "run -all; quit" \
	    >> $(OUTDIR)/$*.log 2>&1 || \
	    (echo "  [vsim] FAILED -- see $(OUTDIR)/$*.log"; cat $(OUTDIR)/$*.log; exit 1)
endef

# -----------------------------------------------------------------------
# Icarus Verilog
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
	rm -rf $(OUTDIR) work msim_lib transcript vsim.wlf modelsim.ini
	@rm -f $(MODELSIM_DIR)/modelsim.ini 2>/dev/null || true

# Single-test shortcut:  make I-ADD-01
$(TESTS): %: $(OUTDIR)/%.pass
