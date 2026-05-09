// top_tb.sv
`timescale 1ns / 1ps

`include "uvm_macros.svh"
import uvm_pkg::*;

module top_tb (
    input logic           clk,
          simple_if.tb_mp sif
);
    import mem_ctrl_tb_pkg::*;

    logic [16:0] rw_addr;
    logic [7:0]  rw_data;

    task automatic wait_completion(output logic timed_out);
        timed_out = 1'b0;
        for (int i = 0; i < TIMEOUT; i++) begin
            @(posedge clk);
            if (sif.done || sif.error) begin
                return;
            end
        end
        timed_out = 1'b1;
        `uvm_fatal("TB", $sformatf("TIMEOUT at %0t", $time))
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
        rw_addr  = $urandom();
        rw_data  = 8'hA5;
        fail_cnt = 0;

        sif.rst_n <= 1'b0;
        sif.op    <= '0;
        sif.addr  <= '0;
        sif.wdata <= '0;
        sif.start <= 1'b0;
        repeat (10) @(posedge clk);
        sif.rst_n <= 1'b1;
        repeat (15) @(posedge clk);

        `uvm_info("TB", "=== Simulation start ===", UVM_NONE)
        `uvm_info("TB", "Test verbosity", UVM_MEDIUM)

        // SW_RESET
        run_op(OP_SW_RESET, '0, '0, rd, fail);
        if (fail) begin
            `uvm_error("TB", "[FAIL] SW_RESET")
            fail_cnt++;
        end else begin
            `uvm_info("TB", "[PASS] SW_RESET", UVM_LOW)
        end
        repeat (15) @(posedge clk);

        // READ_ID
        run_op(OP_READ_ID, '0, '0, rd, fail);
        if (fail) begin
            `uvm_error("TB", "[FAIL] READ_ID")
            fail_cnt++;
        end else if (rd !== DEVICE_ID) begin
            `uvm_error("TB", $sformatf("[FAIL] READ_ID got=0x%06X expected=0x%06X", rd, DEVICE_ID))
            fail_cnt++;
        end else begin
            `uvm_info("TB", $sformatf("[PASS] READ_ID  ManID=0x%06X", rd), UVM_LOW)
        end
        repeat (15) @(posedge clk);

        // READ_STATUS
        run_op(OP_READ_STATUS, '0, '0, rd, fail);
        if (fail) begin
            `uvm_error("TB", "[FAIL] READ_STATUS")
            fail_cnt++;
        end else begin
            `uvm_info("TB", $sformatf("[PASS] READ_STATUS  rdata=0x%02X", rd[7:0]), UVM_LOW)
        end
        repeat (15) @(posedge clk);

        // WRITE_DATA
        run_op(OP_WRITE_DATA, rw_addr, rw_data, rd, fail);
        if (fail) begin
            `uvm_error("TB", "[FAIL] WRITE_DATA")
            fail_cnt++;
        end else begin
            `uvm_info("TB", $sformatf("[PASS] WRITE_DATA addr=0x%05X  data=0x%02X", rw_addr,
                                      rw_data), UVM_LOW)
        end
        repeat (WRITE_CYCLE_WAIT) @(posedge clk);

        // READ_DATA
        run_op(OP_READ_DATA, rw_addr, rw_data, rd, fail);
        if (fail) begin
            `uvm_error("TB", "[FAIL] READ_DATA")
            fail_cnt++;
        end else if (rd[7:0] !== rw_data) begin
            `uvm_error("TB", $sformatf("[FAIL] READ_DATA got=0x%02X expected=0x%02X", rd[7:0],
                                       rw_data))
            fail_cnt++;
        end else begin
            `uvm_info("TB", $sformatf("[PASS] READ_DATA  rdata=0x%02X", rd[7:0]), UVM_LOW)
        end

        `uvm_info("TB", $sformatf("=== %0d test(s) failed ===", fail_cnt), UVM_NONE)
        $finish;
    end

    initial begin
        #200_000_000;
        `uvm_fatal("TB", "WATCHDOG timeout")
        $finish;
    end

endmodule
