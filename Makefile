TOP        = top_tb
SIM        = sim

VERIF_FILES  = verif.f
RTL_FILES    = rtl.f

RTL_LIB     = myrtl
TB_LIB      = tb

all: comp_rtl comp_tb elab run

comp_rtl:
	xvlog -f $(RTL_FILES) --sv --work $(RTL_LIB)
	@echo "\nComp RTL Done!"

comp_tb:
	xvlog -f $(VERIF_FILES) --sv --work $(TB_LIB)
	@echo "\nComp TB Done!"

elab:
	xelab $(TB_LIB).$(TOP) -s $(SIM)
	@echo "\nElab Done!"

run:
	xsim $(SIM) -runall
	@echo "\nSim Done!"

clean:
	rm -rf  xsim.dir *.log *.jou *.pb
	@echo "\nClean Done!"

.PHONY: all comp_rtl comp_tb run clean
