// =============================================================================
// Environment: gpio_unit_env
// Purpose: UVM Environment for GPIO IP Unit Verification
// =============================================================================

`ifndef GPIO_UNIT_ENV_SV
`define GPIO_UNIT_ENV_SV

`uvm_analysis_imp_decl(_apb)
`uvm_analysis_imp_decl(_gpio)

class gpio_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(gpio_scoreboard)

    uvm_analysis_imp_apb  #(apb_transfer#(32, 32), gpio_scoreboard) apb_imp;
    uvm_analysis_imp_gpio #(gpio_item,              gpio_scoreboard) gpio_imp;

    int match_count = 0;
    int mismatch_count = 0;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        apb_imp  = new("apb_imp", this);
        gpio_imp = new("gpio_imp", this);
    endfunction

    virtual function void write_apb(apb_transfer tr);
        // Track APB writes and reads
    endfunction

    virtual function void write_gpio(gpio_item tr);
        // Track GPIO pin events
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("GPIO_SCB", $sformatf("Scoreboard finished with %0d errors.", mismatch_count), UVM_LOW)
    endfunction
endclass : gpio_scoreboard

class gpio_unit_env extends uvm_env;
    `uvm_component_utils(gpio_unit_env)

    apb_agent                  apb_ag;
    gpio_agent                 gpio_ag;
    gpio_scoreboard            scb;
    virtual gpio_if            gpio_vif;
    virtual apb_if#(32, 32)    apb_vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        apb_ag  = apb_agent#(32, 32)::type_id::create("apb_ag", this);
        gpio_ag = gpio_agent::type_id::create("gpio_ag", this);
        scb     = gpio_scoreboard::type_id::create("scb", this);

        void'(uvm_config_db#(virtual gpio_if)::get(this, "", "gpio_vif", gpio_vif));
        void'(uvm_config_db#(virtual apb_if#(32, 32))::get(this, "", "apb_vif", apb_vif));
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        apb_ag.item_collected_port.connect(scb.apb_imp);
        gpio_ag.item_collected_port.connect(scb.gpio_imp);
    endfunction
endclass : gpio_unit_env

`endif // GPIO_UNIT_ENV_SV
