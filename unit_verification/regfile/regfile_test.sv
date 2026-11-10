class regfile_test extends uvm_test;
    `uvm_component_utils(regfile_test)

    regfile_env env;

    function new(string name = "regfile_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = regfile_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        regfile_sequence seq;
        phase.raise_objection(this);
        seq = regfile_sequence::type_id::create("seq");
        seq.start(env.agent.sequencer);
        phase.drop_objection(this);
    endtask
endclass
