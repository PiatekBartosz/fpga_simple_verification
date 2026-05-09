class mem_ctrl_sequence extends uvm_sequence #(mem_ctrl_seq_item);
    `uvm_object_utils(mem_ctrl_sequence)

    function new(string name = "mem_ctrl_sequence");
        super.new(name);
    endfunction

    task send_op(input op_codes_e op, input logic [16:0] addr, input logic [7:0] wdata,
                 output logic [23:0] rdata, output logic error);
        mem_ctrl_seq_item item = mem_ctrl_seq_item::type_id::create("item");
        start_item(item);
        item.op    = op;
        item.addr  = addr;
        item.wdata = wdata;
        finish_item(item);
        rdata = item.rdata;
        error = item.error;
    endtask

    task body();
        logic [23:0] rdata;
        logic        error;
        logic [16:0] rw_addr;
        logic [ 7:0] rw_data;
        int          fail_cnt;

        fail_cnt = 0;
        rw_addr  = $urandom();
        rw_data  = 8'hA5;

        `uvm_info(get_name(), "=== Simulation start ===", UVM_NONE)

        // SW_RESET
        send_op(OP_SW_RESET, '0, '0, rdata, error);
        if (error) begin
            `uvm_error(get_name(), "[FAIL] SW_RESET")
            fail_cnt++;
        end else begin
            `uvm_info(get_name(), "[PASS] SW_RESET", UVM_LOW)
        end

        // READ_ID
        send_op(OP_READ_ID, '0, '0, rdata, error);
        if (error) begin
            `uvm_error(get_name(), "[FAIL] READ_ID")
            fail_cnt++;
        end else if (rdata !== DEVICE_ID) begin
            `uvm_error(get_name(), $sformatf("[FAIL] READ_ID got=0x%06X expected=0x%06X", rdata, DEVICE_ID))
            fail_cnt++;
        end else begin
            `uvm_info(get_name(), $sformatf("[PASS] READ_ID ManID=0x%06X", rdata), UVM_LOW)
        end

        // READ_STATUS
        send_op(OP_READ_STATUS, '0, '0, rdata, error);
        if (error) begin
            `uvm_error(get_name(), "[FAIL] READ_STATUS")
            fail_cnt++;
        end else begin
            `uvm_info(get_name(), $sformatf("[PASS] READ_STATUS rdata=0x%02X", rdata[7:0]), UVM_LOW)
        end

        // WRITE_DATA
        send_op(OP_WRITE_DATA, rw_addr, rw_data, rdata, error);
        if (error) begin
            `uvm_error(get_name(), "[FAIL] WRITE_DATA")
            fail_cnt++;
        end else begin
            `uvm_info(get_name(), $sformatf("[PASS] WRITE_DATA addr=0x%05X data=0x%02X", rw_addr, rw_data), UVM_LOW)
        end

        // READ_DATA
        send_op(OP_READ_DATA, rw_addr, rw_data, rdata, error);
        if (error) begin
            `uvm_error(get_name(), "[FAIL] READ_DATA")
            fail_cnt++;
        end else if (rdata[7:0] !== rw_data) begin
            `uvm_error(get_name(), $sformatf("[FAIL] READ_DATA got=0x%02X expected=0x%02X", rdata[7:0], rw_data))
            fail_cnt++;
        end else begin
            `uvm_info(get_name(), $sformatf("[PASS] READ_DATA rdata=0x%02X", rdata[7:0]), UVM_LOW)
        end

        `uvm_info(get_name(), $sformatf("=== %0d test(s) failed ===", fail_cnt), UVM_NONE)
    endtask
endclass
