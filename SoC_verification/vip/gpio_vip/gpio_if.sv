// =============================================================================
// Interface: gpio_if
// Purpose: GPIO VIP SystemVerilog Interface
// =============================================================================

`ifndef GPIO_IF_SV
`define GPIO_IF_SV

interface gpio_if (
    input logic clk,
    input logic rst_n
);

    logic [31:0] gpio_in;   // Testbench drives, DUT reads (GPIOIN)
    logic [31:0] gpio_out;  // DUT drives, Testbench monitors (GPIOOUT)
    logic [31:0] gpio_en;   // DUT drives, Testbench monitors (GPIOEN)
    logic        gpio_intr; // DUT drives, Testbench monitors (GPIOIntr)

    // Driver Clocking Block
    clocking drv_cb @(posedge clk);
        default input #1step output #1ns;
        output gpio_in;
        input  gpio_out, gpio_en, gpio_intr;
    endclocking

    // Monitor Clocking Block
    clocking mon_cb @(posedge clk);
        default input #1step;
        input gpio_in, gpio_out, gpio_en, gpio_intr;
    endclocking

    modport driver  (clocking drv_cb, input rst_n);
    modport monitor (clocking mon_cb, input rst_n);

endinterface : gpio_if

`endif // GPIO_IF_SV

