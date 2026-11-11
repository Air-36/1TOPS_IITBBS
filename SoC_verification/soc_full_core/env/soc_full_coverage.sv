// =============================================================================
// Class: soc_full_coverage
// Purpose: Functional Coverage Collector for Full 1TOPS RISC-V SoC
// =============================================================================

`ifndef SOC_FULL_COVERAGE_SV
`define SOC_FULL_COVERAGE_SV

class soc_full_coverage extends uvm_subscriber #(gpio_item);
    `uvm_component_utils(soc_full_coverage)

    // Variables sampled in covergroups
    bit [31:0] sample_gpio_in;
    bit [31:0] sample_gpio_out;
    bit [15:0] sample_irq_mask;
    bit [ 1:0] sample_boot_mode;
    bit [ 7:0] sample_uart_char;

    // 1. Boot Mode Coverage
    covergroup cg_boot_modes;
        option.per_instance = 1;
        cp_boot: coverpoint sample_boot_mode {
            bins mode_internal_rom = {2'd0};
            bins mode_spi_flash    = {2'd1};
            bins mode_direct_iram  = {2'd2};
        }
    endgroup

    // 2. Interrupt Routing Coverage
    covergroup cg_interrupts;
        option.per_instance = 1;
        cp_timer_irq: coverpoint sample_irq_mask[0] {
            bins inactive = {1'b0};
            bins active   = {1'b1};
        }
        cp_sw_irq: coverpoint sample_irq_mask[1] {
            bins inactive = {1'b0};
            bins active   = {1'b1};
        }
        cp_plic_ext_irq: coverpoint sample_irq_mask[2] {
            bins inactive = {1'b0};
            bins active   = {1'b1};
        }
        cp_gpio_irq: coverpoint sample_irq_mask[3] {
            bins inactive = {1'b0};
            bins active   = {1'b1};
        }
    endgroup

    // 3. GPIO Pin Coverage
    covergroup cg_gpio;
        option.per_instance = 1;
        cp_gpio_out: coverpoint sample_gpio_out[15:0] {
            bins bin_a5a5 = {16'hA5A5};
            bins bin_5a5a = {16'h5A5A};
            bins bin_cafe = {16'hCAFE};
            bins bin_beef = {16'hBEEF};
        }
        cp_gpio_in: coverpoint sample_gpio_in[31:16] {
            bins in_5678 = {16'h5678};
            bins in_1234 = {16'h1234};
        }
    endgroup

    // 4. UART Character Coverage
    covergroup cg_uart;
        option.per_instance = 1;
        cp_uart_char: coverpoint sample_uart_char {
            bins ascii_printable = {[8'd32 : 8'd126]};
            bins newline         = {8'd10};
        }
    endgroup

    function new(string name = "soc_full_coverage", uvm_component parent = null);
        super.new(name, parent);
        cg_boot_modes = new();
        cg_interrupts = new();
        cg_gpio       = new();
        cg_uart       = new();
    endfunction

    // Sample from GPIO subscriber
    virtual function void write(gpio_item t);
        sample_gpio_in  = t.sampled_in;
        sample_gpio_out = t.sampled_out;
        cg_gpio.sample();
    endfunction

    // Sample Interrupts
    virtual function void sample_irq(bit [15:0] irq_mask);
        sample_irq_mask = irq_mask;
        cg_interrupts.sample();
    endfunction

    // Sample Boot Mode
    virtual function void sample_boot(bit [1:0] mode);
        sample_boot_mode = mode;
        cg_boot_modes.sample();
    endfunction

    // Sample UART Character
    virtual function void sample_uart(bit [7:0] ch);
        sample_uart_char = ch;
        cg_uart.sample();
    endfunction

endclass : soc_full_coverage

`endif

