// =============================================================================
// controller.sv  -  I2C Master Controller for Microchip 24CSM01 (1Mbit EEPROM)
// =============================================================================
`timescale 1ns/1ps

module controller #(
    parameter int CLK_DIV           = 62,
    parameter logic [1:0] CHIP_ADDR = 2'b00
)(
    input  logic        clk,
    input  logic        rst_n,

    input  logic [1:0]  op,
    input  logic [16:0] addr,
    input  logic [7:0]  wdata,
    input  logic        start,
    output logic [23:0] rdata,
    output logic        done,
    output logic        busy,
    output logic        error,

    input  logic        sw_reset,

    output logic        scl,
    inout  wire         sda
);

localparam OP_READ_ID     = 2'b00;
localparam OP_READ_STATUS = 2'b01;
localparam OP_READ_DATA   = 2'b10;
localparam OP_WRITE_DATA  = 2'b11;

logic sda_drive;
assign sda = sda_drive ? 1'b0 : 1'bz;

typedef enum logic [5:0] {
    ST_IDLE,
    // Software reset
    ST_SR_SCL_LO,
    ST_SR_SCL_HI,
    ST_SR_STOP_SDA,
    ST_SR_HOLD,
    // START
    ST_S_SDA_LO,
    ST_S_HOLD,
    ST_S_SCL_LO,
    // Repeated START
    ST_RS_SDA_HI,
    ST_RS_SCL_HI,
    ST_RS_SDA_LO,
    ST_RS_HOLD,
    ST_RS_SCL_LO,
    // STOP  (SDA must be low before entering ST_P_SCL_HI)
    ST_P_SDA_LO,    // pull SDA low  (SCL=0) — setup for STOP
    ST_P_SCL_HI,    // SCL->1  (SDA=0)
    ST_P_SDA_HI,    // SDA->1  (SCL=1) = STOP event
    ST_P_HOLD,
    // TX
    ST_TX_SDA,
    ST_TX_RISE,
    ST_TX_FALL,
    // Receive ACK
    ST_AK_REL,
    ST_AK_RISE,
    ST_AK_FALL,
    // RX
    ST_RX_REL,
    ST_RX_RISE,
    ST_RX_FALL,
    // Send ACK
    ST_ATXK_SDA,
    ST_ATXK_RISE,
    ST_ATXK_FALL,
    ST_ATXK_REL,
    // Send NACK then STOP
    ST_NK_RISE,
    ST_NK_FALL,
    // Dispatch / terminal
    ST_BYTE_DONE,
    ST_FINISH,
    ST_ERROR
} state_t;

state_t state;

logic [$clog2(CLK_DIV+1)-1:0] cnt;
wire  cnt_done = (cnt == CLK_DIV - 1);

logic [1:0]  op_lat;
logic [16:0] addr_lat;
logic [7:0]  wdata_lat;
logic [3:0]  bit_idx;
logic [7:0]  tx_byte;
logic [7:0]  rx_shift;
logic [7:0]  rx_latch;
logic [7:0]  rx_byte1;
logic [7:0]  rx_byte2;
logic [3:0]  seq_step;
logic [3:0]  sr_clocks;
logic        scl_r;

assign scl = scl_r;

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
        OP_READ_ID     : return 8'hF8;
        default        : return 8'hFF;
    endcase
endfunction

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
        rx_byte1  <= '0;
        rx_byte2  <= '0;
        seq_step  <= '0;
        sr_clocks <= '0;
        op_lat    <= '0;
        addr_lat  <= '0;
        wdata_lat <= '0;
        rdata     <= '0;
        done      <= 1'b0;
        busy      <= 1'b0;
        error     <= 1'b0;
    end else begin
        done <= 1'b0;
        cnt  <= cnt + 1;

        case (state)

        // ------------------------------------------------------------------
        ST_IDLE: begin
            scl_r <= 1'b1; sda_drive <= 1'b0;
            busy  <= 1'b0; seq_step  <= '0;

            if (sw_reset) begin
                sda_drive <= 1'b0;
                sr_clocks <= '0;
                busy      <= 1'b1;
                state     <= ST_SR_SCL_LO;
                cnt       <= 0;
            end else if (start) begin
                op_lat    <= op;
                addr_lat  <= addr;
                wdata_lat <= wdata;
                busy      <= 1'b1;
                error     <= 1'b0;
                state     <= ST_S_SDA_LO;
                cnt       <= 0;
            end
        end

        // ------------------------------------------------------------------
        // Software Reset (datasheet Section 5.7)
        // Clock SCL up to 9 times with SDA released until SDA goes high.
        // Then issue a clean STOP: SDA low (SCL high) → SDA high.
        // ------------------------------------------------------------------
        ST_SR_SCL_LO: begin
            scl_r     <= 1'b0;
            sda_drive <= 1'b0;
            if (cnt_done) begin
                state <= ST_SR_SCL_HI;
                cnt   <= 0;
            end
        end
        ST_SR_SCL_HI: begin
            scl_r <= 1'b1;
            if (cnt_done) begin
                sr_clocks <= sr_clocks + 1;
                if (sda === 1'b1 || sr_clocks == 4'd8) begin
                    // SDA high: device released. Pull SDA low to set up STOP.
                    sda_drive <= 1'b1;
                    state     <= ST_SR_STOP_SDA;
                    cnt       <= 0;
                end else begin
                    state <= ST_SR_SCL_LO;
                    cnt   <= 0;
                end
            end
        end
        ST_SR_STOP_SDA: begin   // SDA low, SCL high → release SDA = STOP
            sda_drive <= 1'b0;
            if (cnt_done) begin
                state <= ST_SR_HOLD;
                cnt   <= 0;
            end
        end
        ST_SR_HOLD: begin
            if (cnt_done) begin
                done  <= 1'b1;
                busy  <= 1'b0;
                state <= ST_IDLE;
                cnt   <= 0;
            end
        end

        // ------------------------------------------------------------------
        // START
        // ------------------------------------------------------------------
        ST_S_SDA_LO: begin
            sda_drive <= 1'b1;
            if (cnt_done) begin
                state <= ST_S_HOLD;
                cnt   <= 0;
            end
        end
        ST_S_HOLD: begin
            if (cnt_done) begin
                state <= ST_S_SCL_LO;
                cnt   <= 0;
            end
        end
        ST_S_SCL_LO: begin
            scl_r <= 1'b0;
            if (cnt_done) begin
                tx_byte  <= f_first_ctrl(op_lat, addr_lat);
                bit_idx  <= 4'd7;
                seq_step <= '0;
                state    <= ST_TX_SDA;
                cnt      <= 0;
            end
        end

        // ------------------------------------------------------------------
        // Repeated START
        // ------------------------------------------------------------------
        ST_RS_SDA_HI: begin
            sda_drive <= 1'b0;
            if (cnt_done) begin
                state <= ST_RS_SCL_HI;
                cnt   <= 0;
            end
        end
        ST_RS_SCL_HI: begin
            scl_r <= 1'b1;
            if (cnt_done) begin
                state <= ST_RS_SDA_LO;
                cnt   <= 0;
            end
        end
        ST_RS_SDA_LO: begin
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
        ST_RS_SCL_LO: begin
            scl_r <= 1'b0;
            if (cnt_done) begin
                bit_idx <= 4'd7;
                state   <= ST_TX_SDA;
                cnt     <= 0;
            end
        end

        // ------------------------------------------------------------------
        // STOP
        // Invariant: SCL must be low when entering ST_P_SDA_LO.
        // SDA is pulled low first, then SCL rises, then SDA rises = STOP.
        // ------------------------------------------------------------------
        ST_P_SDA_LO: begin     // pull SDA low while SCL is low
            sda_drive <= 1'b1;
            if (cnt_done) begin
                state <= ST_P_SCL_HI;
                cnt   <= 0;
            end
        end
        ST_P_SCL_HI: begin     // SCL rises (SDA=0)
            scl_r <= 1'b1;
            if (cnt_done) begin
                state <= ST_P_SDA_HI;
                cnt   <= 0;
            end
        end
        ST_P_SDA_HI: begin     // SDA rises (SCL=1) = STOP event
            sda_drive <= 1'b0;
            if (cnt_done) begin
                state <= ST_P_HOLD;
                cnt   <= 0;
            end
        end
        ST_P_HOLD: begin
            if (cnt_done) begin
                state <= ST_FINISH;
                cnt   <= 0;
            end
        end

        // ------------------------------------------------------------------
        // TX bit
        // ------------------------------------------------------------------
        ST_TX_SDA: begin
            sda_drive <= !tx_byte[bit_idx];
            if (cnt_done) begin
                state <= ST_TX_RISE;
                cnt   <= 0;
            end
        end
        ST_TX_RISE: begin
            scl_r <= 1'b1;
            if (cnt_done) begin
                state <= ST_TX_FALL;
                cnt   <= 0;
            end
        end
        ST_TX_FALL: begin
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

        // ------------------------------------------------------------------
        // Receive ACK
        // ------------------------------------------------------------------
        ST_AK_REL: begin
            sda_drive <= 1'b0;
            if (cnt_done) begin
                state <= ST_AK_RISE;
                cnt   <= 0;
            end
        end
        ST_AK_RISE: begin
            scl_r <= 1'b1;
            if (cnt_done) begin
                if (sda === 1'b0) begin
                    state <= ST_AK_FALL;
                    cnt   <= 0;
                end else begin
                    state <= ST_ERROR;
                    cnt   <= 0;
                end
            end
        end
        ST_AK_FALL: begin
            scl_r <= 1'b0;
            if (cnt_done) begin
                state <= ST_BYTE_DONE;
                cnt   <= 0;
            end
        end

        // ------------------------------------------------------------------
        // RX bit
        // ------------------------------------------------------------------
        ST_RX_REL: begin
            sda_drive <= 1'b0;
            if (cnt_done) begin
                state <= ST_RX_RISE;
                cnt   <= 0;
            end
        end
        ST_RX_RISE: begin
            scl_r <= 1'b1;
            if (cnt_done) begin
                rx_shift <= {rx_shift[6:0], sda};
                if (bit_idx == 0)
                    rx_latch <= {rx_shift[6:0], sda};
                state <= ST_RX_FALL;
                cnt   <= 0;
            end
        end
        ST_RX_FALL: begin
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

        // ------------------------------------------------------------------
        // Send ACK
        // ------------------------------------------------------------------
        ST_ATXK_SDA: begin
            sda_drive <= 1'b1;
            if (cnt_done) begin
                state <= ST_ATXK_RISE;
                cnt   <= 0;
            end
        end
        ST_ATXK_RISE: begin
            scl_r <= 1'b1;
            if (cnt_done) begin
                state <= ST_ATXK_FALL;
                cnt   <= 0;
            end
        end
        ST_ATXK_FALL: begin
            scl_r <= 1'b0;
            if (cnt_done) begin
                state <= ST_ATXK_REL;
                cnt   <= 0;
            end
        end
        ST_ATXK_REL: begin
            sda_drive <= 1'b0;
            if (cnt_done) begin
                state <= ST_BYTE_DONE;
                cnt   <= 0;
            end
        end

        // ------------------------------------------------------------------
        // Send NACK then STOP
        // SDA is already released (high) = NACK value.
        // After NACK clock, SCL falls, then we go to ST_P_SDA_LO for STOP.
        // ------------------------------------------------------------------
        ST_NK_RISE: begin
            scl_r <= 1'b1;
            if (cnt_done) begin
                state <= ST_NK_FALL;
                cnt   <= 0;
            end
        end
        ST_NK_FALL: begin
            scl_r <= 1'b0;
            if (cnt_done) begin
                state <= ST_P_SDA_LO;   // pull SDA low before STOP
                cnt   <= 0;
            end
        end

        // ------------------------------------------------------------------
        // Byte done dispatch
        //
        // WRITE DATA:
        //   s0 ctrl(W) ACK  -> TX addr[15:8]
        //   s1 addr_hi ACK  -> TX addr[7:0]
        //   s2 addr_lo ACK  -> TX wdata
        //   s3 wdata   ACK  -> STOP  (via ST_P_SDA_LO first)
        //
        // READ DATA:
        //   s0 ctrl(W) ACK  -> TX addr[15:8]
        //   s1 addr_hi ACK  -> TX addr[7:0]
        //   s2 addr_lo ACK  -> rSTART + ctrl(R)
        //   s3 ctrl(R) ACK  -> RX byte
        //   s4 byte rx      -> NACK -> STOP
        //
        // READ STATUS:
        //   s0 ctrl(W) ACK  -> TX addr_hi=0x08
        //   s1 addr_hi ACK  -> TX addr_lo=0x00
        //   s2 addr_lo ACK  -> rSTART + ctrl(R)
        //   s3 ctrl(R) ACK  -> RX byte
        //   s4 byte rx      -> NACK -> STOP
        //
        // READ ID:
        //   s0 F8h  ACK     -> TX 0xA0
        //   s1 0xA0 ACK     -> rSTART + TX F9h
        //   s2 F9h  ACK     -> RX byte0
        //   s3 byte0 done   -> save -> ACK
        //   s4 ACK done     -> RX byte1
        //   s5 byte1 done   -> save -> ACK
        //   s6 ACK done     -> RX byte2
        //   s7 byte2 done   -> assemble rdata -> NACK -> STOP
        // ------------------------------------------------------------------
        ST_BYTE_DONE: begin
            seq_step <= seq_step + 1;
            case (op_lat)

            OP_WRITE_DATA: case (seq_step)
                4'd0: begin tx_byte <= addr_lat[15:8]; bit_idx <= 4'd7; state <= ST_TX_SDA;   cnt <= 0; end
                4'd1: begin tx_byte <= addr_lat[7:0];  bit_idx <= 4'd7; state <= ST_TX_SDA;   cnt <= 0; end
                4'd2: begin tx_byte <= wdata_lat;      bit_idx <= 4'd7; state <= ST_TX_SDA;   cnt <= 0; end
                4'd3: begin                                              state <= ST_P_SDA_LO; cnt <= 0; end
                default: begin                                           state <= ST_ERROR;    cnt <= 0; end
            endcase

            OP_READ_DATA: case (seq_step)
                4'd0: begin tx_byte <= addr_lat[15:8];                    bit_idx <= 4'd7; state <= ST_TX_SDA;    cnt <= 0; end
                4'd1: begin tx_byte <= addr_lat[7:0];                     bit_idx <= 4'd7; state <= ST_TX_SDA;    cnt <= 0; end
                4'd2: begin tx_byte <= f_eeprom_ctrl(addr_lat[16], 1'b1); bit_idx <= 4'd7; state <= ST_RS_SDA_HI; cnt <= 0; end
                4'd3: begin rx_shift <= '0; bit_idx <= 4'd7;                               state <= ST_RX_REL;    cnt <= 0; end
                4'd4: begin rdata <= {16'h0000, rx_latch};                                 state <= ST_NK_RISE;   cnt <= 0; end
                default: begin                                                              state <= ST_ERROR;     cnt <= 0; end
            endcase

            OP_READ_STATUS: case (seq_step)
                4'd0: begin tx_byte <= 8'h08;                         bit_idx <= 4'd7; state <= ST_TX_SDA;    cnt <= 0; end
                4'd1: begin tx_byte <= 8'h00;                         bit_idx <= 4'd7; state <= ST_TX_SDA;    cnt <= 0; end
                4'd2: begin tx_byte <= f_seccfg_ctrl(1'b0, 1'b1);     bit_idx <= 4'd7; state <= ST_RS_SDA_HI; cnt <= 0; end
                4'd3: begin rx_shift <= '0; bit_idx <= 4'd7;                           state <= ST_RX_REL;    cnt <= 0; end
                4'd4: begin rdata <= {16'h0000, rx_latch};                             state <= ST_NK_RISE;   cnt <= 0; end
                default: begin                                                          state <= ST_ERROR;     cnt <= 0; end
            endcase

            OP_READ_ID: case (seq_step)
                4'd0: begin tx_byte <= 8'hA0; bit_idx <= 4'd7; state <= ST_TX_SDA;    cnt <= 0; end
                4'd1: begin tx_byte <= 8'hF9; bit_idx <= 4'd7; state <= ST_RS_SDA_HI; cnt <= 0; end
                4'd2: begin rx_shift <= '0;   bit_idx <= 4'd7; state <= ST_RX_REL;    cnt <= 0; end
                4'd3: begin rx_byte1 <= rx_latch;              state <= ST_ATXK_SDA;  cnt <= 0; end
                4'd4: begin rx_shift <= '0;   bit_idx <= 4'd7; state <= ST_RX_REL;    cnt <= 0; end
                4'd5: begin rx_byte2 <= rx_latch;              state <= ST_ATXK_SDA;  cnt <= 0; end
                4'd6: begin rx_shift <= '0;   bit_idx <= 4'd7; state <= ST_RX_REL;    cnt <= 0; end
                4'd7: begin rdata <= {rx_byte1, rx_byte2, rx_latch}; state <= ST_NK_RISE; cnt <= 0; end
                default: begin                                 state <= ST_ERROR;     cnt <= 0; end
            endcase

            default: begin state <= ST_ERROR; cnt <= 0; end
            endcase
        end

        // ------------------------------------------------------------------
        ST_FINISH: begin
            done  <= 1'b1;
            busy  <= 1'b0;
            state <= ST_IDLE;
            cnt   <= 0;
        end

        ST_ERROR: begin
            error <= 1'b1;
            busy  <= 1'b0;
            scl_r <= 1'b0;
            if (cnt_done) begin
                state <= ST_P_SDA_LO;   // ensure clean STOP from error too
                cnt   <= 0;
            end
        end

        default: begin state <= ST_IDLE; cnt <= 0; end
        endcase
    end
end

endmodule
