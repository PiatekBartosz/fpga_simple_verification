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
        if (!uvm_config_db#(virtual simple_if)::get(this, "", "vif", vif))
            `uvm_fatal(get_full_name(), "Could not get virtual interface from uvm_config_db")
    endfunction

    task run_phase(uvm_phase phase);
        mem_ctrl_seq_item item;
        forever begin
            @(posedge vif.clk);
            if (vif.start) begin
                item       = mem_ctrl_seq_item::type_id::create("mon_item");
                item.op    = op_codes_e'(vif.op);
                item.addr  = vif.addr;
                item.wdata = vif.wdata;
                do @(posedge vif.clk); while (!vif.done && !vif.error);
                item.rdata = vif.rdata;
                item.error = vif.error;
                `uvm_info(get_full_name(),
                          $sformatf("Observed: op=%s addr=0x%05X rdata=0x%06X error=%0b",
                                    item.op.name(), item.addr, item.rdata, item.error), UVM_MEDIUM)
                ap.write(item);
            end
        end
    endtask
endclass
