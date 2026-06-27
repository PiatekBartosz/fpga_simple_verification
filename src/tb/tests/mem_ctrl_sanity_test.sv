// Sanity test: verifies compilation, elaboration and basic environment functionality.
// Coverage and report generation are intentionally disabled.
// Configurable via mem_ctrl_config: scoreboard always on, coverage always off.
class mem_ctrl_sanity_test extends uvm_test;
    `uvm_component_utils(mem_ctrl_sanity_test)

    mem_ctrl_env    m_env;
    mem_ctrl_config m_cfg;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_cfg                   = mem_ctrl_config::type_id::create("m_cfg");
        m_cfg.scoreboard_enable = 1;
        m_cfg.coverage_enable   = 0;
        uvm_config_db#(mem_ctrl_config)::set(this, "*", "cfg", m_cfg);
        m_env = mem_ctrl_env::type_id::create("m_env", this);
        uvm_root::get().set_timeout(50ms, 1);
    endfunction

    task main_phase(uvm_phase phase);
        mem_ctrl_sanity_seq seq;
        phase.raise_objection(this);
        phase.phase_done.set_drain_time(this, 250us);
        seq = mem_ctrl_sanity_seq::type_id::create("seq");
        seq.start(m_env.m_seqr);
        phase.drop_objection(this);
    endtask
endclass
