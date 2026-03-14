TOP        = top_tb
SIM        = sim

VERIF_FILES  = verif.f
RTL_FILES    = rtl.f

RTL_LIB     = myrtl
TB_LIB      = tb

all: comp_rtl comp_tb elab run

comp_rtl:
	xvlog -f $(RTL_FILES) --sv --work $(RTL_LIB)

comp_tb:
	xvlog -f $(VERIF_FILES) --sv --work $(TB_LIB)

elab:
	xelab $(TB_LIB).$(TOP) -s $(SIM)

run:
	xsim $(SIM) -runall

clean:
	rm -rf  xsim.dir *.log *.jou *.pb

.PHONY: all comp_rtl comp_tb run clean
