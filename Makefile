TOP        = top_tb
SIM        = sim

SOURCES    = dut.sv top.sv top_tb.sv

all: compile elaborate run

compile:
	xvlog $(SOURCES) --sv --work mylib

elab:
	xelab mylib.$(TOP) -s $(SIM)

run:
	xsim $(SIM) -runall

clean:
	rm -rf  xsim.dir *.log *.jou *.pb

.PHONY: all compile elaborate run clean
