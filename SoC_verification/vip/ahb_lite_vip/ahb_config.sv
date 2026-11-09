// =============================================================================
// Class: ahb_config
// Purpose: Configuration object for AHB-Lite Master VIP
// =============================================================================

`ifndef AHB_CONFIG_SV
`define AHB_CONFIG_SV

class ahb_config extends uvm_object;

    uvm_active_passive_enum is_active = UVM_ACTIVE;
    bit has_functional_coverage       = 1;
    bit has_protocol_checks           = 1;

    `uvm_object_utils_begin(ahb_config)
        `uvm_field_enum(uvm_active_passive_enum, is_active, UVM_ALL_ON)
        `uvm_field_int(has_functional_coverage,             UVM_ALL_ON)
        `uvm_field_int(has_protocol_checks,                 UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "ahb_config");
        super.new(name);
    endfunction

endclass : ahb_config

`endif // AHB_CONFIG_SV

