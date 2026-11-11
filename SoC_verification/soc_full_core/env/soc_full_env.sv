// =============================================================================
// Class: soc_full_env
// Purpose: Top-level UVM Environment for Full 1TOPS RISC-V SoC Verification
// =============================================================================

`ifndef SOC_FULL_ENV_SV
`define SOC_FULL_ENV_SV

class soc_full_env extends uvm_env;
    `uvm_component_utils(soc_full_env)

    gpio_agent          gpio_agt;
    irq_agent           irq_agt;
    uart_agent          uart_agt;
    soc_full_scoreboard scb;
    soc_full_coverage   cov;

    function new(string name = "soc_full_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        gpio_agt = gpio_agent::type_id::create("gpio_agt", this);
        irq_agt  = irq_agent::type_id::create("irq_agt", this);
        uart_agt = uart_agent::type_id::create("uart_agt", this);
        scb      = soc_full_scoreboard::type_id::create("scb", this);
        cov      = soc_full_coverage::type_id::create("cov", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // Connect Analysis Ports to Scoreboard
        gpio_agt.item_collected_port.connect(scb.gpio_export);
        irq_agt.item_collected_port.connect(scb.irq_export);
        uart_agt.ap.connect(scb.uart_export);

        // Connect GPIO to Coverage
        gpio_agt.item_collected_port.connect(cov.analysis_export);
    endfunction

endclass : soc_full_env

`endif

