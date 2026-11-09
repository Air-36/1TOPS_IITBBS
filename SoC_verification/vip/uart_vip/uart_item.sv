// =============================================================================
// Class: uart_item
// Purpose: Sequence item representing a single UART byte frame
// =============================================================================

`ifndef UART_ITEM_SV
`define UART_ITEM_SV

class uart_item extends uvm_sequence_item;
    rand bit [7:0] data;
    time           timestamp;

    `uvm_object_utils_begin(uart_item)
        `uvm_field_int(data, UVM_ALL_ON | UVM_HEX)
    `uvm_object_utils_end

    function new(string name = "uart_item");
        super.new(name);
    endfunction

    virtual function string convert2string();
        return $sformatf("UART Byte: 0x%02h ('%c')", data, (data >= 32 && data <= 126) ? data : ".");
    endfunction
endclass : uart_item

`endif

