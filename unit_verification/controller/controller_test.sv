class controller_test extends uvm_test;
    `uvm_component_utils(controller_test)

    controller_env env;
    virtual controller_if vif;

    function new(string name = "controller_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual controller_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "Virtual interface not found")
        uvm_config_db#(virtual controller_if)::set(this, "env.agent.*", "vif", vif);
        env = controller_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        controller_sequence seq;
        phase.raise_objection(this);
        seq = controller_sequence::type_id::create("seq");
        seq.start(env.agent.seqr);
        #20ns;
        phase.drop_objection(this);
    endtask

endclass
