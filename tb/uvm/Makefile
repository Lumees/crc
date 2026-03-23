# =============================================================================
# Copyright (c) 2026 Lumees Lab
# SPDX-License-Identifier: MIT
# =============================================================================
# CRC UVM Testbench — Makefile
# Supports: Questa / ModelSim (default), VCS (SIM=vcs)
# =============================================================================
#
# Usage:
#   make sim              # compile + run with default test (crc_directed_test)
#   make sim-directed     # directed test
#   make sim-random       # random CRC transactions
#   make sim-stress       # stress test with back-to-back transactions
#   make compile          # compile only
#   make run              # run only (must compile first)
#   make clean            # remove build artefacts
#
# Overrides:
#   make sim UVM_TEST=crc_random_test SEED=42
#   make sim SIM=vcs
# =============================================================================

# -- Simulator selection -------------------------------------------------------
SIM       ?= questa

# -- Design under test --------------------------------------------------------
TOP        = crc_tb_top
RTL_DIR    = ../../rtl
UVM_HOME  ?= $(QUESTA_HOME)/verilog_src/uvm-1.2

# -- Test / DUT parameters ----------------------------------------------------
UVM_TEST  ?= crc_directed_test
UVM_VERB  ?= UVM_MEDIUM
SEED      ?= 1

# -- Build directories --------------------------------------------------------
BUILD_DIR  = work
LOG_DIR    = logs

# -- RTL source list ----------------------------------------------------------
RTL_SRCS = \
	$(RTL_DIR)/crc_pkg.sv            \
	$(RTL_DIR)/crc_core.sv           \
	$(RTL_DIR)/crc_axis.sv           \
	$(RTL_DIR)/crc_axil.sv           \
	$(RTL_DIR)/crc_wb.sv             \
	$(RTL_DIR)/crc_top.sv

# -- TB source (top includes all others via `include) -------------------------
TB_TOP = crc_tb_top.sv

# =============================================================================
# Questa / ModelSim targets
# =============================================================================
ifeq ($(SIM),questa)

VLOG  = vlog
VSIM  = vsim

VLOG_FLAGS  = -sv \
              +incdir+$(RTL_DIR) \
              +incdir+. \
              -timescale "1ns/1ps" \
              -work $(BUILD_DIR)

VSIM_FLAGS  = -sv_seed $(SEED) \
              -t 1ns \
              +UVM_TESTNAME=$(UVM_TEST) \
              +UVM_VERBOSITY=$(UVM_VERB) \
              -permit_unmatched_virtual_intf \
              -do "run -all; quit -f"

.PHONY: compile
compile: $(BUILD_DIR)/_lib.qdb

$(BUILD_DIR)/_lib.qdb: $(RTL_SRCS) $(TB_TOP)
	@mkdir -p $(BUILD_DIR) $(LOG_DIR)
	$(VLOG) -work $(BUILD_DIR) $(VLOG_FLAGS) $(RTL_SRCS) $(TB_TOP) \
		2>&1 | tee $(LOG_DIR)/compile.log
	@echo "Compilation complete."

.PHONY: run
run:
	@mkdir -p $(LOG_DIR)
	$(VSIM) $(VSIM_FLAGS) \
		-work $(BUILD_DIR) \
		$(TOP) \
		2>&1 | tee $(LOG_DIR)/run_$(UVM_TEST).log

.PHONY: sim
sim: compile run

# Named convenience targets
.PHONY: sim-directed
sim-directed:
	$(MAKE) sim UVM_TEST=crc_directed_test

.PHONY: sim-random
sim-random:
	$(MAKE) sim UVM_TEST=crc_random_test

.PHONY: sim-stress
sim-stress:
	$(MAKE) sim UVM_TEST=crc_stress_test UVM_VERB=UVM_MEDIUM

# Run all three in sequence
.PHONY: sim-all
sim-all: sim-directed sim-random sim-stress

endif  # questa

# =============================================================================
# VCS targets
# =============================================================================
ifeq ($(SIM),vcs)

VCS      = vcs
SIMV_OUT = simv

VCS_FLAGS = -sverilog \
            +incdir+$(RTL_DIR) \
            +incdir+. \
            -timescale=1ns/1ps \
            -ntb_opts uvm \
            -full64 \
            -debug_access+all

SIMV_FLAGS = +UVM_TESTNAME=$(UVM_TEST) \
             +UVM_VERBOSITY=$(UVM_VERB) \
             -sv_seed $(SEED)

.PHONY: compile
compile:
	@mkdir -p $(LOG_DIR)
	$(VCS) $(VCS_FLAGS) $(RTL_SRCS) $(TB_TOP) \
		-o $(SIMV_OUT) \
		2>&1 | tee $(LOG_DIR)/compile.log

.PHONY: run
run:
	@mkdir -p $(LOG_DIR)
	./$(SIMV_OUT) $(SIMV_FLAGS) \
		2>&1 | tee $(LOG_DIR)/run_$(UVM_TEST).log

.PHONY: sim
sim: compile run

.PHONY: sim-directed
sim-directed:
	$(MAKE) sim UVM_TEST=crc_directed_test

.PHONY: sim-random
sim-random:
	$(MAKE) sim UVM_TEST=crc_random_test

.PHONY: sim-stress
sim-stress:
	$(MAKE) sim UVM_TEST=crc_stress_test UVM_VERB=UVM_MEDIUM

.PHONY: sim-all
sim-all: sim-directed sim-random sim-stress

endif  # vcs

# =============================================================================
# Clean
# =============================================================================
.PHONY: clean
clean:
	@rm -rf $(BUILD_DIR) $(LOG_DIR) $(SIMV_OUT) simv.daidir \
	        transcript vsim.wlf *.log *.vcd *.fsdb ucdb \
	        csrc DVEfiles inter.vpd urgReport
	@echo "Clean complete."

# =============================================================================
# Help
# =============================================================================
.PHONY: help
help:
	@echo ""
	@echo "CRC UVM Testbench Makefile"
	@echo "--------------------------"
	@echo "Targets:"
	@echo "  sim           Compile + run (default test: $(UVM_TEST))"
	@echo "  sim-directed  Run directed test"
	@echo "  sim-random    Run random CRC transactions"
	@echo "  sim-stress    Run stress test with back-to-back transactions"
	@echo "  sim-all       Run directed + random + stress"
	@echo "  compile       Compile only"
	@echo "  run           Run only (compile first)"
	@echo "  clean         Remove all build artefacts"
	@echo ""
	@echo "Key variables:"
	@echo "  SIM       Simulator: questa (default) | vcs"
	@echo "  UVM_TEST  Test class name (default: crc_directed_test)"
	@echo "  UVM_VERB  UVM verbosity (default: UVM_MEDIUM)"
	@echo "  SEED      Random seed (default: 1)"
	@echo ""
	@echo "Examples:"
	@echo "  make sim UVM_TEST=crc_random_test SEED=42"
	@echo "  make sim-stress SIM=vcs"
	@echo ""
