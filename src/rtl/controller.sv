// controller.sv
`timescale 1ns / 1ps

module controller #(
    parameter int         CLK_DIV   = 62,
    parameter logic [1:0] CHIP_ADDR = 2'b00
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [ 2:0] op,
    input  logic [ 7:0] wdata,
    input  logic [16:0] addr,
    output logic [23:0] rdata,
    output logic        done,
    output logic        error,
    output logic        scl,
    inout  wire         sda
);

    localparam OP_READ_ID = 3'b000;
    localparam OP_READ_STATUS = 3'b001;
    localparam OP_READ_DATA = 3'b010;
    localparam OP_WRITE_DATA = 3'b011;
    localparam OP_SW_RESET = 3'b100;

    logic sda_drive, scl_r;
    assign sda = sda_drive ? 1'b0 : 1'bz;
    assign scl = scl_r;

    typedef enum logic [5:0] {
        ST_IDLE,
        ST_SR_SCL_LO,
        ST_SR_SCL_HI,
        ST_SR_STOP_SDA,
        ST_SR_HOLD,
        ST_S_SDA_LO,
        ST_S_HOLD,
        ST_S_SCL_LO,
        ST_RS_SDA_HI,
        ST_RS_SCL_HI,
        ST_RS_SDA_LO,
        ST_RS_HOLD,
        ST_RS_SCL_LO,
        ST_P_SDA_LO,
        ST_P_SCL_HI,
        ST_P_SDA_HI,
        ST_P_HOLD,
        ST_TX_SDA,
        ST_TX_RISE,
        ST_TX_FALL,
        ST_AK_REL,
        ST_AK_RISE,
        ST_AK_FALL,
        ST_RX_REL,
        ST_RX_RISE,
        ST_RX_FALL,
        ST_ATXK_SDA,
        ST_ATXK_RISE,
        ST_ATXK_FALL,
        ST_ATXK_REL,
        ST_NK_RISE,
        ST_NK_FALL,
        ST_BYTE_DONE,
        ST_FINISH,
        ST_ERROR
    } state_t;

    state_t                         state;

    logic   [$clog2(CLK_DIV+1)-1:0] cnt;
    wire                            cnt_done = (cnt == CLK_DIV - 1);

    logic   [                  2:0] op_lat;
    logic   [                 16:0] addr_lat;
    logic [7:0] wdata_lat, tx_byte;
    logic [7:0] rx_shift, rx_latch, rx_byte1, rx_byte2;
    logic [3:0] bit_idx, seq_step, sr_clocks;

    // Build a device-address control byte:
    //   eeprom=0 -> 1010 | eeprom=1 -> 1011
    function automatic logic [7:0] ctrl_byte(input logic eeprom, input logic page, input logic rw);
        return {3'b101, eeprom, page, CHIP_ADDR[1], CHIP_ADDR[0], rw};
    endfunction

    function automatic logic [7:0] first_ctrl(input logic [2:0] op_in, input logic [16:0] addr_in);
        case (op_in)
            OP_WRITE_DATA, OP_READ_DATA: return ctrl_byte(1'b0, addr_in[16], 1'b0);
            OP_READ_STATUS:              return ctrl_byte(1'b1, 1'b0, 1'b0);
            OP_READ_ID:                  return 8'hF8;
            default:                     return 8'hFF;
        endcase
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= ST_IDLE;
            cnt       <= '0;
            scl_r     <= 1'b1;
            sda_drive <= 1'b0;
            bit_idx   <= 4'd7;
            seq_step  <= '0;
            sr_clocks <= '0;
            tx_byte   <= '0;
            rx_shift  <= '0;
            rx_latch  <= '0;
            rx_byte1  <= '0;
            rx_byte2  <= '0;
            op_lat    <= '0;
            addr_lat  <= '0;
            wdata_lat <= '0;
            rdata     <= '0;
            done      <= 1'b0;
            error     <= 1'b0;
        end else begin
            done <= 1'b0;
            cnt  <= cnt + 1;

            case (state)

                ST_IDLE: begin
                    scl_r     <= 1'b1;
                    sda_drive <= 1'b0;
                    seq_step  <= '0;
                    if (start) begin
                        op_lat    <= op;
                        addr_lat  <= addr;
                        wdata_lat <= wdata;
                        error     <= 1'b0;
                        cnt       <= 0;
                        if (op == OP_SW_RESET) begin
                            sr_clocks <= '0;
                            state     <= ST_SR_SCL_LO;
                        end else begin
                            state <= ST_S_SDA_LO;
                        end
                    end
                end

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
                            sda_drive <= 1'b1;
                            state     <= ST_SR_STOP_SDA;
                            cnt       <= 0;
                        end else begin
                            state <= ST_SR_SCL_LO;
                            cnt   <= 0;
                        end
                    end
                end
                ST_SR_STOP_SDA: begin
                    sda_drive <= 1'b0;
                    if (cnt_done) begin
                        state <= ST_SR_HOLD;
                        cnt   <= 0;
                    end
                end
                ST_SR_HOLD: begin
                    if (cnt_done) begin
                        done  <= 1'b1;
                        state <= ST_IDLE;
                        cnt   <= 0;
                    end
                end

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
                        tx_byte  <= first_ctrl(op_lat, addr_lat);
                        bit_idx  <= 4'd7;
                        seq_step <= '0;
                        state    <= ST_TX_SDA;
                        cnt      <= 0;
                    end
                end

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

                ST_P_SDA_LO: begin
                    sda_drive <= 1'b1;
                    if (cnt_done) begin
                        state <= ST_P_SCL_HI;
                        cnt   <= 0;
                    end
                end
                ST_P_SCL_HI: begin
                    scl_r <= 1'b1;
                    if (cnt_done) begin
                        state <= ST_P_SDA_HI;
                        cnt   <= 0;
                    end
                end
                ST_P_SDA_HI: begin
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
                        if (bit_idx == 0) begin
                            rx_latch <= {rx_shift[6:0], sda};
                        end
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
                        state <= ST_P_SDA_LO;
                        cnt   <= 0;
                    end
                end

                ST_BYTE_DONE: begin
                    seq_step <= seq_step + 1;
                    case (op_lat)

                        OP_WRITE_DATA: begin
                            case (seq_step)
                                4'd0: begin
                                    tx_byte <= addr_lat[15:8];
                                    bit_idx <= 4'd7;
                                    state   <= ST_TX_SDA;
                                    cnt     <= 0;
                                end
                                4'd1: begin
                                    tx_byte <= addr_lat[7:0];
                                    bit_idx <= 4'd7;
                                    state   <= ST_TX_SDA;
                                    cnt     <= 0;
                                end
                                4'd2: begin
                                    tx_byte <= wdata_lat;
                                    bit_idx <= 4'd7;
                                    state   <= ST_TX_SDA;
                                    cnt     <= 0;
                                end
                                4'd3: begin
                                    state <= ST_P_SDA_LO;
                                    cnt   <= 0;
                                end
                                default: begin
                                    state <= ST_ERROR;
                                end
                            endcase
                        end

                        OP_READ_DATA: begin
                            case (seq_step)
                                4'd0: begin
                                    tx_byte <= addr_lat[15:8];
                                    bit_idx <= 4'd7;
                                    state   <= ST_TX_SDA;
                                    cnt     <= 0;
                                end
                                4'd1: begin
                                    tx_byte <= addr_lat[7:0];
                                    bit_idx <= 4'd7;
                                    state   <= ST_TX_SDA;
                                    cnt     <= 0;
                                end
                                4'd2: begin
                                    tx_byte <= ctrl_byte(1'b0, addr_lat[16], 1'b1);
                                    bit_idx <= 4'd7;
                                    state   <= ST_RS_SDA_HI;
                                    cnt     <= 0;
                                end
                                4'd3: begin
                                    rx_shift <= '0;
                                    bit_idx  <= 4'd7;
                                    state    <= ST_RX_REL;
                                    cnt      <= 0;
                                end
                                4'd4: begin
                                    rdata <= {16'h0000, rx_latch};
                                    state <= ST_NK_RISE;
                                    cnt   <= 0;
                                end
                                default: begin
                                    state <= ST_ERROR;
                                end
                            endcase
                        end

                        OP_READ_STATUS: begin
                            case (seq_step)
                                4'd0: begin
                                    tx_byte <= 8'h08;
                                    bit_idx <= 4'd7;
                                    state   <= ST_TX_SDA;
                                    cnt     <= 0;
                                end
                                4'd1: begin
                                    tx_byte <= 8'h00;
                                    bit_idx <= 4'd7;
                                    state   <= ST_TX_SDA;
                                    cnt     <= 0;
                                end
                                4'd2: begin
                                    tx_byte <= ctrl_byte(1'b1, 1'b0, 1'b1);
                                    bit_idx <= 4'd7;
                                    state   <= ST_RS_SDA_HI;
                                    cnt     <= 0;
                                end
                                4'd3: begin
                                    rx_shift <= '0;
                                    bit_idx  <= 4'd7;
                                    state    <= ST_RX_REL;
                                    cnt      <= 0;
                                end
                                4'd4: begin
                                    rdata <= {16'h0000, rx_latch};
                                    state <= ST_NK_RISE;
                                    cnt   <= 0;
                                end
                                default: begin
                                    state <= ST_ERROR;
                                end
                            endcase
                        end

                        OP_READ_ID: begin
                            case (seq_step)
                                4'd0: begin
                                    tx_byte <= 8'hA0;
                                    bit_idx <= 4'd7;
                                    state   <= ST_TX_SDA;
                                    cnt     <= 0;
                                end
                                4'd1: begin
                                    tx_byte <= 8'hF9;
                                    bit_idx <= 4'd7;
                                    state   <= ST_RS_SDA_HI;
                                    cnt     <= 0;
                                end
                                4'd2: begin
                                    rx_shift <= '0;
                                    bit_idx  <= 4'd7;
                                    state    <= ST_RX_REL;
                                    cnt      <= 0;
                                end
                                4'd3: begin
                                    rx_byte1 <= rx_latch;
                                    state    <= ST_ATXK_SDA;
                                    cnt      <= 0;
                                end
                                4'd4: begin
                                    rx_shift <= '0;
                                    bit_idx  <= 4'd7;
                                    state    <= ST_RX_REL;
                                    cnt      <= 0;
                                end
                                4'd5: begin
                                    rx_byte2 <= rx_latch;
                                    state    <= ST_ATXK_SDA;
                                    cnt      <= 0;
                                end
                                4'd6: begin
                                    rx_shift <= '0;
                                    bit_idx  <= 4'd7;
                                    state    <= ST_RX_REL;
                                    cnt      <= 0;
                                end
                                4'd7: begin
                                    rdata <= {rx_byte1, rx_byte2, rx_latch};
                                    state <= ST_NK_RISE;
                                    cnt   <= 0;
                                end
                                default: begin
                                    state <= ST_ERROR;
                                end
                            endcase
                        end

                        default: begin
                            state <= ST_ERROR;
                        end
                    endcase
                end

                ST_FINISH: begin
                    done  <= 1'b1;
                    state <= ST_IDLE;
                    cnt   <= 0;
                end

                ST_ERROR: begin
                    error <= 1'b1;
                    scl_r <= 1'b0;
                    if (cnt_done) begin
                        state <= ST_P_SDA_LO;
                        cnt   <= 0;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                    cnt   <= 0;
                end
            endcase
        end
    end

endmodule
