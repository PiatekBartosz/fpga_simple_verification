class mem_ctrl_coverage extends uvm_subscriber #(mem_ctrl_seq_item);
    `uvm_component_utils(mem_ctrl_coverage)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void write(mem_ctrl_seq_item item);
        `uvm_info(get_full_name(), $sformatf("Received: op=%s", item.op.name()), UVM_HIGH)
    endfunction
endclass
