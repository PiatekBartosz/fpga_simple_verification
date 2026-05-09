class mem_ctrl_seq_item extends uvm_sequence_item;
    `uvm_object_utils(mem_ctrl_seq_item)

    rand op_codes_e   op;
    rand logic [16:0] addr;
    rand logic [7:0]  wdata;
    logic [23:0]      rdata;
    logic             error;

    function new(string name = "mem_ctrl_seq_item");
        super.new(name);
    endfunction
endclass
