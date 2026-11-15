class controller_sequence extends uvm_sequence #(controller_transaction);
    `uvm_object_utils(controller_sequence)

    // Opcodes supported 
    bit [6:0] opcode_list[11] = '{
        7'b0000011,  // LOAD
        7'b0100011,  // STORE
        7'b0110011,  // R-type
        7'b1100011,  // BRANCH
        7'b0010011,  // I-type ALU
        7'b1101111,  // JAL
        7'b1100111,  // JALR
        7'b0010111,  // AUIPC
        7'b0110111,  // LUI
        7'b1110011,  // SYSTEM
        7'b0001111   // FENCE
    };

    function new(string name = "controller_sequence");
        super.new(name);
    endfunction

    task send_instr(input bit [31:0] instr);
        controller_transaction trans;
        trans = controller_transaction::type_id::create("trans");
        start_item(trans);
        trans.InstrD = instr;
        finish_item(trans);
    endtask

    task body();
        controller_transaction trans;
        foreach (opcode_list[i]) begin
            for (int f3 = 0; f3 < 8; f3++) begin
                for (int f7 = 0; f7 < 2; f7++) begin
                    trans = controller_transaction::type_id::create("trans");
                    start_item(trans);
                    trans.InstrD = 32'b0;
                    trans.InstrD[6:0]   = opcode_list[i];
                    trans.InstrD[14:12] = f3;
                    trans.InstrD[30]    = f7;

                    // Exercise non-zero source and destination registers
                    trans.InstrD[19:15] = 5'd1;
                    trans.InstrD[11:7]  = 5'd1;
                    finish_item(trans);
                end
            end
         end

            send_instr(32'h30200073); // MRET
            send_instr(32'h10500073); // WFI
            send_instr(32'h00000073); // ECALL
            send_instr(32'h00100073); // EBREAK
            send_instr(32'h00200073); // Illegal privileged instruction 
            send_instr(32'h300090F3); // CSRRW
            send_instr(32'h3000A0F3); // CSRRS
            send_instr(32'h3000B0F3); // CSRRC
            send_instr(32'h3000D0F3); // CSRRWI
            send_instr(32'h3000E0F3); // CSRRSI
            send_instr(32'h3000F0F3); // CSRRCI 
            send_instr(32'h300020F3); // CSRRS, rs1=0
            send_instr(32'h300030F3); // CSRRC, rs1=0
            send_instr(32'h300060F3); // CSRRSI, zimm=0
            send_instr(32'h300070F3); // CSRRCI, zimm=0 
            send_instr(32'h300010F3); // CSRRW, rs1=0
            send_instr(32'h300050F3); // CSRRWI, zimm=0

    endtask
endclass
