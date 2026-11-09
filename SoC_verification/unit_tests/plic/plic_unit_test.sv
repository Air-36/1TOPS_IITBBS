// =============================================================================
// Test: plic_unit_test
// Purpose: UVM Test for Platform-Level Interrupt Controller (PLIC) Routing & Priority
// =============================================================================

`ifndef PLIC_UNIT_TEST_SV
`define PLIC_UNIT_TEST_SV

class plic_unit_test extends uvm_test;
    `uvm_component_utils(plic_unit_test)

    plic_unit_env env;

    localparam [23:0] PLIC_PRIORITY_SRC1 = 24'h000004; // UART
    localparam [23:0] PLIC_PRIORITY_SRC2 = 24'h000008; // GPIO
    localparam [23:0] PLIC_PRIORITY_SRC3 = 24'h00000C; // SPI
    localparam [23:0] PLIC_PRIORITY_SRC4 = 24'h000010; // SDC
    localparam [23:0] PLIC_PENDING       = 24'h001000;
    localparam [23:0] PLIC_ENABLE        = 24'h002000;
    localparam [23:0] PLIC_THRESHOLD     = 24'h200000;
    localparam [23:0] PLIC_CLAIM         = 24'h200004;

    function new(string name = "plic_unit_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = plic_unit_env::type_id::create("env", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        apb_base_seq#(32, 32) apb_seq;
        bit [31:0] rd_data;
        bit slverr;

        phase.raise_objection(this);
        apb_seq = apb_base_seq#(32, 32)::type_id::create("apb_seq");

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " STARTING PLIC IP UNIT TESTBENCH (IRQ & PRIORITY) ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        apb_seq.start(env.apb_ag.sequencer);

        // ---------------------------------------------------------------------
        // Phase 1: Reset Values Check
        // ---------------------------------------------------------------------
        `uvm_info("TEST", "--- Phase 1: Checking Reset Values ---", UVM_LOW)
        apb_seq.read_check(PLIC_PRIORITY_SRC1, 32'd1, 32'h7, "Reset Prio UART");
        apb_seq.read_check(PLIC_PRIORITY_SRC2, 32'd1, 32'h7, "Reset Prio GPIO");
        apb_seq.read_check(PLIC_ENABLE,        32'd0, 32'h1F, "Reset Enables");
        apb_seq.read_check(PLIC_THRESHOLD,     32'd0, 32'h7, "Reset Threshold");
        apb_seq.read_check(PLIC_CLAIM,         32'd0, 32'h7, "Reset Claim ID");

        if (env.irq_vif.mext_int !== 1'b0) begin
            `uvm_error("TEST", "MExtInt asserted at reset!")
        end else begin
            `uvm_info("TEST", "MExtInt is 0 at reset as expected.", UVM_LOW)
        end

        // ---------------------------------------------------------------------
        // Phase 2: Masking / Disabled Interrupt Check
        // ---------------------------------------------------------------------
        `uvm_info("TEST", "--- Phase 2: Interrupt Masking Test ---", UVM_LOW)
        // Assert GPIOIntr while enables = 0
        env.irq_vif.gpio_intr = 1'b1;
        #40;
        if (env.irq_vif.mext_int !== 1'b0) begin
            `uvm_error("TEST", "MExtInt asserted when interrupt source was disabled!")
        end else begin
            `uvm_info("TEST", "MExtInt correctly stayed 0 when source was disabled.", UVM_LOW)
        end

        // Read PLIC_PENDING: bit 2 must be 1 even though disabled
        apb_seq.read_check(PLIC_PENDING, 32'h0000_0004, 32'h0000_0004, "PLIC_PENDING bit 2");

        // ---------------------------------------------------------------------
        // Phase 3: Single Interrupt Enable & Claim
        // ---------------------------------------------------------------------
        `uvm_info("TEST", "--- Phase 3: Single Interrupt Enable & Claim Test ---", UVM_LOW)
        // Enable GPIO (source 2)
        apb_seq.write(PLIC_ENABLE, 32'h0000_0004);
        #40;
        if (env.irq_vif.mext_int !== 1'b1) begin
            `uvm_error("TEST", "MExtInt did NOT assert after enabling GPIO interrupt!")
        end else begin
            `uvm_info("TEST", "MExtInt successfully ASSERTED for GPIO interrupt!", UVM_LOW)
        end

        // Read PLIC_CLAIM to verify claimed interrupt is source 2 (GPIO)
        apb_seq.read_check(PLIC_CLAIM, 32'd2, 32'h7, "Claimed Interrupt ID == 2 (GPIO)");

        // Deassert GPIOIntr
        env.irq_vif.gpio_intr = 1'b0;
        #40;
        if (env.irq_vif.mext_int !== 1'b0) begin
            `uvm_error("TEST", "MExtInt did not deassert when GPIOIntr was cleared!")
        end else begin
            `uvm_info("TEST", "MExtInt successfully DEASSERTED after peripheral event cleared!", UVM_LOW)
        end

        // ---------------------------------------------------------------------
        // Phase 4: Priority Arbitration (Multiple Simultaneous Interrupts)
        // ---------------------------------------------------------------------
        `uvm_info("TEST", "--- Phase 4: Priority Arbitration Test ---", UVM_LOW)
        // Enable both UART (source 1) and GPIO (source 2)
        apb_seq.write(PLIC_ENABLE, 32'h0000_0006);
        // Set UART priority = 2, GPIO priority = 5
        apb_seq.write(PLIC_PRIORITY_SRC1, 32'd2);
        apb_seq.write(PLIC_PRIORITY_SRC2, 32'd5);

        // Assert both UART and GPIO interrupts simultaneously
        env.irq_vif.uart_intr = 1'b1;
        env.irq_vif.gpio_intr = 1'b1;
        #40;

        if (env.irq_vif.mext_int !== 1'b1) begin
            `uvm_error("TEST", "MExtInt did not assert for simultaneous interrupts!")
        end

        // Claim must return GPIO (source 2) because priority 5 > 2
        apb_seq.read_check(PLIC_CLAIM, 32'd2, 32'h7, "Priority Winner: GPIO (prio 5 > 2)");

        // Now change UART priority to 6 (higher than GPIO's 5)
        apb_seq.write(PLIC_PRIORITY_SRC1, 32'd6);
        #40;

        // Claim must now return UART (source 1) because priority 6 > 5
        apb_seq.read_check(PLIC_CLAIM, 32'd1, 32'h7, "Priority Winner: UART (prio 6 > 5)");

        // ---------------------------------------------------------------------
        // Phase 5: Threshold Filtering
        // ---------------------------------------------------------------------
        `uvm_info("TEST", "--- Phase 5: Threshold Filtering Test ---", UVM_LOW)
        // Set threshold = 6. Since UART is 6 (not > 6) and GPIO is 5 (not > 6), both are masked!
        apb_seq.write(PLIC_THRESHOLD, 32'd6);
        #40;
        if (env.irq_vif.mext_int !== 1'b0) begin
            `uvm_error("TEST", "MExtInt was NOT masked by PLIC threshold = 6!")
        end else begin
            `uvm_info("TEST", "MExtInt correctly MASKED by PLIC threshold = 6!", UVM_LOW)
        end

        // Lower threshold = 5: UART (prio 6 > 5) should pass through
        apb_seq.write(PLIC_THRESHOLD, 32'd5);
        #40;
        if (env.irq_vif.mext_int !== 1'b1) begin
            `uvm_error("TEST", "MExtInt did NOT unmask when threshold was lowered to 5!")
        end else begin
            `uvm_info("TEST", "MExtInt correctly UNMASKED when threshold lowered below priority!", UVM_LOW)
        end

        // Clean up
        env.irq_vif.uart_intr = 1'b0;
        env.irq_vif.gpio_intr = 1'b0;
        #40;

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " PLIC IP UNIT VERIFICATION PASSED SUCCESSFULLY!   ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        #100;
        phase.drop_objection(this);
    endtask

endclass : plic_unit_test

`endif // PLIC_UNIT_TEST_SV

