### Options ###
WAVE ?= 0
COV  ?= 0
UVM_VERBOSITY ?= UVM_LOW
###############

# --------------------------------------------------------------------------
# Project
# --------------------------------------------------------------------------
TOP         = top
SIM         = sim
RTL_FILES   = rtl.f
VERIF_FILES = verif.f
RTL_LIB     = myrtl
TB_LIB      = tb
WDB         = waves.wdb

# --------------------------------------------------------------------------
# Coverage
# --------------------------------------------------------------------------
COV_DIR     = cov
COV_DB_NAME = coverage
REPORT_DIR  = $(COV_DIR)/report

# --------------------------------------------------------------------------
# Formatting
# --------------------------------------------------------------------------
FORMAT_SRC  = interfaces.sv controller.sv dut.sv top.sv top_tb.sv
FORMAT_TOOL = verible-verilog-format
FORMAT_ARGS = --flagfile=.verilog_format --inplace

# --------------------------------------------------------------------------
# Flags
# --------------------------------------------------------------------------

XVLOG_FLAGS    := -sv --work $(RTL_LIB)
XVLOG_TB_FLAGS := -sv --work $(TB_LIB) -L uvm

XELAB_FLAGS := -s $(SIM) -L $(RTL_LIB) -L uvm -timescale 1ns/1ps
ifeq ($(WAVE),1)
  XELAB_FLAGS += --debug typical
endif
ifeq ($(COV),1)
  XELAB_FLAGS += --debug typical -cc_type sbct \
                 -cov_db_dir $(COV_DIR) -cov_db_name $(COV_DB_NAME)
endif

XSIM_FLAGS := -runall
XSIM_FLAGS += -testplusarg UVM_VERBOSITY=$(UVM_VERBOSITY)
# FIXME: this flag does not work
XSIM_FLAGS += -testplusarg UVM_NO_RELNOTES
ifeq ($(WAVE),1)
  XSIM_FLAGS += -wdb $(WDB)
endif

XCRG_FLAGS := -cov_db_dir $(COV_DIR) -cov_db_name $(COV_DB_NAME) \
              -cc_report $(REPORT_DIR)

# --------------------------------------------------------------------------

.PHONY: all comp_rtl comp_tb elab run waves report snapshot format clean

all: comp_rtl comp_tb elab run

comp_rtl:
	xvlog -f $(RTL_FILES) $(XVLOG_FLAGS)
	@echo "\nComp RTL Done!"

comp_tb:
	xvlog -f $(VERIF_FILES) $(XVLOG_TB_FLAGS)
	@echo "\nComp TB Done!"

elab:
ifeq ($(COV),1)
	@mkdir -p $(COV_DIR)
endif
	xelab $(TB_LIB).$(TOP) $(XELAB_FLAGS)
	@echo "\nElab Done!"

run:
	xsim $(SIM) $(XSIM_FLAGS)
ifeq ($(WAVE),1)
	@echo "\nWaveforms saved to $(WDB)"
endif
ifeq ($(COV),1)
	@echo "\nCoverage database written to: $(COV_DIR)/$(COV_DB_NAME)"
endif
	@echo "\nSim Done!"

waves:
	xsim --gui $(WDB) &

report:
ifeq ($(COV),1)
	@mkdir -p $(REPORT_DIR)
	xcrg $(XCRG_FLAGS)
	@echo "\nHTML report : $(REPORT_DIR)/dashboard.html"
	@echo "Text report : $(REPORT_DIR)/xcrg_report.txt"
else
	@echo "\nNothing to report -- re-run with COV=1"
endif

format:
	$(FORMAT_TOOL) $(FORMAT_ARGS) $(FORMAT_SRC)
	@echo "\nFormat Done!"

clean:
	rm -rf xsim.dir *.log *.jou *.pb *.wdb *.wcfg $(COV_DIR)
	@echo "\nClean Done!"
