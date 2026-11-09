// =============================================================================
// Environment: spi_unit_env
// Purpose: UVM Environment for SPI IP Unit Verification
// =============================================================================

`ifndef SPI_UNIT_ENV_SV
`define SPI_UNIT_ENV_SV

class spi_unit_env extends uvm_env;
    `uvm_component_utils(spi_unit_env)

    apb_agent                  apb_ag;
    irq_agent                  irq_ag;
    virtual irq_if             irq_vif;
    virtual apb_if#(32, 32)    apb_vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        apb_ag = apb_agent#(32, 32)::type_id::create("apb_ag", this);
        irq_ag = irq_agent::type_id::create("irq_ag", this);

        void'(uvm_config_db#(virtual irq_if)::get(this, "", "irq_vif", irq_vif));
        void'(uvm_config_db#(virtual apb_if#(32, 32))::get(this, "", "apb_vif", apb_vif));
    endfunction

endclass : spi_unit_env

`endif // SPI_UNIT_ENV_SV

