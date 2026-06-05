class mem_ctrl_monitor extends uvm_monitor;
    `uvm_component_utils(mem_ctrl_monitor)

    virtual simple_if vif;
    uvm_analysis_port #(mem_ctrl_seq_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db #(virtual simple_if)::get(this, "", "vif", vif))
            `uvm_fatal(get_full_name(), "Could not get virtual interface from uvm_config_db")
    endfunction

    task run_phase(uvm_phase phase);
    endtask
endclass
