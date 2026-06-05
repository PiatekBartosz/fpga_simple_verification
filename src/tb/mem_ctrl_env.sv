class mem_ctrl_env extends uvm_env;
    `uvm_component_utils(mem_ctrl_env)

    mem_ctrl_sequencer m_seqr;
    mem_ctrl_driver    m_drv;
    mem_ctrl_monitor   m_mon;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_seqr = mem_ctrl_sequencer::type_id::create("m_seqr", this);
        m_drv  = mem_ctrl_driver::type_id::create("m_drv", this);
        m_mon  = mem_ctrl_monitor::type_id::create("m_mon", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        m_drv.seq_item_port.connect(m_seqr.seq_item_export);
    endfunction
endclass
