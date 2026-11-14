#ifndef SOC_REGS_H
#define SOC_REGS_H

#include <stdint.h>

// =============================================================================
// 1TOPS RISC-V SoC Memory-Mapped Register Definitions
// =============================================================================

#define REG32(addr) (*(volatile uint32_t *)(addr))
#define REG16(addr) (*(volatile uint16_t *)(addr))
#define REG8(addr)  (*(volatile uint8_t  *)(addr))

// -----------------------------------------------------------------------------
// Base Addresses
// -----------------------------------------------------------------------------
#define IRAM_BASE           0x80000000
#define DRAM_BASE           0x80010000
#define CLINT_BASE          0x02000000
#define PLIC_BASE           0x0C000000
#define UART_BASE           0x10000000
#define SPI_BASE            0x10040000
#define GPIO_BASE           0x10060000
#define SYSCTRL_BASE        0x10080000
#define MULTIPLIER_BASE     0x30000000

// Verification Mailbox / Status Signatures
#define MAILBOX_STATUS_ADDR (DRAM_BASE + 0x7FFC)
#define TOHOST_ADDR         (IRAM_BASE + 0x1000)

#define STATUS_RUNNING      0x00000000
#define STATUS_PASS         0xCAFEBABE
#define STATUS_FAIL         0xDEADBEEF
#define STATUS_READY_PLIC   0x12345678

// -----------------------------------------------------------------------------
// CLINT Registers (Core Local Interruptor)
// -----------------------------------------------------------------------------
#define CLINT_MSIP          REG32(CLINT_BASE + 0x0000)
#define CLINT_MTIMECMP      REG32(CLINT_BASE + 0x4000)
#define CLINT_MTIMECMPH     REG32(CLINT_BASE + 0x4004)
#define CLINT_MTIME         REG32(CLINT_BASE + 0xBFF8)
#define CLINT_MTIMEH        REG32(CLINT_BASE + 0xBFFC)

// -----------------------------------------------------------------------------
// PLIC Registers (Platform-Level Interrupt Controller)
// -----------------------------------------------------------------------------
#define PLIC_PRIO_UART      REG32(PLIC_BASE + 0x000004)
#define PLIC_PRIO_GPIO      REG32(PLIC_BASE + 0x000008)
#define PLIC_PRIO_SPI       REG32(PLIC_BASE + 0x00000C)
#define PLIC_PRIO_SDC       REG32(PLIC_BASE + 0x000010)

#define PLIC_ENABLE         REG32(PLIC_BASE + 0x002000)
#define PLIC_THRESHOLD      REG32(PLIC_BASE + 0x200000)
#define PLIC_CLAIM          REG32(PLIC_BASE + 0x200004)

// -----------------------------------------------------------------------------
// GPIO Registers
// -----------------------------------------------------------------------------
#define GPIO_INPUT_VAL      REG32(GPIO_BASE + 0x0000)
#define GPIO_INPUT_EN       REG32(GPIO_BASE + 0x0004)
#define GPIO_OUTPUT_EN      REG32(GPIO_BASE + 0x0008)
#define GPIO_OUTPUT_VAL     REG32(GPIO_BASE + 0x000C)
#define GPIO_RISE_IE        REG32(GPIO_BASE + 0x0010)
#define GPIO_RISE_IP        REG32(GPIO_BASE + 0x0014)
#define GPIO_FALL_IE        REG32(GPIO_BASE + 0x0018)
#define GPIO_FALL_IP        REG32(GPIO_BASE + 0x001C)

// -----------------------------------------------------------------------------
// 16550 UART Registers
// -----------------------------------------------------------------------------
// 16550 registers are 1 byte apart (uart_apb decodes PADDR[2:0]); access them as bytes.
#define UART_RBR            REG8(UART_BASE + 0x0) // Receiver Buffer (R)
#define UART_THR            REG8(UART_BASE + 0x0) // Transmitter Holding (W)
#define UART_DLL            REG8(UART_BASE + 0x0) // Divisor Latch LSB (DLAB=1)
#define UART_IER            REG8(UART_BASE + 0x1) // Interrupt Enable
#define UART_DLM            REG8(UART_BASE + 0x1) // Divisor Latch MSB (DLAB=1)
#define UART_IIR            REG8(UART_BASE + 0x2) // Interrupt Ident (R)
#define UART_FCR            REG8(UART_BASE + 0x2) // FIFO Control (W)
#define UART_LCR            REG8(UART_BASE + 0x3) // Line Control
#define UART_MCR            REG8(UART_BASE + 0x4) // Modem Control
#define UART_LSR            REG8(UART_BASE + 0x5) // Line Status
#define UART_MSR            REG8(UART_BASE + 0x6) // Modem Status
#define UART_SCR            REG8(UART_BASE + 0x7) // Scratch

#define UART_LSR_DR         0x01
#define UART_LSR_THRE       0x20
#define UART_LSR_TEMT       0x40

// -----------------------------------------------------------------------------
// SPI Controller Registers
// -----------------------------------------------------------------------------
#define SPI_SCKDIV          REG32(SPI_BASE + 0x0000)
#define SPI_SCKMODE         REG32(SPI_BASE + 0x0004)
#define SPI_CSID            REG32(SPI_BASE + 0x0010)
#define SPI_CSDEF           REG32(SPI_BASE + 0x0014)
#define SPI_CSMODE          REG32(SPI_BASE + 0x0018)
#define SPI_TXDATA          REG32(SPI_BASE + 0x0048)
#define SPI_RXDATA          REG32(SPI_BASE + 0x004C)

#define SPI_CSMODE_AUTO     0
#define SPI_CSMODE_HOLD     2
#define SPI_CSMODE_OFF      3

// -----------------------------------------------------------------------------
// System Controller Registers
// -----------------------------------------------------------------------------
#define SYSCTRL_REMAP       REG32(SYSCTRL_BASE + 0x0000)
#define SYSCTRL_BOOT_STATUS REG32(SYSCTRL_BASE + 0x0008)
#define SYSCTRL_SOFT_RESET  REG32(SYSCTRL_BASE + 0x000C)
#define SYSCTRL_RESET_VEC   REG32(SYSCTRL_BASE + 0x0010)
#define SYSCTRL_SCRATCHPAD  REG32(SYSCTRL_BASE + 0x0014)

// -----------------------------------------------------------------------------
// Multiplier Hardware Accelerator
// -----------------------------------------------------------------------------
#define MULT_OPA            REG32(MULTIPLIER_BASE + 0x0000)
#define MULT_OPB            REG32(MULTIPLIER_BASE + 0x0004)
#define MULT_RESULT         REG32(MULTIPLIER_BASE + 0x0008)

// -----------------------------------------------------------------------------
// RISC-V CSR Helper Functions
// -----------------------------------------------------------------------------
static inline void set_csr_mstatus(uint32_t bit) {
    __asm__ volatile ("csrs mstatus, %0" : : "r"(bit));
}

static inline void clear_csr_mstatus(uint32_t bit) {
    __asm__ volatile ("csrc mstatus, %0" : : "r"(bit));
}

static inline void set_csr_mie(uint32_t bit) {
    __asm__ volatile ("csrs mie, %0" : : "r"(bit));
}

static inline void clear_csr_mie(uint32_t bit) {
    __asm__ volatile ("csrc mie, %0" : : "r"(bit));
}

static inline void write_csr_mtvec(uint32_t addr) {
    __asm__ volatile ("csrw mtvec, %0" : : "r"(addr));
}

static inline uint32_t read_csr_mcause(void) {
    uint32_t val;
    __asm__ volatile ("csrr %0, mcause" : "=r"(val));
    return val;
}

static inline uint32_t read_csr_mepc(void) {
    uint32_t val;
    __asm__ volatile ("csrr %0, mepc" : "=r"(val));
    return val;
}

// Global Interrupt Enables
#define MSTATUS_MIE         (1 << 3)
#define MIE_MSIE            (1 << 3)
#define MIE_MTIE            (1 << 7)
#define MIE_MEIE            (1 << 11)

// Interrupt Causes
#define MCAUSE_INT_BIT      (1U << 31)
#define CAUSE_MSW_INT       (MCAUSE_INT_BIT | 3)
#define CAUSE_MTIMER_INT    (MCAUSE_INT_BIT | 7)
#define CAUSE_MEXT_INT      (MCAUSE_INT_BIT | 11)

// Test result helper
static inline void pass_test(void) {
    REG32(MAILBOX_STATUS_ADDR) = STATUS_PASS;
    REG32(SYSCTRL_SCRATCHPAD)  = 0x1;
    REG32(TOHOST_ADDR)         = 0x1;
    while (1) {
        __asm__ volatile ("wfi");
    }
}

static inline void fail_test(uint32_t err_code) {
    REG32(MAILBOX_STATUS_ADDR) = STATUS_FAIL;
    REG32(SYSCTRL_SCRATCHPAD)  = (err_code << 1) | 1;
    REG32(TOHOST_ADDR)         = (err_code << 1) | 1;
    while (1) {
        __asm__ volatile ("wfi");
    }
}

#endif // SOC_REGS_H

