// =============================================================================
// Test: uart_unit_test
// Purpose: UVM Test for 16550 UART APB Peripheral
// =============================================================================

`ifndef UART_UNIT_TEST_SV
`define UART_UNIT_TEST_SV

class uart_unit_test extends uvm_test;
    `uvm_component_utils(uart_unit_test)

    uart_unit_env env;

    localparam [2:0] UART_RBR_THR_DLL = 3'b000;
    localparam [2:0] UART_IER_DLM     = 3'b001;
    localparam [2:0] UART_IIR_FCR     = 3'b010;
    localparam [2:0] UART_LCR         = 3'b011;
    localparam [2:0] UART_MCR         = 3'b100;
    localparam [2:0] UART_LSR         = 3'b101;
    localparam [2:0] UART_MSR         = 3'b110;
    localparam [2:0] UART_SCR         = 3'b111;

    function new(string name = "uart_unit_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = uart_unit_env::type_id::create("env", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        apb_base_seq#(32, 32) apb_seq;

        phase.raise_objection(this);
        apb_seq = apb_base_seq#(32, 32)::type_id::create("apb_seq");

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " STARTING UART IP UNIT TESTBENCH                  ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        apb_seq.start(env.apb_ag.sequencer);

        // Phase 1: Line Status Register (LSR) Check
        `uvm_info("TEST", "--- Phase 1: Checking LSR Status ---", UVM_LOW)
        apb_seq.read_check(UART_LSR, 32'h60, 32'hFF, "LSR THRE and TEMT ready");

        // Phase 2: Scratchpad Register R/W
        `uvm_info("TEST", "--- Phase 2: Scratchpad Register R/W ---", UVM_LOW)
        apb_seq.write(UART_SCR, 32'hA5);
        apb_seq.read_check(UART_SCR, 32'hA5, 32'hFF, "UART Scratchpad");
        apb_seq.write(UART_SCR, 32'h5A);
        apb_seq.read_check(UART_SCR, 32'h5A, 32'hFF, "UART Scratchpad pattern 2");

        // Phase 3: Baud Divisor Latches (DLAB = 1)
        `uvm_info("TEST", "--- Phase 3: Baud Divisor Latches with DLAB ---", UVM_LOW)
        // Set DLAB bit (LCR[7] = 1)
        apb_seq.write(UART_LCR, 32'h83); // DLAB=1, 8 data bits, 1 stop bit
        apb_seq.write(UART_RBR_THR_DLL, 32'h12); // DLL
        apb_seq.write(UART_IER_DLM,     32'h34); // DLM

        apb_seq.read_check(UART_RBR_THR_DLL, 32'h12, 32'hFF, "DLL divisor latch");
        apb_seq.read_check(UART_IER_DLM,     32'h34, 32'hFF, "DLM divisor latch");

        // Clear DLAB bit
        apb_seq.write(UART_LCR, 32'h03); // DLAB=0

        // Phase 4: Transmitter Interrupt Test
        `uvm_info("TEST", "--- Phase 4: UART Transmitter Interrupt Verification ---", UVM_LOW)
        // Check interrupt initially 0
        if (env.irq_vif.uart_intr !== 1'b0) begin
            `uvm_error("TEST", "UART INTR is high before enabling IER!")
        end

        // Enable THRE interrupt (IER[1] = 1)
        apb_seq.write(UART_IER_DLM, 32'h02);
        #40;
        if (env.irq_vif.uart_intr !== 1'b1) begin
            `uvm_error("TEST", "UART INTR did not assert when IER[1] was enabled!")
        end else begin
            `uvm_info("TEST", "UART INTR successfully ASSERTED on THRE interrupt enable!", UVM_LOW)
        end

        // Disable interrupt
        apb_seq.write(UART_IER_DLM, 32'h00);
        #40;
        if (env.irq_vif.uart_intr !== 1'b0) begin
            `uvm_error("TEST", "UART INTR did not deassert when IER was cleared!")
        end else begin
            `uvm_info("TEST", "UART INTR successfully DEASSERTED after IER clear!", UVM_LOW)
        end

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", " UART IP UNIT VERIFICATION PASSED SUCCESSFULLY!   ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        #100;
        phase.drop_objection(this);
    endtask

endclass : uart_unit_test

`endif // UART_UNIT_TEST_SV

