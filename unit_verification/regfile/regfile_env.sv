class regfile_env extends uvm_env;
    `uvm_component_utils(regfile_env)

    regfile_agent      agent;
    regfile_scoreboard scoreboard;
    regfile_coverage   coverage;

    function new(string name = "regfile_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = regfile_agent::type_id::create("agent", this);
        scoreboard = regfile_scoreboard::type_id::create("scoreboard", this);
        coverage = regfile_coverage::type_id::create("coverage", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.monitor.mon_ap.connect(scoreboard.sb_imp);
        agent.monitor.mon_ap.connect(coverage.analysis_export);
    endfunction

endclass
