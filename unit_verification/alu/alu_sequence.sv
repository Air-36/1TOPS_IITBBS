class alu_sequence extends uvm_sequence #(alu_transaction);
    `uvm_object_utils(alu_sequence)

    function new(string name = "alu_sequence");
        super.new(name);
    endfunction

    task body();
        alu_transaction tr;
        bit [31:0] values[5] = '{
            32'h00000000,
            32'h00000001,
            32'hFFFFFFFF,
            32'h7FFFFFFF,
            32'h80000000
        };

        // Directed tests:
        for (int op = 0; op < 10; op++) begin
            for (int i = 0; i < 5; i++) begin
                tr = alu_transaction::type_id::create("tr");
                start_item(tr);
                tr.alu_ctrl = op;
                tr.a = values[i];
                tr.b = values[i];
                finish_item(tr);
            end

            // Signed comparison combinations
            tr = alu_transaction::type_id::create("tr");
            start_item(tr);
            tr.alu_ctrl = op;
            tr.a = 32'h00000001;
            tr.b = 32'hFFFFFFFF;
            finish_item(tr);

            tr = alu_transaction::type_id::create("tr");
            start_item(tr);
            tr.alu_ctrl = op;
            tr.a = 32'hFFFFFFFF;
            tr.b = 32'h00000001;
            finish_item(tr);
        end

        //random testing
        repeat (100) begin
            tr = alu_transaction::type_id::create("tr");
            start_item(tr);
            if (!tr.randomize())
                `uvm_error("ALU_SEQ", "Randomization failed")
            finish_item(tr);
        end
    endtask
endclass
