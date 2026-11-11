# 08_debugger_verification

Self-checking verification of the debugger subsystem.

| Suite | Files | What it covers |
|---|---|---|
| block | tb_dbg_block.sv, tb_models.sv, sva_dbg.sv | riscv_debugger_top + ahb_mux + core_step_controller: every ADP command, parser edge cases, UART and FT1248 links, bus errors, wait states, random core traffic, step controller, 200 random commands (528 checks) |
| soc | tb_soc_dbg_full.sv, progD.S (+ progA, progB) | full riscv_soc_ahb through the debugger pins: halt/step, GPR/CSR/PC/trace readback, traps, interrupt, reset, upload/poll, FT1248 (84 checks) |

Run using Makefile (QuestaSim default, clean recompile):

    make test_all                  # Run both block and full-SoC suites on QuestaSim
    make test_block                # Run block-level suite on QuestaSim
    make test_soc                  # Run full-SoC suite on QuestaSim
    make test_icarus               # Run both suites on Icarus Verilog
    make clean                     # Clean all build and simulation artifacts

Or run scripts directly (paths default to this repo):

    block/run_icarus.sh            # Icarus 12
    block/run_verilator.sh         # Verilator 5 + SVA
    soc/run_icarus.sh              # Icarus 12
    soc/run_verilator.sh "" 2      # Verilator, RAM latency 2
    soc/build_prog.sh progD        # rebuild test program (autodetects riscv-none-elf-gcc / riscv64-unknown-elf-gcc)

Verdicts: PASS | FAIL (new bug) | XFAIL{id} (known open bug reproduced) | XPASS{id} (known bug gone: remove the tag).
Expected today: block 524 PASS / 0 FAIL / 3 XFAIL, soc 75 PASS / 0 FAIL / 9 XFAIL.
Open tags: C11 (COMMANDS.md vs RTL), A3 (no default slave), core N2, N3, N8, N9.
