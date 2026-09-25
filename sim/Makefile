#===============================================================================
# Frame Aligner verification -- simulation makefile
#-------------------------------------------------------------------------------
#  make sim   [DUT=orig|fixed] [TEST=regression] [MODEL=spec|dut] [SEED=1]
#             [NUM_ITEMS=400] [VERBOSITY=1] [WAVES=1]
#  make regress          full regression matrix (sim/regress.py)
#  make lint             Verilator lint of both RTL versions
#  make lint-fixed       lint of the corrected RTL only (must be clean)
#  make check-rtl-untouched   prove rtl/frame_aligner.sv == delivered DUT
#  make clean
#
#  Simulator: Verilator >= 5.030 (open source; --timing, SVA, classes,
#  constrained randomisation with z3/cvc5).  Commands for commercial
#  simulators are given at the bottom (SIM=questa|vcs|xcelium); they use the
#  same file lists.
#===============================================================================
DUT        ?= orig
TEST       ?= regression
MODEL      ?= spec
SEED       ?= 1
NUM_ITEMS  ?= 400
VERBOSITY  ?= 1
WAVES      ?= 0
SIM        ?= verilator
VERILATOR  ?= verilator

ifeq ($(DUT),fixed)
  DUT_FILE := ../rtl/frame_aligner_fixed.sv
else
  DUT_FILE := ../rtl/frame_aligner.sv
endif

BUILD_DIR  := build/$(DUT)$(if $(filter 1,$(WAVES)),_waves,)
RUN_ARGS   := +TEST=$(TEST) +MODEL=$(MODEL) +SEED=$(SEED) +NUM_ITEMS=$(NUM_ITEMS) \
              +VERBOSITY=$(VERBOSITY) +DUT_NAME=$(DUT) $(if $(filter 1,$(WAVES)),+DUMP,)
LOG        := logs/$(DUT)_$(MODEL)_$(TEST)_s$(SEED).log

VLT_FLAGS  := --binary --timing --assert -j 4 --top-module tb_top \
              -Wno-fatal -Wno-COVERIGN -Wno-lint -Wno-style \
              $(if $(filter 1,$(WAVES)),--trace,) \
              --Mdir $(BUILD_DIR)

.PHONY: sim build regress lint lint-fixed check-rtl-untouched clean

build: $(BUILD_DIR)/Vtb_top

$(BUILD_DIR)/Vtb_top: $(DUT_FILE) $(wildcard ../tb/*.sv ../tb/*.svh) files_tb.f
	@mkdir -p $(BUILD_DIR)
	$(VERILATOR) $(VLT_FLAGS) $(DUT_FILE) -f files_tb.f

sim: build
	@mkdir -p logs
	$(BUILD_DIR)/Vtb_top $(RUN_ARGS) +verilator+seed+$(SEED) | tee $(LOG)

regress:
	python3 regress.py

lint:
	-$(VERILATOR) --lint-only -Wall -Wno-DECLFILENAME ../rtl/frame_aligner.sv
	$(VERILATOR) --lint-only -Wall -Wno-DECLFILENAME ../rtl/frame_aligner_fixed.sv

# The corrected RTL must be completely lint clean (-Wall warnings are fatal).
lint-fixed:
	$(VERILATOR) --lint-only -Wall -Wno-DECLFILENAME ../rtl/frame_aligner_fixed.sv

check-rtl-untouched:
	python3 ../scripts/check_rtl_untouched.py ../rtl/frame_aligner.sv

clean:
	rm -rf build logs waves.vcd

#-------------------------------------------------------------------------------
# Commercial simulators (not exercised in this repository's CI):
#   Questa : vlog -sv $(DUT_FILE) -f files_tb.f && vsim -c tb_top -sv_seed $(SEED) $(RUN_ARGS) -do "run -all"
#   VCS    : vcs -sverilog -timescale=1ns/1ps $(DUT_FILE) -f files_tb.f -top tb_top && ./simv +ntb_random_seed=$(SEED) $(RUN_ARGS)
#   Xcelium: xrun -sv $(DUT_FILE) -f files_tb.f -top tb_top -svseed $(SEED) $(RUN_ARGS)
#-------------------------------------------------------------------------------
