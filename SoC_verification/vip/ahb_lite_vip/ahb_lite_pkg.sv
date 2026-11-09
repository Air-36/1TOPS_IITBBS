// =============================================================================
// Package: ahb_lite_pkg
// Purpose: AMBA 3 AHB-Lite Master UVM VIP Package
// =============================================================================

`ifndef AHB_LITE_PKG_SV
`define AHB_LITE_PKG_SV

package ahb_lite_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "ahb_transfer.sv"
    `include "ahb_config.sv"
    `include "ahb_driver.sv"
    `include "ahb_monitor.sv"
    `include "ahb_sequencer.sv"
    `include "ahb_agent.sv"
    `include "ahb_base_seq.sv"

endpackage : ahb_lite_pkg

`endif // AHB_LITE_PKG_SV

