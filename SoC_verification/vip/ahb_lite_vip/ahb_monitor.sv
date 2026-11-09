// =============================================================================
// Component: ahb_monitor
// Purpose: AMBA 3 AHB-Lite Bus Monitor
// =============================================================================

`ifndef AHB_MONITOR_SV
`define AHB_MONITOR_SV

class ahb_monitor #(parameter ADDR_WIDTH = 32, parameter DATA_WIDTH = 32)
    extends uvm_monitor;

    `uvm_component_param_utils(ahb_monitor #(ADDR_WIDTH, DATA_WIDTH))

    virtual ahb_lite_if #(ADDR_WIDTH, DATA_WIDTH) vif;
    uvm_analysis_port #(ahb_transfer #(ADDR_WIDTH, DATA_WIDTH)) item_collected_port;
    ahb_config cfg;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        item_collected_port = new("item_collected_port", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual ahb_lite_if #(ADDR_WIDTH, DATA_WIDTH))::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        ahb_transfer #(ADDR_WIDTH, DATA_WIDTH) pending_tr = null;

        @(posedge vif.HRESETn);

        forever begin
            @(vif.mon_cb);

            // Handle completion of previous transfer data phase
            if (pending_tr != null && vif.mon_cb.HREADY) begin
                if (pending_tr.write) begin
                    pending_tr.data = vif.mon_cb.HWDATA;
                    pending_tr.strb = vif.mon_cb.HWSTRB;
                end else begin
                    pending_tr.rdata = vif.mon_cb.HRDATA;
                end
                pending_tr.resp = vif.mon_cb.HRESP;

                item_collected_port.write(pending_tr);
                pending_tr = null;
            end

            // Sample new address phase
            if (vif.mon_cb.HREADY && vif.mon_cb.HTRANS[1]) begin // NONSEQ or SEQ
                pending_tr = ahb_transfer#(ADDR_WIDTH, DATA_WIDTH)::type_id::create("mon_tr");
                pending_tr.addr     = vif.mon_cb.HADDR;
                pending_tr.write    = vif.mon_cb.HWRITE;
                pending_tr.trans    = ahb_transfer#(ADDR_WIDTH, DATA_WIDTH)::trans_type_e'(vif.mon_cb.HTRANS);
                pending_tr.size     = ahb_transfer#(ADDR_WIDTH, DATA_WIDTH)::size_type_e'(vif.mon_cb.HSIZE);
                pending_tr.burst    = ahb_transfer#(ADDR_WIDTH, DATA_WIDTH)::burst_type_e'(vif.mon_cb.HBURST);
                pending_tr.prot     = vif.mon_cb.HPROT;
                pending_tr.mastlock = vif.mon_cb.HMASTLOCK;
            end
        end
    endtask

endclass : ahb_monitor

`endif // AHB_MONITOR_SV

