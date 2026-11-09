// =============================================================================
// Package: soc_coreless_env_pkg
// Purpose: Coreless SoC Environment Package
// =============================================================================

`ifndef SOC_CORELESS_ENV_PKG_SV
`define SOC_CORELESS_ENV_PKG_SV

package soc_coreless_env_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import ahb_lite_pkg::*;
    import apb_pkg::*;
    import gpio_pkg::*;
    import irq_pkg::*;

    `include "soc_ral_model.sv"
    `include "soc_scoreboard.sv"
    `include "soc_coverage.sv"
    `include "soc_coreless_env.sv"

endpackage : soc_coreless_env_pkg

`endif // SOC_CORELESS_ENV_PKG_SV

