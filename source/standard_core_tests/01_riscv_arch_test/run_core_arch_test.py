#!/usr/bin/env python3
"""
Automated Test Runner for RISC-V International Architecture Tests on CPU Core Only.
Tests riscv_cpu directly connected to ahb_ram in QuestaSim and validates against Spike ISS.
"""

import os
import sys
import glob
import re
import struct
import shutil
import subprocess
import argparse

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))

def find_tool(tool_names, search_dirs=None):
    if search_dirs:
        for d in search_dirs:
            if not d or not os.path.exists(d):
                continue
            for name in tool_names:
                full_path = os.path.join(d, name)
                if os.path.isfile(full_path) and os.access(full_path, os.X_OK):
                    return full_path
    for name in tool_names:
        p = shutil.which(name)
        if p:
            return p
    return tool_names[0]

RISCV_SEARCH_DIRS = [
    os.environ.get("RISCV_BIN", ""),
    "/home/23EC01043/tools/xpack-riscv-none-elf-gcc-15.2.0-1/bin",
    "/home/23EC01009/cvw/1tops_soc/1tops_iitbbs/riscv_gcc/bin",
    "/cad/mentor/xpack-riscv-none-elf-gcc/bin",
]
SPIKE_SEARCH_DIRS = [
    os.environ.get("RISCV_BIN", ""),
    "/home/23EC01009/cvw/1tops_soc/1tops_iitbbs/spike_iss/install/bin",
]
QUESTA_SEARCH_DIRS = [
    os.environ.get("QUESTA_HOME", ""),
    "/cad/mentor/questa_sim-2023.4_5/questasim/bin",
    "/cad/mentor/questa_sim-2023.4_5/bin",
]

GCC     = find_tool(["riscv-none-elf-gcc",     "riscv32-unknown-elf-gcc",     "riscv64-unknown-elf-gcc"],     RISCV_SEARCH_DIRS)
OBJCOPY = find_tool(["riscv-none-elf-objcopy", "riscv32-unknown-elf-objcopy", "riscv64-unknown-elf-objcopy"], RISCV_SEARCH_DIRS)
NM      = find_tool(["riscv-none-elf-nm",      "riscv32-unknown-elf-nm",      "riscv64-unknown-elf-nm"],      RISCV_SEARCH_DIRS)
SPIKE   = find_tool(["spike"], SPIKE_SEARCH_DIRS)
VSIM    = find_tool(["vsim"], QUESTA_SEARCH_DIRS)
VLOG    = find_tool(["vlog"], QUESTA_SEARCH_DIRS)
VLIB    = find_tool(["vlib"], QUESTA_SEARCH_DIRS)

# Reference test suite (riscv-arch-tests from ibex vendor)
_ARCH_REF = "/home/23EC01043/Desktop/RiscV_Core_verification/IbexDV/ibex/vendor/riscv-arch-tests"
RV32I_SUITE_DIR = os.path.join(_ARCH_REF, "riscv-test-suite/rv32i_m/I/src")
PRIV_SUITE_DIR  = os.path.join(_ARCH_REF, "riscv-test-suite/rv32i_m/privilege/src")
ZICSR_SUITE_DIR = os.path.join(SCRIPT_DIR, "zicsr_env")  # local fallback if no external

# Env headers: all unified in local env directory
ENV_DIR       = os.path.join(SCRIPT_DIR, "env")
MODEL_ENV_DIR = os.path.join(SCRIPT_DIR, "env")
LINK_LD       = os.path.join(SCRIPT_DIR, "env", "link.ld")
ZICSR_ENV_DIR   = os.path.join(SCRIPT_DIR, "zicsr_env")
ZICSR_TESTS_ENV = ZICSR_ENV_DIR

TEST_GROUPS = {
    "alu": [
        "add-01", "addi-01", "and-01", "andi-01", "or-01", "ori-01",
        "xor-01", "xori-01", "sll-01", "slli-01", "srl-01", "srli-01",
        "sra-01", "srai-01", "slt-01", "slti-01", "sltu-01", "sltiu-01",
        "sub-01", "lui-01", "auipc-01"
    ],
    "branch": [
        "beq-01", "bne-01", "blt-01", "bge-01", "bltu-01", "bgeu-01",
        "jal-01", "jalr-01"
    ],
    "memory": [
        "lw-align-01", "lh-align-01", "lhu-align-01", "lb-align-01", "lbu-align-01",
        "sw-align-01", "sh-align-01", "sb-align-01"
    ],
    "priv": [
        "ecall", "ebreak"
    ],
    # Zicsr tests require external test suite not present locally; skip in default 'all' run.
    "zicsr": []
}

# Tests whose source contains 'la x0, ...' (dead code after jalr x0) which newer GAS rejects.
# We preprocess a patched copy replacing 'la\tx0,' / 'la x0,' with 'la t6,' (signature unaffected).
_NEEDS_X0_PATCH = {"jalr-01"}

def run_cmd(cmd, cwd=None):
    res = subprocess.run(cmd, shell=True, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.returncode != 0:
        return False, res.stdout + "\n" + res.stderr
    return True, res.stdout

def preprocess_x0_patch(src_file, build_dir, test_name):
    """Return a patched copy of src_file with 'la x0,' replaced by 'la t6,' to work
    around newer GAS rejecting writes to x0 in dead-code paths (e.g. after jalr x0)."""
    import re
    patched = os.path.join(build_dir, f"{test_name}_patched.S")
    with open(src_file, "r") as f:
        content = f.read()
    # Replace  "la   x0,"  or  "la\tx0,"  with  "la t6,"
    content = re.sub(r'\bla\s+x0\s*,', 'la t6,', content)
    with open(patched, "w") as f:
        f.write(content)
    return patched

def compile_core_rtl():
    """Compiles the CPU core and single-cycle memory fresh into QuestaSim work library."""
    work_dir = os.path.join(SCRIPT_DIR, "work")
    if os.path.exists(work_dir):
        shutil.rmtree(work_dir, ignore_errors=True)

    ok, out = run_cmd(f"{VLIB} work", cwd=SCRIPT_DIR)
    if not ok:
        print(f"[RTL COMPILE ERROR] Failed to vlib work:\n{out}")
        return False

    components = sorted(glob.glob(f"{REPO_ROOT}/components/*.v"))
    core_files = [
        f"{REPO_ROOT}/main/riscv_cpu.v",
        f"{REPO_ROOT}/main/ahb_ram.v",
        f"{SCRIPT_DIR}/tb_core_arch.sv"
    ]
    src_str = " ".join(components + core_files)
    cmd = f"{VLOG} -sv -timescale 1ns/1ps -work work +incdir+{REPO_ROOT}/main +incdir+{REPO_ROOT}/components {src_str}"
    ok, out = run_cmd(cmd, cwd=SCRIPT_DIR)
    if not ok:
        print(f"[RTL COMPILE ERROR] Compilation failed:\n{out}")
        return False
    return True

def locate_source(test_name):
    if test_name.startswith("Zicsr"):
        s = os.path.join(ZICSR_SUITE_DIR, f"{test_name}.S")
        if os.path.exists(s): return s, "zicsr"
    s_priv = os.path.join(PRIV_SUITE_DIR, f"{test_name}.S")
    if os.path.exists(s_priv): return s_priv, "priv"
    s_i = os.path.join(RV32I_SUITE_DIR, f"{test_name}.S")
    if os.path.exists(s_i): return s_i, "rv32i"
    return None, None

def get_symbols(elf_file):
    symbols = {}
    ok, out = run_cmd(f"{NM} {elf_file}")
    if not ok: return symbols
    for line in out.splitlines():
        parts = line.split()
        if len(parts) == 3:
            addr, _, name = parts
            symbols[name] = int(addr, 16)
    return symbols

def bin_to_hex(bin_path, hex_path):
    with open(bin_path, "rb") as f:
        data = f.read()
    pad = (4 - (len(data) % 4)) % 4
    data += b'\x00' * pad
    words = struct.unpack(f"<{len(data)//4}I", data)
    with open(hex_path, "w") as f:
        for w in words:
            f.write(f"{w:08x}\n")

def run_test(test_name, build_dir):
    os.makedirs(build_dir, exist_ok=True)
    src_file, test_type = locate_source(test_name)
    if not src_file:
        print(f"[-] Source file for {test_name} not found!")
        return False

    elf_file = os.path.join(build_dir, f"{test_name}.elf")
    bin_file = os.path.join(build_dir, f"{test_name}.bin")
    hex_file = os.path.join(build_dir, f"{test_name}.hex")
    spike_sig = os.path.join(build_dir, f"{test_name}.spike.sig")
    dut_sig   = os.path.join(build_dir, f"{test_name}.dut.sig")

    tfile = os.path.basename(src_file)
    if test_type == "zicsr":
        compile_cmd = (
            f"{GCC} -march=rv32i_zicsr -mabi=ilp32 -mno-relax -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles "
            f"-T {LINK_LD} -I {ZICSR_ENV_DIR} -I {ZICSR_TESTS_ENV} -DSIGNATURE "
            f"-DSAIL_CLINT_BASE_ADDRESS=0x2000000 -DSAIL_SIMPLE_INTERRUPT_GENERATOR_BASE_ADDRESS=0x3000000 "
            f'-DTEST_FILE=\\"{tfile}\\" -DXLEN=32 '
            f"{src_file} -o {elf_file}"
        )
        spike_isa = "rv32i_zicsr"
    elif test_type == "priv":
        compile_cmd = (
            f"{GCC} -march=rv32i_zicsr -mabi=ilp32 -mno-relax -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles "
            f"-T {LINK_LD} -I {MODEL_ENV_DIR} -I {ENV_DIR} -DTEST_CASE_1=True -Drvtest_mtrap_routine=True -DXLEN=32 "
            f"{src_file} -o {elf_file}"
        )
        spike_isa = "rv32i_zicsr"
    else:
        compile_cmd = (
            f"{GCC} -march=rv32i -mabi=ilp32 -mno-relax -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles "
            f"-T {LINK_LD} -I {MODEL_ENV_DIR} -I {ENV_DIR} -DTEST_CASE_1=True -DXLEN=32 "
            f"{src_file} -o {elf_file}"
        )
        spike_isa = "rv32i"

    ok, out = run_cmd(compile_cmd)
    if not ok:
        print(f"[-] GCC Compilation failed for {test_name}:\n{out}")
        return False

    # Extract binary & hex
    run_cmd(f"{OBJCOPY} -O binary {elf_file} {bin_file}")
    bin_to_hex(bin_file, hex_file)

    symbols = get_symbols(elf_file)
    begin_sig = symbols.get("begin_signature", 0)
    end_sig   = symbols.get("end_signature", 0)
    tohost    = symbols.get("tohost", 0)

    # 1. Run Spike Golden Model
    spike_cmd = f"{SPIKE} --isa={spike_isa} --priv=m --disable-dtb +signature={spike_sig} +signature-granularity=4 {elf_file}"
    ok, out = run_cmd(spike_cmd)
    if not ok or not os.path.exists(spike_sig):
        print(f"[-] Spike execution failed for {test_name}:\n{out}")
        return False

    # 2. Run QuestaSim on CPU Core Only
    vsim_cmd = (
        f"{VSIM} -c -do \"run -all; quit -f\" work.tb_core_arch "
        f"\"+HEX={hex_file}\" \"+SIG={dut_sig}\" \"+TOHOST={tohost:x}\" "
        f"\"+BEGIN_SIG={begin_sig:x}\" \"+END_SIG={end_sig:x}\" \"+MAX_CYCLES=200000\""
    )
    ok, out = run_cmd(vsim_cmd, cwd=SCRIPT_DIR)
    if not ok or not os.path.exists(dut_sig):
        print(f"[-] QuestaSim execution failed for {test_name}:\n{out}")
        return False

    # 3. Compare Signatures
    with open(spike_sig, "r") as f:
        spike_lines = [l.strip().lower() for l in f if l.strip()]
    with open(dut_sig, "r") as f:
        dut_lines = [l.strip().lower() for l in f if l.strip()]

    if spike_lines == dut_lines:
        print(f"  [PASS] {test_name:<20} (Signature match: {len(dut_lines)} words)")
        return True
    else:
        print(f"  [FAIL] {test_name:<20} Signature MISMATCH!")
        for idx, (exp, act) in enumerate(zip(spike_lines, dut_lines)):
            if exp != act:
                print(f"         Word {idx}: Spike=0x{exp} vs DUT=0x{act}")
                break
        return False

def main():
    parser = argparse.ArgumentParser(description="RISC-V CPU Core Architecture Compliance Runner")
    parser.add_argument("--group", choices=["alu", "branch", "memory", "priv", "zicsr", "all"], default="all")
    parser.add_argument("--test", type=str, help="Specific test to execute")
    parser.add_argument("--recompile-rtl", action="store_true", default=True, help="Recompile core RTL fresh")
    args = parser.parse_args()

    print("==================================================================")
    print(" RISC-V International Architecture Tests (CPU Core Only vs Spike)")
    print("==================================================================")

    if args.recompile_rtl:
        print("[*] Compiling riscv_cpu RTL and testbench fresh in QuestaSim...")
        if not compile_core_rtl():
            sys.exit(1)
        print("[+] RTL Compilation successful.\n")

    build_dir = os.path.join(SCRIPT_DIR, "build")
    os.makedirs(build_dir, exist_ok=True)

    tests_to_run = []
    if args.test:
        tests_to_run = [args.test]
    elif args.group == "all":
        for grp in ["alu", "branch", "memory", "priv", "zicsr"]:
            tests_to_run.extend(TEST_GROUPS[grp])
    else:
        tests_to_run = TEST_GROUPS[args.group]

    passed = 0
    failed = 0
    for t in tests_to_run:
        res = run_test(t, build_dir)
        if res: passed += 1
        else: failed += 1

    print("\n------------------------------------------------------------------")
    print(f" ARCHITECTURE TEST RESULTS: {passed} PASSED, {failed} FAILED (Total: {len(tests_to_run)})")
    print("------------------------------------------------------------------")

    if failed == 0:
        print(">>> ALL CPU CORE ARCHITECTURAL COMPLIANCE TESTS PASSED! <<<\n")
        sys.exit(0)
    else:
        print(">>> ARCHITECTURAL COMPLIANCE VERIFICATION FAILED! <<<\n")
        sys.exit(1)

if __name__ == "__main__":
    main()
