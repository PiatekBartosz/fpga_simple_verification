// dut.sv
`timescale 1ns / 1ps

module dut (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [ 1:0] op,
    input  logic [ 7:0] wdata,
    input  logic [16:0] addr,
    output logic [23:0] rdata,
    output logic        done,
    output logic        error
);

    wire scl, sda;
    assign (pull1, highz0) sda = 1'b1;

    controller #(
        .CLK_DIV  (62),
        .CHIP_ADDR(2'b00)
    ) u_ctrl (
        .clk  (clk),
        .rst_n(rst_n),
        .op   (op),
        .addr (addr),
        .wdata(wdata),
        .start(start),
        .rdata(rdata),
        .done (done),
        .error(error),
        .scl  (scl),
        .sda  (sda)
    );

    M24CSM01 u_mem (
        .A1   (1'b0),
        .A2   (1'b0),
        .WP   (1'b0),
        .SDA  (sda),
        .SCL  (scl),
        .RESET(1'b0)
    );

endmodule
