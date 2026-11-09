// =============================================================================
// Component: ahb_driver
// Purpose: AMBA 3 AHB-Lite Master Driver (Cycle-accurate pipelined driving)
// =============================================================================

`ifndef AHB_DRIVER_SV
`define AHB_DRIVER_SV

class ahb_driver #(parameter ADDR_WIDTH = 32, parameter DATA_WIDTH = 32)
    extends uvm_driver #(ahb_transfer #(ADDR_WIDTH, DATA_WIDTH));

    `uvm_component_param_utils(ahb_driver #(ADDR_WIDTH, DATA_WIDTH))

    virtual ahb_lite_if #(ADDR_WIDTH, DATA_WIDTH) vif;
    ahb_config cfg;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual ahb_lite_if #(ADDR_WIDTH, DATA_WIDTH))::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        reset_signals();

        @(posedge vif.HRESETn);
        @(vif.master_cb);

        forever begin
            seq_item_port.get_next_item(req);
            drive_transfer(req);
            seq_item_port.item_done();
        end
    endtask

    virtual task reset_signals();
        vif.master_cb.HADDR     <= '0;
        vif.master_cb.HWDATA    <= '0;
        vif.master_cb.HWSTRB    <= '0;
        vif.master_cb.HWRITE    <= 1'b0;
        vif.master_cb.HTRANS    <= 2'b00; // TR_IDLE
        vif.master_cb.HSIZE     <= 3'b010;
        vif.master_cb.HBURST    <= 3'b000;
        vif.master_cb.HPROT     <= 4'b0011;
        vif.master_cb.HMASTLOCK <= 1'b0;
    endtask

    virtual task drive_transfer(ahb_transfer #(ADDR_WIDTH, DATA_WIDTH) tr);
        // Synchronize to master clocking block
        @(vif.master_cb);

        // Wait for bus ready before address phase
        while (!vif.master_cb.HREADY) begin
            @(vif.master_cb);
        end

        // Address Phase
        vif.master_cb.HADDR     <= tr.addr;
        vif.master_cb.HWRITE    <= tr.write;
        vif.master_cb.HTRANS    <= tr.trans;
        vif.master_cb.HSIZE     <= tr.size;
        vif.master_cb.HBURST    <= tr.burst;
        vif.master_cb.HPROT     <= tr.prot;
        vif.master_cb.HMASTLOCK <= tr.mastlock;

        // Wait for Address Phase to complete
        do begin
            @(vif.master_cb);
        end while (!vif.master_cb.HREADY);

        // Data Phase
        vif.master_cb.HTRANS <= 2'b00; // Return to IDLE unless pipelined

        if (tr.write) begin
            vif.master_cb.HWDATA <= tr.data;
            vif.master_cb.HWSTRB <= tr.strb;
        end else begin
            vif.master_cb.HWDATA <= '0;
            vif.master_cb.HWSTRB <= '0;
        end

        // Wait for Data Phase to complete
        tr.wait_cycles = 0;
        do begin
            @(vif.master_cb);
            if (!vif.master_cb.HREADY) tr.wait_cycles++;
        end while (!vif.master_cb.HREADY);

        // Sample response and read data on completion
        tr.resp = vif.master_cb.HRESP;
        if (!tr.write) begin
            tr.rdata = vif.master_cb.HRDATA;
        end

        // Clean up data bus
        vif.master_cb.HWDATA <= '0;
        vif.master_cb.HWSTRB <= '0;
    endtask

endclass : ahb_driver

`endif // AHB_DRIVER_SV
