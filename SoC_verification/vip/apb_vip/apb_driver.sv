// =============================================================================
// Component: apb_driver
// Purpose: AMBA 3 APB Master Driver
// =============================================================================

`ifndef APB_DRIVER_SV
`define APB_DRIVER_SV

class apb_driver #(parameter ADDR_WIDTH = 32, parameter DATA_WIDTH = 32)
    extends uvm_driver #(apb_transfer #(ADDR_WIDTH, DATA_WIDTH));

    `uvm_component_param_utils(apb_driver #(ADDR_WIDTH, DATA_WIDTH))

    virtual apb_if #(ADDR_WIDTH, DATA_WIDTH) vif;
    apb_config cfg;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual apb_if #(ADDR_WIDTH, DATA_WIDTH))::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        reset_signals();

        @(posedge vif.PRESETn);
        @(vif.master_cb);

        forever begin
            seq_item_port.get_next_item(req);
            drive_transfer(req);
            seq_item_port.item_done();
        end
    endtask

    virtual task reset_signals();
        vif.master_cb.PSEL    <= 1'b0;
        vif.master_cb.PENABLE <= 1'b0;
        vif.master_cb.PWRITE  <= 1'b0;
        vif.master_cb.PADDR   <= '0;
        vif.master_cb.PWDATA  <= '0;
        vif.master_cb.PSTRB   <= '0;
    endtask

    virtual task drive_transfer(apb_transfer #(ADDR_WIDTH, DATA_WIDTH) tr);
        // Setup Phase
        vif.master_cb.PSEL    <= 1'b1;
        vif.master_cb.PENABLE <= 1'b0;
        vif.master_cb.PADDR   <= tr.addr;
        vif.master_cb.PWRITE  <= tr.write;
        vif.master_cb.PWDATA  <= tr.write ? tr.data : '0;
        vif.master_cb.PSTRB   <= tr.strb;

        @(vif.master_cb);

        // Access Phase
        vif.master_cb.PENABLE <= 1'b1;
        tr.wait_cycles = 0;

        @(vif.master_cb);
        while (!vif.master_cb.PREADY) begin
            tr.wait_cycles++;
            @(vif.master_cb);
        end

        // Sample on PREADY == 1
        if (!tr.write) begin
            tr.rdata = vif.PRDATA;
        end
        tr.slverr = vif.PSLVERR;

        // End of transfer
        vif.master_cb.PSEL    <= 1'b0;
        vif.master_cb.PENABLE <= 1'b0;
        vif.master_cb.PWRITE  <= 1'b0;
        vif.master_cb.PWDATA  <= '0;
        vif.master_cb.PSTRB   <= '0;
    endtask

endclass : apb_driver

`endif // APB_DRIVER_SV
