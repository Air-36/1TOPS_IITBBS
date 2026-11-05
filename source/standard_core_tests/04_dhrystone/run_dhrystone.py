#!/usr/bin/env python3
"""
Automated Build & Execution Runner for Dhrystone 2.1 on Pure CPU Core.
"""

import os
import sys
import glob
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
    "/cad/mentor/xpack-riscv-none-elf-gcc/bin",
    "/home/23EC01009/cvw/1tops_soc/1tops_iitbbs/riscv_gcc/bin",
]
QUESTA_SEARCH_DIRS = [
    os.environ.get("QUESTA_HOME", ""),
    "/cad/mentor/questa_sim-2023.4_5/questasim/bin",
    "/cad/mentor/questa_sim-2023.4_5/bin"
]

GCC = find_tool(["riscv-none-elf-gcc", "riscv32-unknown-elf-gcc", "riscv64-unknown-elf-gcc"], RISCV_SEARCH_DIRS)
OBJCOPY = find_tool(["riscv-none-elf-objcopy", "riscv32-unknown-elf-objcopy", "riscv64-unknown-elf-objcopy"], RISCV_SEARCH_DIRS)
VSIM = find_tool(["vsim"], QUESTA_SEARCH_DIRS)
VLOG = find_tool(["vlog"], QUESTA_SEARCH_DIRS)
VLIB = find_tool(["vlib"], QUESTA_SEARCH_DIRS)

def run_cmd(cmd, cwd=None):
    res = subprocess.run(cmd, shell=True, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return res.returncode == 0, res.stdout

def compile_core_rtl():
    work_dir = os.path.join(SCRIPT_DIR, "work")
    if os.path.exists(work_dir):
        shutil.rmtree(work_dir)
    
    ok, out = run_cmd(f"{VLIB} work", cwd=SCRIPT_DIR)
    if not ok:
        print(f"[-] vlib failed:\n{out}")
        return False

    components = sorted(glob.glob(f"{REPO_ROOT}/components/*.v"))
    core_files = [
        f"{REPO_ROOT}/main/riscv_cpu.v",
        f"{REPO_ROOT}/main/ahb_ram.v",
        f"{SCRIPT_DIR}/tb_core_dhrystone.sv"
    ]
    src_str = " ".join(components + core_files)
    vlog_cmd = f"{VLOG} -sv -timescale 1ns/1ps -work work +incdir+{REPO_ROOT}/main +incdir+{REPO_ROOT}/components {src_str}"
    ok, out = run_cmd(vlog_cmd, cwd=SCRIPT_DIR)
    if not ok:
        print(f"[-] vlog failed:\n{out}")
        return False
    return True

def bin_to_hex(bin_path, hex_path):
    with open(bin_path, "rb") as f:
        data = f.read()
    pad = (4 - (len(data) % 4)) % 4
    data += b'\x00' * pad
    words = struct.unpack(f"<{len(data)//4}I", data)
    with open(hex_path, "w") as f:
        for w in words:
            f.write(f"{w:08x}\n")

def main():
    parser = argparse.ArgumentParser(description="Dhrystone 2.1 CPU Core Runner")
    parser.add_argument("--runs", type=int, default=100, help="Number of benchmark iterations")
    parser.add_argument("--recompile-rtl", action="store_true", default=True, help="Recompile core RTL fresh")
    args = parser.parse_args()

    print("==================================================================")
    print(" Dhrystone 2.1 Integer Benchmark (Pure CPU Core Only)             ")
    print("==================================================================")

    if args.recompile_rtl:
        print("[*] Compiling riscv_cpu RTL and testbench fresh in QuestaSim...")
        if not compile_core_rtl():
            sys.exit(1)
        print("[+] RTL Compilation successful.\n")

    build_dir = os.path.join(SCRIPT_DIR, "build")
    os.makedirs(build_dir, exist_ok=True)

    elf_file = os.path.join(build_dir, "dhrystone.elf")
    bin_file = os.path.join(build_dir, "dhrystone.bin")
    hex_file = os.path.join(build_dir, "dhrystone.hex")

    c_sources = glob.glob(os.path.join(SCRIPT_DIR, "src", "*.c"))
    bsp_c = os.path.join(SCRIPT_DIR, "bsp", "syscalls.c")
    bsp_s = os.path.join(SCRIPT_DIR, "bsp", "crt.S")
    link_ld = os.path.join(SCRIPT_DIR, "bsp", "link.ld")

    compile_cmd = (
        f"{GCC} -O2 -march=rv32i_zicsr_zicntr -mabi=ilp32 -mno-relax -static -nostdlib -nostartfiles "
        f"-T {link_ld} {bsp_s} {bsp_c} {' '.join(c_sources)} "
        f"-I {os.path.join(SCRIPT_DIR, 'src')} -I {os.path.join(SCRIPT_DIR, 'bsp')} "
        f"-DNUMBER_OF_RUNS={args.runs} -o {elf_file} -lgcc"
    )

    print("[*] Compiling Dhrystone C source with GCC...")
    ok, out = run_cmd(compile_cmd)
    if not ok:
        print(f"[-] Compilation failed:\n{out}")
        sys.exit(1)
    print("[+] Dhrystone ELF successfully compiled.")

    run_cmd(f"{OBJCOPY} -O binary {elf_file} {bin_file}")
    bin_to_hex(bin_file, hex_file)

    print("[*] Running Dhrystone on riscv_cpu in QuestaSim...\n")
    vsim_cmd = f"{VSIM} -c -voptargs=\"+acc\" -do \"run -all; quit -f\" work.tb_core_dhrystone \"+HEX={hex_file}\""
    
    p = subprocess.Popen(vsim_cmd, shell=True, cwd=SCRIPT_DIR, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    passed = False
    for line in iter(p.stdout.readline, ''):
        line_clean = line.rstrip()
        if line_clean.startswith("# Loading") or line_clean.startswith("# ** Note: (vsim-3812") or line_clean.startswith("# Reading"):
            continue
        if line_clean.startswith("# "):
            line_clean = line_clean[2:]
        if line_clean:
            print(line_clean)
            sys.stdout.flush()
        if "[PASS]" in line:
            passed = True

    p.wait()

    if passed:
        print("\n>>> DHRYSTONE 2.1 BENCHMARK EXECUTION SUCCESSFUL! <<<\n")
        sys.exit(0)
    else:
        print("\n>>> DHRYSTONE 2.1 BENCHMARK FAILED! <<<\n")
        sys.exit(1)

if __name__ == "__main__":
    main()
