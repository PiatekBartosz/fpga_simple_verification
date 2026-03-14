module top;
    logic clk; 
    logic rtsn; 

    dut dut_int(
        .i_clk(clk),
        .i_rtsn(rtsn)
    );

    top_tb tb_inst(
        .o_clk(clk),
        .o_rtsn(rtsn)
    );

endmodule