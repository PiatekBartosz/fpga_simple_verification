module top;
    logic clk; 
    logic rtsn; 

    // TestBench Controller
    logic cmd_valid;
    logic cmd_ready;
    logic cmd_read_write;
    logic [16:0] cmd_addr;
    logic [7:0] cmd_wdata;
    logic [7:0] cmd_rdata;

    dut dut_inst(
        .i_clk(clk),
        .i_rtsn(rtsn)
    );

    top_tb tb_inst(
        .o_clk(clk),
        .o_rtsn(rtsn)
    );

endmodule