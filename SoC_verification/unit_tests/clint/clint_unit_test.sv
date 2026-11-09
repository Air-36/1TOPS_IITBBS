// =============================================================================
// Test: clint_unit_test
// Purpose: UVM Test for Core-Local Interruptor (CLINT) Timer & Software IRQ
// =============================================================================

`ifndef CLINT_UNIT_TEST_SV
`define CLINT_UNIT_TEST_SV

class clint_unit_test extends uvm_test;
    `uvm_component_utils(clint_unit_test)

    clint_unit_env env;

    localparam [15:0] CLINT_MSIP      = 16'h0000;
    localparam [15:0] CLINT_MTIMECMP  = 16'h4000;
    localparam [15:0] CLINT_MTIMECMPH = 16'h4004;
    localparam [15:0] CLINT_MTIME     = 16'hBFF8;
    localparam [15:0] CLINT_MTIMEH    = 16'hBFFC;

    function new(string name = "clint_unit_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = clint_unit_env::type_id::create("env", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        apb_base_seq#(32, 32) apb_seq;
        bit [31:0] mtime_1, mtime_2;
        bit slverr;

        phase.raise_objection(this);
        apb_seq = apb_base_seq#(32, 32)::type_id::create("apb_seq");

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " STARTING CLINT IP UNIT TESTBENCH (TIMER & SW IRQ)", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        apb_seq.start(env.apb_ag.sequencer);

        // ---------------------------------------------------------------------
        // Phase 1: Reset Values Check
        // ---------------------------------------------------------------------
        `uvm_info("TEST", "--- Phase 1: Checking Reset Values ---", UVM_LOW)
        apb_seq.read_check(CLINT_MSIP,      32'h0,         32'h1,         "Reset MSIP");
        apb_seq.read_check(CLINT_MTIMECMP,  32'hFFFF_FFFF, 32'hFFFF_FFFF, "Reset MTIMECMP Low");
        apb_seq.read_check(CLINT_MTIMECMPH, 32'hFFFF_FFFF, 32'hFFFF_FFFF, "Reset MTIMECMP High");

        if (env.irq_vif.mtimer_int !== 1'b0 || env.irq_vif.msw_int !== 1'b0) begin
            `uvm_error("TEST", "CLINT interrupts asserted at reset!")
        end else begin
            `uvm_info("TEST", "CLINT MTimerInt and MSwInt both deasserted at reset as expected.", UVM_LOW)
        end

        // ---------------------------------------------------------------------
        // Phase 2: MTIME Counter Progression
        // ---------------------------------------------------------------------
        `uvm_info("TEST", "--- Phase 2: MTIME Free-Running Counter Test ---", UVM_LOW)
        apb_seq.read(CLINT_MTIME, mtime_1, slverr);
        #200; // wait 10 clock cycles
        apb_seq.read(CLINT_MTIME, mtime_2, slverr);

        if (mtime_2 <= mtime_1) begin
            `uvm_error("TEST", $sformatf("MTIME did not advance! mtime_1=%0d, mtime_2=%0d", mtime_1, mtime_2))
        end else begin
            `uvm_info("TEST", $sformatf("MTIME advanced successfully from %0d to %0d (delta: %0d)",
                                        mtime_1, mtime_2, mtime_2 - mtime_1), UVM_LOW)
        end

        // ---------------------------------------------------------------------
        // Phase 3: Timer Interrupt (MTimerInt) Verification
        // ---------------------------------------------------------------------
        `uvm_info("TEST", "--- Phase 3: MTimerInt Timer Interrupt Generation & Clear ---", UVM_LOW)
        // Reset MTIME to a known low value
        apb_seq.write(CLINT_MTIMEH, 32'h0000_0000);
        apb_seq.write(CLINT_MTIME,  32'h0000_0010);
        apb_seq.write(CLINT_MTIMECMPH, 32'h0000_0000);
        // Set MTIMECMP to 0x0000_0025 (only slightly ahead)
        apb_seq.write(CLINT_MTIMECMP,  32'h0000_0025);

        // Wait until counter surpasses MTIMECMP
        #500;

        if (env.irq_vif.mtimer_int !== 1'b1) begin
            `uvm_error("TEST", "MTimerInt did not assert when MTIME >= MTIMECMP!")
        end else begin
            `uvm_info("TEST", "MTimerInt successfully ASSERTED when counter passed MTIMECMP threshold!", UVM_LOW)
        end

        // Clear interrupt by moving MTIMECMP into the distant future
        apb_seq.write(CLINT_MTIMECMP,  32'hFFFF_0000);
        #40;
        if (env.irq_vif.mtimer_int !== 1'b0) begin
            `uvm_error("TEST", "MTimerInt did not deassert when MTIMECMP moved forward!")
        end else begin
            `uvm_info("TEST", "MTimerInt successfully DEASSERTED after threshold update!", UVM_LOW)
        end

        // ---------------------------------------------------------------------
        // Phase 4: Software Interrupt (MSwInt) Verification
        // ---------------------------------------------------------------------
        `uvm_info("TEST", "--- Phase 4: MSwInt Software Interrupt Generation & Clear ---", UVM_LOW)
        // Set MSIP bit
        apb_seq.write(CLINT_MSIP, 32'h0000_0001);
        #40;
        if (env.irq_vif.msw_int !== 1'b1) begin
            `uvm_error("TEST", "MSwInt did not assert when MSIP was set to 1!")
        end else begin
            `uvm_info("TEST", "MSwInt successfully ASSERTED via MSIP register write!", UVM_LOW)
        end

        // Clear MSIP bit
        apb_seq.write(CLINT_MSIP, 32'h0000_0000);
        #40;
        if (env.irq_vif.msw_int !== 1'b0) begin
            `uvm_error("TEST", "MSwInt did not deassert when MSIP was cleared to 0!")
        end else begin
            `uvm_info("TEST", "MSwInt successfully DEASSERTED via MSIP register clear!", UVM_LOW)
        end

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " CLINT IP UNIT VERIFICATION PASSED SUCCESSFULLY!  ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        #100;
        phase.drop_objection(this);
    endtask

endclass : clint_unit_test

`endif // CLINT_UNIT_TEST_SV

