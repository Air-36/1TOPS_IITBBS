// =============================================================================
// Environment: multiplier_unit_env
// Purpose: UVM Environment for Multiplier AHB Slave Unit Verification
// =============================================================================

`ifndef MULTIPLIER_UNIT_ENV_SV
`define MULTIPLIER_UNIT_ENV_SV

class multiplier_unit_env extends uvm_env;
    `uvm_component_utils(multiplier_unit_env)

    ahb_agent#(32, 32)            ahb_ag;
    virtual ahb_lite_if#(32, 32)  ahb_vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ahb_ag = ahb_agent#(32, 32)::type_id::create("ahb_ag", this);
        void'(uvm_config_db#(virtual ahb_lite_if#(32, 32))::get(this, "", "ahb_vif", ahb_vif));
    endfunction

endclass : multiplier_unit_env

`endif // MULTIPLIER_UNIT_ENV_SV

