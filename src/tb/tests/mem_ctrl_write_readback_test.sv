// Direct test: write then poll READ_STATUS (busy polling) until device is ready,
// then read back and verify. Skips the static write-cycle delay in the driver;
// device readiness is determined by whether the EEPROM ACKs the I2C control byte.
class mem_ctrl_write_readback_test extends uvm_test;
    `uvm_component_utils(mem_ctrl_write_readback_test)

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
        // 1 write (skip wait) + ~300 polls × ~20 µs + 1 read + margin
        uvm_root::get().set_timeout(100ms, 1);
    endfunction

    task main_phase(uvm_phase phase);
        mem_ctrl_write_readback_seq seq;
        phase.raise_objection(this);
        phase.phase_done.set_drain_time(this, 250us);
        seq = mem_ctrl_write_readback_seq::type_id::create("seq");
        seq.start(m_env.m_seqr);
        phase.drop_objection(this);
    endtask
endclass
