// top_tb.sv
`timescale 1ns / 1ps

module top_tb (
    input logic           clk,
          simple_if.tb_mp sif
);

    localparam int WRITE_CYCLE_WAIT = 260_000;
    localparam int TIMEOUT = 500_000;

    localparam logic [2:0] OP_READ_ID = 3'b000;
    localparam logic [2:0] OP_READ_STATUS = 3'b001;
    localparam logic [2:0] OP_READ_DATA = 3'b010;
    localparam logic [2:0] OP_WRITE_DATA = 3'b011;
    localparam logic [2:0] OP_SW_RESET = 3'b100;

    task automatic wait_completion(output logic timed_out);
        timed_out = 1'b0;
        for (int i = 0; i < TIMEOUT; i++) begin
            @(posedge clk);
            if (sif.done || sif.error) begin
                return;
            end
        end
        timed_out = 1'b1;
        $display("[TB] TIMEOUT at %0t", $time);
    endtask

    task automatic run_op(input logic [2:0] op_in, input logic [16:0] addr_in,
                          input logic [7:0] wdata_in, output logic [23:0] rdata_out,
                          output logic failed);
        logic timed_out;
        @(posedge clk);
        sif.op    <= op_in;
        sif.addr  <= addr_in;
        sif.wdata <= wdata_in;
        sif.start <= 1'b1;
        @(posedge clk);
        sif.start <= 1'b0;
        wait_completion(timed_out);
        rdata_out = sif.rdata;
        failed    = sif.error | timed_out;
    endtask

    int          fail_cnt;
    logic [23:0] rd;
    logic        fail;

    initial begin
        sif.rst_n <= 1'b0;
        sif.op    <= '0;
        sif.addr  <= '0;
        sif.wdata <= '0;
        sif.start <= 1'b0;
        fail_cnt = 0;
        repeat (10) @(posedge clk);
        sif.rst_n <= 1'b1;
        repeat (5) @(posedge clk);
        $display("=== Simulation start ===");

        // SW_RESET
        run_op(OP_SW_RESET, '0, '0, rd, fail);
        if (fail) begin
            $display("[FAIL] SW_RESET");
            fail_cnt++;
        end else begin
            $display("[PASS] SW_RESET");
        end
        repeat (5) @(posedge clk);

        // READ_ID
        run_op(OP_READ_ID, '0, '0, rd, fail);
        if (fail) begin
            $display("[FAIL] READ_ID");
            fail_cnt++;
        end else if (rd !== 24'h00D0D0) begin
            $display("[FAIL] READ_ID got=0x%06X expected=0x00D0D0", rd);
            fail_cnt++;
        end else begin
            $display("[PASS] READ_ID  ManID=0x%06X", rd);
        end
        repeat (5) @(posedge clk);

        // READ_STATUS
        run_op(OP_READ_STATUS, '0, '0, rd, fail);
        if (fail) begin
            $display("[FAIL] READ_STATUS");
            fail_cnt++;
        end else begin
            $display("[PASS] READ_STATUS  rdata=0x%02X", rd[7:0]);
        end
        repeat (5) @(posedge clk);

        // WRITE_DATA
        run_op(OP_WRITE_DATA, 17'h0_0010, 8'hA5, rd, fail);
        if (fail) begin
            $display("[FAIL] WRITE_DATA");
            fail_cnt++;
        end else begin
            $display("[PASS] WRITE_DATA addr=0x00010 data=0xA5");
        end
        repeat (WRITE_CYCLE_WAIT) @(posedge clk);

        // READ_DATA
        run_op(OP_READ_DATA, 17'h0_0010, '0, rd, fail);
        if (fail) begin
            $display("[FAIL] READ_DATA");
            fail_cnt++;
        end else if (rd[7:0] !== 8'hA5) begin
            $display("[FAIL] READ_DATA got=0x%02X expected=0xA5", rd[7:0]);
            fail_cnt++;
        end else begin
            $display("[PASS] READ_DATA  rdata=0x%02X", rd[7:0]);
        end

        $display("=== %0d test(s) failed ===", fail_cnt);
        $finish;
    end

    initial begin
        #200_000_000;
        $display("[TB] WATCHDOG");
        $finish;
    end

endmodule
