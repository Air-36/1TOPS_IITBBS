// =============================================================================
// Environment: sysctrl_unit_env
// Purpose: UVM Environment for SysCtrl IP Unit Verification
// =============================================================================

`ifndef SYSCTRL_UNIT_ENV_SV
`define SYSCTRL_UNIT_ENV_SV

class sysctrl_unit_env extends uvm_env;
    `uvm_component_utils(sysctrl_unit_env)

    apb_agent               apb_ag;
    virtual apb_if#(32, 32) apb_vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        apb_ag = apb_agent#(32, 32)::type_id::create("apb_ag", this);
        void'(uvm_config_db#(virtual apb_if#(32, 32))::get(this, "", "apb_vif", apb_vif));
    endfunction

endclass : sysctrl_unit_env

`endif // SYSCTRL_UNIT_ENV_SV

