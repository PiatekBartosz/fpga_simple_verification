class mem_ctrl_sequence extends uvm_sequence #(mem_ctrl_seq_item);
    `uvm_object_utils(mem_ctrl_sequence)

    function new(string name = "mem_ctrl_sequence");
        super.new(name);
    endfunction

    task body();
        mem_ctrl_seq_item item;
        item = mem_ctrl_seq_item::type_id::create("item");
        start_item(item);
        if (!item.randomize()) begin
            `uvm_fatal(get_name(), "Randomization failed")
        end
        finish_item(item);
    endtask
endclass
