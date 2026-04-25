// top_tb.sv
`timescale 1ns / 1ps

`include "uvm_macros.svh"
import uvm_pkg::*;

package mem_ctrl_pkg;
    typedef enum logic [2:0] {
        OP_READ_ID     = 3'b000,
        OP_READ_STATUS = 3'b001,
        OP_READ_DATA   = 3'b010,
        OP_WRITE_DATA  = 3'b011,
        OP_SW_RESET    = 3'b100
    } op_codes_e;

    int WRITE_CYCLE_WAIT = 260_000;
    int TIMEOUT = 500_000;
endpackage

package mem_ctrl_test_sequence_pkg;
    logic [23:0] DEVICE_ID = 24'h00D0D0;
    logic [16:0] RW_ADDRESS = $urandom();
    logic [7:0] RW_DATA = 8'hA5;
endpackage

module top_tb (
    input logic           clk,
          simple_if.tb_mp sif
);
    task automatic wait_completion(output logic timed_out);
        timed_out = 1'b0;
        for (int i = 0; i < mem_ctrl_pkg::TIMEOUT; i++) begin
            @(posedge clk);
            if (sif.done || sif.error) return;
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
        sif.rst_n <= 1'b0;
        sif.op    <= '0;
        sif.addr  <= '0;
        sif.wdata <= '0;
        sif.start <= 1'b0;
        fail_cnt = 0;
        repeat (10) @(posedge clk);
        sif.rst_n <= 1'b1;
        repeat (15) @(posedge clk);

        `uvm_info("TB", "=== Simulation start ===", UVM_NONE)
        `uvm_info("TB", "Test verbosity", UVM_MEDIUM)

        // SW_RESET
        run_op(mem_ctrl_pkg::OP_SW_RESET, '0, '0, rd, fail);
        if (fail) begin
            `uvm_error("TB", "[FAIL] SW_RESET")
            fail_cnt++;
        end else begin
            `uvm_info("TB", "[PASS] SW_RESET", UVM_LOW)
        end
        repeat (15) @(posedge clk);

        // READ_ID
        run_op(mem_ctrl_pkg::OP_READ_ID, '0, '0, rd, fail);
        if (fail) begin
            `uvm_error("TB", "[FAIL] READ_ID")
            fail_cnt++;
        end else if (rd !== mem_ctrl_test_sequence_pkg::DEVICE_ID) begin
            `uvm_error("TB", $sformatf("[FAIL] READ_ID got=0x%06X expected=0x%06X", rd,
                                       mem_ctrl_test_sequence_pkg::DEVICE_ID))
            fail_cnt++;
        end else begin
            `uvm_info("TB", $sformatf("[PASS] READ_ID  ManID=0x%06X", rd), UVM_LOW)
        end
        repeat (15) @(posedge clk);

        // READ_STATUS
        run_op(mem_ctrl_pkg::OP_READ_STATUS, '0, '0, rd, fail);
        if (fail) begin
            `uvm_error("TB", "[FAIL] READ_STATUS")
            fail_cnt++;
        end else begin
            `uvm_info("TB", $sformatf("[PASS] READ_STATUS  rdata=0x%02X", rd[7:0]), UVM_LOW)
        end
        repeat (15) @(posedge clk);

        // WRITE_DATA
        run_op(mem_ctrl_pkg::OP_WRITE_DATA, mem_ctrl_test_sequence_pkg::RW_ADDRESS,
               mem_ctrl_test_sequence_pkg::RW_DATA, rd, fail);
        if (fail) begin
            `uvm_error("TB", "[FAIL] WRITE_DATA")
            fail_cnt++;
        end else begin
            `uvm_info("TB", $sformatf(
                      "[PASS] WRITE_DATA addr=0x%05X  data=0x%02X",
                      mem_ctrl_test_sequence_pkg::RW_ADDRESS,
                      mem_ctrl_test_sequence_pkg::RW_DATA
                      ), UVM_LOW)
        end
        repeat (mem_ctrl_pkg::WRITE_CYCLE_WAIT) @(posedge clk);

        // READ_DATA
        run_op(mem_ctrl_pkg::OP_READ_DATA, mem_ctrl_test_sequence_pkg::RW_ADDRESS,
               mem_ctrl_test_sequence_pkg::RW_DATA, rd, fail);
        if (fail) begin
            `uvm_error("TB", "[FAIL] READ_DATA")
            fail_cnt++;
        end else if (rd[7:0] !== mem_ctrl_test_sequence_pkg::RW_DATA) begin
            `uvm_error("TB", $sformatf("[FAIL] READ_DATA got=0x%02X expected=0x%02X", rd[7:0],
                                       mem_ctrl_test_sequence_pkg::RW_DATA))
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
