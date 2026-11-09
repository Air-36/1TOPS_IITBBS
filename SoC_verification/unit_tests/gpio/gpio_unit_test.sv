// =============================================================================
// Test: gpio_unit_test
// Purpose: UVM Test for GPIO APB Peripheral with APB & GPIO VIPs
// =============================================================================

`ifndef GPIO_UNIT_TEST_SV
`define GPIO_UNIT_TEST_SV

class gpio_unit_test extends uvm_test;
    `uvm_component_utils(gpio_unit_test)

    gpio_unit_env env;

    localparam [7:0] GPIO_INPUT_VAL  = 8'h00;
    localparam [7:0] GPIO_INPUT_EN   = 8'h04;
    localparam [7:0] GPIO_OUTPUT_EN  = 8'h08;
    localparam [7:0] GPIO_OUTPUT_VAL = 8'h0C;
    localparam [7:0] GPIO_RISE_IE    = 8'h18;
    localparam [7:0] GPIO_RISE_IP    = 8'h1C;
    localparam [7:0] GPIO_FALL_IE    = 8'h20;
    localparam [7:0] GPIO_FALL_IP    = 8'h24;
    localparam [7:0] GPIO_HIGH_IE    = 8'h28;
    localparam [7:0] GPIO_HIGH_IP    = 8'h2C;
    localparam [7:0] GPIO_LOW_IE     = 8'h30;
    localparam [7:0] GPIO_LOW_IP     = 8'h34;

    function new(string name = "gpio_unit_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = gpio_unit_env::type_id::create("env", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        apb_base_seq#(32, 32) apb_seq;
        gpio_base_seq         gpio_seq;
        bit [31:0] rd_data;
        bit slverr;

        phase.raise_objection(this);

        apb_seq  = apb_base_seq#(32, 32)::type_id::create("apb_seq");
        gpio_seq = gpio_base_seq::type_id::create("gpio_seq");

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " STARTING GPIO IP UNIT TESTBENCH                  ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        // ---------------------------------------------------------------------
        // Phase 1: Reset Values Check
        // ---------------------------------------------------------------------
        `uvm_info("TEST", "--- Phase 1: Checking Reset Values ---", UVM_LOW)
        apb_seq.start(env.apb_ag.sequencer);
        apb_seq.read_check(GPIO_INPUT_EN,   32'h0, 32'hFFFF_FFFF, "Reset GPIO_INPUT_EN");
        apb_seq.read_check(GPIO_OUTPUT_EN,  32'h0, 32'hFFFF_FFFF, "Reset GPIO_OUTPUT_EN");
        apb_seq.read_check(GPIO_OUTPUT_VAL, 32'h0, 32'hFFFF_FFFF, "Reset GPIO_OUTPUT_VAL");
        apb_seq.read_check(GPIO_RISE_IE,    32'h0, 32'hFFFF_FFFF, "Reset GPIO_RISE_IE");
        apb_seq.read_check(GPIO_FALL_IE,    32'h0, 32'hFFFF_FFFF, "Reset GPIO_FALL_IE");

        // ---------------------------------------------------------------------
        // Phase 2: GPIO Output Direction and Value Configuration
        // ---------------------------------------------------------------------
        `uvm_info("TEST", "--- Phase 2: GPIO Output Register & Pin Test ---", UVM_LOW)
        apb_seq.write(GPIO_OUTPUT_EN, 32'hFFFF_0000);
        apb_seq.write(GPIO_OUTPUT_VAL, 32'hA5A5_0000);
        apb_seq.read_check(GPIO_OUTPUT_EN, 32'hFFFF_0000, 32'hFFFF_FFFF, "GPIO_OUTPUT_EN");
        apb_seq.read_check(GPIO_OUTPUT_VAL, 32'hA5A5_0000, 32'hFFFF_FFFF, "GPIO_OUTPUT_VAL");

        #20;
        if (env.gpio_vif.gpio_out !== 32'hA5A5_0000 || env.gpio_vif.gpio_en !== 32'hFFFF_0000) begin
            `uvm_error("TEST", $sformatf("GPIO Output pins mismatch! out: 0x%08h en: 0x%08h",
                                         env.gpio_vif.gpio_out, env.gpio_vif.gpio_en))
        end else begin
            `uvm_info("TEST", "GPIO Output pins successfully matched expected 0xA5A50000!", UVM_LOW)
        end

        // ---------------------------------------------------------------------
        // Phase 3: GPIO Input VIP Driving & APB Readback
        // ---------------------------------------------------------------------
        `uvm_info("TEST", "--- Phase 3: GPIO VIP Input Driving & Readback ---", UVM_LOW)
        apb_seq.write(GPIO_INPUT_EN, 32'h0000_FFFF);

        gpio_seq.start(env.gpio_ag.sequencer);
        gpio_seq.drive_pattern(32'h0000_5A5A, 32'h0000_FFFF, 4);

        apb_seq.read_check(GPIO_INPUT_VAL, 32'h0000_5A5A, 32'h0000_FFFF, "GPIO_INPUT_VAL");

        gpio_seq.drive_pattern(32'h0000_F0F0, 32'h0000_FFFF, 4);
        apb_seq.read_check(GPIO_INPUT_VAL, 32'h0000_F0F0, 32'h0000_FFFF, "GPIO_INPUT_VAL pattern 2");

        // ---------------------------------------------------------------------
        // Phase 4: GPIO Rising-Edge Interrupt Generation & W1C Clear
        // ---------------------------------------------------------------------
        `uvm_info("TEST", "--- Phase 4: Rising-Edge Interrupt Test with GPIO VIP ---", UVM_LOW)
        // Enable input and rising-edge interrupt for bit 2
        apb_seq.write(GPIO_INPUT_EN, 32'h0000_000F);
        apb_seq.write(GPIO_RISE_IE,  32'h0000_0004); // Pin 2 enabled
        apb_seq.write(GPIO_RISE_IP,  32'hFFFF_FFFF); // Clear pending

        #20;
        // Trigger rising edge on pin 2 via GPIO VIP
        gpio_seq.trigger_rising_edge(2, 4);

        #20;
        // Verify GPIOIntr is asserted
        if (env.gpio_vif.gpio_intr !== 1'b1) begin
            `uvm_error("TEST", "GPIOIntr was NOT asserted after rising edge on pin 2!")
        end else begin
            `uvm_info("TEST", "GPIOIntr successfully ASSERTED upon rising edge!", UVM_LOW)
        end

        // Read RISE_IP to confirm bit 2 is set
        apb_seq.read_check(GPIO_RISE_IP, 32'h0000_0004, 32'h0000_0004, "GPIO_RISE_IP asserted");

        // Clear interrupt via Write-1-to-Clear (W1C)
        apb_seq.write(GPIO_RISE_IP, 32'h0000_0004);

        #20;
        if (env.gpio_vif.gpio_intr !== 1'b0) begin
            `uvm_error("TEST", "GPIOIntr did NOT deassert after W1C clear!")
        end else begin
            `uvm_info("TEST", "GPIOIntr successfully DEASSERTED after W1C clear!", UVM_LOW)
        end

        // ---------------------------------------------------------------------
        // Phase 5: GPIO Falling-Edge Interrupt Generation & W1C Clear
        // ---------------------------------------------------------------------
        `uvm_info("TEST", "--- Phase 5: Falling-Edge Interrupt Test with GPIO VIP ---", UVM_LOW)
        apb_seq.write(GPIO_RISE_IE, 32'h0000_0000); // Disable rise IE
        apb_seq.write(GPIO_FALL_IE, 32'h0000_0002); // Enable fall IE on pin 1
        apb_seq.write(GPIO_FALL_IP, 32'hFFFF_FFFF); // Clear pending

        #20;
        gpio_seq.trigger_falling_edge(1, 4);

        #20;
        if (env.gpio_vif.gpio_intr !== 1'b1) begin
            `uvm_error("TEST", "GPIOIntr was NOT asserted after falling edge on pin 1!")
        end else begin
            `uvm_info("TEST", "GPIOIntr successfully ASSERTED upon falling edge!", UVM_LOW)
        end

        apb_seq.read_check(GPIO_FALL_IP, 32'h0000_0002, 32'h0000_0002, "GPIO_FALL_IP asserted");

        // Clear via W1C
        apb_seq.write(GPIO_FALL_IP, 32'h0000_0002);

        #20;
        if (env.gpio_vif.gpio_intr !== 1'b0) begin
            `uvm_error("TEST", "GPIOIntr did NOT deassert after falling edge W1C clear!")
        end else begin
            `uvm_info("TEST", "GPIOIntr successfully DEASSERTED after falling edge clear!", UVM_LOW)
        end

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " GPIO IP UNIT VERIFICATION PASSED SUCCESSFULLY!   ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        #100;
        phase.drop_objection(this);
    endtask

endclass : gpio_unit_test

`endif // GPIO_UNIT_TEST_SV
