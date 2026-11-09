// =============================================================================
// Sequence Item: irq_item
// Purpose: Captures Interrupt Events & Transitions
// =============================================================================

`ifndef IRQ_ITEM_SV
`define IRQ_ITEM_SV

class irq_item extends uvm_sequence_item;

    typedef enum {
        IRQ_NONE,
        IRQ_CLINT_TIMER,
        IRQ_CLINT_SW,
        IRQ_PLIC_MEXT,
        IRQ_PERIPH_UART,
        IRQ_PERIPH_GPIO,
        IRQ_PERIPH_SPI
    } irq_source_e;

    irq_source_e source;
    bit          asserted;      // 1 = asserted (rose), 0 = deasserted (fell)
    time         timestamp;

    // Snapshot of all lines
    bit          mtimer_int;
    bit          msw_int;
    bit          mext_int;
    bit          uart_intr;
    bit          gpio_intr;
    bit          spi_intr;

    `uvm_object_utils_begin(irq_item)
        `uvm_field_enum(irq_source_e, source, UVM_ALL_ON)
        `uvm_field_int(asserted,              UVM_ALL_ON)
        `uvm_field_int(mtimer_int,            UVM_ALL_ON)
        `uvm_field_int(msw_int,               UVM_ALL_ON)
        `uvm_field_int(mext_int,              UVM_ALL_ON)
        `uvm_field_int(uart_intr,             UVM_ALL_ON)
        `uvm_field_int(gpio_intr,             UVM_ALL_ON)
        `uvm_field_int(spi_intr,              UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "irq_item");
        super.new(name);
        source    = IRQ_NONE;
        asserted  = 0;
        timestamp = $time;
    endfunction

endclass : irq_item

`endif // IRQ_ITEM_SV

