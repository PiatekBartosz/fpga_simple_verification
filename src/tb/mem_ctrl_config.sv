class mem_ctrl_config extends uvm_object;
    `uvm_object_utils_begin(mem_ctrl_config)
        `uvm_field_int(scoreboard_enable, UVM_ALL_ON)
        `uvm_field_int(coverage_enable,   UVM_ALL_ON)
    `uvm_object_utils_end

    bit scoreboard_enable = 0;
    bit coverage_enable   = 0;

    function new(string name = "mem_ctrl_config");
        super.new(name);
    endfunction
endclass
