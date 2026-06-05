class mem_ctrl_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(mem_ctrl_scoreboard)

    uvm_analysis_imp #(mem_ctrl_seq_item, mem_ctrl_scoreboard)       analysis_export;

    logic                                                      [7:0] mem_model[logic  [16:0]];
    logic                                                      [7:0] last_status;
    int                                                              fail_cnt;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        analysis_export = new("analysis_export", this);
        fail_cnt        = 0;
    endfunction

    function void write(mem_ctrl_seq_item item);
        `uvm_info(get_full_name(), $sformatf("Received: op=%s", item.op.name()), UVM_HIGH)
        case (item.op)
            OP_READ_ID:     check_read_id(item);
            OP_READ_STATUS: check_read_status(item);
            OP_WRITE_DATA:  check_write_data(item);
            OP_READ_DATA:   check_read_data(item);
            default:        ;
        endcase
    endfunction

    function void check_read_id(mem_ctrl_seq_item item);
        if (item.rdata !== DEVICE_ID) begin
            `uvm_error(get_full_name(), $sformatf("[SB FAIL] READ_ID: got=0x%06X expected=0x%06X",
                                                  item.rdata, DEVICE_ID))
            fail_cnt++;
        end else
            `uvm_info(get_full_name(), $sformatf("[SB PASS] READ_ID: 0x%06X", item.rdata), UVM_LOW)
    endfunction

    function void check_read_status(mem_ctrl_seq_item item);
        last_status = item.rdata[7:0];
        `uvm_info(get_full_name(), $sformatf("[SB] READ_STATUS stored: 0x%02X", last_status),
                  UVM_LOW)
    endfunction

    function void check_write_data(mem_ctrl_seq_item item);
        mem_model[item.addr] = item.wdata;
        `uvm_info(get_full_name(), $sformatf(
                  "[SB] WRITE_DATA stored: addr=0x%05X data=0x%02X", item.addr, item.wdata),
                  UVM_LOW)
    endfunction

    function void check_read_data(mem_ctrl_seq_item item);
        logic [7:0] expected;
        expected = mem_model.exists(item.addr) ? mem_model[item.addr] : 8'hFF;
        if (item.rdata[7:0] !== expected) begin
            `uvm_error(get_full_name(),
                       $sformatf("[SB FAIL] READ_DATA: addr=0x%05X got=0x%02X expected=0x%02X",
                                 item.addr, item.rdata[7:0], expected))
            fail_cnt++;
        end else
            `uvm_info(get_full_name(), $sformatf(
                      "[SB PASS] READ_DATA: addr=0x%05X data=0x%02X", item.addr, item.rdata[7:0]),
                      UVM_LOW)
    endfunction

    function void check_phase(uvm_phase phase);
        if (fail_cnt > 0)
            `uvm_error(get_full_name(), $sformatf("%0d scoreboard check(s) failed", fail_cnt))
        else `uvm_info(get_full_name(), "All scoreboard checks passed", UVM_LOW)
    endfunction
endclass
