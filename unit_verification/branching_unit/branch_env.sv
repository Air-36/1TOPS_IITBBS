class branch_env extends uvm_env;
    `uvm_component_utils(branch_env)

    branch_agent      agent;
    branch_scoreboard sb;
    branch_coverage   cov;

    function new(string name = "branch_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = branch_agent::type_id::create("agent", this);
        sb    = branch_scoreboard::type_id::create("sb", this);
        cov   = branch_coverage::type_id::create("cov", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.mon.mon_ap.connect(sb.sb_imp);
        agent.mon.mon_ap.connect(cov.analysis_export);
    endfunction

endclass
