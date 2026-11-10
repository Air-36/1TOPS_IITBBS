class branch_sequence extends uvm_sequence #(branch_transaction);
    `uvm_object_utils(branch_sequence)

    function new(string name = "branch_sequence");
        super.new(name);
    endfunction

    task body();
        branch_transaction tx;

        for (int f = 0; f < 8; f++) begin
            for (int flags = 0; flags < 8; flags++) begin
                tx = branch_transaction::type_id::create("tx");
                start_item(tx);
                tx.funct3 = f;
                tx.Zero   = flags[2];
                tx.Less   = flags[1];
                tx.LessU  = flags[0];
                finish_item(tx);
            end
        end
    endtask
endclass

