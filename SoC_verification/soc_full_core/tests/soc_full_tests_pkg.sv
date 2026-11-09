// =============================================================================
// Package: soc_full_tests_pkg
// =============================================================================

`ifndef SOC_FULL_TESTS_PKG_SV
`define SOC_FULL_TESTS_PKG_SV

package soc_full_tests_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import gpio_pkg::*;
    import irq_pkg::*;
    import uart_pkg::*;
    import soc_full_env_pkg::*;

    `include "soc_full_base_test.sv"
    `include "soc_full_boot_test.sv"
    `include "soc_full_bringup_test.sv"
    `include "soc_full_gpio_test.sv"
    `include "soc_full_uart_test.sv"
    `include "soc_full_spi_test.sv"
    `include "soc_full_clint_test.sv"
    `include "soc_full_plic_test.sv"
    `include "soc_full_stress_test.sv"
    `include "soc_full_suite_test.sv"
endpackage : soc_full_tests_pkg

`endif

