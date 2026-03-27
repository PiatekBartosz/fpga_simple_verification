module dut (
    input  logic        i_clk,
    input  logic        i_rtsn,

    input  logic        i_valid,
    output logic        o_ready,
    input  logic [16:0] i_addr,
    input  logic        i_rw,
    input  logic [7:0]  i_wdata,
    output logic [7:0]  o_rdata
);
    wire sda;
    wire scl;

    pullup(sda);
    pullup(scl);

    AT24CM02 model_inst(
        .SDA(sda),
        .SCL(scl),
        .WP(1'b0)
    );

    controller controller_inst(
        .clk(i_clk),
        .i_rtsn(i_rtsn),

        .valid(i_valid),
        .ready(i_ready),
        .addr(i_addr),
        .rw(i_rw),
        .wdata(i_wdata),
        .rdata(i_rdata),

        .sda(sda),
        .scl(scl)
    );

endmodule