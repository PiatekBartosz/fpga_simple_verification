// interfaces.sv
`timescale 1ns / 1ps

interface simple_if (
    input logic clk
);
    logic        rst_n;
    logic [ 1:0] op;
    logic [16:0] addr;
    logic [ 7:0] wdata;
    logic        start;
    logic        sw_reset;
    logic [23:0] rdata;
    logic        done;
    logic        busy;
    logic        error;

    modport ctrl_mp(input rst_n, op, addr, wdata, start, sw_reset, output rdata, done, busy, error);
    modport tb_mp(output rst_n, op, addr, wdata, start, sw_reset, input rdata, done, busy, error);
endinterface
