// =============================================================================
// Environment: soc_coreless_env
// Purpose: Top-level UVM Environment for Full Coreless SoC Verification
// =============================================================================

`ifndef SOC_CORELESS_ENV_SV
`define SOC_CORELESS_ENV_SV

class soc_coreless_env extends uvm_env;
    `uvm_component_utils(soc_coreless_env)

    ahb_agent#(32, 32)           ahb_ag;
    gpio_agent                   gpio_ag;
    irq_agent                    irq_ag;
    soc_scoreboard               scb;
    soc_coverage                 cov;
    soc_ral_model                ral;
    ahb_reg_adapter              adapter;

    virtual ahb_lite_if#(32, 32) ahb_vif;
    virtual gpio_if              gpio_vif;
    virtual irq_if               irq_vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        ahb_ag  = ahb_agent#(32, 32)::type_id::create("ahb_ag", this);
        gpio_ag = gpio_agent::type_id::create("gpio_ag", this);
        irq_ag  = irq_agent::type_id::create("irq_ag", this);
        scb     = soc_scoreboard::type_id::create("scb", this);
        cov     = soc_coverage::type_id::create("cov", this);
        adapter = ahb_reg_adapter::type_id::create("adapter");

        ral = soc_ral_model::type_id::create("ral");
        ral.build();

        void'(uvm_config_db#(virtual ahb_lite_if#(32, 32))::get(this, "", "ahb_vif",  ahb_vif));
        void'(uvm_config_db#(virtual gpio_if)::get(this,              "", "gpio_vif", gpio_vif));
        void'(uvm_config_db#(virtual irq_if)::get(this,               "", "irq_vif",  irq_vif));
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        ahb_ag.item_collected_port.connect(scb.ahb_export);
        ahb_ag.item_collected_port.connect(cov.analysis_export);
        gpio_ag.item_collected_port.connect(scb.gpio_export);
        irq_ag.item_collected_port.connect(scb.irq_export);

        ral.default_map.set_sequencer(ahb_ag.sequencer, adapter);
    endfunction

endclass : soc_coreless_env

`endif // SOC_CORELESS_ENV_SV

