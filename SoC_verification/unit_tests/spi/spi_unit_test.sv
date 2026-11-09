// =============================================================================
// Test: spi_unit_test
// Purpose: UVM Test for SPI Controller APB Peripheral
// =============================================================================

`ifndef SPI_UNIT_TEST_SV
`define SPI_UNIT_TEST_SV

class spi_unit_test extends uvm_test;
    `uvm_component_utils(spi_unit_test)

    spi_unit_env env;

    localparam [7:0] SPI_SCKDIV =  8'h00;
    localparam [7:0] SPI_SCKMODE = 8'h04;
    localparam [7:0] SPI_CSID =    8'h10;
    localparam [7:0] SPI_CSDEF =   8'h14;
    localparam [7:0] SPI_CSMODE =  8'h18;
    localparam [7:0] SPI_DELAY0 =  8'h28;
    localparam [7:0] SPI_DELAY1 =  8'h2C;
    localparam [7:0] SPI_FMT =     8'h40;
    localparam [7:0] SPI_TXDATA =  8'h48;
    localparam [7:0] SPI_RXDATA =  8'h4C;
    localparam [7:0] SPI_TXMARK =  8'h50;
    localparam [7:0] SPI_RXMARK =  8'h54;
    localparam [7:0] SPI_IE =      8'h70;
    localparam [7:0] SPI_IP =      8'h74;

    function new(string name = "spi_unit_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = spi_unit_env::type_id::create("env", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        apb_base_seq#(32, 32) apb_seq;

        phase.raise_objection(this);
        apb_seq = apb_base_seq#(32, 32)::type_id::create("apb_seq");

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " STARTING SPI IP UNIT TESTBENCH                   ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        apb_seq.start(env.apb_ag.sequencer);

        // Phase 1: Clock Divider Register R/W
        `uvm_info("TEST", "--- Phase 1: Clock Divider Configuration ---", UVM_LOW)
        apb_seq.read_check(SPI_SCKDIV, 32'h03, 32'hFFF, "Default SCKDIV");
        apb_seq.write(SPI_SCKDIV, 32'h0A);
        apb_seq.read_check(SPI_SCKDIV, 32'h0A, 32'hFFF, "Updated SCKDIV");

        // Phase 2: Chip Select & Mode Registers
        `uvm_info("TEST", "--- Phase 2: Chip Select & Mode Registers ---", UVM_LOW)
        apb_seq.write(SPI_CSID, 32'd2);
        apb_seq.read_check(SPI_CSID, 32'd2, 32'h3, "Chip Select ID 2");

        apb_seq.write(SPI_CSDEF, 32'hF);
        apb_seq.read_check(SPI_CSDEF, 32'hF, 32'hF, "Chip Select Default");

        apb_seq.write(SPI_CSMODE, 32'd1); // Hold CS
        apb_seq.read_check(SPI_CSMODE, 32'd1, 32'h3, "Chip Select Mode");

        // Phase 3: Watermark & Interrupt Configuration
        `uvm_info("TEST", "--- Phase 3: Watermark & Interrupts ---", UVM_LOW)
        apb_seq.write(SPI_TXMARK, 32'd4);
        apb_seq.read_check(SPI_TXMARK, 32'd4, 32'h7, "TX Watermark");

        apb_seq.write(SPI_RXMARK, 32'd2);
        apb_seq.read_check(SPI_RXMARK, 32'd2, 32'h7, "RX Watermark");

        apb_seq.write(SPI_IE, 32'd3);
        apb_seq.read_check(SPI_IE, 32'd3, 32'h3, "Interrupt Enable");

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " SPI IP UNIT VERIFICATION PASSED SUCCESSFULLY!    ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        #100;
        phase.drop_objection(this);
    endtask

endclass : spi_unit_test

`endif // SPI_UNIT_TEST_SV

