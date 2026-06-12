### Options ###
WAVE ?= 0
COV  ?= 0
TOPO ?= 0
VERBOSITY ?= UVM_LOW
TESTNAME ?= mem_ctrl_test
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
# format works file-by-file (verible does not follow `include`s),
# so unlike compilation it needs every source listed
# external/vendor sources are excluded from formatting
FORMAT_IGNORE = src/rtl/24CSM01.v
FORMAT_SRC    = $(filter-out $(FORMAT_IGNORE), \
                $(wildcard src/rtl/*.sv src/rtl/*.v src/tb/*.sv src/tb/seq/*.sv src/tb/tests/*.sv))
FORMAT_TOOL = verible-verilog-format
FORMAT_ARGS = --flagfile=.verilog_format --inplace

# --------------------------------------------------------------------------
# Flags
# --------------------------------------------------------------------------

XVLOG_FLAGS    := -sv --work $(RTL_LIB)
XVLOG_TB_FLAGS := -sv --work $(TB_LIB) -L uvm -L $(RTL_LIB)

XELAB_FLAGS := -s $(SIM) -L $(RTL_LIB) -L uvm -timescale 1ns/1ps
ifeq ($(WAVE),1)
  XELAB_FLAGS += --debug typical
endif
ifeq ($(COV),1)
  XVLOG_TB_FLAGS += --define COV
  XELAB_FLAGS += --debug typical -cc_type sbct \
                 -cov_db_dir $(COV_DIR) -cov_db_name $(COV_DB_NAME)
endif

XSIM_FLAGS := -runall
XSIM_FLAGS += -testplusarg UVM_VERBOSITY=$(VERBOSITY)
XSIM_FLAGS += -testplusarg UVM_TESTNAME=$(TESTNAME)
# FIXME: this flag does not work
XSIM_FLAGS += -testplusarg UVM_NO_RELNOTES
ifeq ($(WAVE),1)
  XSIM_FLAGS += -wdb $(WDB)
endif
ifeq ($(TOPO),1)
  XSIM_FLAGS += -testplusarg PRINT_TOPO
endif

XCRG_FLAGS := -cov_db_dir $(COV_DIR) -cov_db_name $(COV_DB_NAME) \
              -report_dir $(REPORT_DIR) \
              -report_format all

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
	@echo "\nCC report : $(REPORT_DIR)/codeCoverageReport/dashboard.html"
	@echo "FC report : $(REPORT_DIR)/functionalCoverageReport/dashboard.html"
else
	@echo "\nNothing to report -- re-run with COV=1"
endif

format:
	$(FORMAT_TOOL) $(FORMAT_ARGS) $(FORMAT_SRC)
	@echo "\nFormat Done!"

clean:
	rm -rf xsim.dir *.log *.jou *.pb *.wdb *.wcfg $(COV_DIR)
	@echo "\nClean Done!"
