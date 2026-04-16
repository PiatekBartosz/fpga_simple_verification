// =============================================================================
// controller.sv  -  I2C Master Controller for Microchip 24CSM01 (1Mbit EEPROM)
// =============================================================================
// Design rules (verified against 24CSM01 Verilog model and datasheet):
//
//  1. SCL and SDA never change in the same clock cycle.
//     Every FSM state changes at most ONE of {scl_r, sda_drive}.
//
//  2. The half-period counter (cnt) is reset explicitly on every state
//     transition by writing cnt<=0 alongside the state change.
//     This is the only reliable method in Xsim — wire-based state_changed
//     detection suffers from delta-cycle ordering issues.
//
//  3. ManID sequence (from datasheet Fig 11-1 + model source):
//     START -> F8h(WR) -> 0xA0(device addr as addr_hi) -> rSTART ->
//     F9h(RD) -> RX byte0(ACK) -> RX byte1(ACK) -> RX byte2(NACK) -> STOP
//     Note: NO addr_lo for ManID (model aborts if addr_lo received).
//
//  4. Security register address (from datasheet Table 3-3 + model line 455):
//     addr_hi must have bits[3:2]=10 -> use 0x08.
//     First serial number byte at address 0x0800.
//
//  5. All device protections confirmed off: WP=0, EWPM=0, LOCK=0, SWP=0.
// =============================================================================

`timescale 1ns/1ps

module controller #(
    parameter int CLK_DIV           = 62,    // SCL half-period in sys-clk cycles
    parameter logic [1:0] CHIP_ADDR = 2'b00  // must match A2,A1 pins on device
)(
    input  logic        clk,
    input  logic        rst_n,

    input  logic [1:0]  op,
    input  logic [16:0] addr,
    input  logic [7:0]  wdata,
    input  logic        start,
    output logic [7:0]  rdata,
    output logic        done,
    output logic        busy,
    output logic        error,

    output logic        scl,
    inout  wire         sda
);

localparam OP_READ_ID     = 2'b00;
localparam OP_READ_STATUS = 2'b01;
localparam OP_READ_DATA   = 2'b10;
localparam OP_WRITE_DATA  = 2'b11;

// Open-drain SDA
logic sda_drive;
assign sda = sda_drive ? 1'b0 : 1'bz;

// ---------------------------------------------------------------------------
// States — each state changes at most one of {scl_r, sda_drive}
// ---------------------------------------------------------------------------
typedef enum logic [5:0] {
    ST_IDLE,
    ST_S_SDA_LO,    // SDA->0  (SCL=1) : START event
    ST_S_HOLD,      // hold tHD_STA
    ST_S_SCL_LO,    // SCL->0  (SDA=0)
    ST_RS_SDA_HI,   // SDA->1  (SCL=0) : begin repeated START
    ST_RS_SCL_HI,   // SCL->1  (SDA=1)
    ST_RS_SDA_LO,   // SDA->0  (SCL=1) : rSTART event
    ST_RS_HOLD,     // hold tHD_STA
    ST_RS_SCL_LO,   // SCL->0  (SDA=0)
    ST_P_SCL_HI,    // SCL->1  (SDA=0) : begin STOP
    ST_P_SDA_HI,    // SDA->1  (SCL=1) : STOP event
    ST_P_HOLD,      // hold tBUF
    ST_TX_SDA,      // SDA->bit (SCL=0)
    ST_TX_RISE,     // SCL->1
    ST_TX_FALL,     // SCL->0
    ST_AK_REL,      // SDA->1  (SCL=0) : release for device ACK
    ST_AK_RISE,     // SCL->1  : sample SDA at end
    ST_AK_FALL,     // SCL->0
    ST_RX_REL,      // SDA->1  (SCL=0)
    ST_RX_RISE,     // SCL->1  : sample SDA at end
    ST_RX_FALL,     // SCL->0
    ST_ATXK_SDA,    // SDA->0  (SCL=0) : master sends ACK
    ST_ATXK_RISE,   // SCL->1
    ST_ATXK_FALL,   // SCL->0
    ST_ATXK_REL,    // SDA->1  (SCL=0)
    ST_NK_RISE,     // SCL->1  (SDA=1=NACK)
    ST_NK_FALL,     // SCL->0  -> STOP
    ST_BYTE_DONE,   // one-cycle dispatch
    ST_FINISH,
    ST_ERROR
} state_t;

state_t state;

// ---------------------------------------------------------------------------
// Counter: driven exclusively by the FSM always_ff block below.
// Increments every cycle; reset to 0 on every state transition alongside
// the state assignment. cnt_done pulses on the last cycle of each half-period.
// ---------------------------------------------------------------------------
logic [$clog2(CLK_DIV+1)-1:0] cnt;
wire  cnt_done = (cnt == CLK_DIV - 1);

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

function automatic logic [7:0] f_first_ctrl(input logic [1:0]  op_in,
                                             input logic [16:0] addr_in);
    case (op_in)
        OP_WRITE_DATA  : return f_eeprom_ctrl(addr_in[16], 1'b0);
        OP_READ_DATA   : return f_eeprom_ctrl(addr_in[16], 1'b0);
        OP_READ_STATUS : return f_seccfg_ctrl(1'b0,        1'b0);
        OP_READ_ID     : return 8'hF8;   // ManID host code (write)
        default        : return 8'hFF;
    endcase
endfunction

// ---------------------------------------------------------------------------
// FSM
// ---------------------------------------------------------------------------
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state     <= ST_IDLE;
        cnt       <= '0;
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
        cnt  <= cnt + 1;   // default: free-running; overridden to 0 on every state transition

        case (state)

        ST_IDLE: begin
            scl_r <= 1'b1; sda_drive <= 1'b0;
            busy  <= 1'b0; seq_step  <= '0;
            if (start) begin
                op_lat    <= op;
                addr_lat  <= addr;
                wdata_lat <= wdata;
                busy      <= 1'b1;
                error     <= 1'b0;
                state     <= ST_S_SDA_LO;
                cnt       <= 0;
            end
        end

        // ---- START -------------------------------------------------------
        ST_S_SDA_LO: begin  // SDA falls (SCL=1)
            sda_drive <= 1'b1;
            if (cnt_done) begin
                state <= ST_S_HOLD;
                cnt   <= 0;
            end
        end
        ST_S_HOLD: begin    // hold tHD_STA (1240 ns >> 250 ns required)
            if (cnt_done) begin
                state <= ST_S_SCL_LO;
                cnt   <= 0;
            end
        end
        ST_S_SCL_LO: begin  // SCL falls
            scl_r <= 1'b0;
            if (cnt_done) begin
                tx_byte  <= f_first_ctrl(op_lat, addr_lat);
                bit_idx  <= 4'd7;
                seq_step <= '0;
                state    <= ST_TX_SDA;
                cnt      <= 0;
            end
        end

        // ---- REPEATED START ----------------------------------------------
        ST_RS_SDA_HI: begin // SDA rises (SCL=0)
            sda_drive <= 1'b0;
            if (cnt_done) begin
                state <= ST_RS_SCL_HI;
                cnt   <= 0;
            end
        end
        ST_RS_SCL_HI: begin // SCL rises (SDA=1)
            scl_r <= 1'b1;
            if (cnt_done) begin
                state <= ST_RS_SDA_LO;
                cnt   <= 0;
            end
        end
        ST_RS_SDA_LO: begin // SDA falls (SCL=1) = rSTART event
            sda_drive <= 1'b1;
            if (cnt_done) begin
                state <= ST_RS_HOLD;
                cnt   <= 0;
            end
        end
        ST_RS_HOLD: begin
            if (cnt_done) begin
                state <= ST_RS_SCL_LO;
                cnt   <= 0;
            end
        end
        ST_RS_SCL_LO: begin // SCL falls
            scl_r <= 1'b0;
            if (cnt_done) begin
                bit_idx <= 4'd7;
                state   <= ST_TX_SDA;  // tx_byte pre-loaded by ST_BYTE_DONE
                cnt     <= 0;
            end
        end

        // ---- STOP --------------------------------------------------------
        ST_P_SCL_HI: begin  // SCL rises (SDA=0)
            scl_r <= 1'b1;
            if (cnt_done) begin
                state <= ST_P_SDA_HI;
                cnt   <= 0;
            end
        end
        ST_P_SDA_HI: begin  // SDA rises (SCL=1) = STOP event
            sda_drive <= 1'b0;
            if (cnt_done) begin
                state <= ST_P_HOLD;
                cnt   <= 0;
            end
        end
        ST_P_HOLD: begin    // bus free time
            if (cnt_done) begin
                state <= ST_FINISH;
                cnt   <= 0;
            end
        end

        // ---- TX BIT ------------------------------------------------------
        // SDA set (SCL already low) -> SCL rises -> SCL falls -> repeat or ACK
        ST_TX_SDA: begin    // SDA -> new bit  (SCL=0)
            sda_drive <= !tx_byte[bit_idx];
            if (cnt_done) begin
                state <= ST_TX_RISE;
                cnt   <= 0;
            end
        end
        ST_TX_RISE: begin   // SCL rises
            scl_r <= 1'b1;
            if (cnt_done) begin
                state <= ST_TX_FALL;
                cnt   <= 0;
            end
        end
        ST_TX_FALL: begin   // SCL falls
            scl_r <= 1'b0;
            if (cnt_done) begin
                if (bit_idx == 0) begin
                    state <= ST_AK_REL;
                    cnt   <= 0;
                end else begin
                    bit_idx <= bit_idx - 1;
                    state   <= ST_TX_SDA;
                    cnt     <= 0;
                end
            end
        end

        // ---- RECEIVE ACK -------------------------------------------------
        ST_AK_REL: begin    // SDA released (SCL=0)
            sda_drive <= 1'b0;
            if (cnt_done) begin
                state <= ST_AK_RISE;
                cnt   <= 0;
            end
        end
        ST_AK_RISE: begin   // SCL rises; sample SDA at end
            scl_r <= 1'b1;
            if (cnt_done) begin
                if (sda === 1'b0) begin
                    state <= ST_AK_FALL;  // ACK
                    cnt   <= 0;
                end else begin
                    state <= ST_ERROR;    // NACK
                    cnt   <= 0;
                end
            end
        end
        ST_AK_FALL: begin   // SCL falls -> dispatch
            scl_r <= 1'b0;
            if (cnt_done) begin
                state <= ST_BYTE_DONE;
                cnt   <= 0;
            end
        end

        // ---- RX BIT ------------------------------------------------------
        ST_RX_REL: begin    // SDA released (SCL=0)
            sda_drive <= 1'b0;
            if (cnt_done) begin
                state <= ST_RX_RISE;
                cnt   <= 0;
            end
        end
        ST_RX_RISE: begin   // SCL rises; sample at end
            scl_r <= 1'b1;
            if (cnt_done) begin
                rx_shift <= {rx_shift[6:0], sda};
                if (bit_idx == 0)
                    rx_latch <= {rx_shift[6:0], sda};
                state <= ST_RX_FALL;
                cnt   <= 0;
            end
        end
        ST_RX_FALL: begin   // SCL falls
            scl_r <= 1'b0;
            if (cnt_done) begin
                if (bit_idx == 0) begin
                    state <= ST_BYTE_DONE;
                    cnt   <= 0;
                end else begin
                    bit_idx <= bit_idx - 1;
                    state   <= ST_RX_REL;
                    cnt     <= 0;
                end
            end
        end

        // ---- SEND ACK ----------------------------------------------------
        ST_ATXK_SDA: begin  // SDA->0 (SCL=0)
            sda_drive <= 1'b1;
            if (cnt_done) begin
                state <= ST_ATXK_RISE;
                cnt   <= 0;
            end
        end
        ST_ATXK_RISE: begin // SCL rises
            scl_r <= 1'b1;
            if (cnt_done) begin
                state <= ST_ATXK_FALL;
                cnt   <= 0;
            end
        end
        ST_ATXK_FALL: begin // SCL falls
            scl_r <= 1'b0;
            if (cnt_done) begin
                state <= ST_ATXK_REL;
                cnt   <= 0;
            end
        end
        ST_ATXK_REL: begin  // SDA released (SCL=0)
            sda_drive <= 1'b0;
            if (cnt_done) begin
                state <= ST_BYTE_DONE;
                cnt   <= 0;
            end
        end

        // ---- SEND NACK then STOP -----------------------------------------
        ST_NK_RISE: begin   // SCL rises (SDA=1=NACK)
            scl_r <= 1'b1;
            if (cnt_done) begin
                state <= ST_NK_FALL;
                cnt   <= 0;
            end
        end
        ST_NK_FALL: begin   // SCL falls -> STOP
            scl_r <= 1'b0;
            if (cnt_done) begin
                state <= ST_P_SCL_HI;
                cnt   <= 0;
            end
        end

        // ---- BYTE DONE (one-cycle dispatch) ------------------------------
        // Entry: SCL=0. cnt is reset by the transition into this state.
        // All transitions here reset cnt for the next state.
        //
        // WRITE DATA:
        //   s0 ctrl(W) ACK  -> TX addr[15:8]
        //   s1 addr_hi ACK  -> TX addr[7:0]
        //   s2 addr_lo ACK  -> TX wdata
        //   s3 wdata   ACK  -> STOP
        //
        // READ DATA (random read):
        //   s0 ctrl(W) ACK  -> TX addr[15:8]
        //   s1 addr_hi ACK  -> TX addr[7:0]
        //   s2 addr_lo ACK  -> rSTART + ctrl(R)
        //   s3 ctrl(R) ACK  -> RX 8 bits
        //   s4 byte rx      -> NACK -> STOP
        //
        // READ STATUS (Security reg first serial number byte at 0x0800):
        //   addr_hi=0x08: bits[3:2]=10 satisfies model addr check.
        //   s0 ctrl(W) ACK  -> TX addr_hi=0x08
        //   s1 addr_hi ACK  -> TX addr_lo=0x00
        //   s2 addr_lo ACK  -> rSTART + ctrl(R)
        //   s3 ctrl(R) ACK  -> RX 8 bits
        //   s4 byte rx      -> NACK -> STOP
        //
        // READ ID (ManID, 3 bytes, per datasheet Fig 11-1 + model):
        //   START -> F8h -> 0xA0(device addr as addr_hi) -> rSTART ->
        //   F9h -> RX byte0(ACK) -> RX byte1(ACK) -> RX byte2(NACK) -> STOP
        //   s0 F8h  ACK  -> TX 0xA0 (device addr byte sent as addr_hi)
        //   s1 0xA0 ACK  -> rSTART + F9h  (NO addr_lo!)
        //   s2 F9h  ACK  -> RX byte0
        //   s3 byte0 rx  -> store rdata, ACK
        //   s4 ACK sent  -> RX byte1
        //   s5 byte1 rx  -> ACK
        //   s6 ACK sent  -> RX byte2
        //   s7 byte2 rx  -> NACK -> STOP
        // ------------------------------------------------------------------
        ST_BYTE_DONE: begin
            seq_step <= seq_step + 1;
            case (op_lat)

            OP_WRITE_DATA: case (seq_step)
                4'd0: begin tx_byte <= addr_lat[15:8]; bit_idx <= 4'd7; state <= ST_TX_SDA;   cnt <= 0; end
                4'd1: begin tx_byte <= addr_lat[7:0];  bit_idx <= 4'd7; state <= ST_TX_SDA;   cnt <= 0; end
                4'd2: begin tx_byte <= wdata_lat;      bit_idx <= 4'd7; state <= ST_TX_SDA;   cnt <= 0; end
                4'd3: begin                                              state <= ST_P_SCL_HI; cnt <= 0; end
                default:   begin                                         state <= ST_ERROR;    cnt <= 0; end
            endcase

            OP_READ_DATA: case (seq_step)
                4'd0: begin tx_byte <= addr_lat[15:8];                    bit_idx <= 4'd7; state <= ST_TX_SDA;    cnt <= 0; end
                4'd1: begin tx_byte <= addr_lat[7:0];                     bit_idx <= 4'd7; state <= ST_TX_SDA;    cnt <= 0; end
                4'd2: begin tx_byte <= f_eeprom_ctrl(addr_lat[16], 1'b1); bit_idx <= 4'd7; state <= ST_RS_SDA_HI; cnt <= 0; end
                4'd3: begin rx_shift <= '0; bit_idx <= 4'd7;                               state <= ST_RX_REL;    cnt <= 0; end
                4'd4: begin rdata <= rx_latch;                                             state <= ST_NK_RISE;   cnt <= 0; end
                default:   begin                                                            state <= ST_ERROR;     cnt <= 0; end
            endcase

            OP_READ_STATUS: case (seq_step)
                4'd0: begin tx_byte <= 8'h08;                          bit_idx <= 4'd7; state <= ST_TX_SDA;    cnt <= 0; end
                4'd1: begin tx_byte <= 8'h00;                          bit_idx <= 4'd7; state <= ST_TX_SDA;    cnt <= 0; end
                4'd2: begin tx_byte <= f_seccfg_ctrl(1'b0, 1'b1);      bit_idx <= 4'd7; state <= ST_RS_SDA_HI; cnt <= 0; end
                4'd3: begin rx_shift <= '0; bit_idx <= 4'd7;                            state <= ST_RX_REL;    cnt <= 0; end
                4'd4: begin rdata <= rx_latch;                                          state <= ST_NK_RISE;   cnt <= 0; end
                default:   begin                                                         state <= ST_ERROR;     cnt <= 0; end
            endcase

            OP_READ_ID: case (seq_step)
                4'd0: begin tx_byte <= 8'hA0; bit_idx <= 4'd7; state <= ST_TX_SDA;    cnt <= 0; end  // device addr as addr_hi
                4'd1: begin tx_byte <= 8'hF9; bit_idx <= 4'd7; state <= ST_RS_SDA_HI; cnt <= 0; end  // rSTART + ManID read
                4'd2: begin rx_shift <= '0;   bit_idx <= 4'd7; state <= ST_RX_REL;    cnt <= 0; end  // RX byte0
                4'd3: begin rdata <= rx_latch;                 state <= ST_ATXK_SDA;  cnt <= 0; end  // ACK byte0
                4'd4: begin rx_shift <= '0;   bit_idx <= 4'd7; state <= ST_RX_REL;    cnt <= 0; end  // RX byte1
                4'd5: begin                                    state <= ST_ATXK_SDA;  cnt <= 0; end  // ACK byte1
                4'd6: begin rx_shift <= '0;   bit_idx <= 4'd7; state <= ST_RX_REL;    cnt <= 0; end  // RX byte2
                4'd7: begin                                    state <= ST_NK_RISE;   cnt <= 0; end  // NACK -> STOP
                default:   begin                               state <= ST_ERROR;     cnt <= 0; end
            endcase

            default: begin state <= ST_ERROR; cnt <= 0; end
            endcase
        end

        // ---- TERMINAL STATES ---------------------------------------------
        ST_FINISH: begin
            done  <= 1'b1;
            busy  <= 1'b0;
            state <= ST_IDLE;
            cnt   <= 0;
        end

        ST_ERROR: begin
            // Entry: SCL=1 (from ST_AK_RISE on NACK), SDA released.
            // Lower SCL only (no SDA change). Wait full period before STOP.
            error <= 1'b1;
            busy  <= 1'b0;
            scl_r <= 1'b0;
            if (cnt_done) begin
                state <= ST_P_SCL_HI;
                cnt   <= 0;
            end
        end

        default: begin state <= ST_IDLE; cnt <= 0; end
        endcase
    end
end

endmodule
