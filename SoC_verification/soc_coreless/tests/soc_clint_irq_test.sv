// =============================================================================
// Test: soc_clint_irq_test
// Purpose: Whole SoC CLINT Timer & Software Interrupt Verification via AHB
// =============================================================================

`ifndef SOC_CLINT_IRQ_TEST_SV
`define SOC_CLINT_IRQ_TEST_SV

class soc_clint_irq_test extends soc_base_test;
    `uvm_component_utils(soc_clint_irq_test)

    localparam [31:0] CLINT_BASE      = 32'h0200_0000;
    localparam [31:0] CLINT_MSIP      = CLINT_BASE + 32'h0000;
    localparam [31:0] CLINT_MTIMECMP  = CLINT_BASE + 32'h4000;
    localparam [31:0] CLINT_MTIMECMPH = CLINT_BASE + 32'h4004;
    localparam [31:0] CLINT_MTIME     = CLINT_BASE + 32'hBFF8;
    localparam [31:0] CLINT_MTIMEH    = CLINT_BASE + 32'hBFFC;

    function new(string name = "soc_clint_irq_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        ahb_base_seq#(32, 32) ahb_seq;

        phase.raise_objection(this);
        ahb_seq = ahb_base_seq#(32, 32)::type_id::create("ahb_seq");

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " STARTING WHOLE SOC CLINT IRQ VERIFICATION TEST    ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        ahb_seq.start(env.ahb_ag.sequencer);

        // Phase 1: Timer Interrupt (MTimerInt) Verification via AHB
        `uvm_info("TEST", "--- Phase 1: MTimerInt Verification via AHB bus ---", UVM_LOW)
        ahb_seq.write_word(CLINT_MTIMEH, 32'h0000_0000);
        ahb_seq.write_word(CLINT_MTIME,  32'h0000_0010);
        ahb_seq.write_word(CLINT_MTIMECMPH, 32'h0000_0000);
        ahb_seq.write_word(CLINT_MTIMECMP,  32'h0000_0030);

        #800; // Allow counter to surpass MTIMECMP
        if (env.irq_vif.mtimer_int !== 1'b1) begin
            `uvm_error("TEST", "MTimerInt did not assert at SoC boundary after MTIME threshold reached!")
        end else begin
            `uvm_info("TEST", "MTimerInt successfully ASSERTED at SoC boundary!", UVM_LOW)
        end

        // Clear timer interrupt
        ahb_seq.write_word(CLINT_MTIMECMP, 32'hFFFF_0000);
        #100;
        if (env.irq_vif.mtimer_int !== 1'b0) begin
            `uvm_error("TEST", "MTimerInt did not deassert at SoC boundary after MTIMECMP advance!")
        end else begin
            `uvm_info("TEST", "MTimerInt successfully DEASSERTED after threshold update!", UVM_LOW)
        end

        // Phase 2: Software Interrupt (MSwInt) Verification via AHB
        `uvm_info("TEST", "--- Phase 2: MSwInt Verification via AHB bus ---", UVM_LOW)
        ahb_seq.write_word(CLINT_MSIP, 32'h0000_0001);
        #100;
        if (env.irq_vif.msw_int !== 1'b1) begin
            `uvm_error("TEST", "MSwInt did not assert at SoC boundary after AHB write to MSIP!")
        end else begin
            `uvm_info("TEST", "MSwInt successfully ASSERTED at SoC boundary via MSIP write!", UVM_LOW)
        end

        ahb_seq.write_word(CLINT_MSIP, 32'h0000_0000);
        #100;
        if (env.irq_vif.msw_int !== 1'b0) begin
            `uvm_error("TEST", "MSwInt did not deassert at SoC boundary after MSIP clear!")
        end else begin
            `uvm_info("TEST", "MSwInt successfully DEASSERTED after MSIP clear!", UVM_LOW)
        end

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " WHOLE SOC CLINT IRQ VERIFICATION PASSED!         ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        #100;
        phase.drop_objection(this);
    endtask

endclass : soc_clint_irq_test

`endif // SOC_CLINT_IRQ_TEST_SV

