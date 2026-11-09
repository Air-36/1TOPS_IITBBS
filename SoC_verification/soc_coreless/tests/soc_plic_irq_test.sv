// =============================================================================
// Test: soc_plic_irq_test
// Purpose: Whole SoC End-to-End Peripheral-to-PLIC-to-Core Interrupt Path
// =============================================================================

`ifndef SOC_PLIC_IRQ_TEST_SV
`define SOC_PLIC_IRQ_TEST_SV

class soc_plic_irq_test extends soc_base_test;
    `uvm_component_utils(soc_plic_irq_test)

    localparam [31:0] PLIC_BASE           = 32'h0C00_0000;
    localparam [31:0] PLIC_PRIORITY_SRC1  = PLIC_BASE + 32'h000004;
    localparam [31:0] PLIC_PRIORITY_SRC2  = PLIC_BASE + 32'h000008; // GPIO is Source 2
    localparam [31:0] PLIC_PENDING        = PLIC_BASE + 32'h001000;
    localparam [31:0] PLIC_ENABLE         = PLIC_BASE + 32'h002000;
    localparam [31:0] PLIC_THRESHOLD      = PLIC_BASE + 32'h200000;
    localparam [31:0] PLIC_CLAIM          = PLIC_BASE + 32'h200004;

    localparam [31:0] GPIO_BASE           = 32'h1006_0000;
    localparam [31:0] GPIO_INPUT_EN       = GPIO_BASE + 32'h04;
    localparam [31:0] GPIO_RISE_IE        = GPIO_BASE + 32'h18;
    localparam [31:0] GPIO_RISE_IP        = GPIO_BASE + 32'h1C;

    function new(string name = "soc_plic_irq_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        ahb_base_seq#(32, 32) ahb_seq;
        gpio_base_seq         gpio_seq;

        phase.raise_objection(this);
        ahb_seq  = ahb_base_seq#(32, 32)::type_id::create("ahb_seq");
        gpio_seq = gpio_base_seq::type_id::create("gpio_seq");

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " STARTING WHOLE SOC PLIC IRQ VERIFICATION TEST     ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        ahb_seq.start(env.ahb_ag.sequencer);
        gpio_seq.start(env.gpio_ag.sequencer);

        // Phase 1: Setup PLIC Registers via AHB
        `uvm_info("TEST", "--- Phase 1: Configuring PLIC via AHB Bus ---", UVM_LOW)
        ahb_seq.write_word(PLIC_PRIORITY_SRC2, 32'd4); // Priority 4 for GPIO
        ahb_seq.write_word(PLIC_THRESHOLD,     32'd0); // Threshold 0
        ahb_seq.write_word(PLIC_ENABLE,        32'd4); // Enable source 2 (GPIO)

        // Phase 2: Setup GPIO Peripheral for Rising Edge Interrupt on Pin 2
        `uvm_info("TEST", "--- Phase 2: Configuring GPIO Peripheral via AHB Bus ---", UVM_LOW)
        ahb_seq.write_word(GPIO_INPUT_EN, 32'h0000_000F);
        ahb_seq.write_word(GPIO_RISE_IE,  32'h0000_0004); // Enable Pin 2
        ahb_seq.write_word(GPIO_RISE_IP,  32'hFFFF_FFFF); // Clear pending

        #40;
        // Verify MExtInt is 0 before event
        if (env.irq_vif.mext_int !== 1'b0) begin
            `uvm_error("TEST", "MExtInt asserted before interrupt event occurred!")
        end

        // Phase 3: Trigger GPIO Edge via GPIO VIP
        `uvm_info("TEST", "--- Phase 3: GPIO VIP Triggers Edge -> PLIC -> MExtInt ---", UVM_LOW)
        gpio_seq.trigger_rising_edge(2, 4);

        #80;
        // Verify GPIOIntr is asserted
        if (env.irq_vif.gpio_intr !== 1'b1) begin
            `uvm_error("TEST", "GPIOIntr was NOT asserted after rising edge on pin 2!")
        end else begin
            `uvm_info("TEST", "GPIOIntr successfully ASSERTED!", UVM_LOW)
        end

        // Verify MExtInt is asserted at SoC top boundary
        if (env.irq_vif.mext_int !== 1'b1) begin
            `uvm_error("TEST", "MExtInt was NOT asserted at SoC boundary by PLIC!")
        end else begin
            `uvm_info("TEST", "MExtInt successfully ASSERTED at SoC boundary via PLIC routing!", UVM_LOW)
        end

        // Phase 4: Claim Interrupt via AHB Bus
        `uvm_info("TEST", "--- Phase 4: Claiming Interrupt from PLIC via AHB Bus ---", UVM_LOW)
        ahb_seq.read_check(PLIC_CLAIM, 32'd2, 32'h7, "Claimed Source ID == 2 (GPIO)");

        // Phase 5: Clear Original GPIO Event and Verify Deassertion
        `uvm_info("TEST", "--- Phase 5: Clearing Peripheral Event & Verifying Deassertion ---", UVM_LOW)
        ahb_seq.write_word(GPIO_RISE_IP, 32'h0000_0004); // Clear pin 2 rise IP
        #80;

        if (env.irq_vif.gpio_intr !== 1'b0) begin
            `uvm_error("TEST", "GPIOIntr did not deassert after W1C clear!")
        end else begin
            `uvm_info("TEST", "GPIOIntr successfully DEASSERTED after clear!", UVM_LOW)
        end

        if (env.irq_vif.mext_int !== 1'b0) begin
            `uvm_error("TEST", "MExtInt did not deassert at SoC boundary after source deassertion!")
        end else begin
            `uvm_info("TEST", "MExtInt successfully DEASSERTED at SoC boundary!", UVM_LOW)
        end

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " WHOLE SOC PLIC IRQ VERIFICATION PASSED!          ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        #100;
        phase.drop_objection(this);
    endtask

endclass : soc_plic_irq_test

`endif // SOC_PLIC_IRQ_TEST_SV

