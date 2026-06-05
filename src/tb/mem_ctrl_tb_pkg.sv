`include "uvm_macros.svh"

package mem_ctrl_tb_pkg;
    import uvm_pkg::*;

    `include "mem_ctrl_definitions.sv"
    `include "mem_ctrl_seq_item.sv"
    `include "seq/mem_ctrl_sequence.sv"
    `include "mem_ctrl_driver.sv"
    `include "mem_ctrl_sequencer.sv"
    `include "mem_ctrl_config.sv"
    `include "mem_ctrl_monitor.sv"
    `include "mem_ctrl_scoreboard.sv"
    `include "mem_ctrl_coverage.sv"
    `include "mem_ctrl_env.sv"
    `include "tests/mem_ctrl_test.sv"
endpackage
