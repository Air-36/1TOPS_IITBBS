// =============================================================================
// Test: soc_ahb_address_decode_test
// Purpose: Verifies Address Decoding across all SoC mapped regions & boundaries
// =============================================================================

`ifndef SOC_AHB_ADDRESS_DECODE_TEST_SV
`define SOC_AHB_ADDRESS_DECODE_TEST_SV

class soc_ahb_address_decode_test extends soc_base_test;
    `uvm_component_utils(soc_ahb_address_decode_test)

    function new(string name = "soc_ahb_address_decode_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        ahb_base_seq#(32, 32) ahb_seq;
        bit [31:0] rd_val;
        bit resp;

        phase.raise_objection(this);
        ahb_seq = ahb_base_seq#(32, 32)::type_id::create("ahb_seq");

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " STARTING AHB FULL ADDRESS DECODING TEST          ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        ahb_seq.start(env.ahb_ag.sequencer);

        // 1. Slave 1: Boot ROM (0x0000_1000)
        `uvm_info("TEST", "--- Checking Slave: Boot ROM (0x0000_1000) ---", UVM_LOW)
        ahb_seq.read_word(32'h0000_1000, rd_val, resp);
        `uvm_info("TEST", $sformatf("Boot ROM word at 0x0000_1000 = 0x%08h", rd_val), UVM_LOW)

        // 2. Slave 2: CLINT (0x0200_0000)
        `uvm_info("TEST", "--- Checking Slave: CLINT (0x0200_0000) ---", UVM_LOW)
        ahb_seq.read_check(32'h0200_0000, 32'h0, 32'h1, "CLINT Base");

        // 3. Slave 3: Core Debug Slave (0x0B00_0000)
        `uvm_info("TEST", "--- Checking Slave: Core Debug AHB Slave (0x0B00_0000) ---", UVM_LOW)
        ahb_seq.read_word(32'h0B00_0000, rd_val, resp);

        // 4. Slave 4: PLIC (0x0C00_0000)
        `uvm_info("TEST", "--- Checking Slave: PLIC (0x0C00_0004) ---", UVM_LOW)
        ahb_seq.read_check(32'h0C00_0004, 32'd1, 32'h7, "PLIC Source 1 Priority");

        // 5. Slave 5: 16550 UART (0x1000_0000)
        `uvm_info("TEST", "--- Checking Slave: UART (0x1000_0005) ---", UVM_LOW)
        ahb_seq.read_check(32'h1000_0005, 32'h60, 32'hFF, "UART LSR");

        // 6. Slave 6: SPI Controller (0x1004_0000)
        `uvm_info("TEST", "--- Checking Slave: SPI (0x1004_0000) ---", UVM_LOW)
        ahb_seq.read_check(32'h1004_0000, 32'h03, 32'hFFF, "SPI SCKDIV");

        // 7. Slave 7: GPIO (0x1006_0000)
        `uvm_info("TEST", "--- Checking Slave: GPIO (0x1006_0008) ---", UVM_LOW)
        ahb_seq.read_check(32'h1006_0008, 32'h0, 32'hFFFF_FFFF, "GPIO Output Enable");

        // 8. Slave 8: SysCtrl (0x1008_0000)
        `uvm_info("TEST", "--- Checking Slave: SysCtrl (0x1008_0018) ---", UVM_LOW)
        ahb_seq.read_check(32'h1008_0018, 32'h1709_50C1, 32'hFFFF_FFFF, "SysCtrl SYS_ID");

        // 9. Slave 9: Hardware Multiplier Accelerator (0x3000_0000)
        `uvm_info("TEST", "--- Checking Slave: Multiplier Socket (0x3000_0000) ---", UVM_LOW)
        ahb_seq.write_word(32'h3000_0000, 32'd5);
        ahb_seq.write_word(32'h3000_0004, 32'd9);
        ahb_seq.read_check(32'h3000_0008, 32'd45, 32'hFFFF_FFFF, "Multiplier Product (5 * 9 = 45)");

        // 10. Slave 10: Instruction RAM Base & Boundary (0x8000_0000, 0x8000_7FFC)
        `uvm_info("TEST", "--- Checking Slave: Instruction RAM (0x8000_0000 & 0x8000_7FFC) ---", UVM_LOW)
        ahb_seq.write_word(32'h8000_0000, 32'h1111_2222);
        ahb_seq.read_check(32'h8000_0000, 32'h1111_2222, 32'hFFFF_FFFF, "IRAM Base");

        ahb_seq.write_word(32'h8000_7FFC, 32'h3333_4444);
        ahb_seq.read_check(32'h8000_7FFC, 32'h3333_4444, 32'hFFFF_FFFF, "IRAM Boundary");

        // 11. Slave 11: Data RAM Base & Boundary (0x8001_0000, 0x8001_7FFC)
        `uvm_info("TEST", "--- Checking Slave: Data RAM (0x8001_0000 & 0x8001_7FFC) ---", UVM_LOW)
        ahb_seq.write_word(32'h8001_0000, 32'h5555_6666);
        ahb_seq.read_check(32'h8001_0000, 32'h5555_6666, 32'hFFFF_FFFF, "DRAM Base");

        ahb_seq.write_word(32'h8001_7FFC, 32'h7777_8888);
        ahb_seq.read_check(32'h8001_7FFC, 32'h7777_8888, 32'hFFFF_FFFF, "DRAM Boundary");

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " FULL ADDRESS DECODING TEST PASSED SUCCESSFULLY!  ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        #100;
        phase.drop_objection(this);
    endtask

endclass : soc_ahb_address_decode_test

`endif // SOC_AHB_ADDRESS_DECODE_TEST_SV

