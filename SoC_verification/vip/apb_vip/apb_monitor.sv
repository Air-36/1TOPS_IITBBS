// =============================================================================
// Component: apb_monitor
// Purpose: AMBA 3 APB Bus Monitor
// =============================================================================

`ifndef APB_MONITOR_SV
`define APB_MONITOR_SV

class apb_monitor #(parameter ADDR_WIDTH = 32, parameter DATA_WIDTH = 32)
    extends uvm_monitor;

    `uvm_component_param_utils(apb_monitor #(ADDR_WIDTH, DATA_WIDTH))

    virtual apb_if #(ADDR_WIDTH, DATA_WIDTH) vif;
    uvm_analysis_port #(apb_transfer #(ADDR_WIDTH, DATA_WIDTH)) item_collected_port;
    apb_config cfg;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        item_collected_port = new("item_collected_port", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual apb_if #(ADDR_WIDTH, DATA_WIDTH))::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        apb_transfer #(ADDR_WIDTH, DATA_WIDTH) tr;

        @(posedge vif.PRESETn);

        forever begin
            @(vif.mon_cb);
            if (vif.mon_cb.PSEL && vif.mon_cb.PENABLE && vif.mon_cb.PREADY) begin
                tr = apb_transfer#(ADDR_WIDTH, DATA_WIDTH)::type_id::create("mon_apb_tr");
                tr.addr   = vif.mon_cb.PADDR;
                tr.write  = vif.mon_cb.PWRITE;
                tr.strb   = vif.mon_cb.PSTRB;
                tr.slverr = vif.mon_cb.PSLVERR;
                if (tr.write) tr.data  = vif.mon_cb.PWDATA;
                else          tr.rdata = vif.mon_cb.PRDATA;

                item_collected_port.write(tr);
            end
        end
    endtask

endclass : apb_monitor

`endif // APB_MONITOR_SV

