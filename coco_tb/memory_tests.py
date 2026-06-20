
import cocotb
from cocotb.triggers import Timer, FallingEdge
from enum import Enum

# class OpCodes(Enum):
#     __init__():
#     pass

# OP_WRITE_DATA

async def generate_clock(dut):
    """Generate clock pulses."""

    for _ in range(10):
        dut.clk.value = 0
        await Timer(1, unit="ns")
        dut.clk.value = 1
        await Timer(1, unit="ns")

@cocotb.test()
async def my_first_test(dut):
    """Try accessing the design."""

    cocotb.start_soon(generate_clock(dut))

    await Timer(5, unit="ns")
    await FallingEdge(dut.clk)

    for _ in range(10):
        dut.clk.value = 0
        await Timer(1, unit="ns")
        dut.clk.value = 1
        await Timer(1, unit="ns")

    # dut.op = OP_WRITE_DATA
    # dut.wdata = 0xDD
    # dut.addr = 0
        