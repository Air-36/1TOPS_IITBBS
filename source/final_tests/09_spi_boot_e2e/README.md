# Subsystem 09: SPI Boot Flow, End to End

This suite runs every part of the SPI boot flow together, which no other suite does. After a reset, the real CPU executes the real generated boot ROM. It pulls a real boot stream built by `software/make_image.py` from an SPI partner model, over the real SPI controller. It copies the stream into RAM, jumps to it, and the program checks itself. The reset split is checked with the SoC's **default** reset addresses:

| Reset | First fetch |
|---|---|
| System reset, or SYSCTRL soft reset | Boot ROM `0x0000_1000` |
| Debugger core reset | Instruction RAM `0x8000_0000` |

Every other suite overrides both addresses to `0x8000_0000`.

## What is simulated
| Part | Here |
|---|---|
| SoC | `riscv_soc_ahb`, unmodified, at 50 MHz, so the SPI clock is 250 kHz as on the FPGA. The debugger UART runs at 3.125 Mbaud so commands are fast. |
| Boot ROM | Whatever `make -C software rom` generated into `source/uncore/rom_ahb.sv`. The suite refuses to run on the old ROM. |
| Streams | Built by `make_image.py` from `src/boot_e2e.S`: mode 0 `[test]`, mode 1 `[second-stage ROM][test]`, and a corrupted copy for S4 (`scripts/make_bad_stream.py`) |
| Partner | `tb/spi_partner_model.sv`: SPI mode-3 slave with rules R1–R4. Two flavours: *ideal*, which reacts to every edge instantly, and *Pi 4 timed*, which is the bare-metal Pi firmware's polling algorithm with poll period ±25 % jitter and MISO write latency. |
| Terminal | The testbench types real ADP commands on the debugger UART and parses the replies, as on the bench |
| Test program | `src/boot_e2e.S`: code + an expected table in instruction RAM, and the same table as initialised data in data RAM. It writes `0x600DB007` to `0x8001_4000` only if both chunks arrived intact. |

## Scenarios
| Target | Scenario | Pass condition |
|---|---|---|
| `s1` | Mode-0 boot | PASS word; whole stream consumed; 1 CS window; first fetch `0x1000`; CS released; no stray writes |
| `s2` | Mode-1 boot | As s1, with execution passing through `0x8000_7C00` (second-stage ROM). The partner sees 1 or 2 CS windows: see the note below |
| `s3` | Partner not armed | Error `0xE1` at `0x8001_7FFC`; a0 = `0xFFFFFFFF`; both values also read back through the debugger (`A`/`R`) |
| `s4` | First chunk pointed at `0x8000_8000` (gap between the RAMs) | Error `0xE2`; s0/s1 = rejected address/size; program never ran |
| `s5` | Boot, then debugger `C 0201`/`C 0101` | First fetch `0x8000_0000`; **no SPI activity**; program re-runs from RAM and passes |
| `s6` | Boot, then SYSCTRL soft core reset (`0x1008_0000` ← 2, then 3) | First fetch `0x1000`; boots again from the reloaded partner |
| `s7` | (a) System reset without reloading; (b) reset in mid-load | (a) E1 with magic `0xFFFFFFFF`; (b) E1 with the mid-stream bytes as magic. Shows rule R4: a SoC reset never rewinds the partner. |
| `s8a` | Mode-1 boot, Pi 4 timed partner (poll 200 ns, latency 300 ns) | As s2 |
| `s8b` | Mode-0 boot, 5× slower Pi 4 (poll 1000 ns, latency 500 ns) | As s1 |

**Note on chip-select in mode 1.** At the end of the first image the internal ROM releases CS (CSMODE = AUTO). About 100 cycles later the second-stage ROM asserts it again (HOLD). The SPI controller's state machine only advances on its SCLK ticks, every SCKDIV+1 = 100 cycles. So CS can stay low across the hand-over, and does in simulation. That is harmless under the partner rules: bytes stay aligned and the pointer simply continues (R1/R2). The partner must not rely on a CS-high gap between the two images.

## Running
```bash
make -C software rom                          # once: put the SPI loader into the boot ROM RTL
make -C source/final_tests test_09_spi_boot   # all scenarios, QuestaSim
cd source/final_tests/09_spi_boot_e2e
make test_all SIM=icarus                      # same with Icarus Verilog
make s3                                       # one scenario
make streams                                  # only build boot_e2e.elf and the streams (build/)
```
Options:
- `RISCV_PREFIX=riscv-none-elf-` (or a full path prefix) selects the RISC-V GCC. The default is `riscv64-unknown-elf-`.
- `python3` must have `pyelftools`.

Logs are in `build/<scenario>.log`. Each scenario prints its `[PASS]`/`[FAIL]` checks and ends with `SCENARIO <name> RESULT: PASS|FAIL`.

## Run time
The 250 kHz SPI transfer dominates, at about 37 µs per byte: about 9 ms of simulated time for the 248-byte mode-0 stream and 23 ms for the mode-1 stream. With Icarus that is about 1 minute for s1 and up to about 3 minutes for s2, s6 and s7. QuestaSim is faster.

## What passing means
The boot ROM contents, the loader, 250 kHz SPI, the stream format, both boot modes, both error codes, the partner rules and the debug/boot reset split all work together at RTL level, including with the Pi 4 algorithm as the partner. What is left for the bench is physical: wiring and ground, the Pi's real loop timing (its `TIME` command), the FPGA clock and pins, and JTAG through hw_server.
