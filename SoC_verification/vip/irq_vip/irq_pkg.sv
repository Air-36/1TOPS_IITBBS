// =============================================================================
// Package: irq_pkg
// Purpose: UVM Interrupt VIP Package
// =============================================================================

`ifndef IRQ_PKG_SV
`define IRQ_PKG_SV

package irq_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "irq_item.sv"
    `include "irq_monitor.sv"
    `include "irq_agent.sv"

endpackage : irq_pkg

`endif // IRQ_PKG_SV

