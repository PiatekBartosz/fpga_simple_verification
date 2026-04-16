// interfaces.sv
`timescale 1ns / 1ps

interface simple_if (
    input logic clk
);
    logic rst_n, start, sw_reset, done, error;
    logic [ 1:0] op;
    logic [ 7:0] wdata;
    logic [16:0] addr;
    logic [23:0] rdata;

    modport ctrl_mp(input rst_n, op, addr, wdata, start, sw_reset, output rdata, done, error);
    modport tb_mp(output rst_n, op, addr, wdata, start, sw_reset, input rdata, done, error);
endinterface
