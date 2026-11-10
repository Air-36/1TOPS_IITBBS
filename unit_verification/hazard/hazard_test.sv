class hazard_test extends uvm_test;
    `uvm_component_utils(hazard_test)

    hazard_env env;

    function new(string name = "hazard_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = hazard_env::type_id::create("env", this);
    endfunction


    task run_phase(uvm_phase phase);
        hazard_sequence seq;
        phase.raise_objection(this);
        seq = hazard_sequence::type_id::create("seq");
        `uvm_info("TEST", "Starting hazard verification", UVM_LOW)
        seq.start(env.agent.seqr);
        `uvm_info("TEST", "Hazard sequence completed", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass
