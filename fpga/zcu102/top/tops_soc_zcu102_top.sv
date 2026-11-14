////////////////////////////////////////////////////////////////////////////////
// tops_soc_zcu102_top.sv
//
// Top-level FPGA wrapper for the 1TOPS SoC on the AMD ZCU102 (xczu9eg-ffvb1156-2-e).
// Port of the Basys 3 top (fpga/top/tops_soc_fpga_top.sv): same SoC, same 50 MHz clock,
// same debugger and SPI boot. Only the board resources change. The board is local
// (buttons, switches, LEDs, USB-UART used directly); Vivado runs on a remote server and
// programs it through hw_server (see ../Makefile, ../README.md).
//
// Port names are the UG1182 schematic net names, so constrs/zcu102_pinmap.xdc is the
// UG1182 master XDC lines unchanged.
//
//   Basys 3                                ZCU102
//   -------------------------------------  ---------------------------------------------
//   clk 100 MHz (W5) -> MMCM -> 50 MHz      CLK_125 (G21/F21) -> MMCM -> 50 MHz
//                                           (or USER_SI570 300 MHz: define ZCU102_CLK_SI570,
//                                            CLK_SRC=SI570 in the Makefile)
//   reset_btn  btnC (U18)                   CPU_RESET  SW20 (AM13)
//   dbg_sel    SW0  (V17)                   GPIO_DIP_SW0  SW13.1 (AN14)
//   boot_mode  SW1  (V16)                   GPIO_DIP_SW1  SW13.2 (AP14)
//   uart_rx/tx USB-UART (B18/A18)           CP2108 ch.2 on micro-USB J83 (E13 rx / F13 tx)
//   UARTSin/out PMOD JA 1/2                 PMOD1_0 / PMOD1_1  (J87.1 / J87.3)
//   SPI         PMOD JC 1-4                 PMOD0_0..3         (J55.1/.3/.5/.7)
//   FT1248      PMOD JB 1-4                 PMOD0_4..7         (J55.2/.4/.6/.8)
//   LED0/1/15                               GPIO_LED_0..7 (DS37..DS44), see below
////////////////////////////////////////////////////////////////////////////////

module tops_soc_zcu102_top #(
  parameter CLK_FREQ    = 50_000_000,   // 50 MHz SoC clock from the MMCM (same as Basys 3)
  parameter BAUD_RATE   = 115200,       // Debugger UART baud rate
  parameter PROMPT_CHAR = "]",          // ADP CLI prompt
  parameter FT_WIDTH    = 1,            // FT1248 bus width (1-bit on PMOD0)
  parameter FT_CLKDIV   = 8'd1          // FT1248 SCLK = 50 MHz / (2 * (1 + 1)) = 12.5 MHz
) (
  // 1. Clock: one board oscillator, selected at build time (only that pair exists as ports,
  //    so only its constraints/IOSTANDARD are applied: constrs/zcu102_clk125.xdc or _si570.xdc)
`ifdef ZCU102_CLK_SI570
  input  logic        USER_SI570_P,     // AL8  300 MHz default (U42), DIFF_SSTL12, bank 64
  input  logic        USER_SI570_N,     // AL7
`else
  input  logic        CLK_125_P,        // G21  125 MHz (U69 SI5341B), LVDS_25, bank 47
  input  logic        CLK_125_N,        // F21
`endif

  // 2. Reset and configuration switches (all active high)
  input  logic        CPU_RESET,        // SW20 pushbutton (btnC equivalent)
  input  logic        GPIO_DIP_SW0,     // SW13 position 1: dbg_sel (0 = UART, 1 = FT1248)
  input  logic        GPIO_DIP_SW1,     // SW13 position 2: boot_mode strap

  // 3. Debugger UART: CP2108 channel 2 (PL-side), micro-USB J83 -> HTerm on the PC
  input  logic        UART2_TXD_O_FPGA_RXD, // E13: CP2108 TX -> FPGA RX (uart_rx)
  output logic        UART2_RXD_I_FPGA_TXD, // F13: FPGA TX -> CP2108 RX (uart_tx)

  // 4. SPI boot interface on PMOD0 top row (J55.1/.3/.5/.7) -> Pico
  output logic        PMOD0_0,          // spi_cs_n (registered)   -> Pico GP17 CSn
  output logic        PMOD0_1,          // spi_mosi                -> Pico GP16 RX
  input  logic        PMOD0_2,          // spi_miso (pull-up)      <- Pico GP19 TX
  output logic        PMOD0_3,          // spi_sclk (mode 3)       -> Pico GP18 SCK

  // 5. FT1248 debugger interface on PMOD0 bottom row (J55.2/.4/.6/.8)
  output logic        PMOD0_4,          // ft1248_clk
  output logic        PMOD0_5,          // ft1248_ss_n
  input  logic        PMOD0_6,          // ft1248_miso (pull-up)
  inout  wire         PMOD0_7,          // ft1248_miosio (pull-up)

  // 6. Application 16550 UART on PMOD1 (J87.1 / J87.3) -> external USB-UART dongle
  input  logic        PMOD1_0,          // UARTSin  (from dongle TXD)
  output logic        PMOD1_1,          // UARTSout (to dongle RXD)

  // 7. Status LEDs (DS37..DS44)
  output logic        GPIO_LED_0,       // core halted            (Basys LED0)
  output logic        GPIO_LED_1,       // dbg_sel = SW13.1       (Basys LED1)
  output logic        GPIO_LED_2,       // UART RX activity / ']' (Basys LED15)
  output logic        GPIO_LED_3,       // boot_mode = SW13.2
  output logic        GPIO_LED_4,       // MMCM locked (clock OK)
  output logic        GPIO_LED_5,       // trap seen since the last reset
  output logic        GPIO_LED_6,       // SPI activity (CS asserted, ~200 ms blink)
  output logic        GPIO_LED_7        // heartbeat (~1.5 Hz while the 50 MHz clock runs)
);

  // Basys 3 signal names used by the shared logic below
  wire reset_btn = CPU_RESET;
  wire dbg_sel   = GPIO_DIP_SW0;
  wire boot_mode = GPIO_DIP_SW1;
  wire uart_rx   = UART2_TXD_O_FPGA_RXD;
  wire uart_tx;
  assign UART2_RXD_I_FPGA_TXD = uart_tx;

  // -------------------------------------------------------------------------
  // On-chip clock generation: board oscillator -> MMCME4 -> 50 MHz SoC clock
  //   CLK125: 125 MHz x 8 = 1000 MHz VCO / 20 = 50 MHz
  //   SI570 : 300 MHz x 4 = 1200 MHz VCO / 24 = 50 MHz
  // -------------------------------------------------------------------------
  wire clk_soc;
  wire mmcm_locked;

`ifdef SYNTHESIS
`ifdef ZCU102_CLK_SI570
  localparam real  IN_PERIOD = 3.333;   // 300 MHz
  localparam real  MULT      = 4.0;     // VCO 1200 MHz
  localparam real  DIV0      = 24.0;    // 50 MHz
`else
  localparam real  IN_PERIOD = 8.000;   // 125 MHz
  localparam real  MULT      = 8.0;     // VCO 1000 MHz
  localparam real  DIV0      = 20.0;    // 50 MHz
`endif

  wire clk_ibuf;                        // after the differential input buffer
  wire clk_in;                          // after the BUFG, into the MMCM
  wire clk_soc_unbuf;
  wire clk_fb;

`ifdef ZCU102_CLK_SI570
  IBUFDS u_ibufds (.I(USER_SI570_P), .IB(USER_SI570_N), .O(clk_ibuf));
`else
  IBUFDS u_ibufds (.I(CLK_125_P), .IB(CLK_125_N), .O(clk_ibuf));
`endif
  // CLK_125 (bank 47) is an HD bank: no dedicated clock route to an MMCM, so the placer rejects
  // a direct IBUFDS -> MMCM connection (Place 30-681). A BUFG in between is the documented
  // workaround; harmless for the SI570 input as well.
  BUFG u_bufg_in (.I(clk_ibuf), .O(clk_in));

  MMCME4_BASE #(
    .BANDWIDTH          ("OPTIMIZED"),
    .CLKFBOUT_MULT_F    (MULT),
    .CLKFBOUT_PHASE     (0.0),
    .CLKIN1_PERIOD      (IN_PERIOD),
    .CLKOUT0_DIVIDE_F   (DIV0),
    .CLKOUT0_DUTY_CYCLE (0.5),
    .CLKOUT0_PHASE      (0.0),
    .DIVCLK_DIVIDE      (1),
    .REF_JITTER1        (0.010),
    .STARTUP_WAIT       ("FALSE")
  ) u_mmcm (
    .CLKOUT0   (clk_soc_unbuf), .CLKOUT0B (), .CLKOUT1 (), .CLKOUT1B (), .CLKOUT2 (), .CLKOUT2B (),
    .CLKOUT3   (), .CLKOUT3B (), .CLKOUT4 (), .CLKOUT5 (), .CLKOUT6 (),
    .CLKFBOUT  (clk_fb), .CLKFBOUTB (),
    .LOCKED    (mmcm_locked),
    .CLKIN1    (clk_in),
    .PWRDWN    (1'b0),
    .RST       (reset_btn),
    .CLKFBIN   (clk_fb)
  );

  BUFG u_bufg_soc (.I(clk_soc_unbuf), .O(clk_soc));
`else
  // Simulation: the testbench drives a 50 MHz clock on CLK_125_P directly (as on Basys 3)
  assign clk_soc     = CLK_125_P;
  assign mmcm_locked = 1'b1;
`endif

  // Active-high SoC reset: CPU_RESET pressed OR MMCM not locked (same as Basys btnC)
  wire reset_ext = reset_btn | (~mmcm_locked);

  // -------------------------------------------------------------------------
  // Status LEDs carried over from the Basys 3 top
  // -------------------------------------------------------------------------
  wire led_core_halted;
  wire led_rx_detect;
  assign GPIO_LED_0 = led_core_halted;
  assign GPIO_LED_1 = dbg_sel;
  assign GPIO_LED_2 = led_rx_detect;

  // >>> Copied verbatim from fpga/top/tops_soc_fpga_top.sv (Basys 3), lines 107-238
  // -------------------------------------------------------------------------
  // Synchronous UART RX Monitor & Activity / Character ']' Detector
  // -------------------------------------------------------------------------
  // Baud timing: at 50 MHz SoC clock and 115200 baud, bit period is 434 cycles.
  localparam int UART_CLKS_PER_BIT = CLK_FREQ / BAUD_RATE; // 50_000_000 / 115200 = 434
  localparam int UART_HALF_BIT     = UART_CLKS_PER_BIT / 2; // 217
  localparam int CLK_CNT_W         = $clog2(UART_CLKS_PER_BIT + 1);
  localparam int PULSE_CYCLES      = CLK_FREQ / 5;          // ~200 ms visible blink (10,000,000 cycles)
  localparam [7:0] TARGET_CHAR     = 8'h5D;                 // ASCII ']' (0x5D)

  // 1. Two-stage synchronizer to prevent metastability on asynchronous uart_rx input
  logic [1:0] rx_sync;
  always_ff @(posedge clk_soc) begin
    if (reset_btn) begin
      rx_sync <= 2'b11; // UART idle line state is high
    end else begin
      rx_sync <= {rx_sync[0], uart_rx};
    end
  end
  wire rx_clean = rx_sync[1];

  // 2. Dedicated UART RX Byte Deserializer
  typedef enum logic [1:0] {
    RX_IDLE  = 2'd0,
    RX_START = 2'd1,
    RX_DATA  = 2'd2,
    RX_STOP  = 2'd3
  } rx_state_t;

  rx_state_t              rx_state;
  logic [CLK_CNT_W-1:0]   rx_clk_cnt;
  logic [2:0]             rx_bit_idx;
  logic [7:0]             rx_shift_reg;
  logic [7:0]             rx_byte;
  logic                   rx_byte_valid;

  always_ff @(posedge clk_soc) begin
    if (reset_btn || !mmcm_locked) begin
      rx_state      <= RX_IDLE;
      rx_clk_cnt    <= '0;
      rx_bit_idx    <= '0;
      rx_shift_reg  <= 8'h00;
      rx_byte       <= 8'h00;
      rx_byte_valid <= 1'b0;
    end else begin
      rx_byte_valid <= 1'b0; // Default single-cycle strobe

      case (rx_state)
        RX_IDLE: begin
          rx_clk_cnt <= '0;
          rx_bit_idx <= '0;
          if (!rx_clean) begin // Falling edge indicates potential start bit
            rx_state <= RX_START;
          end
        end

        RX_START: begin
          if (rx_clk_cnt == UART_HALF_BIT) begin
            if (!rx_clean) begin // Valid start bit sampled at midpoint
              rx_clk_cnt <= '0;
              rx_state   <= RX_DATA;
            end else begin
              rx_state   <= RX_IDLE; // Glitch rejection: return to idle
            end
          end else begin
            rx_clk_cnt <= rx_clk_cnt + 1'b1;
          end
        end

        RX_DATA: begin
          if (rx_clk_cnt < UART_CLKS_PER_BIT - 1) begin
            rx_clk_cnt <= rx_clk_cnt + 1'b1;
          end else begin
            rx_clk_cnt   <= '0;
            rx_shift_reg <= {rx_clean, rx_shift_reg[7:1]}; // LSB first
            if (rx_bit_idx < 3'd7) begin
              rx_bit_idx <= rx_bit_idx + 1'b1;
            end else begin
              rx_bit_idx <= '0;
              rx_state   <= RX_STOP;
            end
          end
        end

        RX_STOP: begin
          if (rx_clk_cnt < UART_CLKS_PER_BIT - 1) begin
            rx_clk_cnt <= rx_clk_cnt + 1'b1;
          end else begin
            rx_clk_cnt <= '0;
            rx_state   <= RX_IDLE;
            if (rx_clean) begin // Valid stop bit received (High)
              rx_byte       <= rx_shift_reg;
              rx_byte_valid <= 1'b1;
            end
          end
        end

        default: rx_state <= RX_IDLE;
      endcase
    end
  end

  // 3. LED Detection Logic
  // - Glows / latches solidly ON when target character ']' (0x5D) is received
  // - Stretches a ~200ms blink whenever ANY valid UART byte is received for immediate visual feedback
  wire char_match = rx_byte_valid && (rx_byte == TARGET_CHAR);
  wire any_byte   = rx_byte_valid;

  logic [23:0] pulse_timer;
  logic        sticky_match;

  always_ff @(posedge clk_soc) begin
    if (reset_btn || !mmcm_locked) begin
      pulse_timer  <= '0;
      sticky_match <= 1'b0;
    end else begin
      // Latch HIGH if target character ']' was detected (sticky until reset)
      if (char_match) begin
        sticky_match <= 1'b1;
      end

      // Pulse stretcher: keeps LED ON for ~200ms when any byte arrives
      if (any_byte) begin
        pulse_timer <= PULSE_CYCLES[23:0];
      end else if (pulse_timer > 0) begin
        pulse_timer <= pulse_timer - 1'b1;
      end
    end
  end

  // Drive LED: Solid ON if ']' detected; Blinks ~200ms on any UART activity
  assign led_rx_detect = sticky_match | (pulse_timer != '0);
  // <<< end of Basys 3 block

  // -------------------------------------------------------------------------
  // Extra ZCU102 LEDs (the board has 8): boot_mode, clock, trap, SPI, heartbeat
  // -------------------------------------------------------------------------
  wire TrapM;
  logic       trap_seen;
  logic [24:0] heartbeat = '0;                // free-running; FPGA registers power up at 0
  logic [23:0] spi_pulse;
  always_ff @(posedge clk_soc) begin
    heartbeat <= heartbeat + 1'b1;
    if (reset_ext) begin
      trap_seen <= 1'b0;
      spi_pulse <= '0;
    end else begin
      if (TrapM) trap_seen <= 1'b1;
      if (!PMOD0_0)              spi_pulse <= PULSE_CYCLES[23:0];   // CS asserted
      else if (spi_pulse != '0)  spi_pulse <= spi_pulse - 1'b1;
    end
  end
  assign GPIO_LED_3 = boot_mode;
  assign GPIO_LED_4 = mmcm_locked;
  assign GPIO_LED_5 = trap_seen;
  assign GPIO_LED_6 = (spi_pulse != '0);
  assign GPIO_LED_7 = heartbeat[24];          // 50 MHz / 2^25 = ~1.5 Hz

  // -------------------------------------------------------------------------
  // SPI boot interface (PMOD0 top row). CS is decoded combinationally from the SPI
  // controller state inside spi_apb, so it is re-registered: a glitch on CS would reset
  // the Pico's bit position. (Same as Basys 3.)
  // -------------------------------------------------------------------------
  wire        SPIOut;
  wire [3:0]  SPICS;
  wire        SPICLK;
  wire [31:0] PCW;

  logic spi_cs_n_q;
  always_ff @(posedge clk_soc) begin
    if (reset_ext) spi_cs_n_q <= 1'b1;          // CS idle (high) during reset
    else           spi_cs_n_q <= SPICS[0];
  end
  assign PMOD0_0 = spi_cs_n_q;
  assign PMOD0_1 = SPIOut;
  assign PMOD0_3 = SPICLK;

  // -------------------------------------------------------------------------
  // 1TOPS SoC (source/main/soc/riscv_soc_ahb.v), same parameters as Basys 3
  // -------------------------------------------------------------------------
  riscv_soc_ahb #(
    .CLK_FREQ    (CLK_FREQ),
    .BAUD_RATE   (BAUD_RATE),
    .PROMPT_CHAR (PROMPT_CHAR),
    .FT_WIDTH    (FT_WIDTH),
    .FT_CLKDIV   (FT_CLKDIV)
  ) soc (
    .clk              (clk_soc),
    .reset            (reset_ext),
    .boot_mode        (boot_mode),
    .MExtInt          (1'b0),
    .TrapM            (TrapM),
    .mretM            (),
    .PCW              (PCW),
    .ResultW          (),
    .GPIOIN           (32'b0),
    .GPIOOUT          (),
    .GPIOEN           (),
    .UARTSin          (PMOD1_0),
    .UARTSout         (PMOD1_1),
    .SPIIn            (PMOD0_2),
    .SPIOut           (SPIOut),
    .SPICS            (SPICS),
    .SPICLK           (SPICLK),

    // Debugger subsystem
    .dbg_sel          (dbg_sel),
    .uart_rx          (uart_rx),
    .uart_tx          (uart_tx),
    .ft1248_clk       (PMOD0_4),
    .ft1248_ss_n      (PMOD0_5),
    .ft1248_miso      (PMOD0_6),
    .ft1248_miosio    (PMOD0_7),
    .core_halted_led  (led_core_halted)
  );

`ifdef ZCU102_ILA
  // -------------------------------------------------------------------------
  // Integrated Logic Analyzer (viewed from the remote Vivado over hw_server; probes in .ltx)
  // Defined by build_zcu102.tcl when ENABLE_ILA=1.
  // -------------------------------------------------------------------------
  ila_boot u_ila (
    .clk    (clk_soc),
    .probe0 ({PMOD0_0, PMOD0_1, PMOD0_2, PMOD0_3,          // SPI: cs_n, mosi, miso, sclk
              uart_rx, uart_tx,                            // debugger UART
              PMOD1_0, PMOD1_1}),                          // application UART
    .probe1 (PCW),                                         // write-back PC
    .probe2 ({reset_ext, mmcm_locked, boot_mode, dbg_sel,
              trap_seen, led_core_halted, TrapM, 1'b0})    // status
  );
`endif

endmodule
