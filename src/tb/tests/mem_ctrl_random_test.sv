// Random test: runs mem_ctrl_rand_seq with randomized data_length.
// Distribution: SHORT highest, SINGLE and MAX lowest.
// Runs 3 iterations so distribution is observable in a single sim run.
class mem_ctrl_random_test extends uvm_test;
    `uvm_component_utils(mem_ctrl_random_test)

    mem_ctrl_env    m_env;
    mem_ctrl_config m_cfg;

    localparam int NUM_RUNS = 3;

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
        // MAX=16 pairs × 3 runs × ~5.2 ms/write + read overhead → ~300 ms
        uvm_root::get().set_timeout(1000ms, 1);
    endfunction

    task main_phase(uvm_phase phase);
        mem_ctrl_rand_seq seq;
        phase.raise_objection(this);
        phase.phase_done.set_drain_time(this, 250us);

        for (int i = 0; i < NUM_RUNS; i++) begin
            seq = mem_ctrl_rand_seq::type_id::create($sformatf("seq_%0d", i));
            if (!seq.randomize()) `uvm_fatal(get_name(), "seq randomization failed")
            `uvm_info(get_name(), $sformatf(
                      "--- Run %0d/%0d: data_length=%s ---", i + 1, NUM_RUNS, seq.data_length.name()
                      ), UVM_NONE)
            seq.start(m_env.m_seqr);
        end

        phase.drop_objection(this);
    endtask
endclass
