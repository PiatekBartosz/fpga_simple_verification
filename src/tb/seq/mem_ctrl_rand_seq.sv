class mem_ctrl_rand_seq extends uvm_sequence #(mem_ctrl_seq_item);
    `uvm_object_utils(mem_ctrl_rand_seq)

    rand data_length_e data_length;

    // SHORT gets highest probability; SINGLE and MAX get lowest
    constraint c_data_length_dist {
        data_length dist {
            SINGLE :=  5,
            SHORT  := 40,
            MEDIUM := 30,
            LONG   := 20,
            MAX    :=  5
        };
    }

    function new(string name = "mem_ctrl_rand_seq");
        super.new(name);
    endfunction

    task send_write(output mem_ctrl_seq_item item);
        item = mem_ctrl_seq_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with {op == OP_WRITE_DATA;})
            `uvm_fatal(get_name(), "Randomization failed")
        finish_item(item);
    endtask

    task send_read(input logic [16:0] exp_addr, output mem_ctrl_seq_item item);
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
        logic             [16:0] addrs    [];
        logic             [ 7:0] datas    [];
        int                      n;
        int                      fail_cnt;

        n        = int'(data_length);
        addrs    = new[n];
        datas    = new[n];
        fail_cnt = 0;

        `uvm_info(get_name(),
                  $sformatf("=== Random seq start: data_length=%s (%0d write+read pairs) ===",
                            data_length.name(), n), UVM_NONE)

        // Phase 1: N writes — guarantees at least one write
        for (int i = 0; i < n; i++) begin
            send_write(item);
            addrs[i] = item.addr;
            datas[i] = item.wdata;
            if (item.error) begin
                `uvm_error(get_name(), $sformatf("[FAIL] WRITE[%0d] addr=0x%05X", i, item.addr))
                fail_cnt++;
            end else
                `uvm_info(get_name(), $sformatf(
                          "[PASS] WRITE[%0d] addr=0x%05X data=0x%02X", i, item.addr, item.wdata),
                          UVM_LOW)
        end

        // Phase 2: N reads from the same addresses — guarantees at least one read
        for (int i = 0; i < n; i++) begin
            send_read(addrs[i], item);
            if (item.error) begin
                `uvm_error(get_name(), $sformatf("[FAIL] READ[%0d] addr=0x%05X returned error", i,
                                                 addrs[i]))
                fail_cnt++;
            end else if (item.rdata[7:0] !== datas[i]) begin
                `uvm_error(get_name(),
                           $sformatf("[FAIL] READ[%0d] addr=0x%05X got=0x%02X expected=0x%02X", i,
                                     addrs[i], item.rdata[7:0], datas[i]))
                fail_cnt++;
            end else
                `uvm_info(get_name(), $sformatf(
                          "[PASS] READ[%0d] addr=0x%05X data=0x%02X", i, addrs[i], item.rdata[7:0]),
                          UVM_LOW)
        end

        `uvm_info(get_name(), $sformatf("=== %0d test(s) failed ===", fail_cnt), UVM_NONE)
    endtask
endclass
