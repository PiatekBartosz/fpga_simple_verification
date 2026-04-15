// =============================================================================
// interfaces.sv  -  Interface definitions
// =============================================================================

`timescale 1ns/1ps

// Simple control interface between testbench and controller
interface simple_if (input logic clk);
    logic        rst_n;
    logic [1:0]  op;       // 00=READ_ID  01=READ_STATUS  10=READ_DATA  11=WRITE_DATA
    logic [16:0] addr;     // 17-bit word address (bit16 = block select for 24CSM01)
    logic [7:0]  wdata;    // write data
    logic        start;    // pulse high 1 cycle to launch

    logic [7:0]  rdata;    // read data (valid when done=1)
    logic        done;     // pulses high 1 cycle on completion
    logic        busy;     // high while operation in progress
    logic        error;    // high if NACK received (cleared on next start)

    modport ctrl_mp (
        input  rst_n, op, addr, wdata, start,
        output rdata, done, busy, error
    );

    modport tb_mp (
        output rst_n, op, addr, wdata, start,
        input  rdata, done, busy, error
    );
endinterface
