// =============================================================================
// Component: gpio_sequencer
// Purpose: Sequencer for GPIO VIP
// =============================================================================

`ifndef GPIO_SEQUENCER_SV
`define GPIO_SEQUENCER_SV

class gpio_sequencer extends uvm_sequencer #(gpio_item);

    `uvm_component_utils(gpio_sequencer)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

endclass : gpio_sequencer

`endif // GPIO_SEQUENCER_SV

