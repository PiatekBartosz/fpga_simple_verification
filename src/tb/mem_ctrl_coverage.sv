class mem_ctrl_coverage extends uvm_subscriber #(mem_ctrl_seq_item);
    `uvm_component_utils(mem_ctrl_coverage)

    mem_ctrl_seq_item trans;

    covergroup cg_transaction;
        cp_op: coverpoint trans.op {
            bins read_id = {OP_READ_ID};
            bins read_status = {OP_READ_STATUS};
            bins read_data = {OP_READ_DATA};
            bins write_data = {OP_WRITE_DATA};
            bins sw_reset = {OP_SW_RESET};
        }
        cp_error: coverpoint trans.error {
            bins no_error = {1'b0};
            bins error    = {1'b1};
        }
        cp_addr: coverpoint trans.addr {
            bins low_range = {[17'h0_0000 : 17'h0_7FFF]};
            bins high_range = {[17'h0_8000 : 17'h1_FFFF]};
        }
        cx_op_error: cross cp_op, cp_error;
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_transaction = new();
    endfunction

    function void write(mem_ctrl_seq_item t);
        trans = t;
        cg_transaction.sample();
        `uvm_info(get_full_name(), $sformatf(
                  "Coverage sampled: op=%s addr=0x%05X error=%0b",
                  trans.op.name(),
                  trans.addr,
                  trans.error
                  ), UVM_MEDIUM)
    endfunction
endclass
