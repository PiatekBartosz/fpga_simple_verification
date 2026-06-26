class mem_ctrl_write_readback_seq extends uvm_sequence #(mem_ctrl_seq_item);
    `uvm_object_utils(mem_ctrl_write_readback_seq)

    localparam int MAX_POLL = 300;

    function new(string name = "mem_ctrl_write_readback_seq");
        super.new(name);
    endfunction

    task send_op(input op_codes_e op_val, output mem_ctrl_seq_item item);
        item = mem_ctrl_seq_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with {op == op_val;}) `uvm_fatal(get_name(), "Randomization failed")
        finish_item(item);
    endtask

    // Write a byte without waiting for the write cycle to complete.
    // Caller is responsible for polling device readiness before the next operation.
    task send_write_no_wait(input logic [16:0] wr_addr, input logic [7:0] wr_data,
                            output mem_ctrl_seq_item item);
        item = mem_ctrl_seq_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with {op == OP_WRITE_DATA; addr == wr_addr; wdata == wr_data;})
            `uvm_fatal(get_name(), "Randomization failed")
        item.skip_write_wait = 1;
        finish_item(item);
    endtask

    task send_read_at(input logic [16:0] rd_addr, output mem_ctrl_seq_item item);
        item = mem_ctrl_seq_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with {op == OP_READ_DATA; addr == rd_addr;})
            `uvm_fatal(get_name(), "Randomization failed")
        finish_item(item);
    endtask

    // Poll READ_STATUS until the device ACKs, meaning the write cycle is done.
    // The EEPROM NACKs all I2C accesses while WriteActive=1 (during tWR).
    task poll_until_ready(output mem_ctrl_seq_item item);
        for (int i = 0; i < MAX_POLL; i++) begin
            send_op(OP_READ_STATUS, item);
            if (!item.error) begin
                `uvm_info(get_name(), $sformatf(
                          "Device ready after %0d poll(s)", i + 1), UVM_LOW)
                return;
            end
            `uvm_info(get_name(), $sformatf("Busy polling [%0d]...", i), UVM_HIGH)
        end
        `uvm_fatal(get_name(), "Device never became ready after max polls")
    endtask

    task body();
        mem_ctrl_seq_item item;
        logic [16:0]      wr_addr;
        logic [ 7:0]      wr_data;
        int               fail_cnt;

        fail_cnt = 0;
        `uvm_info(get_name(), "=== Write-readback with busy polling start ===", UVM_NONE)

        // SW_RESET for clean state
        send_op(OP_SW_RESET, item);
        if (item.error) begin
            `uvm_error(get_name(), "[FAIL] SW_RESET")
            fail_cnt++;
        end

        // Randomise address and data
        void'(std::randomize(wr_addr));
        void'(std::randomize(wr_data));
        `uvm_info(get_name(), $sformatf(
                  "Writing addr=0x%05X data=0x%02X (no post-write wait)", wr_addr, wr_data),
                  UVM_LOW)

        // Write without waiting — driver returns as soon as done signal is seen
        send_write_no_wait(wr_addr, wr_data, item);
        if (item.error) begin
            `uvm_error(get_name(), "[FAIL] WRITE_DATA")
            fail_cnt++;
        end else `uvm_info(get_name(), "[PASS] WRITE_DATA sent (write cycle in progress)", UVM_LOW)

        // Busy-poll: spin on READ_STATUS until device ACKs (write cycle complete)
        poll_until_ready(item);

        // Read back and verify
        send_read_at(wr_addr, item);
        if (item.error) begin
            `uvm_error(get_name(), "[FAIL] READ_DATA returned error")
            fail_cnt++;
        end else if (item.rdata[7:0] !== wr_data) begin
            `uvm_error(get_name(), $sformatf(
                       "[FAIL] READ_DATA: got=0x%02X expected=0x%02X",
                       item.rdata[7:0], wr_data))
            fail_cnt++;
        end else `uvm_info(get_name(), $sformatf(
                           "[PASS] READ_DATA: addr=0x%05X data=0x%02X", wr_addr, wr_data),
                           UVM_LOW)

        `uvm_info(get_name(), $sformatf("=== %0d test(s) failed ===", fail_cnt), UVM_NONE)
    endtask
endclass
