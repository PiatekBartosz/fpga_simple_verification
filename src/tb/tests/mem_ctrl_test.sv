class mem_ctrl_test extends uvm_test;
    `uvm_component_utils(mem_ctrl_test)

    mem_ctrl_env m_env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_env = mem_ctrl_env::type_id::create("m_env", this);
        uvm_root::get().set_timeout(10ms, 1);
    endfunction

    function void start_of_simulation_phase(uvm_phase phase);
        uvm_top.print_topology();
    endfunction

    task main_phase(uvm_phase phase);
        mem_ctrl_sequence seq;
        phase.raise_objection(this);
        phase.phase_done.set_drain_time(this, 250us);
        seq = mem_ctrl_sequence::type_id::create("seq");
        seq.start(m_env.m_seqr);
        phase.drop_objection(this);
    endtask
endclass
