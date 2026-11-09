// =============================================================================
// Component: gpio_monitor
// Purpose: Observes GPIO Inputs, Outputs, Output Enables, and Interrupt Line
// =============================================================================

`ifndef GPIO_MONITOR_SV
`define GPIO_MONITOR_SV

class gpio_monitor extends uvm_monitor;

    `uvm_component_utils(gpio_monitor)

    virtual gpio_if             vif;
    uvm_analysis_port #(gpio_item) item_collected_port;
    gpio_config                 cfg;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        item_collected_port = new("item_collected_port", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual gpio_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        bit [31:0] prev_in   = '0;
        bit [31:0] prev_out  = '0;
        bit [31:0] prev_en   = '0;
        bit        prev_intr = 1'b0;
        gpio_item  item;

        @(posedge vif.rst_n);

        forever begin
            @(vif.mon_cb);

            if ((vif.mon_cb.gpio_in   !== prev_in)  ||
                (vif.mon_cb.gpio_out  !== prev_out) ||
                (vif.mon_cb.gpio_en   !== prev_en)  ||
                (vif.mon_cb.gpio_intr !== prev_intr)) begin

                item = gpio_item::type_id::create("gpio_mon_item");
                item.sampled_in   = vif.mon_cb.gpio_in;
                item.sampled_out  = vif.mon_cb.gpio_out;
                item.sampled_en   = vif.mon_cb.gpio_en;
                item.sampled_intr = vif.mon_cb.gpio_intr;

                prev_in   = vif.mon_cb.gpio_in;
                prev_out  = vif.mon_cb.gpio_out;
                prev_en   = vif.mon_cb.gpio_en;
                prev_intr = vif.mon_cb.gpio_intr;

                item_collected_port.write(item);
            end
        end
    endtask

endclass : gpio_monitor

`endif // GPIO_MONITOR_SV

