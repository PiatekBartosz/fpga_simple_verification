class mem_ctrl_long_read_seq extends uvm_sequence #(mem_ctrl_seq_item);
    `uvm_object_utils(mem_ctrl_long_read_seq)

    localparam int NUM_BYTES = 16;
    localparam logic [16:0] BASE_ADDR = 17'h0_0200;

    function new(string name = "mem_ctrl_long_read_seq");
        super.new(name);
    endfunction

    task send_write_at(input logic [16:0] wr_addr, input logic [7:0] wr_data,
                       output mem_ctrl_seq_item item);
        item = mem_ctrl_seq_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with {
                op == OP_WRITE_DATA;
                addr == wr_addr;
                wdata == wr_data;
            })
            `uvm_fatal(get_name(), "Randomization failed")
        finish_item(item);
    endtask

    task send_read_at(input logic [16:0] rd_addr, output mem_ctrl_seq_item item);
        item = mem_ctrl_seq_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with {
                op == OP_READ_DATA;
                addr == rd_addr;
            })
            `uvm_fatal(get_name(), "Randomization failed")
        finish_item(item);
    endtask

    task body();
        mem_ctrl_seq_item        item;
        logic             [ 7:0] expected [NUM_BYTES];
        logic             [16:0] cur_addr;
        int                      fail_cnt;

        fail_cnt = 0;
        `uvm_info(get_name(), $sformatf("=== Long read seq start: %0d bytes at 0x%05X ===",
                                        NUM_BYTES, BASE_ADDR), UVM_NONE)

        // Inject known data pattern into sequential addresses
        for (int i = 0; i < NUM_BYTES; i++) begin
            cur_addr    = BASE_ADDR + 17'(i);
            expected[i] = 8'(i * 7 + 1);  // deterministic, non-trivial pattern
            send_write_at(cur_addr, expected[i], item);
            if (item.error) begin
                `uvm_error(get_name(), $sformatf("[FAIL] WRITE[%0d] addr=0x%05X", i, cur_addr))
                fail_cnt++;
            end else
                `uvm_info(get_name(), $sformatf(
                          "[PASS] WRITE[%0d] addr=0x%05X data=0x%02X", i, cur_addr, expected[i]),
                          UVM_LOW)
        end

        // Long sequential read and verify
        `uvm_info(get_name(), "--- Starting long sequential read ---", UVM_LOW)
        for (int i = 0; i < NUM_BYTES; i++) begin
            cur_addr = BASE_ADDR + 17'(i);
            send_read_at(cur_addr, item);
            if (item.error) begin
                `uvm_error(get_name(), $sformatf("[FAIL] READ[%0d] addr=0x%05X returned error", i,
                                                 cur_addr))
                fail_cnt++;
            end else if (item.rdata[7:0] !== expected[i]) begin
                `uvm_error(get_name(),
                           $sformatf("[FAIL] READ[%0d] addr=0x%05X got=0x%02X expected=0x%02X", i,
                                     cur_addr, item.rdata[7:0], expected[i]))
                fail_cnt++;
            end else
                `uvm_info(get_name(), $sformatf(
                          "[PASS] READ[%0d] addr=0x%05X data=0x%02X", i, cur_addr, item.rdata[7:0]),
                          UVM_LOW)
        end

        `uvm_info(get_name(), $sformatf("=== %0d test(s) failed ===", fail_cnt), UVM_NONE)
    endtask
endclass
