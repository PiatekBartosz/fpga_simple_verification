// top.sv
`timescale 1ns / 1ps

`include "uvm_macros.svh"
import uvm_pkg::*;
import mem_ctrl_tb_pkg::*;

module top;

    logic clk;
    initial clk = 1'b0;
    always #10 clk = ~clk;

    simple_if sif (.clk(clk));

    dut u_dut (
        .clk  (clk),
        .rst_n(sif.rst_n),
        .op   (sif.op),
        .addr (sif.addr),
        .wdata(sif.wdata),
        .start(sif.start),
        .rdata(sif.rdata),
        .done (sif.done),
        .error(sif.error)
    );

    initial begin
        uvm_config_db#(virtual simple_if)::set(null, "uvm_test_top.*", "vif", sif);
        run_test();
    end

endmodule
