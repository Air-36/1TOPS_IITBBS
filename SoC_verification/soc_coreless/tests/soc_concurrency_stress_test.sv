// =============================================================================
// Test: soc_concurrency_stress_test
// Purpose: Stress & Concurrency Verification across Memories and Peripherals
// =============================================================================

`ifndef SOC_CONCURRENCY_STRESS_TEST_SV
`define SOC_CONCURRENCY_STRESS_TEST_SV

class soc_concurrency_stress_test extends soc_base_test;
    `uvm_component_utils(soc_concurrency_stress_test)

    function new(string name = "soc_concurrency_stress_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        ahb_base_seq#(32, 32) ahb_seq1;
        ahb_base_seq#(32, 32) ahb_seq2;
        gpio_base_seq         gpio_seq;

        phase.raise_objection(this);
        ahb_seq1 = ahb_base_seq#(32, 32)::type_id::create("ahb_seq1");
        ahb_seq2 = ahb_base_seq#(32, 32)::type_id::create("ahb_seq2");
        gpio_seq = gpio_base_seq::type_id::create("gpio_seq");

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " STARTING SOC CONCURRENCY & STRESS TEST           ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        ahb_seq1.start(env.ahb_ag.sequencer);
        ahb_seq2.start(env.ahb_ag.sequencer);
        gpio_seq.start(env.gpio_ag.sequencer);

        // Enable GPIO inputs
        ahb_seq1.write_word(32'h1006_0004, 32'hFFFF_FFFF);

        fork
            // Thread 1: Rapid memory writes and reads (DRAM & IRAM)
            begin
                for (int i = 0; i < 50; i++) begin
                    bit [31:0] dram_addr = 32'h8001_0000 + ((i % 16) * 4);
                    bit [31:0] iram_addr = 32'h8000_0000 + ((i % 16) * 4);
                    bit [31:0] wdata = $urandom();

                    ahb_seq1.write_word(dram_addr, wdata);
                    ahb_seq1.read_check(dram_addr, wdata, 32'hFFFF_FFFF, "Stress DRAM Readback");

                    ahb_seq1.write_word(iram_addr, ~wdata);
                    ahb_seq1.read_check(iram_addr, ~wdata, 32'hFFFF_FFFF, "Stress IRAM Readback");
                end
            end

            // Thread 2: Multiplier accelerator continuous computations
            begin
                for (int i = 0; i < 25; i++) begin
                    bit [31:0] a = $urandom_range(1, 500);
                    bit [31:0] b = $urandom_range(1, 500);
                    ahb_seq2.write_word(32'h3000_0000, a);
                    ahb_seq2.write_word(32'h3000_0004, b);
                    ahb_seq2.read_check(32'h3000_0008, a * b, 32'hFFFF_FFFF, "Stress Multiplier");
                end
            end

            // Thread 3: Asynchronous GPIO pin toggling
            begin
                for (int i = 0; i < 30; i++) begin
                    gpio_seq.drive_pattern($urandom(), 32'hFFFF_FFFF, 2);
                end
            end
        join

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " SOC CONCURRENCY & STRESS TEST PASSED!             ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        #100;
        phase.drop_objection(this);
    endtask

endclass : soc_concurrency_stress_test

`endif // SOC_CONCURRENCY_STRESS_TEST_SV
