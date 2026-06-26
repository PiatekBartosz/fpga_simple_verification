class mem_ctrl_sanity_seq extends uvm_sequence #(mem_ctrl_seq_item);
    `uvm_object_utils(mem_ctrl_sanity_seq)

    function new(string name = "mem_ctrl_sanity_seq");
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
        if (!item.randomize() with {op == OP_READ_DATA; addr == exp_addr;})
            `uvm_fatal(get_name(), "Randomization failed")
        finish_item(item);
    endtask

    task body();
        mem_ctrl_seq_item item;
        logic      [16:0] rw_addr;
        logic      [ 7:0] rw_data;
        int               fail_cnt;

        fail_cnt = 0;
        `uvm_info(get_name(), "=== Sanity check start ===", UVM_NONE)

        send_op(OP_SW_RESET, item);
        if (item.error) begin
            `uvm_error(get_name(), "[SANITY FAIL] SW_RESET")
            fail_cnt++;
        end else `uvm_info(get_name(), "[SANITY PASS] SW_RESET", UVM_LOW)

        send_op(OP_READ_ID, item);
        if (item.error) begin
            `uvm_error(get_name(), "[SANITY FAIL] READ_ID returned error")
            fail_cnt++;
        end else if (item.rdata !== DEVICE_ID) begin
            `uvm_error(get_name(), $sformatf(
                       "[SANITY FAIL] READ_ID: got=0x%06X expected=0x%06X", item.rdata, DEVICE_ID))
            fail_cnt++;
        end else `uvm_info(get_name(), "[SANITY PASS] READ_ID", UVM_LOW)

        send_op(OP_WRITE_DATA, item);
        rw_addr = item.addr;
        rw_data = item.wdata;
        if (item.error) begin
            `uvm_error(get_name(), "[SANITY FAIL] WRITE_DATA")
            fail_cnt++;
        end else `uvm_info(get_name(), $sformatf(
                           "[SANITY PASS] WRITE_DATA addr=0x%05X data=0x%02X", rw_addr, rw_data),
                           UVM_LOW)

        send_read_data(rw_addr, item);
        if (item.error) begin
            `uvm_error(get_name(), "[SANITY FAIL] READ_DATA returned error")
            fail_cnt++;
        end else if (item.rdata[7:0] !== rw_data) begin
            `uvm_error(get_name(), $sformatf(
                       "[SANITY FAIL] READ_DATA: got=0x%02X expected=0x%02X",
                       item.rdata[7:0], rw_data))
            fail_cnt++;
        end else `uvm_info(get_name(), "[SANITY PASS] READ_DATA", UVM_LOW)

        `uvm_info(get_name(), $sformatf("=== Sanity: %0d check(s) failed ===", fail_cnt), UVM_NONE)
    endtask
endclass
