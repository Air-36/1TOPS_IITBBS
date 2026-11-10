class branch_test extends uvm_test;
    `uvm_component_utils(branch_test)

    branch_env env;

    function new(string name = "branch_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = branch_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        branch_sequence seq;
        phase.raise_objection(this);
        seq = branch_sequence::type_id::create("seq");
        seq.start(env.agent.seqr);
        phase.drop_objection(this);
    endtask

endclass
