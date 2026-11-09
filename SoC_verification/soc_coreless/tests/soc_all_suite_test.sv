// =============================================================================
// Test: soc_all_suite_test
// Purpose: Comprehensive Master Test Suite running all integration phases
// =============================================================================

`ifndef SOC_ALL_SUITE_TEST_SV
`define SOC_ALL_SUITE_TEST_SV

class soc_all_suite_test extends soc_base_test;
    `uvm_component_utils(soc_all_suite_test)

    function new(string name = "soc_all_suite_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        ahb_base_seq#(32, 32) ahb_seq;
        gpio_base_seq         gpio_seq;
        bit [31:0] rd_data;
        bit resp;

        phase.raise_objection(this);
        ahb_seq  = ahb_base_seq#(32, 32)::type_id::create("ahb_seq");
        gpio_seq = gpio_base_seq::type_id::create("gpio_seq");

        `uvm_info("MASTER_TEST", "==================================================", UVM_NONE)
        `uvm_info("MASTER_TEST", " STARTING COMPLETE SOC VERIFICATION MASTER SUITE   ", UVM_NONE)
        `uvm_info("MASTER_TEST", "==================================================", UVM_NONE)

        ahb_seq.start(env.ahb_ag.sequencer);
        gpio_seq.start(env.gpio_ag.sequencer);

        // ---------------------------------------------------------------------
        // STEP 1: Reset Values Verification
        // ---------------------------------------------------------------------
        `uvm_info("MASTER_TEST", ">>> STEP 1: Peripheral & Subsystem Reset Values <<<", UVM_LOW)
        ahb_seq.read_check(32'h1008_0018, 32'h1709_50C1, 32'hFFFF_FFFF, "SysCtrl SYS_ID");
        ahb_seq.read_check(32'h1008_0004, 32'h0000_1000, 32'hFFFF_FFFF, "Reset Vector");
        ahb_seq.read_check(32'h1006_0008, 32'h0, 32'hFFFF_FFFF, "GPIO Output Enable");
        ahb_seq.read_check(32'h3000_0008, 32'h0, 32'hFFFF_FFFF, "Multiplier Product");

        // ---------------------------------------------------------------------
        // STEP 2: Address Decoding across all Slaves
        // ---------------------------------------------------------------------
        `uvm_info("MASTER_TEST", ">>> STEP 2: Address Decoding & Bus Access <<<", UVM_LOW)
        ahb_seq.read_word(32'h0000_1000, rd_data, resp); // Boot ROM
        ahb_seq.read_check(32'h0200_0000, 32'h0, 32'h1, "CLINT MSIP");
        ahb_seq.read_check(32'h0C00_0004, 32'd1, 32'h7, "PLIC UART Priority");
        ahb_seq.read_check(32'h1000_0005, 32'h60, 32'hFF, "UART LSR");
        ahb_seq.read_check(32'h1004_0000, 32'h03, 32'hFFF, "SPI SCKDIV");
        ahb_seq.read_check(32'h1006_0004, 32'h0, 32'hFFFF_FFFF, "GPIO Input Enable");
        ahb_seq.read_check(32'h1008_0018, 32'h1709_50C1, 32'hFFFF_FFFF, "SysCtrl ID");

        // ---------------------------------------------------------------------
        // STEP 3: Memories Read/Write Integrity (IRAM & DRAM)
        // ---------------------------------------------------------------------
        `uvm_info("MASTER_TEST", ">>> STEP 3: SRAM Read/Write Data Integrity <<<", UVM_LOW)
        ahb_seq.write_word(32'h8001_0000, 32'hA5A5_5A5A);
        ahb_seq.read_check(32'h8001_0000, 32'hA5A5_5A5A, 32'hFFFF_FFFF, "DRAM Base R/W");

        ahb_seq.write_word(32'h8000_0000, 32'h1234_5678);
        ahb_seq.read_check(32'h8000_0000, 32'h1234_5678, 32'hFFFF_FFFF, "IRAM Base R/W");

        // ---------------------------------------------------------------------
        // STEP 4: Hardware Multiplier Accelerator Socket
        // ---------------------------------------------------------------------
        `uvm_info("MASTER_TEST", ">>> STEP 4: Hardware Multiplier Accelerator <<<", UVM_LOW)
        ahb_seq.write_word(32'h3000_0000, 32'd25);
        ahb_seq.write_word(32'h3000_0004, 32'd4);
        ahb_seq.read_check(32'h3000_0008, 32'd100, 32'hFFFF_FFFF, "Multiplier Product (25 * 4 = 100)");

        // ---------------------------------------------------------------------
        // STEP 5: GPIO VIP Integration (Output & Input)
        // ---------------------------------------------------------------------
        `uvm_info("MASTER_TEST", ">>> STEP 5: GPIO VIP Integration <<<", UVM_LOW)
        ahb_seq.write_word(32'h1006_0008, 32'h0000_00FF);
        ahb_seq.write_word(32'h1006_000C, 32'h0000_003C);
        #40;
        if ((env.gpio_vif.gpio_out & 32'h0000_00FF) !== 32'h0000_003C) begin
            `uvm_error("MASTER_TEST", "GPIO output pin mismatch!")
        end

        ahb_seq.write_word(32'h1006_0004, 32'h0000_FF00);
        gpio_seq.drive_pattern(32'h0000_A500, 32'h0000_FF00, 4);
        #40;
        ahb_seq.read_check(32'h1006_0000, 32'h0000_A500, 32'h0000_FF00, "GPIO Input Value via VIP");

        // ---------------------------------------------------------------------
        // STEP 6: CLINT Timer & Software Interrupts
        // ---------------------------------------------------------------------
        `uvm_info("MASTER_TEST", ">>> STEP 6: CLINT Timer & Software Interrupts <<<", UVM_LOW)
        // Software interrupt
        ahb_seq.write_word(32'h0200_0000, 32'h1);
        #60;
        if (env.irq_vif.msw_int !== 1'b1) `uvm_error("MASTER_TEST", "MSwInt did not assert!");
        ahb_seq.write_word(32'h0200_0000, 32'h0);
        #60;
        if (env.irq_vif.msw_int !== 1'b0) `uvm_error("MASTER_TEST", "MSwInt did not deassert!");

        // ---------------------------------------------------------------------
        // STEP 7: PLIC Peripheral Interrupt Routing & Claim/Complete
        // ---------------------------------------------------------------------
        `uvm_info("MASTER_TEST", ">>> STEP 7: PLIC Peripheral Routing & Claim <<<", UVM_LOW)
        ahb_seq.write_word(32'h0C00_0008, 32'd5); // GPIO Priority
        ahb_seq.write_word(32'h0C20_0000, 32'd0); // Threshold 0
        ahb_seq.write_word(32'h0C00_2000, 32'd4); // Enable GPIO

        ahb_seq.write_word(32'h1006_0004, 32'h0000_000F);
        ahb_seq.write_word(32'h1006_0018, 32'h0000_0002); // Enable Pin 1
        ahb_seq.write_word(32'h1006_001C, 32'hFFFF_FFFF); // Clear pending

        #40;
        gpio_seq.trigger_rising_edge(1, 4);
        #80;
        if (env.irq_vif.mext_int !== 1'b1) `uvm_error("MASTER_TEST", "MExtInt did not assert through PLIC!");

        ahb_seq.read_check(32'h0C20_0004, 32'd2, 32'h7, "Claimed Source ID == 2 (GPIO)");
        ahb_seq.write_word(32'h1006_001C, 32'h0000_0002);
        #80;
        if (env.irq_vif.mext_int !== 1'b0) `uvm_error("MASTER_TEST", "MExtInt did not deassert after clear!");

        // ---------------------------------------------------------------------
        // STEP 8: SysCtrl ROM-to-RAM Remap
        // ---------------------------------------------------------------------
        `uvm_info("MASTER_TEST", ">>> STEP 8: SysCtrl ROM-to-RAM Remapping <<<", UVM_LOW)
        ahb_seq.write_word(32'h8000_0000, 32'hCAFE_BABE);
        ahb_seq.write_word(32'h1008_000C, 32'h1); // Enable remap
        #40;
        ahb_seq.read_check(32'h0000_0000, 32'hCAFE_BABE, 32'hFFFF_FFFF, "0x0000_0000 remapped to IRAM");
        ahb_seq.write_word(32'h1008_000C, 32'h0); // Disable remap

        `uvm_info("MASTER_TEST", "==================================================", UVM_NONE)
        `uvm_info("MASTER_TEST", " ALL SOC INTEGRATION PHASES PASSED SUCCESSFULLY! ", UVM_NONE)
        `uvm_info("MASTER_TEST", "==================================================", UVM_NONE)

        #100;
        phase.drop_objection(this);
    endtask

endclass : soc_all_suite_test

`endif // SOC_ALL_SUITE_TEST_SV

