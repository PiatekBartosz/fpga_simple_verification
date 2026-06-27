class mem_ctrl_env extends uvm_env;
    `uvm_component_utils(mem_ctrl_env)

    mem_ctrl_sequencer  m_seqr;
    mem_ctrl_driver     m_drv;
    mem_ctrl_monitor    m_mon;
    mem_ctrl_scoreboard m_sb;
    mem_ctrl_coverage   m_cov;
    mem_ctrl_config     m_cfg;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(mem_ctrl_config)::get(this, "", "cfg", m_cfg))
            `uvm_fatal(get_full_name(), "Could not get config from uvm_config_db")
        m_seqr = mem_ctrl_sequencer::type_id::create("m_seqr", this);
        m_drv  = mem_ctrl_driver::type_id::create("m_drv", this);
        m_mon  = mem_ctrl_monitor::type_id::create("m_mon", this);
        if (m_cfg.scoreboard_enable) m_sb = mem_ctrl_scoreboard::type_id::create("m_sb", this);
        if (m_cfg.coverage_enable) m_cov = mem_ctrl_coverage::type_id::create("m_cov", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        m_drv.seq_item_port.connect(m_seqr.seq_item_export);
        if (m_cfg.scoreboard_enable) m_mon.ap.connect(m_sb.analysis_export);
        if (m_cfg.coverage_enable) m_mon.ap.connect(m_cov.analysis_export);
    endfunction
endclass
