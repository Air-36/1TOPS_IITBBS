// =============================================================================
// Component: ahb_sequencer
// Purpose: Sequencer for AHB-Lite Master VIP
// =============================================================================

`ifndef AHB_SEQUENCER_SV
`define AHB_SEQUENCER_SV

class ahb_sequencer #(parameter ADDR_WIDTH = 32, parameter DATA_WIDTH = 32)
    extends uvm_sequencer #(ahb_transfer #(ADDR_WIDTH, DATA_WIDTH));

    `uvm_component_param_utils(ahb_sequencer #(ADDR_WIDTH, DATA_WIDTH))

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

endclass : ahb_sequencer

`endif // AHB_SEQUENCER_SV

