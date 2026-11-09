// =============================================================================
// Package / Classes: soc_ral_model
// Purpose: UVM Register Abstraction Layer (RAL) Model & AHB Adapter for 1TOPS SoC
// =============================================================================

`ifndef SOC_RAL_MODEL_SV
`define SOC_RAL_MODEL_SV

// -----------------------------------------------------------------------------
// 1. AHB-to-RAL Adapter
// -----------------------------------------------------------------------------
class ahb_reg_adapter extends uvm_reg_adapter;
    `uvm_object_utils(ahb_reg_adapter)

    function new(string name = "ahb_reg_adapter");
        super.new(name);
        supports_byte_enable = 1;
        provides_responses   = 1;
    endfunction

    virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
        ahb_transfer#(32, 32) tr = ahb_transfer#(32, 32)::type_id::create("tr");
        tr.addr  = rw.addr;
        tr.write = (rw.kind == UVM_WRITE);
        tr.data  = rw.data;
        tr.trans = ahb_transfer#(32, 32)::TR_NONSEQ;
        tr.size  = ahb_transfer#(32, 32)::SZ_WORD;
        tr.burst = ahb_transfer#(32, 32)::BURST_SINGLE;
        tr.strb  = rw.byte_en ? rw.byte_en : 4'b1111;
        return tr;
    endfunction

    virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
        ahb_transfer#(32, 32) tr;
        if (!$cast(tr, bus_item)) begin
            `uvm_fatal("NOT_AHB_TYPE", "Provided bus_item is not of the correct type")
            return;
        end
        rw.kind    = tr.write ? UVM_WRITE : UVM_READ;
        rw.addr    = tr.addr;
        rw.data    = tr.write ? tr.data : tr.rdata;
        rw.status  = (tr.resp == 1'b0) ? UVM_IS_OK : UVM_NOT_OK;
        rw.byte_en = tr.strb;
    endfunction
endclass : ahb_reg_adapter

// -----------------------------------------------------------------------------
// 2. Generic Register Class
// -----------------------------------------------------------------------------
class soc_standard_reg extends uvm_reg;
    `uvm_object_utils(soc_standard_reg)

    rand uvm_reg_field val;

    function new(string name = "soc_standard_reg", int width = 32);
        super.new(name, width, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        val = uvm_reg_field::type_id::create("val");
        val.configure(this, 32, 0, "RW", 0, 32'h0, 1, 0, 1);
    endfunction
endclass : soc_standard_reg

// -----------------------------------------------------------------------------
// 3. SysCtrl Register Block
// -----------------------------------------------------------------------------
class sysctrl_reg_block extends uvm_reg_block;
    `uvm_object_utils(sysctrl_reg_block)

    rand soc_standard_reg reset_ctrl;
    rand soc_standard_reg reset_vec;
    rand soc_standard_reg boot_status;
    rand soc_standard_reg remap_ctrl;
    rand soc_standard_reg clk_ctrl;
    rand soc_standard_reg scratchpad;
    rand soc_standard_reg sys_id;

    function new(string name = "sysctrl_reg_block");
        super.new(name, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        reset_ctrl  = soc_standard_reg::type_id::create("reset_ctrl");
        reset_vec   = soc_standard_reg::type_id::create("reset_vec");
        boot_status = soc_standard_reg::type_id::create("boot_status");
        remap_ctrl  = soc_standard_reg::type_id::create("remap_ctrl");
        clk_ctrl    = soc_standard_reg::type_id::create("clk_ctrl");
        scratchpad  = soc_standard_reg::type_id::create("scratchpad");
        sys_id      = soc_standard_reg::type_id::create("sys_id");

        reset_ctrl.configure(this, null, "");  reset_ctrl.build();
        reset_vec.configure(this, null, "");   reset_vec.build();
        boot_status.configure(this, null, ""); boot_status.build();
        remap_ctrl.configure(this, null, "");  remap_ctrl.build();
        clk_ctrl.configure(this, null, "");    clk_ctrl.build();
        scratchpad.configure(this, null, "");  scratchpad.build();
        sys_id.configure(this, null, "");      sys_id.build();

        default_map = create_map("sysctrl_map", 'h0, 4, UVM_LITTLE_ENDIAN);
        default_map.add_reg(reset_ctrl,  32'h00, "RW");
        default_map.add_reg(reset_vec,   32'h04, "RW");
        default_map.add_reg(boot_status, 32'h08, "RO");
        default_map.add_reg(remap_ctrl,  32'h0C, "RW");
        default_map.add_reg(clk_ctrl,    32'h10, "RW");
        default_map.add_reg(scratchpad,  32'h14, "RW");
        default_map.add_reg(sys_id,      32'h18, "RO");
    endfunction
endclass : sysctrl_reg_block

// -----------------------------------------------------------------------------
// 4. GPIO Register Block
// -----------------------------------------------------------------------------
class gpio_reg_block extends uvm_reg_block;
    `uvm_object_utils(gpio_reg_block)

    rand soc_standard_reg input_val;
    rand soc_standard_reg input_en;
    rand soc_standard_reg output_en;
    rand soc_standard_reg output_val;
    rand soc_standard_reg rise_ie;
    rand soc_standard_reg rise_ip;
    rand soc_standard_reg fall_ie;
    rand soc_standard_reg fall_ip;

    function new(string name = "gpio_reg_block");
        super.new(name, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        input_val  = soc_standard_reg::type_id::create("input_val");
        input_en   = soc_standard_reg::type_id::create("input_en");
        output_en  = soc_standard_reg::type_id::create("output_en");
        output_val = soc_standard_reg::type_id::create("output_val");
        rise_ie    = soc_standard_reg::type_id::create("rise_ie");
        rise_ip    = soc_standard_reg::type_id::create("rise_ip");
        fall_ie    = soc_standard_reg::type_id::create("fall_ie");
        fall_ip    = soc_standard_reg::type_id::create("fall_ip");

        input_val.configure(this, null, "");  input_val.build();
        input_en.configure(this, null, "");   input_en.build();
        output_en.configure(this, null, "");  output_en.build();
        output_val.configure(this, null, ""); output_val.build();
        rise_ie.configure(this, null, "");    rise_ie.build();
        rise_ip.configure(this, null, "");    rise_ip.build();
        fall_ie.configure(this, null, "");    fall_ie.build();
        fall_ip.configure(this, null, "");    fall_ip.build();

        default_map = create_map("gpio_map", 'h0, 4, UVM_LITTLE_ENDIAN);
        default_map.add_reg(input_val,  32'h00, "RO");
        default_map.add_reg(input_en,   32'h04, "RW");
        default_map.add_reg(output_en,  32'h08, "RW");
        default_map.add_reg(output_val, 32'h0C, "RW");
        default_map.add_reg(rise_ie,    32'h18, "RW");
        default_map.add_reg(rise_ip,    32'h1C, "RW");
        default_map.add_reg(fall_ie,    32'h20, "RW");
        default_map.add_reg(fall_ip,    32'h24, "RW");
    endfunction
endclass : gpio_reg_block

// -----------------------------------------------------------------------------
// 5. Multiplier Accelerator Register Block
// -----------------------------------------------------------------------------
class multiplier_reg_block extends uvm_reg_block;
    `uvm_object_utils(multiplier_reg_block)

    rand soc_standard_reg operand_a;
    rand soc_standard_reg operand_b;
    rand soc_standard_reg product;

    function new(string name = "multiplier_reg_block");
        super.new(name, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        operand_a = soc_standard_reg::type_id::create("operand_a");
        operand_b = soc_standard_reg::type_id::create("operand_b");
        product   = soc_standard_reg::type_id::create("product");

        operand_a.configure(this, null, ""); operand_a.build();
        operand_b.configure(this, null, ""); operand_b.build();
        product.configure(this, null, "");   product.build();

        default_map = create_map("multiplier_map", 'h0, 4, UVM_LITTLE_ENDIAN);
        default_map.add_reg(operand_a, 32'h00, "RW");
        default_map.add_reg(operand_b, 32'h04, "RW");
        default_map.add_reg(product,   32'h08, "RO");
    endfunction
endclass : multiplier_reg_block

// -----------------------------------------------------------------------------
// 6. Top SoC RAL Model
// -----------------------------------------------------------------------------
class soc_ral_model extends uvm_reg_block;
    `uvm_object_utils(soc_ral_model)

    rand sysctrl_reg_block    sysctrl;
    rand gpio_reg_block       gpio;
    rand multiplier_reg_block multiplier;

    function new(string name = "soc_ral_model");
        super.new(name, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        default_map = create_map("soc_map", 32'h0000_0000, 4, UVM_LITTLE_ENDIAN);

        sysctrl = sysctrl_reg_block::type_id::create("sysctrl");
        sysctrl.configure(this);
        sysctrl.build();
        default_map.add_submap(sysctrl.default_map, 32'h1008_0000);

        gpio = gpio_reg_block::type_id::create("gpio");
        gpio.configure(this);
        gpio.build();
        default_map.add_submap(gpio.default_map, 32'h1006_0000);

        multiplier = multiplier_reg_block::type_id::create("multiplier");
        multiplier.configure(this);
        multiplier.build();
        default_map.add_submap(multiplier.default_map, 32'h3000_0000);

        lock_model();
    endfunction
endclass : soc_ral_model

`endif // SOC_RAL_MODEL_SV
