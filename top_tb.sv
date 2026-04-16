// top_tb.sv
`timescale 1ns / 1ps

module top_tb (
    input logic           clk,
          simple_if.tb_mp sif
);

    localparam int WRITE_CYCLE_WAIT = 260_000;
    localparam int TIMEOUT = 500_000;

    localparam logic [1:0] OP_READ_ID = 2'b00;
    localparam logic [1:0] OP_READ_STATUS = 2'b01;
    localparam logic [1:0] OP_READ_DATA = 2'b10;
    localparam logic [1:0] OP_WRITE_DATA = 2'b11;

    task automatic wait_completion(output logic timed_out);
        int i;
        timed_out = 1'b0;
        for (i = 0; i < TIMEOUT; i++) begin
            @(posedge clk);
            if (sif.done || sif.error) return;
        end
        timed_out = 1'b1;
        $display("[TB] TIMEOUT at time %0t", $time);
    endtask

    task automatic do_sw_reset();
        logic timed_out;
        $display("[TB] Issuing I2C software reset...");
        @(posedge clk);
        sif.sw_reset <= 1'b1;
        @(posedge clk);
        sif.sw_reset <= 1'b0;
        wait_completion(timed_out);
        if (timed_out) $display("[FAIL] SW_RESET timed out");
        else $display("[PASS] SW_RESET complete");
    endtask

    task automatic run_op(input logic [1:0] op_in, input logic [16:0] addr_in,
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
        sif.rst_n    <= 1'b0;
        sif.op       <= '0;
        sif.addr     <= '0;
        sif.wdata    <= '0;
        sif.start    <= 1'b0;
        sif.sw_reset <= 1'b0;
        fail_cnt = 0;
        repeat (10) @(posedge clk);
        sif.rst_n <= 1'b1;
        repeat (5) @(posedge clk);

        $display("=== Simulation start ===");

        do_sw_reset();
        repeat (5) @(posedge clk);

        run_op(OP_READ_ID, '0, '0, rd, fail);
        if (fail) begin
            $display("[FAIL] READ_ID");
            fail_cnt++;
        end else if (rd[23:0] !== 24'h00D0D0) begin
            $display("[FAIL] READ_ID  got=0x%06X expected=0x00D0D0", rd[23:0]);
            fail_cnt++;
        end else $display("[PASS] READ_ID  ManID=0x%06X", rd[23:0]);
        repeat (5) @(posedge clk);

        run_op(OP_READ_STATUS, '0, '0, rd, fail);
        if (fail) begin
            $display("[FAIL] READ_STATUS");
            fail_cnt++;
        end else $display("[PASS] READ_STATUS  rdata=0x%02X", rd[7:0]);
        repeat (5) @(posedge clk);

        run_op(OP_WRITE_DATA, 17'h0_0010, 8'hA5, rd, fail);
        if (fail) begin
            $display("[FAIL] WRITE_DATA");
            fail_cnt++;
        end else $display("[PASS] WRITE_DATA addr=0x00010 data=0xA5");
        $display("[TB] Waiting for EEPROM write cycle (5 ms)...");
        repeat (WRITE_CYCLE_WAIT) @(posedge clk);

        run_op(OP_READ_DATA, 17'h0_0010, '0, rd, fail);
        if (fail) begin
            $display("[FAIL] READ_DATA");
            fail_cnt++;
        end else if (rd[7:0] !== 8'hA5) begin
            $display("[FAIL] READ_DATA got=0x%02X expected=0xA5", rd[7:0]);
            fail_cnt++;
        end else $display("[PASS] READ_DATA  rdata=0x%02X", rd[7:0]);

        $display("=== %0d test(s) failed ===", fail_cnt);
        $finish;
    end

    initial begin
        #200_000_000;
        $display("[TB] WATCHDOG");
        $finish;
    end

endmodule
