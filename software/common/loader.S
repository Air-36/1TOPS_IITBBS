# loader.S - shared SPI loader, included by BOTH boot ROMs.
# Uses no stack. Never returns: ends in a jump (success) or err loop.
# Clobbers t0-t6, a0, s0, s1.

# ---- SPI IP (from register map) ----
.equ SPI_BASE,    0x10040000
.equ SPI_SCKDIV,  0x00
.equ SPI_SCKMODE, 0x04
.equ SPI_CSID,    0x10
.equ SPI_CSDEF,   0x14
.equ SPI_CSMODE,  0x18
.equ SPI_FMT,     0x40
.equ SPI_TXDATA,  0x48
.equ SPI_RXDATA,  0x4C

.equ SCKDIV_VAL,  24            # SCLK = clk/(2*(24+1)): 1 MHz at 50 MHz (FPGA), 2 MHz at 100 MHz
.equ SCKMODE_VAL, 3             # CPOL=1, CPHA=1 (mode 3), so Pico can keep CS low across bytes
.equ CSMODE_AUTO, 0
.equ CSMODE_HOLD, 2

# ---- Memory (from link.ld / riscv_soc_ahb.v): two separate 32 KB windows with a gap between ----
.equ IMEM_BASE,   0x80000000    # instruction RAM 0x8000_0000 - 0x8000_7FFF
.equ IMEM_END,    0x80008000
.equ DMEM_BASE,   0x80010000    # data RAM        0x8001_0000 - 0x8001_7FFF
.equ DMEM_END,    0x80018000
.equ WIN_SIZE,    0x8000        # largest chunk that fits a window
.equ ERR_ADDR,    0x80017FFC    # error code written here (top word of DMEM; debugger can read it)

.equ MAGIC,       0x544F4F42    # bytes 'B','O','O','T' sent lowest byte first

spi_init:
    li   t0, SPI_BASE
    li   t1, SCKDIV_VAL
    sw   t1, SPI_SCKDIV(t0)
    li   t1, SCKMODE_VAL
    sw   t1, SPI_SCKMODE(t0)
    sw   zero, SPI_CSID(t0)           # CS line 0
    li   t1, 0xF
    sw   t1, SPI_CSDEF(t0)            # idle high
    sw   zero, SPI_CSMODE(t0)         # AUTO (CS inactive)
    li   t1, 0x00080000
    sw   t1, SPI_FMT(t0)              # 8-bit frames, MSB first
1:  lw   t1, SPI_RXDATA(t0)           # drain any stale RX bytes
    bgez t1, 1b                       # bit31=0 -> a byte was present, keep popping
    ret

spi_cs_low:
    li   t0, SPI_BASE
    li   t1, CSMODE_HOLD
    sw   t1, SPI_CSMODE(t0)
    ret

spi_cs_high:
    li   t0, SPI_BASE
    li   t1, CSMODE_AUTO
    sw   t1, SPI_CSMODE(t0)
    ret

# returns one byte in a0 (clobbers t0, t1)
spi_read_byte:
    li   t0, SPI_BASE
1:  lw   t1, SPI_TXDATA(t0)
    bltz t1, 1b                       # bit31 = TX FIFO full -> wait
    sw   zero, SPI_TXDATA(t0)         # dummy byte: 8 clocks, 1 byte comes in
2:  lw   a0, SPI_RXDATA(t0)
    bltz a0, 2b                       # bit31 = RX empty -> wait
    andi a0, a0, 0xFF
    ret

# returns 32-bit little-endian word in a0 (clobbers t0-t6)
spi_read_word:
    mv   t6, ra
    li   t3, 0
    li   t4, 0
    li   t5, 32
1:  call spi_read_byte
    sll  a0, a0, t4
    or   t3, t3, a0
    addi t4, t4, 8
    bne  t4, t5, 1b
    mv   a0, t3
    jr   t6

# load_image: read one image from the SPI slave, then jump to its entry point.
load_image:
    call spi_cs_low
    call spi_read_word
    li   t0, MAGIC
    bne  a0, t0, err_magic
next_chunk:
    call spi_read_word
    mv   s0, a0                       # addr
    call spi_read_word
    mv   s1, a0                       # size
    beqz s1, done                     # end marker: s0 = entry
    # bounds check: the chunk must lie entirely inside IMEM or entirely inside DMEM.
    # size <= WIN_SIZE and addr < window end, so addr+size cannot wrap around.
    li   t0, WIN_SIZE
    bgtu s1, t0, err_addr
    add  t1, s0, s1                   # chunk end (exclusive)
    li   t0, IMEM_BASE
    bltu s0, t0, err_addr             # below IMEM
    li   t0, IMEM_END
    bgeu s0, t0, chk_dmem             # not in IMEM -> try DMEM
    bgtu t1, t0, err_addr             # runs past the end of IMEM
    j    copy
chk_dmem:
    li   t0, DMEM_BASE
    bltu s0, t0, err_addr             # in the gap between IMEM and DMEM
    li   t0, DMEM_END
    bgeu s0, t0, err_addr             # above DMEM
    bgtu t1, t0, err_addr             # runs past the end of DMEM
copy:
    call spi_read_byte
    sb   a0, 0(s0)
    addi s0, s0, 1
    addi s1, s1, -1
    bnez s1, copy
    j    next_chunk
done:
    call spi_cs_high
    # No fence.i: the SoC has no I-cache and jr already flushes the pipeline.
    jr   s0

# Error code is kept in t2: spi_cs_high clobbers t0/t1. a0 (received magic) and s0/s1 (addr/size)
# are left intact so the debugger can read them from the core-debug aperture (0x0B00_0000 + 4*reg).
err_magic:
    li   t2, 0xE1
    j    err
err_addr:
    li   t2, 0xE2
err:
    call spi_cs_high
    li   t0, ERR_ADDR
    sw   t2, 0(t0)
    j    .