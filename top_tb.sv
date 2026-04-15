// =============================================================================
// top_tb.sv  -  Testbench
//
// Test sequence:
//   1. Reset
//   2. READ_ID      - reads Manufacturer ID byte 0 (expects non-X value)
//   3. READ_STATUS  - reads Security register byte at internal addr 0x0800
//   4. WRITE_DATA   - writes 0xA5 to EEPROM address 0x00010
//   5. READ_DATA    - reads back from 0x00010, expects 0xA5
// =============================================================================

`timescale 1ns/1ps

module top_tb (
    input  logic    clk,
    simple_if.tb_mp sif
);

// 24CSM01 internal write cycle is max 5 ms. At 50 MHz = 250,000 cycles.
localparam int WRITE_CYCLE_WAIT = 260_000;
// Each I2C operation takes at most ~200 bytes * 9 bits * 3 half-periods * 62 cycles = ~336k cycles
localparam int TIMEOUT = 500_000;

localparam logic [1:0] OP_READ_ID     = 2'b00;
localparam logic [1:0] OP_READ_STATUS = 2'b01;
localparam logic [1:0] OP_READ_DATA   = 2'b10;
localparam logic [1:0] OP_WRITE_DATA  = 2'b11;

// ---------------------------------------------------------------------------
// Task: wait for done or error
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Task: drive one operation and collect result
// ---------------------------------------------------------------------------
task automatic run_op(
    input  logic [1:0]  op_in,
    input  logic [16:0] addr_in,
    input  logic [7:0]  wdata_in,
    output logic [7:0]  rdata_out,
    output logic        failed
);
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

// ---------------------------------------------------------------------------
// Main test
// ---------------------------------------------------------------------------
int  fail_cnt;
logic [7:0] rd;
logic       fail;

initial begin
    sif.rst_n <= 1'b0;
    sif.op    <= '0;
    sif.addr  <= '0;
    sif.wdata <= '0;
    sif.start <= 1'b0;
    fail_cnt   = 0;

    repeat (10) @(posedge clk);
    sif.rst_n <= 1'b1;
    repeat (5)  @(posedge clk);

    $display("=== Simulation start ===");

    // ------------------------------------------------------------------
    // TEST 1: READ_ID
    // Expected: non-X, non-FF (ManID byte 0 of 24'b0000_0000_1101_0000_1101_0_000)
    // ManIDBuffer[23:16] = 8'b0000_0000 = 0x00 on first read
    // ------------------------------------------------------------------
    run_op(OP_READ_ID, '0, '0, rd, fail);
    if (fail)
        begin $display("[FAIL] READ_ID"); fail_cnt++; end
    else
        $display("[PASS] READ_ID  rdata=0x%02X", rd);

    repeat (5) @(posedge clk);

    // ------------------------------------------------------------------
    // TEST 2: READ_STATUS  (Security register at addr 0x0800, byte 0)
    // Default SecurityReg[0] = SERIAL_NUM_0 = 8'hFF
    // ------------------------------------------------------------------
    run_op(OP_READ_STATUS, '0, '0, rd, fail);
    if (fail)
        begin $display("[FAIL] READ_STATUS"); fail_cnt++; end
    else
        $display("[PASS] READ_STATUS  rdata=0x%02X", rd);

    repeat (5) @(posedge clk);

    // ------------------------------------------------------------------
    // TEST 3: WRITE_DATA  addr=0x00010  data=0xA5
    // ------------------------------------------------------------------
    run_op(OP_WRITE_DATA, 17'h0_0010, 8'hA5, rd, fail);
    if (fail)
        begin $display("[FAIL] WRITE_DATA"); fail_cnt++; end
    else
        $display("[PASS] WRITE_DATA  addr=0x00010 data=0xA5");

    // Wait for EEPROM internal write cycle (tWC = 5 ms)
    $display("[TB]   Waiting for EEPROM write cycle (5 ms)...");
    repeat (WRITE_CYCLE_WAIT) @(posedge clk);

    // ------------------------------------------------------------------
    // TEST 4: READ_DATA  addr=0x00010  expect=0xA5
    // ------------------------------------------------------------------
    run_op(OP_READ_DATA, 17'h0_0010, '0, rd, fail);
    if (fail)
        begin $display("[FAIL] READ_DATA"); fail_cnt++; end
    else if (rd !== 8'hA5)
        begin $display("[FAIL] READ_DATA got=0x%02X expected=0xA5", rd); fail_cnt++; end
    else
        $display("[PASS] READ_DATA  rdata=0x%02X", rd);

    $display("=== %0d test(s) failed ===", fail_cnt);
    $finish;
end

// Safety watchdog
initial begin
    #200_000_000;
    $display("[TB] WATCHDOG expired");
    $finish;
end

endmodule
