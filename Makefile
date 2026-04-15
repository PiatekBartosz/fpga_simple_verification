### Options ###
WAVE ?= 0
###############

TOP         = top
SIM         = sim
RTL_FILES   = rtl.f
VERIF_FILES = verif.f
RTL_LIB     = myrtl
TB_LIB      = tb
WDB         = waves.wdb

.PHONY: all comp_rtl comp_tb elab run waves clean

all: comp_rtl comp_tb elab run

comp_rtl:
	xvlog -f $(RTL_FILES) --sv --work $(RTL_LIB)
	@echo "\nComp RTL Done!"

comp_tb:
	xvlog -f $(VERIF_FILES) --sv --work $(TB_LIB)
	@echo "\nComp TB Done!"

elab:
ifeq ($(WAVE),1)
	xelab $(TB_LIB).$(TOP) -s $(SIM) -L $(RTL_LIB) --debug typical
else
	xelab $(TB_LIB).$(TOP) -s $(SIM) -L $(RTL_LIB)
endif
	@echo "\nElab Done!"

run:
ifeq ($(WAVE),1)
	xsim $(SIM) -runall -wdb $(WDB)
	@echo "\nWaveforms saved to $(WDB)"
else
	xsim $(SIM) -runall
endif
	@echo "\nSim Done!"

waves:
	xsim --gui $(WDB) &

clean:
	rm -rf xsim.dir *.log *.jou *.pb *.wdb *.wcfg
	@echo "\nClean Done!"
