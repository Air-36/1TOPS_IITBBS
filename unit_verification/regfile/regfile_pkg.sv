package regfile_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Transaction
    `include "regfile_transaction.sv"

    // Sequence and sequencer
    `include "regfile_sequence.sv"
    `include "regfile_sequencer.sv"

    // Driver and monitor
    `include "regfile_driver.sv"
    `include "regfile_monitor.sv"

    // Scoreboard and coverage
    `include "regfile_scoreboard.sv"
    `include "regfile_coverage.sv"

    // Agent and environment
    `include "regfile_agent.sv"
    `include "regfile_env.sv"

    // Test
    `include "regfile_test.sv"

endpackage
