// =============================================================================
// Component: irq_monitor
// Purpose: Monitors all Interrupt Lines and emits irq_item events on transitions
// =============================================================================

`ifndef IRQ_MONITOR_SV
`define IRQ_MONITOR_SV

class irq_monitor extends uvm_monitor;

    `uvm_component_utils(irq_monitor)

    virtual irq_if vif;
    uvm_analysis_port #(irq_item) item_collected_port;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        item_collected_port = new("item_collected_port", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual irq_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        bit prev_mtimer = 0;
        bit prev_msw    = 0;
        bit prev_mext   = 0;
        bit prev_uart   = 0;
        bit prev_gpio   = 0;
        bit prev_spi    = 0;

        @(posedge vif.rst_n);

        forever begin
            @(vif.mon_cb);

            check_transition(vif.mon_cb.mtimer_int, prev_mtimer, irq_item::IRQ_CLINT_TIMER);
            check_transition(vif.mon_cb.msw_int,    prev_msw,    irq_item::IRQ_CLINT_SW);
            check_transition(vif.mon_cb.mext_int,   prev_mext,   irq_item::IRQ_PLIC_MEXT);
            check_transition(vif.mon_cb.uart_intr,  prev_uart,   irq_item::IRQ_PERIPH_UART);
            check_transition(vif.mon_cb.gpio_intr,  prev_gpio,   irq_item::IRQ_PERIPH_GPIO);
            check_transition(vif.mon_cb.spi_intr,   prev_spi,    irq_item::IRQ_PERIPH_SPI);
        end
    endtask

    virtual function void check_transition(input bit current_val, ref bit prev_val, input irq_item::irq_source_e src);
        if (current_val !== prev_val) begin
            irq_item tr = irq_item::type_id::create("irq_event");
            tr.source     = src;
            tr.asserted   = current_val;
            tr.timestamp  = $time;
            tr.mtimer_int = vif.mon_cb.mtimer_int;
            tr.msw_int    = vif.mon_cb.msw_int;
            tr.mext_int   = vif.mon_cb.mext_int;
            tr.uart_intr  = vif.mon_cb.uart_intr;
            tr.gpio_intr  = vif.mon_cb.gpio_intr;
            tr.spi_intr   = vif.mon_cb.spi_intr;

            `uvm_info("IRQ_CHANGE", $sformatf("Interrupt %s %s at time %0t (MTimer:%b, MSw:%b, MExt:%b, GPIO:%b, UART:%b, SPI:%b)",
                                             src.name(), current_val ? "ASSERTED" : "DEASSERTED", $time,
                                             tr.mtimer_int, tr.msw_int, tr.mext_int, tr.gpio_intr, tr.uart_intr, tr.spi_intr), UVM_MEDIUM)

            item_collected_port.write(tr);
            prev_val = current_val;
        end
    endfunction

endclass : irq_monitor

`endif // IRQ_MONITOR_SV
