// =============================================================================
// Package: gpio_pkg
// Purpose: UVM GPIO VIP Package
// =============================================================================

`ifndef GPIO_PKG_SV
`define GPIO_PKG_SV

package gpio_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "gpio_item.sv"
    `include "gpio_config.sv"
    `include "gpio_driver.sv"
    `include "gpio_monitor.sv"
    `include "gpio_sequencer.sv"
    `include "gpio_agent.sv"
    `include "gpio_sequences.sv"

endpackage : gpio_pkg

`endif // GPIO_PKG_SV

