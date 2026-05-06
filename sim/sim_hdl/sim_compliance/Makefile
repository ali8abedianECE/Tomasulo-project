# Compliance test runner for the Tomasulo RV32I HDL simulator.
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
OUTDIR := work

RISCV_PREFIX ?= riscv32-unknown-elf-
CC      := $(RISCV_PREFIX)gcc
OBJCOPY := $(RISCV_PREFIX)objcopy
NM      := $(RISCV_PREFIX)nm

VSIM ?= vsim

HW_ROOT := ../../../../hardware

CFLAGS := -march=rv32i -mabi=ilp32 -static -nostdlib -nostartfiles \
          -I macros -T link.ld

TESTS := $(basename $(notdir $(wildcard $(SRCDIR)/I-*.S)))

.PHONY: all fetch clean $(TESTS)

all: fetch $(addprefix $(OUTDIR)/,$(addsuffix .pass,$(TESTS)))

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
# Compile: .S -> ELF -> hex
# -----------------------------------------------------------------------
$(OUTDIR)/%.elf: $(SRCDIR)/%.S | $(OUTDIR)
	$(CC) $(CFLAGS) -o $@ $<

$(OUTDIR)/%.hex: $(OUTDIR)/%.elf
	$(OBJCOPY) -O verilog $< $@

# Extract begin_signature / end_signature word indices from the ELF symbol table
$(OUTDIR)/%.sig_range: $(OUTDIR)/%.elf
	@begin_byte=$$($(NM) $< | awk '/begin_signature/{print $$1}'); \
	 end_byte=$$($(NM)   $< | awk '/end_signature/{print $$1}'); \
	 echo "$$(( 16#$$begin_byte / 4 )) $$(( 16#$$end_byte / 4 ))" > $@

# -----------------------------------------------------------------------
# Simulate: run ModelSim, dump signature
# -----------------------------------------------------------------------
$(OUTDIR)/%.sig: $(OUTDIR)/%.hex $(OUTDIR)/%.sig_range sim_compliance.sv
	$(eval RANGE := $(shell cat $(OUTDIR)/$*.sig_range))
	$(eval SB    := $(word 1,$(RANGE)))
	$(eval SE    := $(word 2,$(RANGE)))
	$(VSIM) -c -quiet \
	    -do "vlog -sv \
	              +incdir+$(HW_ROOT)/pkg \
	              $(HW_ROOT)/pkg/rv32if_pkg.sv \
	              $(HW_ROOT)/fetch/instr_mem.sv \
	              $(HW_ROOT)/fetch/data_mem.sv \
	              $(HW_ROOT)/execute/int_ops/alu_unit.sv \
	              $(HW_ROOT)/execute/fp_ops/fp_add.sv \
	              $(HW_ROOT)/execute/fp_ops/fp_mul.sv \
	              $(HW_ROOT)/execute/fp_ops/fp_div.sv \
	              $(HW_ROOT)/execute/fp_ops/fp_cvt.sv \
	              $(HW_ROOT)/execute/fp_ops/fp_round.sv \
	              $(HW_ROOT)/core/reservation_station.sv \
	              $(HW_ROOT)/core/rob_unit.sv \
	              $(HW_ROOT)/core/rat.sv \
	              $(HW_ROOT)/core/dispatch_unit.sv \
	              $(HW_ROOT)/core/lsb.sv \
	              $(HW_ROOT)/core/branch_unit.sv \
	              $(HW_ROOT)/core/commit_unit.sv \
	              $(HW_ROOT)/core/tomasulo_core.sv \
	              sim_compliance.sv; \
	         vsim -c work.sim_compliance \
	              +HEX=$(OUTDIR)/$*.hex \
	              +SIG_BEGIN=$(SB) \
	              +SIG_END=$(SE) \
	              +SIG_OUT=$(OUTDIR)/$*.sig \
	              -do 'run -all; quit'; \
	         quit -f" 2>&1 | grep -E 'PASS|FAIL|TIMEOUT|Error|error' || true

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
	rm -rf $(OUTDIR) work transcript vsim.wlf

# Single-test shortcut:  make I-ADD-01
$(TESTS): %: $(OUTDIR)/%.pass
