// =============================================================================
// Sequences: gpio_sequences
// Purpose: Stimulus sequences for GPIO VIP
// =============================================================================

`ifndef GPIO_SEQUENCES_SV
`define GPIO_SEQUENCES_SV

class gpio_base_seq extends uvm_sequence #(gpio_item);

    `uvm_object_utils(gpio_base_seq)

    function new(string name = "gpio_base_seq");
        super.new(name);
    endfunction

    virtual task drive_pattern(bit [31:0] pattern, bit [31:0] mask = 32'hFFFF_FFFF, int cycles = 2);
        gpio_item item;
        `uvm_create(item)
        item.op          = gpio_item::GPIO_DRIVE_PATTERN;
        item.drive_val   = pattern;
        item.pin_mask    = mask;
        item.hold_cycles = cycles;
        `uvm_send(item)
    endtask

    virtual task trigger_rising_edge(int pin_idx, int cycles = 2);
        bit [31:0] mask = (1 << pin_idx);
        // Step 1: ensure low
        drive_pattern(32'd0, mask, cycles);
        // Step 2: transition to high
        drive_pattern(mask, mask, cycles);
    endtask

    virtual task trigger_falling_edge(int pin_idx, int cycles = 2);
        bit [31:0] mask = (1 << pin_idx);
        // Step 1: ensure high
        drive_pattern(mask, mask, cycles);
        // Step 2: transition to low
        drive_pattern(32'd0, mask, cycles);
    endtask

    virtual task pulse_pin(int pin_idx, int cycles = 2);
        gpio_item item;
        `uvm_create(item)
        item.op          = gpio_item::GPIO_PULSE_PIN;
        item.drive_val   = (1 << pin_idx);
        item.pin_mask    = (1 << pin_idx);
        item.hold_cycles = cycles;
        `uvm_send(item)
    endtask

    virtual task body();
    endtask

endclass : gpio_base_seq

`endif // GPIO_SEQUENCES_SV

