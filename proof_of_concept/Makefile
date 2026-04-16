# =============================================================================
# Makefile – Vivado xsim simulation for 24CSM01 Manufacturer ID testbench
#
# Usage:
#   make          – compile and run simulation
#   make compile  – compile only
#   make sim      – run simulation (after compile)
#   make waves    – open waveform in Vivado GUI
#   make clean    – remove all generated files
#
# Requires: Vivado in PATH  (e.g. source /tools/Xilinx/Vivado/<ver>/settings64.sh)
# =============================================================================

TOPLEVEL   := tb_24csm01_manid
SV_TB      := tb_24csm01_manid.sv
V_MODEL    := 24CSM01.v

XVLOG_OPTS := --incr --relax
XELAB_OPTS := --incr --relax --debug typical \
              --timescale 1ns/1ps \
              --snapshot $(TOPLEVEL)_snap

XSIM_OPTS  := --runall --onerror quit

# -----------------------------------------------------------------------------
.PHONY: all compile sim waves clean

all: compile sim

compile:
	xvlog $(XVLOG_OPTS) -sv $(V_MODEL)
	xvlog $(XVLOG_OPTS) -sv $(SV_TB)
	xelab $(XELAB_OPTS) $(TOPLEVEL)

sim:
	xsim $(TOPLEVEL)_snap $(XSIM_OPTS)

waves:
	xsim $(TOPLEVEL)_snap --gui

clean:
	rm -rf xsim.dir *.jou *.log *.pb *.str *.vcd \
	       webtalk_*.zip webtalk.jou webtalk.log \
	       xelab.* xvlog.*
