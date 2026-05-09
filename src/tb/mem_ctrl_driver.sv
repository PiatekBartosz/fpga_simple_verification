class mem_ctrl_driver extends uvm_driver #(mem_ctrl_seq_item);
    `uvm_component_utils(mem_ctrl_driver)

    virtual simple_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual simple_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal(get_full_name(), "Could not get virtual interface from uvm_config_db")
        end
    endfunction

    task reset_phase(uvm_phase phase);
        phase.raise_objection(this);
        vif.rst_n <= 1'b0;
        vif.op    <= '0;
        vif.addr  <= '0;
        vif.wdata <= '0;
        vif.start <= 1'b0;
        repeat (10) @(posedge vif.clk);
        vif.rst_n <= 1'b1;
        repeat (15) @(posedge vif.clk);
        phase.drop_objection(this);
    endtask

    task main_phase(uvm_phase phase);
        mem_ctrl_seq_item req;
        forever begin
            seq_item_port.get_next_item(req);
            drive_item(req);
            seq_item_port.item_done();
        end
    endtask

    task drive_item(mem_ctrl_seq_item req);
        @(posedge vif.clk);
        vif.op    <= req.op;
        vif.addr  <= req.addr;
        vif.wdata <= req.wdata;
        vif.start <= 1'b1;
        @(posedge vif.clk);
        vif.start <= 1'b0;
        for (int i = 0; i < TIMEOUT; i++) begin
            @(posedge vif.clk);
            if (vif.done || vif.error) begin
                break;
            end
            if (i == TIMEOUT - 1) begin
                `uvm_fatal(get_full_name(), $sformatf("TIMEOUT at %0t", $time))
            end
        end
        req.rdata = vif.rdata;
        req.error = vif.error;
    endtask
endclass
