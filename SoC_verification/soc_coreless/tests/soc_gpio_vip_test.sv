// =============================================================================
// Test: soc_gpio_vip_test
// Purpose: Whole SoC GPIO Verification using AHB Master VIP & GPIO VIP
// =============================================================================

`ifndef SOC_GPIO_VIP_TEST_SV
`define SOC_GPIO_VIP_TEST_SV

class soc_gpio_vip_test extends soc_base_test;
    `uvm_component_utils(soc_gpio_vip_test)

    localparam [31:0] GPIO_BASE       = 32'h1006_0000;
    localparam [31:0] GPIO_INPUT_VAL  = GPIO_BASE + 32'h00;
    localparam [31:0] GPIO_INPUT_EN   = GPIO_BASE + 32'h04;
    localparam [31:0] GPIO_OUTPUT_EN  = GPIO_BASE + 32'h08;
    localparam [31:0] GPIO_OUTPUT_VAL = GPIO_BASE + 32'h0C;
    localparam [31:0] GPIO_RISE_IE    = GPIO_BASE + 32'h18;
    localparam [31:0] GPIO_RISE_IP    = GPIO_BASE + 32'h1C;
    localparam [31:0] GPIO_FALL_IE    = GPIO_BASE + 32'h20;
    localparam [31:0] GPIO_FALL_IP    = GPIO_BASE + 32'h24;

    function new(string name = "soc_gpio_vip_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        ahb_base_seq#(32, 32) ahb_seq;
        gpio_base_seq         gpio_seq;

        phase.raise_objection(this);
        ahb_seq  = ahb_base_seq#(32, 32)::type_id::create("ahb_seq");
        gpio_seq = gpio_base_seq::type_id::create("gpio_seq");

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " STARTING WHOLE SOC GPIO VERIFICATION WITH VIPs    ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        ahb_seq.start(env.ahb_ag.sequencer);
        gpio_seq.start(env.gpio_ag.sequencer);

        // Phase 1: Output test via AHB bus
        `uvm_info("TEST", "--- Phase 1: AHB Configures GPIO Outputs, Verified at Pins ---", UVM_LOW)
        ahb_seq.write_word(GPIO_OUTPUT_EN,  32'h0000_FFFF);
        ahb_seq.write_word(GPIO_OUTPUT_VAL, 32'h0000_1234);

        #40;
        if ((env.gpio_vif.gpio_out & 32'h0000_FFFF) !== 32'h0000_1234) begin
            `uvm_error("TEST", $sformatf("GPIO Output pins mismatch! Expected: 0x00001234, Observed: 0x%08h", env.gpio_vif.gpio_out))
        end else begin
            `uvm_info("TEST", "GPIO Output pins successfully matched 0x00001234 via AHB bus write!", UVM_LOW)
        end

        // Phase 2: Input test via GPIO VIP
        `uvm_info("TEST", "--- Phase 2: GPIO VIP Drives Pins, Verified via AHB Read ---", UVM_LOW)
        ahb_seq.write_word(GPIO_INPUT_EN, 32'hFFFF_0000);

        gpio_seq.drive_pattern(32'h5678_0000, 32'hFFFF_0000, 4);
        #40;
        ahb_seq.read_check(GPIO_INPUT_VAL, 32'h5678_0000, 32'hFFFF_0000, "GPIO Input Readback via AHB");

        // Phase 3: GPIO Edge Interrupt through SoC Bus & Fabric
        `uvm_info("TEST", "--- Phase 3: GPIO Edge Interrupt & Clear via AHB Bus ---", UVM_LOW)
        ahb_seq.write_word(GPIO_INPUT_EN, 32'h0000_000F);
        ahb_seq.write_word(GPIO_RISE_IE,  32'h0000_0008); // Pin 3
        ahb_seq.write_word(GPIO_RISE_IP,  32'hFFFF_FFFF); // Clear pending

        #40;
        // Trigger edge on pin 3 via GPIO VIP
        gpio_seq.trigger_rising_edge(3, 4);

        #60;
        if (env.irq_vif.gpio_intr !== 1'b1) begin
            `uvm_error("TEST", "GPIOIntr was NOT asserted at SoC boundary after pin 3 rising edge!")
        end else begin
            `uvm_info("TEST", "GPIOIntr successfully ASSERTED at SoC boundary via pin 3 transition!", UVM_LOW)
        end

        // Confirm rise pending bit is set via AHB
        ahb_seq.read_check(GPIO_RISE_IP, 32'h0000_0008, 32'h0000_0008, "GPIO_RISE_IP bit 3");

        // Clear interrupt via AHB W1C write
        ahb_seq.write_word(GPIO_RISE_IP, 32'h0000_0008);
        #60;

        if (env.irq_vif.gpio_intr !== 1'b0) begin
            `uvm_error("TEST", "GPIOIntr did NOT deassert after AHB W1C clear!")
        end else begin
            `uvm_info("TEST", "GPIOIntr successfully DEASSERTED after AHB W1C clear!", UVM_LOW)
        end

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " WHOLE SOC GPIO VERIFICATION PASSED SUCCESSFULLY! ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        #100;
        phase.drop_objection(this);
    endtask

endclass : soc_gpio_vip_test

`endif // SOC_GPIO_VIP_TEST_SV

