// =============================================================================
// dut.sv  -  Design Under Test
//
// Instantiates the I2C controller and the Microchip 24CSM01 memory model.
// The I2C SDA bus is a shared inout wire (open-drain, pulled high).
// SCL is driven solely by the controller (master).
// =============================================================================

`timescale 1ns/1ps

module dut (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [1:0]  op,
    input  logic [16:0] addr,
    input  logic [7:0]  wdata,
    input  logic        start,
    output logic [7:0]  rdata,
    output logic        done,
    output logic        busy,
    output logic        error
);

wire scl;
wire sda;

// Controller drives SCL and manages SDA as open-drain
controller #(
    .CLK_DIV   (62),
    .CHIP_ADDR (2'b00)
) u_ctrl (
    .clk    (clk),
    .rst_n  (rst_n),
    .op     (op),
    .addr   (addr),
    .wdata  (wdata),
    .start  (start),
    .rdata  (rdata),
    .done   (done),
    .busy   (busy),
    .error  (error),
    .scl    (scl),
    .sda    (sda)
);

// 24CSM01 EEPROM model (A1=0, A2=0 matches CHIP_ADDR=2'b00)
M24CSM01 u_mem (
    .A1    (1'b0),
    .A2    (1'b0),
    .WP    (1'b0),
    .SDA   (sda),
    .SCL   (scl),
    .RESET (1'b0)
);

endmodule
