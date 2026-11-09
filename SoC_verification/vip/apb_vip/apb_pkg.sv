// =============================================================================
// Package: apb_pkg
// Purpose: AMBA 3 APB Master UVM VIP Package
// =============================================================================

`ifndef APB_PKG_SV
`define APB_PKG_SV

package apb_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "apb_transfer.sv"
    `include "apb_config.sv"
    `include "apb_driver.sv"
    `include "apb_monitor.sv"
    `include "apb_sequencer.sv"
    `include "apb_agent.sv"
    `include "apb_base_seq.sv"

endpackage : apb_pkg

`endif // APB_PKG_SV

