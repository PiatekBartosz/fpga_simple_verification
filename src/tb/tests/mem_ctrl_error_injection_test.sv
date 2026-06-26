// Direct test: demonstrate error injection and recovery.
// Sequence: (1) write and commit data_a, (2) start a new write cycle for data_b
// without waiting, (3) immediately attempt another write — the EEPROM NACKs because
// WriteActive=1, so error=1 is asserted, (4) poll until device ready, (5) verify
// data_b was committed, (6) perform a clean write and verify full recovery.
class mem_ctrl_error_injection_test extends uvm_test;
    `uvm_component_utils(mem_ctrl_error_injection_test)

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
        // 3 writes (2 with wait + 1 skip) + polls + reads + margin
        uvm_root::get().set_timeout(300ms, 1);
    endfunction

    task main_phase(uvm_phase phase);
        mem_ctrl_error_injection_seq seq;
        phase.raise_objection(this);
        phase.phase_done.set_drain_time(this, 250us);
        seq = mem_ctrl_error_injection_seq::type_id::create("seq");
        seq.start(m_env.m_seqr);
        phase.drop_objection(this);
    endtask
endclass
