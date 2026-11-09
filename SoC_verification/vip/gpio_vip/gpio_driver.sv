// =============================================================================
// Component: gpio_driver
// Purpose: Drives GPIO Inputs into the DUT
// =============================================================================

`ifndef GPIO_DRIVER_SV
`define GPIO_DRIVER_SV

class gpio_driver extends uvm_driver #(gpio_item);

    `uvm_component_utils(gpio_driver)

    virtual gpio_if vif;
    gpio_config     cfg;
    bit [31:0]      current_in_val;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        current_in_val = 32'd0;
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual gpio_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        vif.drv_cb.gpio_in <= 32'd0;
        current_in_val <= 32'd0;

        @(posedge vif.rst_n);
        @(vif.drv_cb);

        forever begin
            seq_item_port.get_next_item(req);
            drive_item(req);
            seq_item_port.item_done();
        end
    endtask

    virtual task drive_item(gpio_item item);
        case (item.op)
            gpio_item::GPIO_DRIVE_PATTERN: begin
                current_in_val = (current_in_val & ~item.pin_mask) | (item.drive_val & item.pin_mask);
                vif.drv_cb.gpio_in <= current_in_val;
                repeat (item.hold_cycles) @(vif.drv_cb);
            end

            gpio_item::GPIO_PULSE_PIN: begin
                // Drive pulsed value for hold_cycles, then restore
                bit [31:0] orig_val = current_in_val;
                current_in_val = (current_in_val & ~item.pin_mask) | (item.drive_val & item.pin_mask);
                vif.drv_cb.gpio_in <= current_in_val;
                repeat (item.hold_cycles) @(vif.drv_cb);
                current_in_val = orig_val;
                vif.drv_cb.gpio_in <= current_in_val;
                @(vif.drv_cb);
            end

            gpio_item::GPIO_TOGGLE_PIN: begin
                current_in_val ^= item.pin_mask;
                vif.drv_cb.gpio_in <= current_in_val;
                repeat (item.hold_cycles) @(vif.drv_cb);
            end

            gpio_item::GPIO_SAMPLE: begin
                @(vif.drv_cb);
            end
        endcase

        item.sampled_in   = current_in_val;
        item.sampled_out  = vif.drv_cb.gpio_out;
        item.sampled_en   = vif.drv_cb.gpio_en;
        item.sampled_intr = vif.drv_cb.gpio_intr;
    endtask

endclass : gpio_driver

`endif // GPIO_DRIVER_SV
