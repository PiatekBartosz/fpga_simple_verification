// =============================================================================
// tb_24csm01_manid.sv
//
// Minimal SystemVerilog testbench: reads Manufacturer ID from Microchip
// 24CSM01 I2C EEPROM.
//
// Per datasheet Section 11.0, the Manufacturer ID read sequence is:
//
//   1. START
//   2. Host code F8h  (1111_1000) -> all ManID-capable devices ACK
//   3. EEPROM device address byte (1010_A2_A1_x_0) -> device ACKs
//   4. Repeated START
//   5. Host code F9h  (1111_1001) -> identified device ACKs
//   6. Read 3 bytes: ACK after byte 0 and 1, NACK after byte 2
//   7. STOP
//
// Expected 24-bit result: 0x00D0D0
//
// Open-drain SDA modelling
// ------------------------
// The device model drives SDA via an internal  bufif1 (SDA, 1'b0, enable).
// The host must also drive SDA open-drain.  Both meet on a single 'wire' that
// has a weak pull-up (pull1).  Any driver asserting a strong 0 wins.
// The host drives through a separate tri-state net (sda_host) which is also
// connected to SDA; when the host releases (sda_host = 1'bz) the pull-up or
// the device determines the line value.
// =============================================================================

`timescale 1ns / 1ps

module tb_24csm01_manid;

    // -------------------------------------------------------------------------
    // Timing – 400 kHz I2C (all values in ns, satisfy AC spec with margin)
    // -------------------------------------------------------------------------
    localparam real T_HALF   = 1250.0;  // SCL half-period  (400 kHz)
    localparam real T_BUF    =  600.0;  // bus-free after STOP   (spec >500 ns)
    localparam real T_SU_STA =  300.0;  // START setup           (spec >250 ns)
    localparam real T_HD_STA =  300.0;  // START hold            (spec >250 ns)
    localparam real T_SU_STO =  300.0;  // STOP  setup           (spec >250 ns)
    localparam real T_DATA   =   60.0;  // SDA settle before SCL rises (spec >50 ns)

    // -------------------------------------------------------------------------
    // Open-drain bus
    //
    // SCL: host only drives SCL in this test (no clock stretching by device)
    //      Modelled as a simple logic signal driven directly from the testbench.
    //
    // SDA: true open-drain wired-AND
    //      - pull1 provides the passive pull-up (weak '1')
    //      - host drives via sda_host (tri-state: 1'bz = release, 1'b0 = pull low)
    //      - device drives via its internal bufif1 connected to SDA directly
    // -------------------------------------------------------------------------
    logic scl;          // host drives SCL directly
    logic sda_host;     // host's open-drain drive: 1'bz or 1'b0

    wire  SDA;
    wire  SCL = scl;

    assign (pull1, highz0) SDA = 1'b1;  // passive pull-up
    assign SDA = sda_host;              // host open-drain (1'bz or 1'b0)
    // device's bufif1 is connected directly to SDA inside M24CSM01

    // -------------------------------------------------------------------------
    // DUT  (A1=0, A2=0, WP=0, RESET=0)
    // -------------------------------------------------------------------------
    M24CSM01 dut (
        .A1   (1'b0),
        .A2   (1'b0),
        .WP   (1'b0),
        .SDA  (SDA),
        .SCL  (SCL),
        .RESET(1'b0)
    );

    // -------------------------------------------------------------------------
    // Captured data
    // -------------------------------------------------------------------------
    logic [7:0]  rx_byte [0:2];
    logic [23:0] man_id;

    // =========================================================================
    // I2C primitives  (all automatic tasks – local vars are stack-allocated)
    // =========================================================================

    // START condition: SDA falls while SCL high
    task automatic i2c_start();
        // precondition: SCL=1, SDA released (high)
        #(T_DATA);
        sda_host = 1'b0;       // pull SDA low  → START
        #(T_HD_STA);
        scl      = 1'b0;       // pull SCL low
        #(T_HALF - T_HD_STA);
    endtask

    // Repeated START: release SDA, raise SCL, then pull SDA low again
    task automatic i2c_rep_start();
        // precondition: SCL=0
        sda_host = 1'bz;       // release SDA
        #(T_HALF);
        scl      = 1'b1;       // raise SCL
        #(T_SU_STA);
        sda_host = 1'b0;       // pull SDA low  → Repeated START
        #(T_HD_STA);
        scl      = 1'b0;       // pull SCL low
        #(T_HALF - T_HD_STA);
    endtask

    // STOP condition: SDA rises while SCL high
    task automatic i2c_stop();
        // precondition: SCL=0
        sda_host = 1'b0;       // ensure SDA low
        #(T_HALF);
        scl      = 1'b1;       // raise SCL
        #(T_SU_STO);
        sda_host = 1'bz;       // release SDA  → STOP
        #(T_BUF);
    endtask

    // Write one bit: set SDA, clock SCL high then low
    task automatic i2c_write_bit(input logic b);
        // precondition: SCL=0
        #(T_DATA);
        sda_host = b ? 1'bz : 1'b0;
        #(T_HALF - T_DATA);
        scl = 1'b1;
        #(T_HALF);
        scl = 1'b0;
    endtask

    // Write 8 bits MSB-first then clock the ACK bit.
    // ack=0 means the device pulled SDA low (ACK), ack=1 means NACK/high-Z.
    task automatic i2c_write_byte(input logic [7:0] data, output logic ack);
        for (int i = 7; i >= 0; i--)
            i2c_write_bit(data[i]);
        // ACK clock: host releases SDA, device may pull low
        #(T_DATA);
        sda_host = 1'bz;       // release SDA
        #(T_HALF - T_DATA);
        scl = 1'b1;            // SCL high
        #(T_HALF / 2);
        ack = SDA;             // sample: 0=ACK, 1=NACK
        #(T_HALF / 2);
        scl = 1'b0;
        #(T_DATA);
        // keep SDA released until caller sets it
    endtask

    // Read 8 bits MSB-first; host sends ACK (send_nack=0) or NACK (send_nack=1)
    task automatic i2c_read_byte(input logic send_nack, output logic [7:0] data);
        sda_host = 1'bz;       // release SDA so device can drive
        for (int i = 7; i >= 0; i--) begin
            #(T_HALF);
            scl = 1'b1;        // SCL high
            #(T_HALF / 2);
            data[i] = SDA;     // sample
            #(T_HALF / 2);
            scl = 1'b0;
        end
        // ACK/NACK from host
        #(T_DATA);
        sda_host = send_nack ? 1'bz : 1'b0;
        #(T_HALF - T_DATA);
        scl = 1'b1;
        #(T_HALF);
        scl = 1'b0;
        #(T_DATA);
        sda_host = 1'bz;       // release after ACK bit
    endtask

    // =========================================================================
    // Main test
    // =========================================================================
    initial begin
        logic ack;

        // Bus idle
        scl      = 1'b1;
        sda_host = 1'bz;
        #(T_BUF * 2);

        $display("=== 24CSM01 Manufacturer ID Read ===");

        // ------------------------------------------------------------------
        // Phase 1: START + host code F8h (broadcast, all ManID devices ACK)
        // ------------------------------------------------------------------
        i2c_start();
        i2c_write_byte(8'hF8, ack);
        if (ack !== 1'b0)
            $fatal(1, "FAIL: No ACK for host code F8h (got %0b)", ack);
        $display("[1] Host code F8h ACK'd");

        // ------------------------------------------------------------------
        // Phase 2: EEPROM device address byte 0xA0
        //   1010_A2_A1_A16_R/W = 1010_0000 = 0xA0  (A2=A1=0, R/W=0)
        //   The model treats this as the "dummy write" that identifies
        //   which device will respond to the subsequent F9h.
        // ------------------------------------------------------------------
        i2c_write_byte(8'hA0, ack);
        if (ack !== 1'b0)
            $fatal(1, "FAIL: No ACK for device address 0xA0 (got %0b)", ack);
        $display("[2] Device address 0xA0 ACK'd");

        // ------------------------------------------------------------------
        // Phase 3: Repeated START + host code F9h (targeted device ACKs)
        // ------------------------------------------------------------------
        i2c_rep_start();
        i2c_write_byte(8'hF9, ack);
        if (ack !== 1'b0)
            $fatal(1, "FAIL: No ACK for host code F9h (got %0b)", ack);
        $display("[3] Host code F9h ACK'd");

        // ------------------------------------------------------------------
        // Phase 4: Read 3 bytes of Manufacturer ID
        //   ACK bytes 0 and 1, NACK byte 2 to end the transfer
        // ------------------------------------------------------------------
        i2c_read_byte(1'b0, rx_byte[0]);
        i2c_read_byte(1'b0, rx_byte[1]);
        i2c_read_byte(1'b1, rx_byte[2]);

        // ------------------------------------------------------------------
        // Phase 5: STOP
        // ------------------------------------------------------------------
        i2c_stop();

        // ------------------------------------------------------------------
        // Check
        // ------------------------------------------------------------------
        man_id = {rx_byte[0], rx_byte[1], rx_byte[2]};

        $display("[4] ManID byte[0] = 0x%02X", rx_byte[0]);
        $display("[4] ManID byte[1] = 0x%02X", rx_byte[1]);
        $display("[4] ManID byte[2] = 0x%02X", rx_byte[2]);
        $display("[5] Manufacturer ID = 0x%06X", man_id);

        if (man_id === 24'h00D0D0)
            $display("PASS: Manufacturer ID matches expected 0x00D0D0");
        else
            $fatal(1, "FAIL: Expected 0x00D0D0, got 0x%06X", man_id);

        $finish;
    end

    // =========================================================================
    // Watchdog
    // =========================================================================
    initial begin
        #5_000_000;
        $fatal(1, "TIMEOUT: simulation exceeded 5 ms");
    end

    // =========================================================================
    // Waveform dump
    // =========================================================================
    initial begin
        $dumpfile("tb_24csm01_manid.vcd");
        $dumpvars(0, tb_24csm01_manid);
    end

endmodule
