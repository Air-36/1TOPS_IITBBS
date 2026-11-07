// -----------------------------------------------------------------------------
// RTLvision PRO Filelist for 1TOPS SoC
// Sourced strictly from: 1tops_soc/source/
// -----------------------------------------------------------------------------

// Include directories
+incdir+../source/components
+incdir+../source/debugger
+incdir+../source/main
+incdir+../source/main/soc
+incdir+../source/uncore

// 1. Core Components (source/components/)
../source/components/adder.v
../source/components/ahbinterface.v
../source/components/alu.v
../source/components/alu_decoder.v
../source/components/branching_unit.v
../source/components/controller.v
../source/components/csr_file.v
../source/components/datapath.v
../source/components/ebu.v
../source/components/hazard.v
../source/components/imm_extend.v
../source/components/main_decoder.v
../source/components/mux2.v
../source/components/mux3.v
../source/components/mux4.v
../source/components/mux5.v
../source/components/pl_reg_de.v
../source/components/pl_reg_em.v
../source/components/pl_reg_fd.v
../source/components/pl_reg_mw.v
../source/components/priv_decoder.v
../source/components/reg_file.v
../source/components/reset_ff.v
../source/components/subword_unit.v
../source/components/trap_unit.v

// 2. CPU Core Top Level (source/main/)
../source/main/riscv_cpu.v

// 3. Post-Mortem Hardware Debugger Subsystem (source/debugger/)
../source/debugger/core_debug_ahb.v
../source/debugger/core_step_controller.sv
../source/debugger/ahb_mux.sv
../source/debugger/riscv_debugger_top.sv
../source/debugger/socdebug_adp_control.v
../source/debugger/socdebug_ahb.v
../source/debugger/socdebug_ft1248_control.v
../source/debugger/socdebug_uart.v

// 4. Uncore Subsystem & Peripherals (source/uncore/)
../source/uncore/ahbapbbridge.sv
../source/uncore/clint_apb.sv
../source/uncore/gpio_apb.sv
../source/uncore/plic_apb.sv
../source/uncore/ram_ahb.sv
../source/uncore/rom_ahb.sv
../source/uncore/spi_apb.sv
../source/uncore/spi_controller.sv
../source/uncore/spi_fifo.sv
../source/uncore/uart_apb.sv
../source/uncore/uartPC16550D.sv
../source/uncore/sysctrl_apb.sv
../source/uncore/uncore.sv

// 5. SoC Interconnect, Accelerator & Top-Level (source/main/soc/)
../source/main/soc/multiplier_ahb.v
../source/main/soc/riscv_soc_ahb.v
