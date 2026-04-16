// =============================================================================
// top.sv  -  Top-level simulation module
// =============================================================================

`timescale 1ns/1ps

module top;

// 50 MHz clock
logic clk;
initial clk = 1'b0;
always #10 clk = ~clk;  // 20 ns period

simple_if sif (.clk(clk));

dut u_dut (
    .clk      (clk),
    .rst_n    (sif.rst_n),
    .op       (sif.op),
    .addr     (sif.addr),
    .wdata    (sif.wdata),
    .start    (sif.start),
    .sw_reset (sif.sw_reset),
    .rdata    (sif.rdata),
    .done     (sif.done),
    .busy     (sif.busy),
    .error    (sif.error)
);

top_tb u_tb (.clk(clk), .sif(sif));

endmodule
