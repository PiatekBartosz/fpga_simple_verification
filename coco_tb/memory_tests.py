import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge
from enum import IntEnum

class OpCodes(IntEnum):
    OP_READ_ID = 0b000
    OP_READ_STATUS = 0b001
    OP_READ_DATA = 0b010
    OP_WRITE_DATA = 0b011
    OP_SW_RESET = 0b100


async def drive_op(dut, op, addr=0, wdata=0):
    await RisingEdge(dut.clk)
    dut.op.value = int(op)
    dut.addr.value = addr
    dut.wdata.value = wdata
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    while not (dut.done.value or dut.error.value):
        await RisingEdge(dut.clk)


@cocotb.test()
async def test_clock_and_reset(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())

    dut.rst_n.value = 0
    dut.start.value = 0
    dut.op.value = 0
    dut.wdata.value = 0
    dut.addr.value = 0

    await Timer(200, unit="ns")
    dut.rst_n.value = 1
    await Timer(200, unit="ns")

    cocotb.log.info("Clock and reset test passed")


@cocotb.test()
async def test_readback(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())

    dut.rst_n.value = 0
    dut.start.value = 0
    dut.op.value = 0
    dut.wdata.value = 0
    dut.addr.value = 0
    for _ in range(10):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(15):
        await RisingEdge(dut.clk)

    addr = random.randint(0, 0xFFFF)
    data = random.randint(0, 0xFF)
    cocotb.log.info("Write 0x%02X -> addr 0x%05X", data, addr)

    await drive_op(dut, OpCodes.OP_WRITE_DATA, addr=addr, wdata=data)
    assert not dut.error.value, "Write failed"

    await Timer(6, unit="ms")

    await drive_op(dut, OpCodes.OP_READ_DATA, addr=addr)
    assert not dut.error.value, "Read failed"

    result = int(dut.rdata.value) & 0xFF
    cocotb.log.info("Read  0x%02X <- addr 0x%05X", result, addr)
    assert result == data, f"Mismatch: wrote 0x{data:02X}, got 0x{result:02X}"
