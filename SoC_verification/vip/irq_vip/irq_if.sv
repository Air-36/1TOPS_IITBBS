// =============================================================================
// Interface: irq_if
// Purpose: Interrupt Observation Interface for CLINT, PLIC, and Peripherals
// =============================================================================

`ifndef IRQ_IF_SV
`define IRQ_IF_SV

interface irq_if (
    input logic clk,
    input logic rst_n
);

    // CLINT Interrupts
    logic mtimer_int;
    logic msw_int;

    // PLIC Interrupts
    logic mext_int;
    logic sext_int;

    // Peripheral Interrupt Sources
    logic uart_intr;
    logic gpio_intr;
    logic spi_intr;
    logic sdc_intr;

    // Monitor Clocking Block
    clocking mon_cb @(posedge clk);
        default input #1step;
        input mtimer_int, msw_int, mext_int, sext_int;
        input uart_intr, gpio_intr, spi_intr, sdc_intr;
    endclocking

    modport monitor (clocking mon_cb, input rst_n);

endinterface : irq_if

`endif // IRQ_IF_SV

