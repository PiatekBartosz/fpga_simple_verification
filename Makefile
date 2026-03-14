TOP        = top_tb
# BUILD_DIR  = _build
SIM        = sim

# SOURCES    = dut.sv top.sv top_tb.sv
SOURCES    = top_tb.sv

all: compile elaborate run

compile:
	xvlog $(SOURCES) --sv

elaborate:
	xelab $(TOP) -s $(SIM)

run:
	xsim $(SIM) -runall

clean:
	rm -rf  xsim.dir *.log *.jou *.pb

.PHONY: all compile elaborate run clean
