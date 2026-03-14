module dut (
    input  logic [7:0] a,
    input  logic [7:0] b,
    output logic [8:0] y
);
    assign y = a + b;

endmodule