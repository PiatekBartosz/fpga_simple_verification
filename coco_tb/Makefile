SIM = icarus
TOPLEVEL_LANG = verilog

VERILOG_SOURCES = \
    $(CURDIR)/../src/rtl/interfaces.sv \
    $(CURDIR)/../src/rtl/24CSM01.v \
    $(CURDIR)/../src/rtl/controller.sv \
    $(CURDIR)/../src/rtl/dut.sv

COCOTB_TOPLEVEL = dut
COCOTB_TEST_MODULES = memory_tests
WAVES = 1

include $(shell cocotb-config --makefiles)/Makefile.sim
