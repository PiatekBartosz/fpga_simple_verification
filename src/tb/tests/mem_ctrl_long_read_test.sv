// Direct test: write a known 16-byte pattern then read it all back.
// Exercises the DUT across a sequential address range.
class mem_ctrl_long_read_test extends uvm_test;
    `uvm_component_utils(mem_ctrl_long_read_test)

    mem_ctrl_env    m_env;
    mem_ctrl_config m_cfg;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_cfg                   = mem_ctrl_config::type_id::create("m_cfg");
        m_cfg.scoreboard_enable = 1;
`ifdef COV
        m_cfg.coverage_enable = 1;
`endif
        uvm_config_db#(mem_ctrl_config)::set(this, "*", "cfg", m_cfg);
        m_env = mem_ctrl_env::type_id::create("m_env", this);
        // 16 writes × ~5.2 ms + 16 reads + margin
        uvm_root::get().set_timeout(500ms, 1);
    endfunction

    task main_phase(uvm_phase phase);
        mem_ctrl_long_read_seq seq;
        phase.raise_objection(this);
        phase.phase_done.set_drain_time(this, 250us);
        seq = mem_ctrl_long_read_seq::type_id::create("seq");
        seq.start(m_env.m_seqr);
        phase.drop_objection(this);
    endtask
endclass
