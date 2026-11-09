// =============================================================================
// Class: apb_config
// Purpose: Configuration object for APB Master VIP
// =============================================================================

`ifndef APB_CONFIG_SV
`define APB_CONFIG_SV

class apb_config extends uvm_object;

    uvm_active_passive_enum is_active = UVM_ACTIVE;
    bit has_functional_coverage       = 1;

    `uvm_object_utils_begin(apb_config)
        `uvm_field_enum(uvm_active_passive_enum, is_active, UVM_ALL_ON)
        `uvm_field_int(has_functional_coverage,             UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "apb_config");
        super.new(name);
    endfunction

endclass : apb_config

`endif // APB_CONFIG_SV

