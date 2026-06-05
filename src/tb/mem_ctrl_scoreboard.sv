class mem_ctrl_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(mem_ctrl_scoreboard)

    uvm_analysis_imp #(mem_ctrl_seq_item, mem_ctrl_scoreboard) analysis_export;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        analysis_export = new("analysis_export", this);
    endfunction

    function void write(mem_ctrl_seq_item item);
        `uvm_info(get_full_name(), $sformatf("Received: op=%s", item.op.name()), UVM_HIGH)
    endfunction

    function void check_phase(uvm_phase phase);
    endfunction
endclass
