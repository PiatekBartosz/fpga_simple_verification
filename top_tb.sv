timeunit 1ns;
timeprecision 1ps;

module top_tb(
    output logic o_clk,
    output logic o_rtsn
);

initial begin
    $display("Starting tb");
    o_clk  = 0;
    o_rtsn = 1;
    $display("rtsn = 1");

    repeat (10) @(posedge o_clk);

    o_rtsn = 0;
    $display("rtsn = 0");

    repeat (20) @(posedge o_clk);
    $finish;
end

always #5 o_clk = ~o_clk;

endmodule
