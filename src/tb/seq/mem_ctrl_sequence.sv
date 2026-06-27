class mem_ctrl_sequence extends uvm_sequence #(mem_ctrl_seq_item);
    `uvm_object_utils(mem_ctrl_sequence)

    function new(string name = "mem_ctrl_sequence");
        super.new(name);
    endfunction

    task send_op(input op_codes_e op_val, output mem_ctrl_seq_item item);
        item = mem_ctrl_seq_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with {op == op_val;}) `uvm_fatal(get_name(), "Randomization failed")
        finish_item(item);
    endtask

    task send_read_data(input logic [16:0] exp_addr, output mem_ctrl_seq_item item);
        item = mem_ctrl_seq_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with {
                op == OP_READ_DATA;
                addr == exp_addr;
            })
            `uvm_fatal(get_name(), "Randomization failed")
        finish_item(item);
    endtask

    task body();
        mem_ctrl_seq_item        item;
        logic             [16:0] rw_addr;
        logic             [ 7:0] rw_data;
        int                      fail_cnt;

        fail_cnt = 0;

        `uvm_info(get_name(), "=== Simulation start ===", UVM_NONE)

        // SW_RESET
        send_op(OP_SW_RESET, item);
        if (item.error) begin
            `uvm_error(get_name(), "[FAIL] SW_RESET")
            fail_cnt++;
        end else begin
            `uvm_info(get_name(), "[PASS] SW_RESET", UVM_LOW)
        end

        // READ_ID
        send_op(OP_READ_ID, item);
        if (item.error) begin
            `uvm_error(get_name(), "[FAIL] READ_ID")
            fail_cnt++;
        end else if (item.rdata !== DEVICE_ID) begin
            `uvm_error(get_name(), $sformatf("[FAIL] READ_ID got=0x%06X expected=0x%06X",
                                             item.rdata, DEVICE_ID))
            fail_cnt++;
        end else begin
            `uvm_info(get_name(), $sformatf("[PASS] READ_ID ManID=0x%06X", item.rdata), UVM_LOW)
        end

        // READ_STATUS
        send_op(OP_READ_STATUS, item);
        if (item.error) begin
            `uvm_error(get_name(), "[FAIL] READ_STATUS")
            fail_cnt++;
        end else begin
            `uvm_info(get_name(), $sformatf("[PASS] READ_STATUS rdata=0x%02X", item.rdata[7:0]),
                      UVM_LOW)
        end

        // WRITE_DATA - addr and wdata come from UVM randomization
        send_op(OP_WRITE_DATA, item);
        rw_addr = item.addr;
        rw_data = item.wdata;
        if (item.error) begin
            `uvm_error(get_name(), "[FAIL] WRITE_DATA")
            fail_cnt++;
        end else begin
            `uvm_info(get_name(), $sformatf(
                      "[PASS] WRITE_DATA addr=0x%05X data=0x%02X", rw_addr, rw_data), UVM_LOW)
        end

        // READ_DATA - addr constrained to match the write
        send_read_data(rw_addr, item);
        if (item.error) begin
            `uvm_error(get_name(), "[FAIL] READ_DATA")
            fail_cnt++;
        end else if (item.rdata[7:0] !== rw_data) begin
            `uvm_error(get_name(), $sformatf("[FAIL] READ_DATA got=0x%02X expected=0x%02X",
                                             item.rdata[7:0], rw_data))
            fail_cnt++;
        end else begin
            `uvm_info(get_name(), $sformatf("[PASS] READ_DATA rdata=0x%02X", item.rdata[7:0]),
                      UVM_LOW)
        end

        `uvm_info(get_name(), $sformatf("=== %0d test(s) failed ===", fail_cnt), UVM_NONE)
    endtask
endclass
