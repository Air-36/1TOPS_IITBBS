// =============================================================================
// Class: gpio_config
// Purpose: Configuration object for GPIO VIP
// =============================================================================

`ifndef GPIO_CONFIG_SV
`define GPIO_CONFIG_SV

class gpio_config extends uvm_object;

    uvm_active_passive_enum is_active = UVM_ACTIVE;
    bit has_functional_coverage       = 1;
    bit pullup_enabled                = 0;

    `uvm_object_utils_begin(gpio_config)
        `uvm_field_enum(uvm_active_passive_enum, is_active, UVM_ALL_ON)
        `uvm_field_int(has_functional_coverage,             UVM_ALL_ON)
        `uvm_field_int(pullup_enabled,                      UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "gpio_config");
        super.new(name);
    endfunction

endclass : gpio_config

`endif // GPIO_CONFIG_SV

