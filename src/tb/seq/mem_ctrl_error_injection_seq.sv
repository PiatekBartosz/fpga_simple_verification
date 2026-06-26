class mem_ctrl_error_injection_seq extends uvm_sequence #(mem_ctrl_seq_item);
    `uvm_object_utils(mem_ctrl_error_injection_seq)

    localparam int MAX_POLL = 300;

    function new(string name = "mem_ctrl_error_injection_seq");
        super.new(name);
    endfunction

    task send_op(input op_codes_e op_val, output mem_ctrl_seq_item item);
        item = mem_ctrl_seq_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with {op == op_val;}) `uvm_fatal(get_name(), "Randomization failed")
        finish_item(item);
    endtask

    task send_write_at(input logic [16:0] wr_addr, input logic [7:0] wr_data,
                       input bit           skip_wait, output mem_ctrl_seq_item item);
        item = mem_ctrl_seq_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with {op == OP_WRITE_DATA; addr == wr_addr; wdata == wr_data;})
            `uvm_fatal(get_name(), "Randomization failed")
        item.skip_write_wait = skip_wait;
        finish_item(item);
    endtask

    task send_write_random(output mem_ctrl_seq_item item);
        item = mem_ctrl_seq_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with {op == OP_WRITE_DATA;})
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

    // Poll READ_STATUS until the device ACKs (write cycle finished).
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
        logic [16:0]      addr_a;
        logic [ 7:0]      data_a, data_b;
        int               fail_cnt;

        fail_cnt = 0;
        `uvm_info(get_name(), "=== Error injection seq start ===", UVM_NONE)

        // --- Setup: write data_a to addr_a with full wait ---
        void'(std::randomize(addr_a));
        void'(std::randomize(data_a));
        void'(std::randomize(data_b));
        `uvm_info(get_name(), $sformatf(
                  "Setup: addr_a=0x%05X data_a=0x%02X data_b=0x%02X",
                  addr_a, data_a, data_b), UVM_LOW)

        send_write_at(addr_a, data_a, 0, item);
        if (item.error) begin
            `uvm_error(get_name(), "[FAIL] Initial WRITE_DATA for addr_a")
            fail_cnt++;
        end else `uvm_info(get_name(), "[PASS] Setup write (data_a) committed", UVM_LOW)

        // --- Trigger write cycle: write data_b to addr_a without waiting ---
        // This starts a 5 ms write cycle (WriteActive=1 in EEPROM model).
        send_write_at(addr_a, data_b, 1, item);
        if (item.error) begin
            `uvm_error(get_name(), "[FAIL] Trigger write (data_b) was not accepted")
            fail_cnt++;
        end else `uvm_info(get_name(), "[PASS] Trigger write (data_b) sent; write cycle started",
                           UVM_LOW)

        // --- Error injection: access EEPROM while write cycle is active ---
        // The device NACKs every I2C control byte during WriteActive=1.
        // The controller detects the missing ACK and asserts error=1.
        send_write_random(item);
        if (!item.error) begin
            `uvm_error(get_name(),
                       "[FAIL] Expected error during write cycle but got none (error injection failed)")
            fail_cnt++;
        end else `uvm_info(get_name(),
                           "[PASS] Error correctly detected while device busy (error injected)",
                           UVM_LOW)

        // --- Recovery: poll until write cycle completes ---
        poll_until_ready(item);

        // --- Verification: addr_a should now hold data_b ---
        send_read_at(addr_a, item);
        if (item.error) begin
            `uvm_error(get_name(), "[FAIL] READ_DATA returned error after recovery")
            fail_cnt++;
        end else if (item.rdata[7:0] !== data_b) begin
            `uvm_error(get_name(), $sformatf(
                       "[FAIL] READ_DATA: addr_a=0x%05X got=0x%02X expected=0x%02X (data_b)",
                       addr_a, item.rdata[7:0], data_b))
            fail_cnt++;
        end else `uvm_info(get_name(), $sformatf(
                           "[PASS] Data verified after recovery: addr=0x%05X data=0x%02X",
                           addr_a, item.rdata[7:0]), UVM_LOW)

        // --- Final clean: SW_RESET, write again with proper wait, verify ---
        send_op(OP_SW_RESET, item);
        if (item.error) begin
            `uvm_error(get_name(), "[FAIL] SW_RESET after recovery")
            fail_cnt++;
        end

        void'(std::randomize(data_a));  // reuse data_a as new payload
        send_write_at(addr_a, data_a, 0, item);
        if (item.error) begin
            `uvm_error(get_name(), "[FAIL] Final WRITE_DATA")
            fail_cnt++;
        end

        send_read_at(addr_a, item);
        if (item.error) begin
            `uvm_error(get_name(), "[FAIL] Final READ_DATA returned error")
            fail_cnt++;
        end else if (item.rdata[7:0] !== data_a) begin
            `uvm_error(get_name(), $sformatf(
                       "[FAIL] Final READ_DATA: got=0x%02X expected=0x%02X",
                       item.rdata[7:0], data_a))
            fail_cnt++;
        end else `uvm_info(get_name(), "[PASS] Final verify: device fully recovered", UVM_LOW)

        `uvm_info(get_name(), $sformatf("=== %0d test(s) failed ===", fail_cnt), UVM_NONE)
    endtask
endclass
