// =============================================================================
// Package: soc_full_env_pkg
// =============================================================================

`ifndef SOC_FULL_ENV_PKG_SV
`define SOC_FULL_ENV_PKG_SV

package soc_full_env_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import gpio_pkg::*;
    import irq_pkg::*;
    import uart_pkg::*;

    `include "soc_full_coverage.sv"
    `include "soc_full_scoreboard.sv"
    `include "soc_full_env.sv"
endpackage : soc_full_env_pkg

`endif

