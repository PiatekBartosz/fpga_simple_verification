module controller (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        valid,
    output logic        ready,
    input  logic [16:0] addr,
    input  logic        rw,  
    input  logic [7:0]  wdata,
    output logic [7:0]  rdata,

    inout  wire         sda,
    output wire         scl
);

endmodule