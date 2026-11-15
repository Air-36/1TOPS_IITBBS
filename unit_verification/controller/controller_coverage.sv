class controller_coverage extends uvm_subscriber #(controller_transaction);
    `uvm_component_utils(controller_coverage)

    bit [6:0] opcode;
    bit [2:0] funct3;
    bit funct7b5;

    int sample_count;

    covergroup controller_cg;
        option.per_instance = 1;

        // All 11 supported opcode patterns
        cp_opcode: coverpoint opcode {
            bins load   = {7'b0000011};
            bins store  = {7'b0100011};
            bins rtype  = {7'b0110011};
            bins branch = {7'b1100011};
            bins itype  = {7'b0010011};
            bins jal    = {7'b1101111};
            bins jalr   = {7'b1100111};
            bins auipc  = {7'b0010111};
            bins lui    = {7'b0110111};
            bins system = {7'b1110011};
            bins fence  = {7'b0001111};
        }

        // All eight funct3 values
        cp_funct3: coverpoint funct3 {
            bins funct3_values[] = {[0:7]};
        }

        // Both values of instruction bit 30
        cp_funct7: coverpoint funct7b5 {
            bins zero = {0};
            bins one  = {1};
        }

        // Required cross coverage
        opcode_funct3_funct7_cross:
            cross cp_opcode, cp_funct3, cp_funct7;

    endgroup


    function new(string name = "controller_coverage", uvm_component parent = null);
        super.new(name, parent);
        controller_cg = new();
        sample_count = 0;
    endfunction

    function void write(controller_transaction trans);
        opcode   = trans.InstrD[6:0];
        funct3   = trans.InstrD[14:12];
        funct7b5 = trans.InstrD[30];
        controller_cg.sample();
        sample_count++;
    endfunction


    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        
        `uvm_info("CTRL_COVERAGE",
            $sformatf("Samples = %0d", sample_count),
            UVM_NONE)

        `uvm_info("CTRL_COVERAGE",
            $sformatf("Opcode x Funct3 x Funct7[5] Coverage = %0.2f%%",
                      controller_cg.get_coverage()),
            UVM_NONE)

        if (controller_cg.get_coverage() == 100.0)
            `uvm_info("CTRL_COVERAGE",
                "CROSS COVERAGE CLOSED",
                UVM_NONE)
        else
            `uvm_error("CTRL_COVERAGE",
                "CROSS COVERAGE NOT CLOSED")

    endfunction

endclass
