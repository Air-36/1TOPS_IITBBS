//-----------------------------------------------------------------------------
// Top-Level Debugger Subsystem for 1TOPS SoC
// Integrates:
//   - Dedicated UART Transceiver (socdebug_uart.v)
//   - Dedicated FT1248 Transceiver (socdebug_ft1248_control.v)
//   - Physical Protocol Selection Mux (dbg_sel pin: 0=UART, 1=FT1248)
//   - ASCII Debug Protocol (ADP) AHB-Lite Master Controller (socdebug_ahb.v)
//   - Hardware Core Halt / Resume / Reset pipeline hooks
//-----------------------------------------------------------------------------

// `timescale 1ns / 1ps

module riscv_debugger_top #(
        parameter CLK_FREQ    = 100_000_000, // Basys 3 100 MHz oscillator
        parameter BAUD_RATE   = 115200,
        parameter PROMPT_CHAR = "]",
        parameter FT_WIDTH    = 1,
        parameter FT_CLKDIV   = 8'd4          // 100 MHz / (2 * (4 + 1)) = 10 MHz FT1248 clock
    )(
        input  wire                 clk,
        input  wire                 rst_n,

        // Communication Protocol Selection Pin (Physical hardware pad)
        // 0 = Dedicated Debug UART
        // 1 = Dedicated FT1248 High-Speed Interface
        input  wire                 dbg_sel,

        // UART Physical Interface
        input  wire                 uart_rx,
        output wire                 uart_tx,

        // FT1248 Physical Interface
        output wire                 ft1248_clk,       // SCLK output to FTDI
        output wire                 ft1248_ss_n,      // SS_N output to FTDI
        input  wire                 ft1248_miso,      // MISO input from FTDI (RXF# status)
        output wire [FT_WIDTH-1:0]  ft1248_miosio_o,  // Output data to FTDI
        output wire [FT_WIDTH-1:0]  ft1248_miosio_oe, // Output enable to FTDI (active HIGH)
        input  wire [FT_WIDTH-1:0]  ft1248_miosio_i,  // Input data from FTDI

        // Core Control & Status Signals
        output wire                 core_halt_o,      // Connect to ExternalStall of RISC-V Core
        output wire                 core_reset_o,     // System / Core Reset request
        input  wire                 core_halted_i,    // Core Halted status feedback from Hazard unit
        output wire                 core_step_o,      // Core Step Request (GPO8[2])
        output wire                 core_step_mode_o, // Core Step Mode (GPO8[3]: 0=Instr, 1=Cycle)
        input  wire                 core_step_busy_i, // Core Step in progress (GPI8[1])
        input  wire                 core_step_done_i, // Core Step completed (GPI8[2])

        // AHB-Lite Master Interface (Connect to AHB Mux/Arbiter)
        output wire [31:0]          DEBUG_HADDR,
        output wire [ 2:0]          DEBUG_HBURST,
        output wire                 DEBUG_HMASTLOCK,
        output wire [ 3:0]          DEBUG_HPROT,
        output wire [ 2:0]          DEBUG_HSIZE,
        output wire [ 1:0]          DEBUG_HTRANS,
        output wire [31:0]          DEBUG_HWDATA,
        output wire                 DEBUG_HWRITE,
        input  wire [31:0]          DEBUG_HRDATA,
        input  wire                 DEBUG_HREADY,
        input  wire                 DEBUG_HRESP,

        // Raw GPIO (optional monitor)
        output wire [7:0]           GPO8,
        input  wire [7:0]           GPI8,

        // AHB Slave MMIO Clock Divider Controls
        input  wire                 ahb_uart_clkdiv_we_i,
        input  wire [15:0]          ahb_uart_clkdiv_i,
        input  wire                 ahb_ft_clkdiv_we_i,
        input  wire [ 7:0]          ahb_ft_clkdiv_i,
        output wire [15:0]          uart_clkdiv_o,
        output wire [ 7:0]          ft_clkdiv_o
    );

    //-------------------------------------------------------------------------
    // Internal Reconfigurable Clock Dividers (Controlled only via Debugger)
    //-------------------------------------------------------------------------
    // FIX B9: saturate instead of silently truncating to 16 bits
    localparam integer UART_DIV_FULL = CLK_FREQ / BAUD_RATE;
    localparam [15:0] DEFAULT_UART_DIV = (UART_DIV_FULL > 65535) ? 16'hFFFF : UART_DIV_FULL[15:0];
    // synthesis translate_off
    initial if (UART_DIV_FULL > 65535 || UART_DIV_FULL < 4)
        $display("ERROR riscv_debugger_top: CLK_FREQ/BAUD_RATE = %0d is outside 4..65535", UART_DIV_FULL);
    // synthesis translate_on

    wire [15:0] dbg_uart_clkdiv;
    wire [ 7:0] dbg_ft_clkdiv;

    //-------------------------------------------------------------------------
    // 1. Dedicated Debug UART Transceiver Streams
    //-------------------------------------------------------------------------
    wire [7:0] uart_adp_rx_data;
    wire       uart_adp_rx_valid;
    wire       uart_adp_rx_ready;
    wire [7:0] uart_rx_raw_data;
    wire       uart_rx_raw_valid;
    wire       uart_rx_raw_ready;

    wire [7:0] uart_adp_tx_data;
    wire       uart_adp_tx_valid;
    wire       uart_adp_tx_ready;

    socdebug_uart #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart (
        .clk            (clk),
        .rst_n          (rst_n),
        .clks_per_bit_i (dbg_uart_clkdiv),
        .uart_rx        (uart_rx),
        .uart_tx       (uart_tx),
        .m_axis_tdata  (uart_rx_raw_data),   // FIX C16: through the RX FIFO below
        .m_axis_tvalid (uart_rx_raw_valid),
        .m_axis_tready (uart_rx_raw_ready),
        .s_axis_tdata  (uart_adp_tx_data),
        .s_axis_tvalid (uart_adp_tx_valid),
        .s_axis_tready (uart_adp_tx_ready)
    );

    //-------------------------------------------------------------------------
    // 2. Dedicated FT1248 Transceiver Streams & Tristate IO Buffers
    //-------------------------------------------------------------------------
    wire [7:0] ft_adp_rx_data;
    wire       ft_adp_rx_valid;
    wire       ft_adp_rx_ready;

    wire [7:0] ft_adp_tx_data;
    wire       ft_adp_tx_valid;
    wire       ft_adp_tx_ready;

    wire [FT_WIDTH-1:0] ft_miosio_o;
    wire [FT_WIDTH-1:0] ft_miosio_e;
    wire [FT_WIDTH-1:0] ft_miosio_i;

    assign ft1248_miosio_o  = ft_miosio_o;
    assign ft1248_miosio_oe = ft_miosio_e;
    assign ft_miosio_i      = ft1248_miosio_i;

    socdebug_ft1248_control #(
        .FT1248_WIDTH (FT_WIDTH),
        .FT1248_CLKON (1)
    ) u_ft1248 (
        .clk         (clk),
        .resetn      (rst_n),
        .ft_clkdiv   (dbg_ft_clkdiv),
        .ft_clk_o    (ft1248_clk),
        .ft_ssn_o    (ft1248_ss_n),
        .ft_miso_i   (ft1248_miso),
        .ft_miosio_o (ft_miosio_o),
        .ft_miosio_e (ft_miosio_e),
        // spyglass disable_block W287b
        // SMD: Instance output port is not connected
        // SJ: Active-low enable unused in FT1248 stream interface
        .ft_miosio_z (),
        // spyglass enable_block W287b
        .ft_miosio_i (ft_miosio_i),

        // ADP Interface - Data coming from FTDI to ADP
        .txd_tvalid  (ft_adp_rx_valid),
        .txd_tdata   (ft_adp_rx_data),
        .txd_tready  (ft_adp_rx_ready),
        // spyglass disable_block W287b
        // SMD: Instance output port is not connected
        // SJ: AXI stream tlast unused by ADP protocol
        .txd_tlast   (),
        // spyglass enable_block W287b

        // ADP Interface - Data from ADP going to FTDI
        .rxd_tvalid  (ft_adp_tx_valid),
        .rxd_tdata   (ft_adp_tx_data),
        .rxd_tready  (ft_adp_tx_ready)
    );

    //-------------------------------------------------------------------------
    // 3. 2-to-1 Protocol Stream Multiplexer (Controlled by dbg_sel pin)
    //    dbg_sel == 1'b0: Select UART
    //    dbg_sel == 1'b1: Select FT1248
    //-------------------------------------------------------------------------
    wire [7:0] adp_rxd_data;
    wire       adp_rxd_valid;
    wire       adp_rxd_ready;

    wire [7:0] adp_txd_data;
    wire       adp_txd_valid;
    wire       adp_txd_ready;

    // Rx Stream (Host -> ADP Controller)
    // FIX B6: synchronise the dbg_sel pin and change the selection only when no
    // reply byte is waiting to go out (never in the middle of a reply).
    reg [1:0] dbg_sel_sync;
    reg       sel_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin dbg_sel_sync <= 2'b00; sel_q <= 1'b0; end
        else begin
            dbg_sel_sync <= {dbg_sel_sync[0], dbg_sel};
            if (!adp_txd_valid) sel_q <= dbg_sel_sync[1];
        end
    end

    // FIX C16: 16-byte receive FIFO between the UART and the ADP, so bytes typed
    // while a reply is being sent are queued instead of overwritten.
    reg [7:0] rxf_mem [0:15];
    reg [3:0] rxf_wp, rxf_rp;
    reg [4:0] rxf_cnt;
    wire      rxf_full = rxf_cnt[4];
    wire      rxf_push = uart_rx_raw_valid && uart_rx_raw_ready && !sel_q;
    wire      rxf_pop  = uart_adp_rx_valid && uart_adp_rx_ready;
    // FIX C6: the unselected link is drained, so nothing typed on it runs later
    assign uart_rx_raw_ready = sel_q ? 1'b1 : !rxf_full;
    assign uart_adp_rx_valid = (rxf_cnt != 5'd0);
    assign uart_adp_rx_data  = rxf_mem[rxf_rp];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin rxf_wp <= 4'd0; rxf_rp <= 4'd0; rxf_cnt <= 5'd0; end
        else if (sel_q) begin rxf_rp <= rxf_wp; rxf_cnt <= 5'd0; end      // flush while FT1248 is selected
        else begin
            if (rxf_push) begin rxf_mem[rxf_wp] <= uart_rx_raw_data; rxf_wp <= rxf_wp + 4'd1; end
            if (rxf_pop)  rxf_rp <= rxf_rp + 4'd1;
            rxf_cnt <= rxf_cnt + {4'd0, rxf_push} - {4'd0, rxf_pop};
        end
    end

    assign adp_rxd_data      = (sel_q) ? ft_adp_rx_data  : uart_adp_rx_data;
    assign adp_rxd_valid     = (sel_q) ? ft_adp_rx_valid : uart_adp_rx_valid;

    // Backpressure routing: only the active link feeds the ADP; the other is drained (FIX C6)
    assign uart_adp_rx_ready = (!sel_q) ? adp_rxd_ready : 1'b0;
    assign ft_adp_rx_ready   = ( sel_q) ? adp_rxd_ready : 1'b1;

    // Tx Stream (ADP Controller -> Host)
    assign uart_adp_tx_data  = adp_txd_data;
    assign ft_adp_tx_data    = adp_txd_data;

    // Valid routing: Only the active transceiver receives valid from ADP
    assign uart_adp_tx_valid = (!sel_q) ? adp_txd_valid : 1'b0;
    assign ft_adp_tx_valid   = ( sel_q) ? adp_txd_valid : 1'b0;

    assign adp_txd_ready     = (sel_q) ? ft_adp_tx_ready : uart_adp_tx_ready;

    //-------------------------------------------------------------------------
    // 4. Instantiate SoCDebug AHB Master Controller
    //-------------------------------------------------------------------------
    socdebug_ahb #(
        .PROMPT_CHAR      (PROMPT_CHAR),
        .DEFAULT_UART_DIV (DEFAULT_UART_DIV),
        .DEFAULT_FT_DIV   (FT_CLKDIV)
    ) u_socdebug_ahb (
        .HCLK           (clk),
        .HRESETn        (rst_n),
        .HADDR32_o      (DEBUG_HADDR),
        .HBURST3_o      (DEBUG_HBURST),
        .HMASTLOCK_o    (DEBUG_HMASTLOCK),
        .HPROT4_o       (DEBUG_HPROT),
        .HSIZE3_o       (DEBUG_HSIZE),
        .HTRANS2_o      (DEBUG_HTRANS),
        .HWDATA32_o     (DEBUG_HWDATA),
        .HWRITE_o       (DEBUG_HWRITE),
        .HRDATA32_i     (DEBUG_HRDATA),
        .HREADY_i       (DEBUG_HREADY),
        .HRESP_i        (DEBUG_HRESP),

        // Stream Interface connected to the Protocol Multiplexer
        .COMRX_TDATA_i  (adp_rxd_data),
        .COMRX_TVALID_i (adp_rxd_valid),
        .COMRX_TREADY_o (adp_rxd_ready),
        .COMTX_TDATA_o  (adp_txd_data),
        .COMTX_TVALID_o (adp_txd_valid),
        .COMTX_TREADY_i (adp_txd_ready),

        // Unused STDIO stream tied off
        // spyglass disable_block W287b
        // SMD: Instance output port is not connected
        // SJ: STDIO bypass stream unused in direct command mode
        .STDTX_TVALID_o (),
        .STDTX_TDATA_o  (),
        .STDTX_TREADY_i (1'b1),
        .STDRX_TVALID_i (1'b0),
        .STDRX_TDATA_i  (8'h00),
        .STDRX_TREADY_o (),
        // spyglass enable_block W287b

        // Core Control & Status
        .core_halt_o      (core_halt_o),
        .core_reset_o     (core_reset_o),
        .core_halted_i    (core_halted_i),
        .core_step_o      (core_step_o),
        .core_step_mode_o (core_step_mode_o),
        .core_step_busy_i (core_step_busy_i),
        .core_step_done_i (core_step_done_i),

        .GPO8_o           (GPO8),
        .GPI8_i           (GPI8),

        // Reconfigurable Clock Dividers
        .ahb_uart_clkdiv_we_i (ahb_uart_clkdiv_we_i),
        .ahb_uart_clkdiv_i    (ahb_uart_clkdiv_i),
        .ahb_ft_clkdiv_we_i   (ahb_ft_clkdiv_we_i),
        .ahb_ft_clkdiv_i      (ahb_ft_clkdiv_i),
        .uart_clkdiv_o        (dbg_uart_clkdiv),
        .ft_clkdiv_o          (dbg_ft_clkdiv)
    );

    assign uart_clkdiv_o = dbg_uart_clkdiv;
    assign ft_clkdiv_o   = dbg_ft_clkdiv;

endmodule
