// =============================================================================
// Component: apb_sequencer
// Purpose: Sequencer for APB Master VIP
// =============================================================================

`ifndef APB_SEQUENCER_SV
`define APB_SEQUENCER_SV

class apb_sequencer #(parameter ADDR_WIDTH = 32, parameter DATA_WIDTH = 32)
    extends uvm_sequencer #(apb_transfer #(ADDR_WIDTH, DATA_WIDTH));

    `uvm_component_param_utils(apb_sequencer #(ADDR_WIDTH, DATA_WIDTH))

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

endclass : apb_sequencer

`endif // APB_SEQUENCER_SV

