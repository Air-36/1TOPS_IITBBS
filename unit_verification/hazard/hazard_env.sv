class hazard_env extends uvm_env;
    `uvm_component_utils(hazard_env)

    hazard_agent    agent;
    hazard_scoreboard sb;
    hazard_coverage  cov;

    function new(string name = "hazard_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = hazard_agent::type_id::create("agent", this);
        sb    = hazard_scoreboard::type_id::create("sb", this);
        cov   = hazard_coverage::type_id::create("cov", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.mon.mon_ap.connect(sb.sb_imp);
        agent.mon.mon_ap.connect(cov.analysis_export);
    endfunction
endclass
