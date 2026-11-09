// =============================================================================
// Package: soc_test_pkg
// Purpose: Coreless SoC Verification Tests Package
// =============================================================================

`ifndef SOC_TEST_PKG_SV
`define SOC_TEST_PKG_SV

package soc_test_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import ahb_lite_pkg::*;
    import apb_pkg::*;
    import gpio_pkg::*;
    import irq_pkg::*;
    import soc_coreless_env_pkg::*;

    `include "soc_base_test.sv"
    `include "soc_reset_test.sv"
    `include "soc_ahb_single_rw_test.sv"
    `include "soc_ahb_address_decode_test.sv"
    `include "soc_gpio_vip_test.sv"
    `include "soc_clint_irq_test.sv"
    `include "soc_plic_irq_test.sv"
    `include "soc_sysctrl_remap_test.sv"
    `include "soc_concurrency_stress_test.sv"
    `include "soc_all_suite_test.sv"

endpackage : soc_test_pkg

`endif // SOC_TEST_PKG_SV

