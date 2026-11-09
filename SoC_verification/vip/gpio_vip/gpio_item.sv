// =============================================================================
// Sequence Item: gpio_item
// Purpose: Transaction Item for GPIO VIP
// =============================================================================

`ifndef GPIO_ITEM_SV
`define GPIO_ITEM_SV

class gpio_item extends uvm_sequence_item;

    typedef enum {
        GPIO_DRIVE_PATTERN,
        GPIO_PULSE_PIN,
        GPIO_TOGGLE_PIN,
        GPIO_SAMPLE
    } gpio_op_e;

    rand gpio_op_e    op;
    rand bit [31:0]   drive_val;
    rand bit [31:0]   pin_mask;
    rand int unsigned hold_cycles;

    // Sampled / Monitored values
    bit [31:0]        sampled_in;
    bit [31:0]        sampled_out;
    bit [31:0]        sampled_en;
    bit               sampled_intr;

    `uvm_object_utils_begin(gpio_item)
        `uvm_field_enum(gpio_op_e, op,         UVM_ALL_ON)
        `uvm_field_int(drive_val,              UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(pin_mask,               UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(hold_cycles,            UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(sampled_in,             UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(sampled_out,            UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(sampled_en,             UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(sampled_intr,           UVM_ALL_ON)
    `uvm_object_utils_end

    constraint c_default {
        pin_mask == 32'hFFFF_FFFF;
        hold_cycles inside {[1:20]};
        op inside {GPIO_DRIVE_PATTERN, GPIO_PULSE_PIN, GPIO_TOGGLE_PIN};
    }

    function new(string name = "gpio_item");
        super.new(name);
        op          = GPIO_DRIVE_PATTERN;
        drive_val   = 32'd0;
        pin_mask    = 32'hFFFF_FFFF;
        hold_cycles = 1;
    endfunction

endclass : gpio_item

`endif // GPIO_ITEM_SV

