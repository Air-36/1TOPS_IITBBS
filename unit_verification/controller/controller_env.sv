class controller_env extends uvm_env;
    `uvm_component_utils(controller_env)

    controller_agent    agent;
    controller_scoreboard scoreboard;
    controller_coverage  coverage;

    function new(string name = "controller_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = controller_agent::type_id::create("agent", this);
        scoreboard = controller_scoreboard::type_id::create("scoreboard", this);
        coverage = controller_coverage::type_id::create("coverage", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.mon.ap.connect(scoreboard.analysis_export);
        agent.mon.ap.connect(coverage.analysis_export);
    endfunction

endclass
