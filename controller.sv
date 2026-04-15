// =============================================================================
// controller.sv  -  I2C Master Controller for Microchip 24CSM01 (1Mbit EEPROM)
// =============================================================================
// Supported operations:
//   op=2'b00  READ_ID      - reads first byte of Manufacturer ID
//   op=2'b01  READ_STATUS  - reads Security register byte at address 0x0800
//   op=2'b10  READ_DATA    - random-read one byte from EEPROM at addr[16:0]
//   op=2'b11  WRITE_DATA   - byte write to EEPROM at addr[16:0] with wdata
//
// I2C bus: scl (output), sda (inout, open-drain).
// sda_drive=1 pulls SDA to 0; sda_drive=0 releases (Z → pulled up to 1).
//
// Timing (50 MHz sys-clk, CLK_DIV=62 → SCL ~400kHz):
//
//   KEY FIX FOR tHD_STA (250 ns):
//   The 24CSM01 model checks $hold(negedge SDA, negedge SCL, 250ns).
//   This fires whenever SDA and SCL fall within 250ns of each other.
//   During normal TX, if SDA goes low at the SAME clock edge as SCL falls,
//   the hold time is 0ns → violation. Therefore:
//     Rule: SDA must ONLY change value AFTER SCL has already been low for
//           at least one full system-clock cycle (20ns tsetup margin, 
//           since SCL is driven via non-blocking assign with 1-cycle latency).
//     Implementation: Every bit TX uses THREE sub-states:
//       1. SCL_FALL: SCL goes low, SDA holds previous value
//       2. SDA_SET:  SDA takes new bit value (SCL already low)
//       3. SCL_RISE: SCL goes high, device samples SDA
//     This guarantees SDA only changes while SCL is low.
//
//   KEY FIX FOR ManID sequence:
//   The model requires the addr_hi byte in the ManID dummy write to match
//   CTRL_BYTE_EEPROM pattern (1010_0xx). Use 0xA0.
//   The model ABORTS if addr_lo is sent during ManID dummy write.
//   So ManID sequence: START + 0xF8 + addr_hi(0xA0) + rSTART (no addr_lo).
//
//   KEY FIX FOR READ_STATUS address:
//   The model's SECCFG addr_hi check requires ShiftRegister[2:1]==2'b10,
//   which means addr_hi[3:2]==2'b10, e.g. addr_hi=0x08 (0000_1000).
//   Security register read address = 0x0800.
// =============================================================================

`timescale 1ns/1ps

module controller #(
    parameter int CLK_DIV    = 62,      // SCL half-period in sys-clk cycles
    parameter logic [1:0] CHIP_ADDR = 2'b00
)(
    input  logic        clk,
    input  logic        rst_n,

    // Simple user interface
    input  logic [1:0]  op,
    input  logic [16:0] addr,
    input  logic [7:0]  wdata,
    input  logic        start,
    output logic [7:0]  rdata,
    output logic        done,
    output logic        busy,
    output logic        error,

    // I2C bus
    output logic        scl,
    inout  wire         sda
);

// ---------------------------------------------------------------------------
// Operation codes
// ---------------------------------------------------------------------------
localparam OP_READ_ID     = 2'b00;
localparam OP_READ_STATUS = 2'b01;
localparam OP_READ_DATA   = 2'b10;
localparam OP_WRITE_DATA  = 2'b11;

// ---------------------------------------------------------------------------
// SDA open-drain: pull low when sda_drive=1, release (hi-Z) when 0
// ---------------------------------------------------------------------------
logic sda_drive;
assign sda = sda_drive ? 1'b0 : 1'bz;

// ---------------------------------------------------------------------------
// FSM states
//
// Each state lasts CLK_DIV system-clock cycles (one SCL half-period).
//
// TX bit uses THREE states to guarantee SDA only changes while SCL is low:
//   TX_FALL  : SCL falls,  SDA holds previous value
//   TX_SET   : SCL stays low,  SDA takes new bit value
//   TX_RISE  : SCL rises,  device samples SDA
//
// ACK/NACK/RX similarly ensure SDA changes only while SCL is low.
// ---------------------------------------------------------------------------
typedef enum logic [5:0] {
    ST_IDLE,

    // START: SDA falls while SCL=1, then SCL falls (with hold)
    ST_S_SDALO,     // SCL=1, drive SDA low  (START event)
    ST_S_HOLD,      // SCL=1, SDA=0, hold tHD_STA (CLK_DIV cycles = 1240ns >> 250ns)
    ST_S_SCLFALL,   // SCL falls, SDA=0

    // REPEATED START
    ST_RS_SDAHI,    // SCL=0, release SDA
    ST_RS_SCLRISE,  // SCL rises, SDA=1
    ST_RS_SDALO,    // SCL=1, drive SDA low  (rSTART event)
    ST_RS_HOLD,     // SCL=1, SDA=0, hold tHD_STA
    ST_RS_SCLFALL,  // SCL falls, SDA=0

    // STOP: SDA=0, SCL rises, then SDA rises
    ST_P_SCLRISE,   // SCL=0 SDA=0 → SCL rises
    ST_P_SDAHI,     // SCL=1 SDA=0 → SDA rises (STOP event)
    ST_P_HOLD,      // SCL=1 SDA=1, hold before idle

    // TX bit: three phases
    ST_TX_FALL,     // SCL falls, SDA holds previous value
    ST_TX_SET,      // SCL=0, SDA=new bit value
    ST_TX_RISE,     // SCL rises, device samples SDA

    // Receive ACK (device drives SDA)
    ST_AK_SDAREL,   // SCL=0, release SDA
    ST_AK_RISE,     // SCL rises
    ST_AK_SAMPLE,   // SCL=1, sample SDA (0=ACK, 1=NACK)

    // RX bit: device drives SDA
    ST_RX_REL,      // SCL=0, release SDA
    ST_RX_RISE,     // SCL rises
    ST_RX_SAMPLE,   // SCL=1, sample SDA

    // Send ACK to device (pull SDA low for one SCL pulse)
    ST_ACKTX_LO,    // SCL=0, SDA=0
    ST_ACKTX_RISE,  // SCL rises
    ST_ACKTX_FALL,  // SCL falls  (SDA will be released in BYTE_DONE)

    // Send NACK to device (release SDA for one SCL pulse)
    ST_NACK_REL,    // SCL=0, release SDA
    ST_NACK_RISE,   // SCL rises
    ST_NACK_FALL,   // SCL falls → then STOP

    // Sequencer dispatch
    ST_BYTE_DONE,

    // Terminal
    ST_FINISH,
    ST_ERROR
} state_t;

state_t state;

// ---------------------------------------------------------------------------
// Half-period counter (CLK_DIV cycles per state)
// ---------------------------------------------------------------------------
logic [$clog2(CLK_DIV+1)-1:0] cnt;
wire  cnt_done = (cnt == CLK_DIV - 1);

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)       cnt <= '0;
    else if (cnt_done) cnt <= '0;
    else               cnt <= cnt + 1;
end

// ---------------------------------------------------------------------------
// Registers
// ---------------------------------------------------------------------------
logic [1:0]  op_lat;
logic [16:0] addr_lat;
logic [7:0]  wdata_lat;
logic [3:0]  bit_idx;
logic [7:0]  tx_byte;
logic [7:0]  rx_shift;
logic [7:0]  rx_latch;
logic [3:0]  seq_step;
logic        scl_r;

assign scl = scl_r;

// ---------------------------------------------------------------------------
// Control byte helpers
// ---------------------------------------------------------------------------
function automatic logic [7:0] f_eeprom_ctrl(input logic page, input logic rw);
    return {4'b1010, page, CHIP_ADDR[1], CHIP_ADDR[0], rw};
endfunction

function automatic logic [7:0] f_seccfg_ctrl(input logic page, input logic rw);
    return {4'b1011, page, CHIP_ADDR[1], CHIP_ADDR[0], rw};
endfunction

// First control byte sent after initial START
function automatic logic [7:0] f_first_ctrl(input logic [1:0] op_in,
                                             input logic [16:0] addr_in);
    case (op_in)
        OP_WRITE_DATA  : return f_eeprom_ctrl(addr_in[16], 1'b0);
        OP_READ_DATA   : return f_eeprom_ctrl(addr_in[16], 1'b0); // dummy write phase
        OP_READ_STATUS : return f_seccfg_ctrl(1'b0,        1'b0); // dummy write phase
        OP_READ_ID     : return 8'hF8;  // ManID dummy-write control byte
        default        : return 8'hFF;
    endcase
endfunction

// ---------------------------------------------------------------------------
// FSM
// ---------------------------------------------------------------------------
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state     <= ST_IDLE;
        scl_r     <= 1'b1;
        sda_drive <= 1'b0;
        bit_idx   <= 4'd7;
        tx_byte   <= '0;
        rx_shift  <= '0;
        rx_latch  <= '0;
        seq_step  <= '0;
        op_lat    <= '0;
        addr_lat  <= '0;
        wdata_lat <= '0;
        rdata     <= '0;
        done      <= 1'b0;
        busy      <= 1'b0;
        error     <= 1'b0;
    end else begin
        done <= 1'b0;

        case (state)

            // ================================================================
            ST_IDLE: begin
                scl_r     <= 1'b1;
                sda_drive <= 1'b0;   // SDA released = high
                busy      <= 1'b0;
                seq_step  <= '0;
                if (start) begin
                    op_lat    <= op;
                    addr_lat  <= addr;
                    wdata_lat <= wdata;
                    busy      <= 1'b1;
                    error     <= 1'b0;
                    // SCL and SDA are already high (idle).
                    // Drive SDA low to create START while SCL stays high.
                    state     <= ST_S_SDALO;
                end
            end

            // ================================================================
            // START condition
            // SDA falls while SCL=1  →  hold tHD_STA  →  SCL falls
            // ================================================================
            ST_S_SDALO: begin
                scl_r     <= 1'b1;
                sda_drive <= 1'b1;   // SDA falls (START)
                if (cnt_done) state <= ST_S_HOLD;
            end

            ST_S_HOLD: begin
                scl_r     <= 1'b1;
                sda_drive <= 1'b1;   // hold SCL=1, SDA=0 for full CLK_DIV cycles
                if (cnt_done) state <= ST_S_SCLFALL;
            end

            ST_S_SCLFALL: begin
                scl_r     <= 1'b0;   // SCL falls; SDA stays low
                sda_drive <= 1'b1;
                if (cnt_done) begin
                    // SCL is now low, safe to load first TX byte
                    tx_byte  <= f_first_ctrl(op_lat, addr_lat);
                    bit_idx  <= 4'd7;
                    seq_step <= '0;
                    state    <= ST_TX_SET; // SDA already low; skip FALL, go straight to SET
                end
            end

            // ================================================================
            // REPEATED START
            // From a state where SCL=0: release SDA → SCL rises → SDA falls →
            // hold tHD_STA → SCL falls
            // ================================================================
            ST_RS_SDAHI: begin
                scl_r     <= 1'b0;
                sda_drive <= 1'b0;   // release SDA (goes high)
                if (cnt_done) state <= ST_RS_SCLRISE;
            end

            ST_RS_SCLRISE: begin
                scl_r     <= 1'b1;   // SCL rises; SDA=1
                sda_drive <= 1'b0;
                if (cnt_done) state <= ST_RS_SDALO;
            end

            ST_RS_SDALO: begin
                scl_r     <= 1'b1;
                sda_drive <= 1'b1;   // SDA falls (rSTART) while SCL=1
                if (cnt_done) state <= ST_RS_HOLD;
            end

            ST_RS_HOLD: begin
                scl_r     <= 1'b1;
                sda_drive <= 1'b1;   // hold SCL=1, SDA=0
                if (cnt_done) state <= ST_RS_SCLFALL;
            end

            ST_RS_SCLFALL: begin
                scl_r     <= 1'b0;
                sda_drive <= 1'b1;
                if (cnt_done) begin
                    bit_idx <= 4'd7;
                    state   <= ST_TX_SET; // tx_byte already loaded by ST_BYTE_DONE
                end
            end

            // ================================================================
            // STOP condition
            // From SCL=0, SDA=0: SCL rises → SDA rises (STOP) → hold → idle
            // ================================================================
            ST_P_SCLRISE: begin
                scl_r     <= 1'b1;   // SCL rises; SDA stays 0
                sda_drive <= 1'b1;
                if (cnt_done) state <= ST_P_SDAHI;
            end

            ST_P_SDAHI: begin
                scl_r     <= 1'b1;
                sda_drive <= 1'b0;   // SDA rises (STOP) while SCL=1
                if (cnt_done) state <= ST_P_HOLD;
            end

            ST_P_HOLD: begin
                scl_r     <= 1'b1;
                sda_drive <= 1'b0;   // hold bus idle (tBUF)
                if (cnt_done) state <= ST_FINISH;
            end

            // ================================================================
            // TX BIT — three phases ensure SDA only changes while SCL is low
            //
            // ST_TX_FALL:  SCL was high → falls now.  SDA is NOT changed here.
            //              This guarantees SCL falls while SDA is stable.
            // ST_TX_SET:   SCL is low.  Now set SDA to the new bit value.
            //              SDA can change freely while SCL is low.
            // ST_TX_RISE:  SCL rises.  SDA is stable.  Device samples SDA.
            //
            // After last bit: go to ACK receive states.
            // ================================================================
            ST_TX_FALL: begin
                scl_r <= 1'b0;
                // sda_drive is NOT updated here — hold its current value.
                // This is the transition from SCL=1 → SCL=0.
                if (cnt_done) state <= ST_TX_SET;
            end

            ST_TX_SET: begin
                scl_r     <= 1'b0;
                sda_drive <= !tx_byte[bit_idx]; // 0-bit: pull SDA low; 1-bit: release
                if (cnt_done) state <= ST_TX_RISE;
            end

            ST_TX_RISE: begin
                scl_r <= 1'b1;   // SCL rises; device samples SDA
                if (cnt_done) begin
                    if (bit_idx == 0)
                        state <= ST_AK_SDAREL;
                    else begin
                        bit_idx <= bit_idx - 1;
                        state   <= ST_TX_FALL;  // next bit: fall SCL first
                    end
                end
            end

            // ================================================================
            // RECEIVE ACK from device
            // Device pulls SDA low for ACK; releases for NACK.
            // ================================================================
            ST_AK_SDAREL: begin
                scl_r     <= 1'b0;
                sda_drive <= 1'b0;   // release SDA — device can pull low for ACK
                if (cnt_done) state <= ST_AK_RISE;
            end

            ST_AK_RISE: begin
                scl_r <= 1'b1;
                if (cnt_done) state <= ST_AK_SAMPLE;
            end

            ST_AK_SAMPLE: begin
                scl_r <= 1'b1;
                if (cnt_done) begin
                    if (sda === 1'b0)     // ACK: device pulled SDA low
                        state <= ST_BYTE_DONE;
                    else
                        state <= ST_ERROR; // NACK or bus error
                end
            end

            // ================================================================
            // RX BIT — device drives SDA, master samples on SCL rising edge
            // ================================================================
            ST_RX_REL: begin
                scl_r     <= 1'b0;
                sda_drive <= 1'b0;   // release SDA for device to drive
                if (cnt_done) state <= ST_RX_RISE;
            end

            ST_RX_RISE: begin
                scl_r <= 1'b1;
                if (cnt_done) state <= ST_RX_SAMPLE;
            end

            ST_RX_SAMPLE: begin
                scl_r <= 1'b1;
                if (cnt_done) begin
                    rx_shift <= {rx_shift[6:0], sda};    // shift in MSB first
                    if (bit_idx == 0) begin
                        rx_latch <= {rx_shift[6:0], sda};
                        state    <= ST_BYTE_DONE;
                    end else begin
                        bit_idx <= bit_idx - 1;
                        state   <= ST_RX_REL;
                    end
                end
            end

            // ================================================================
            // SEND ACK to device (after receiving a non-final byte)
            // Pull SDA low during the ACK clock pulse.
            // SDA must be set AFTER SCL has already fallen (ST_ACKTX_LO is 
            // entered from ST_BYTE_DONE with SCL already low).
            // ================================================================
            ST_ACKTX_LO: begin
                scl_r     <= 1'b0;
                sda_drive <= 1'b1;   // pull SDA low (ACK) while SCL=0
                if (cnt_done) state <= ST_ACKTX_RISE;
            end

            ST_ACKTX_RISE: begin
                scl_r <= 1'b1;       // SCL rises; device sees ACK
                if (cnt_done) state <= ST_ACKTX_FALL;
            end

            ST_ACKTX_FALL: begin
                scl_r <= 1'b0;       // SCL falls; sda_drive stays 1 here (safe, SCL low)
                if (cnt_done) begin
                    sda_drive <= 1'b0;  // release SDA before next RX byte
                    state     <= ST_BYTE_DONE;
                end
            end

            // ================================================================
            // SEND NACK to device (after receiving the last byte)
            // Release SDA (high) during the NACK clock pulse, then STOP.
            // ================================================================
            ST_NACK_REL: begin
                scl_r     <= 1'b0;
                sda_drive <= 1'b0;   // release SDA = NACK
                if (cnt_done) state <= ST_NACK_RISE;
            end

            ST_NACK_RISE: begin
                scl_r <= 1'b1;
                if (cnt_done) state <= ST_NACK_FALL;
            end

            ST_NACK_FALL: begin
                scl_r <= 1'b0;
                if (cnt_done) begin
                    // After NACK, SDA is already released (0), SCL=0 → issue STOP
                    state <= ST_P_SCLRISE;
                end
            end

            // ================================================================
            // BYTE_DONE — sequence dispatch
            //
            // Called after:
            //   ST_AK_SAMPLE  : master sent byte, device ACK'd
            //   ST_RX_SAMPLE  : master received byte (before ACK/NACK)
            //   ST_ACKTX_FALL : master sent ACK, ready for next RX byte
            //
            // At entry: SCL=0 (either from ACK fall or from RX sample path)
            // seq_step is incremented on entry.
            //
            // ----------------------------------------------------------------
            // WRITE DATA (byte write):
            //   s0: eeprom_ctrl(W) ACK'd  → TX addr[15:8]
            //   s1: addr[15:8] ACK'd      → TX addr[7:0]
            //   s2: addr[7:0]  ACK'd      → TX wdata
            //   s3: wdata ACK'd           → STOP
            //
            // READ DATA (random read):
            //   s0: eeprom_ctrl(W) ACK'd  → TX addr[15:8]
            //   s1: addr[15:8] ACK'd      → TX addr[7:0]
            //   s2: addr[7:0]  ACK'd      → rSTART, load ctrl(R)
            //   s3: ctrl(R) ACK'd         → RX byte
            //   s4: byte received         → NACK → STOP
            //
            // READ STATUS (Security register random read, addr=0x0800):
            //   addr_hi must be 0x08 (bits[3:2]=10 required by model).
            //   addr_lo = 0x00. addr_hi byte pattern also satisfies AddressValid.
            //   s0: seccfg_ctrl(W) ACK'd  → TX addr_hi=0x08
            //   s1: addr_hi ACK'd         → TX addr_lo=0x00
            //   s2: addr_lo ACK'd         → rSTART, load ctrl(R)
            //   s3: ctrl(R) ACK'd         → RX byte
            //   s4: byte received         → NACK → STOP
            //
            // READ ID (ManID, 3 bytes):
            //   Per model: dummy write is START+0xF8+addr_hi(must match EEPROM pattern).
            //   Model ABORTS if addr_lo is received during ManID dummy write.
            //   So: START + 0xF8 + 0xA0(addr_hi) + rSTART (no addr_lo).
            //   After rSTART: 0xFE + RX byte0(ACK) + RX byte1(ACK) + RX byte2(NACK).
            //   s0: 0xF8 ACK'd            → TX addr_hi=0xA0
            //   s1: addr_hi ACK'd         → rSTART, load 0xFE (NO addr_lo!)
            //   s2: 0xFE ACK'd            → RX byte0
            //   s3: byte0 received        → store rdata, ACK
            //   s4: ACK sent              → RX byte1
            //   s5: byte1 received        → ACK
            //   s6: ACK sent              → RX byte2
            //   s7: byte2 received        → NACK → STOP
            // ================================================================
            ST_BYTE_DONE: begin
                seq_step <= seq_step + 1;

                case (op_lat)

                    OP_WRITE_DATA: case (seq_step)
                        4'd0: begin tx_byte<=addr_lat[15:8]; bit_idx<=4'd7; state<=ST_TX_FALL; end
                        4'd1: begin tx_byte<=addr_lat[7:0];  bit_idx<=4'd7; state<=ST_TX_FALL; end
                        4'd2: begin tx_byte<=wdata_lat;      bit_idx<=4'd7; state<=ST_TX_FALL; end
                        4'd3: begin                                          state<=ST_P_SCLRISE; end
                        default: state<=ST_ERROR;
                    endcase

                    OP_READ_DATA: case (seq_step)
                        4'd0: begin tx_byte<=addr_lat[15:8];                    bit_idx<=4'd7; state<=ST_TX_FALL; end
                        4'd1: begin tx_byte<=addr_lat[7:0];                     bit_idx<=4'd7; state<=ST_TX_FALL; end
                        4'd2: begin tx_byte<=f_eeprom_ctrl(addr_lat[16],1'b1);  bit_idx<=4'd7; state<=ST_RS_SDAHI; end
                        4'd3: begin rx_shift<='0; bit_idx<=4'd7;                               state<=ST_RX_REL; end
                        4'd4: begin rdata<=rx_latch;                                           state<=ST_NACK_REL; end
                        default: state<=ST_ERROR;
                    endcase

                    OP_READ_STATUS: case (seq_step)
                        // addr_hi=0x08: ShiftRegister[2:1]=addr_hi[3:2]=2'b10 → model accepts
                        // AddressPointer[11:10]=addr_hi[3:2]=2'b10 → AddressValid=1
                        // casez(AP[15:8])=casez(0x08): bit[7]=0,bits[3:2]=10 → SecData mux active
                        4'd0: begin tx_byte<=8'h08;                           bit_idx<=4'd7; state<=ST_TX_FALL; end
                        4'd1: begin tx_byte<=8'h00;                           bit_idx<=4'd7; state<=ST_TX_FALL; end
                        4'd2: begin tx_byte<=f_seccfg_ctrl(1'b0,1'b1);        bit_idx<=4'd7; state<=ST_RS_SDAHI; end
                        4'd3: begin rx_shift<='0; bit_idx<=4'd7;                             state<=ST_RX_REL; end
                        4'd4: begin rdata<=rx_latch;                                         state<=ST_NACK_REL; end
                        default: state<=ST_ERROR;
                    endcase

                    OP_READ_ID: case (seq_step)
                        // addr_hi=0xA0: ShiftRegister[6:0]=0xA0[7:1]=7'b1010_000 
                        //              matches CTRL_BYTE_EEPROM=1010_00? ✓
                        // NO addr_lo: model aborts if addr_lo received for ManID
                        4'd0: begin tx_byte<=8'hA0; bit_idx<=4'd7;  state<=ST_TX_FALL; end  // addr_hi for ManID
                        4'd1: begin tx_byte<=8'hFE; bit_idx<=4'd7;  state<=ST_RS_SDAHI; end // rSTART, ctrl read (no addr_lo!)
                        4'd2: begin rx_shift<='0; bit_idx<=4'd7;    state<=ST_RX_REL; end   // RX byte0
                        4'd3: begin rdata<=rx_latch;                 state<=ST_ACKTX_LO; end // store byte0, ACK
                        4'd4: begin rx_shift<='0; bit_idx<=4'd7;    state<=ST_RX_REL; end   // RX byte1
                        4'd5: begin                                  state<=ST_ACKTX_LO; end // ACK byte1
                        4'd6: begin rx_shift<='0; bit_idx<=4'd7;    state<=ST_RX_REL; end   // RX byte2
                        4'd7: begin                                  state<=ST_NACK_REL; end // NACK → STOP
                        default: state<=ST_ERROR;
                    endcase

                    default: state <= ST_ERROR;
                endcase
            end

            // ================================================================
            ST_FINISH: begin
                done  <= 1'b1;
                busy  <= 1'b0;
                state <= ST_IDLE;
            end

            ST_ERROR: begin
                error     <= 1'b1;
                busy      <= 1'b0;
                sda_drive <= 1'b1; // pull SDA low first (SCL already low from ACK_SAMPLE)
                state     <= ST_P_SCLRISE; // then issue STOP
            end

            default: state <= ST_IDLE;

        endcase
    end
end

endmodule
