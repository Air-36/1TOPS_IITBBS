// =============================================================================
// Package: uart_pkg
// =============================================================================

`ifndef UART_PKG_SV
`define UART_PKG_SV

package uart_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "uart_item.sv"
    `include "uart_monitor.sv"
    `include "uart_agent.sv"
endpackage : uart_pkg

`endif

