typedef enum logic [2:0] {
    OP_READ_ID     = 3'b000,
    OP_READ_STATUS = 3'b001,
    OP_READ_DATA   = 3'b010,
    OP_WRITE_DATA  = 3'b011,
    OP_SW_RESET    = 3'b100
} op_codes_e;

typedef enum int {
    SINGLE =  1,
    SHORT  =  3,
    MEDIUM =  6,
    LONG   = 10,
    MAX    = 16
} data_length_e;

parameter int WRITE_CYCLE_WAIT = 260_000;
parameter int TIMEOUT = 500_000;
parameter logic [23:0] DEVICE_ID = 24'h00D0D0;
