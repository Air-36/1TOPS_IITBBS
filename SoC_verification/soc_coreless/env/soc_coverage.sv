// =============================================================================
// Component: soc_coverage
// Purpose: Functional Coverage Collector for Coreless SoC Integration
// =============================================================================

`ifndef SOC_COVERAGE_SV
`define SOC_COVERAGE_SV

class soc_coverage extends uvm_subscriber #(ahb_transfer#(32, 32));
    `uvm_component_utils(soc_coverage)

    ahb_transfer#(32, 32) curr_tr;

    covergroup soc_bus_cg;
        // 1. Slave Address Decode Coverage
        cp_slave_target: coverpoint curr_tr.addr {
            bins boot_rom    = {[32'h0000_1000 : 32'h0000_1FFF]};
            bins clint       = {[32'h0200_0000 : 32'h0200_FFFF]};
            bins core_dbg    = {[32'h0B00_0000 : 32'h0B00_0FFF]};
            bins plic        = {[32'h0C00_0000 : 32'h0FFF_FFFF]};
            bins uart        = {[32'h1000_0000 : 32'h1000_0FFF]};
            bins spi         = {[32'h1004_0000 : 32'h1004_0FFF]};
            bins gpio        = {[32'h1006_0000 : 32'h1006_0FFF]};
            bins sysctrl     = {[32'h1008_0000 : 32'h1008_0FFF]};
            bins multiplier  = {[32'h3000_0000 : 32'h30FF_FFFF]};
            bins ram_instr   = {[32'h8000_0000 : 32'h8000_7FFF]};
            bins ram_data    = {[32'h8001_0000 : 32'h8001_7FFF]};
        }

        // 2. Access Direction
        cp_rw: coverpoint curr_tr.write {
            bins read  = {1'b0};
            bins write = {1'b1};
        }

        // 3. Transfer Size
        cp_size: coverpoint curr_tr.size {
            bins byte_sz = {ahb_transfer#(32, 32)::SZ_BYTE};
            bins half_sz = {ahb_transfer#(32, 32)::SZ_HALFWORD};
            bins word_sz = {ahb_transfer#(32, 32)::SZ_WORD};
        }

        // 4. Cross Coverage: Target Slave x Read/Write
        cross_slave_rw: cross cp_slave_target, cp_rw;

    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        soc_bus_cg = new();
    endfunction

    virtual function void write(ahb_transfer#(32, 32) t);
        curr_tr = t;
        soc_bus_cg.sample();
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SOC_COV", $sformatf("Overall SoC Bus Functional Coverage: %0.2f%%", soc_bus_cg.get_inst_coverage()), UVM_LOW)
    endfunction

endclass : soc_coverage

`endif // SOC_COVERAGE_SV

