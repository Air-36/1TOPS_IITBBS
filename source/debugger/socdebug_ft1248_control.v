//-----------------------------------------------------------------------------
// SoCDebug FTDI FT1248 Interface to AXI-Stream Controller
// A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
//
// Contributors
//
// David Flynn (d.w.flynn@soton.ac.uk)
//
// Copyright � 2022, SoC Labs (www.soclabs.org)
//-----------------------------------------------------------------------------

module socdebug_ft1248_control #(
  parameter integer FT1248_WIDTH	= 1, // FTDI Interface 1,2,4 width supported
  parameter integer FT1248_CLKON	= 1  // FTDI clock always on - else quiet when no access
)(
  // IO pad interface - to FT232R configured in 1/2/4/8 mode
  output wire                    ft_clk_o,      // SCLK
  output wire                    ft_ssn_o,      // SS_N
  input  wire                    ft_miso_i,     // MISO
  output wire [FT1248_WIDTH-1:0] ft_miosio_o,   // MIOSIO tristate output when enabled
  output reg  [FT1248_WIDTH-1:0] ft_miosio_e,   // MIOSIO tristate output enable (active hi)
  output reg  [FT1248_WIDTH-1:0] ft_miosio_z,   // MIOSIO tristate output enable (active lo)
  input  wire [FT1248_WIDTH-1:0] ft_miosio_i,   // MIOSIO tristate input
  
  input  wire [7:0] ft_clkdiv,    // divider prescaler to ensure SCLK <1MHz

  input  wire  clk,
  input  wire  resetn,

  // Ports of Axi Master Bus Interface TXD - To ADP Controller
  output wire       txd_tvalid,
  output wire [7:0] txd_tdata,
  output wire       txd_tlast,
  input  wire       txd_tready,

  // Ports of Axi Slave Bus Interface RXD - To 
  output wire       rxd_tready,
  input  wire [7:0] rxd_tdata,
  input  wire       rxd_tvalid
);

	//----------------------------------------------
	//-- State Machine encoding
	//----------------------------------------------

// Explicit FSM state bit assignment
//  bit [0] SCLK
//  bit [1] MIO_OE
//  bit [2] CMD/W
//  bit [3] DAT/R
//  bit [4] SSEL

  localparam FT_0_IDLE       = 5'b00000;
  localparam FT_1_IDLE       = 5'b00001;
  localparam FT_ZCMD_CLKLO   = 5'b10100;
  localparam FT_CMD_CLKHI    = 5'b10111;
  localparam FT_CMD_CLKLO    = 5'b10110;
  localparam FT_ZBT_CLKHI    = 5'b10001;
  localparam FT_ZBT_CLKLO    = 5'b10000;
  localparam FT_WD_CLKHI     = 5'b11111;
  localparam FT_WD_CLKLO     = 5'b11110;
  localparam FT_ZWD_CLKLO    = 5'b11100;
  localparam FT_RD_CLKHI     = 5'b11001;
  localparam FT_RD_CLKLO     = 5'b11000;

  reg [4:0] ft_state;
  reg [4:0] ft_next_state;
  // 9- bit shift register to support 8-bit data + 1 sequence control flag
  // write data uses bits[7:0], with bit[8] set to flag length for serialized transfers
  // read  data uses bits[8:1], with bit[0] set to flag continuation for serialized transfers
  reg [8:0] ft_reg;

  //----------------------------------------------
  //-- IO PAD control, parameterized on WIDTH param
  //----------------------------------------------
    
  wire bwid8 = (FT1248_WIDTH==8);
  wire bwid4 = (FT1248_WIDTH==4);
  wire bwid2 = (FT1248_WIDTH==2);

  wire [7:0] ft_rdmasked;


  generate 
    if (FT1248_WIDTH == 8) begin
      assign ft_rdmasked[7:1] =  ft_miosio_i[7:1];
      assign ft_miosio_o[7:1] =  ft_reg[7:1];
    end 
  endgenerate

  generate 
    if (FT1248_WIDTH == 4) begin
      assign ft_rdmasked[7:1] =  {4'b1111, ft_miosio_i[3:1]};
      assign ft_miosio_o[3:1] =  ft_reg[3:1];
    end
  endgenerate

  generate 
    if (FT1248_WIDTH == 2) begin
      assign ft_rdmasked[7:1] =  {6'b111111, ft_miosio_i[1]};
      assign ft_miosio_o[1] =  ft_reg[1];
    end
  endgenerate

  generate 
    if (FT1248_WIDTH == 1) begin
      assign ft_rdmasked[7:1] =  {7{1'b1}};
    end
  endgenerate

  assign ft_rdmasked[0] = ft_miosio_i[0];
  assign ft_miosio_o[0] =  ft_reg[0];

  assign ft_clk_o =  ft_state[0];
  assign ft_ssn_o = !ft_state[4];

  // diagnostic decodes
  //wire   ft_cmd = !ft_state[3] &  ft_state[2];
  //wire   ft_dwr =  ft_state[3] &  ft_state[2];
  //wire   ft_drd =  ft_state[3] & !ft_state[2];


  //----------------------------------------------
  //-- Internal clock prescaler
  //----------------------------------------------

  // clock prescaler, ft_clken enables serial IO engine clocking
  reg [7:0] ft_clkcnt_r;
  reg       ft_clken;

  always @(posedge clk or negedge resetn )
  begin
    if (!resetn) begin
      ft_clkcnt_r <= 8'h00;
      ft_clken    <= 1'b0;
      end
    else begin
      ft_clken    <= (ft_clkcnt_r >= ft_clkdiv);
      ft_clkcnt_r <= (ft_clkcnt_r >= ft_clkdiv) ? 8'h00 : ((ft_clkcnt_r + 8'h01) & 8'hff);
      end
  end

  //----------------------------------------------
  //-- Internal "synchronizers" (dual stage)
  //----------------------------------------------
  // synchronizers for channel ready flags when idle
  // (treat these signals as synchronous during transfer sequencing)
  reg ft_miso_i_sync;
  reg ft_miosio_i0_sync;
  reg ft_miso_i_sync_1;
  reg ft_miosio_i0_sync_1;

  always @(posedge clk or negedge resetn )
  begin
    if (!resetn) begin
      ft_miso_i_sync_1   <= 1'b1;
      ft_miosio_i0_sync_1 <= 1'b1;
      ft_miso_i_sync     <= 1'b1;
      ft_miosio_i0_sync   <= 1'b1;
      end
    else begin
      ft_miso_i_sync_1   <= ft_miso_i;
      ft_miosio_i0_sync_1 <= ft_miosio_i[0];
      ft_miso_i_sync     <= ft_miso_i_sync_1;
      ft_miosio_i0_sync   <= ft_miosio_i0_sync_1;
      end
  end

  //----------------------------------------------
  //-- AXI Stream interface handshakes
  //----------------------------------------------

  reg ft_txf;  // FTDI Transmit channel Full
  reg ft_rxe;  // FTDO Receive channel Empty
  reg ft_wcyc; // read access committed
  reg ft_nak;  // check for NAK terminate

  // TX stream delivers valid FT1248 read data transfer
  // 8-bit write port with extra top-bit used as valid qualifer
  reg [8:0] txdata;
  assign txd_tdata = txdata[7:0];
  assign txd_tvalid = txdata[8];
  assign txd_tlast = 1'b0;

  // activate if RX channel data and the stream buffer is not full
  wire ft_rxreq = !ft_rxe & !txdata[8];


  // RX stream handshakes on valid FT1248 write data transfer
  reg       rxdone;
  reg       rxrdy;
  assign    rxd_tready = rxdone;

  // activate if TX channel not full and and the stream buffer data valid
  wire ft_txreq = !ft_txf & rxd_tvalid; // & !rxdone; // FTDI TX data ready and rxstream ready

  // FTDI1248 commands
  wire [3:0] wcmd = 4'b0000; // write request
  wire [3:0] rcmd = 4'b0001; // read  request
  // and full FT1248 command bit patterns (using top-bits for shift sequencing)
  wire [8:0] wcmdpatt = {2'b11, wcmd[0], wcmd[1], 1'b0, wcmd[2], 1'b0, 1'b0, wcmd[3]};
  wire [8:0] rcmdpatt = {2'b11, rcmd[0], rcmd[1], 1'b0, rcmd[2], 1'b0, 1'b0, rcmd[3]};

  reg ssn_del;
  always @(posedge clk or negedge resetn)
  begin
    if (!resetn) begin
      ssn_del  <= 1'b1;
      end
    else if (ft_clken) begin
        ssn_del  <= ft_ssn_o;
        end
  end
  wire ssn_start = ft_ssn_o & ssn_del;

  // FTDI1248 state machine - separated sequential state register and combinational next-state decoder

  // Sequential state register and registered tristate enable outputs
  always @(posedge clk or negedge resetn)
  begin
    if (!resetn) begin
      ft_state    <= FT_0_IDLE;
      ft_miosio_e <= {FT1248_WIDTH{1'b0}};
      ft_miosio_z <= {FT1248_WIDTH{1'b1}};
    end else begin
      ft_state    <= ft_next_state;
      // FIX C4: keep driving MIOSIO through FT_ZWD_CLKLO so the last data bit is still
      // valid on the edge where the FTDI device samples it (all lanes, _e and _z)
      ft_miosio_e <= {FT1248_WIDTH{ft_next_state[1] | (ft_next_state == FT_ZWD_CLKLO)}};
      ft_miosio_z <= ~{FT1248_WIDTH{ft_next_state[1] | (ft_next_state == FT_ZWD_CLKLO)}};
    end
  end

  // Combinational next-state logic
  always @(*) begin
    ft_next_state = ft_state;
    if (ft_clken) begin
      case (ft_state)
        FT_0_IDLE: begin // RX req priority
          if (ssn_start && ft_rxreq)
            ft_next_state = FT_ZCMD_CLKLO;
          else if (ssn_start && ft_txreq)
            ft_next_state = FT_ZCMD_CLKLO;
          else
            ft_next_state = (!ft_txf || !ft_rxe || (FT1248_CLKON != 0)) ? FT_1_IDLE : FT_0_IDLE;
        end
        FT_1_IDLE:
          ft_next_state = FT_0_IDLE;
        FT_ZCMD_CLKLO:
          ft_next_state = FT_CMD_CLKHI;
        FT_CMD_CLKHI:
          ft_next_state = FT_CMD_CLKLO;
        FT_CMD_CLKLO: // 2, 4 or 7 shifts
          if (bwid8)
            ft_next_state = FT_ZBT_CLKHI;
          else if (bwid4)
            ft_next_state = (|ft_reg[8:5]) ? FT_CMD_CLKHI : FT_ZBT_CLKHI;
          else if (bwid2)
            ft_next_state = (|ft_reg[8:3]) ? FT_CMD_CLKHI : FT_ZBT_CLKHI;
          else
            ft_next_state = (|ft_reg[8:3]) ? FT_CMD_CLKHI : FT_ZBT_CLKHI;
        FT_ZBT_CLKHI:
          ft_next_state = FT_ZBT_CLKLO;
        FT_ZBT_CLKLO:
          if (ft_wcyc)
            ft_next_state = FT_WD_CLKHI;
          else
            ft_next_state = FT_RD_CLKHI;
        FT_WD_CLKHI:
          if (ft_miso_i && ft_reg[8])
            ft_next_state = FT_ZWD_CLKLO;
          else if (bwid8)
            ft_next_state = (ft_reg[8]) ? FT_WD_CLKLO : FT_ZWD_CLKLO;
          else if (bwid4)
            ft_next_state = (|ft_reg[8:5]) ? FT_WD_CLKLO : FT_ZWD_CLKLO;
          else if (bwid2)
            ft_next_state = (|ft_reg[8:3]) ? FT_WD_CLKLO : FT_ZWD_CLKLO;
          else
            ft_next_state = (|ft_reg[8:2]) ? FT_WD_CLKLO : FT_ZWD_CLKLO;
        FT_WD_CLKLO:
          ft_next_state = FT_WD_CLKHI;
        FT_ZWD_CLKLO:
          ft_next_state = FT_0_IDLE;
        FT_RD_CLKHI: // capture iodata pins end of CLKHI phase
          ft_next_state = FT_RD_CLKLO;
        FT_RD_CLKLO:
          if (ft_nak)
            ft_next_state = FT_0_IDLE;
          else if (ft_reg[0])
            ft_next_state = FT_RD_CLKHI;
          else
            ft_next_state = FT_0_IDLE;
        default:
          ft_next_state = FT_0_IDLE;
      endcase
    end
  end

  // Sequential datapath outputs and control registers
  always @(posedge clk or negedge resetn)
  begin
    if (!resetn) begin
      ft_reg   <= {9{1'b0}};
      rxdone   <= 1'b0;
      ft_wcyc  <= 1'b0;
      ft_txf   <= 1'b1; // ftdi channel  TXE# ('1' full)
      ft_rxe   <= 1'b1; // ftdi channel  RXF# ('1' empty)
      ft_nak   <= 1'b0;
    end else begin
      ft_txf <= (ft_ssn_o) ? (ft_miosio_i[0] | ft_miosio_i0_sync) : 1'b1; //ft_txf & !( ft_wcyc &(ft_state==FT_ZBT_CLKHI) & ft_miso_i);
      ft_rxe <= (ft_ssn_o) ? (ft_miso_i | ft_miso_i_sync)  : 1'b1; //ft_rxe & !(!ft_wcyc & (ft_state==FT_ZBT_CLKHI) & ft_miso_i);
      rxdone   <= (ft_clken & (ft_state==FT_ZWD_CLKLO) & !ft_nak) | (rxdone & !rxd_tvalid); // hold until acknowledged
      if (ft_clken) begin
        case (ft_state)
        FT_0_IDLE: begin // RX req priority
          if (ssn_start && ft_rxreq) begin
            ft_reg <= rcmdpatt;
            end
          else if (ssn_start && ft_txreq) begin
            ft_reg <= wcmdpatt;
            ft_wcyc <= 1'b1;
            end
          end
        FT_1_IDLE: ;
        FT_ZCMD_CLKLO: ;
        FT_CMD_CLKHI: ;
        FT_CMD_CLKLO: // 2, 4 or 7 shifts
          if (bwid8) begin
            end 
          else if (bwid4) begin
            ft_reg <= {4'b0000,ft_reg[8:4]};
            end 
          else if (bwid2) begin
            ft_reg <= {  2'b00,ft_reg[8:2]};
            end 
          else begin
            ft_reg <= {   1'b0,ft_reg[8:1]};
            end 
        FT_ZBT_CLKHI: ;
        FT_ZBT_CLKLO:
          if    (ft_wcyc) begin
            ft_reg <= {1'b1,rxd_tdata};
            end
          else begin
            ft_reg <=  9'b011111111;
            end
        FT_WD_CLKHI:
          if (ft_miso_i && ft_reg[8]) begin
            ft_nak <= 1'b1;
            end // NAK terminate on first cycle
        FT_WD_CLKLO:
          if      (bwid8) begin
            ft_reg <= {   1'b0,ft_reg[7:0]};
            end // clear top flag
          else if (bwid4) begin
            ft_reg <= {4'b0000,ft_reg[8:4]};
            end // shift 4 bits right
          else if (bwid2) begin
            ft_reg <= {  2'b00,ft_reg[8:2]};
            end // shift 2 bits right
          else begin
            ft_reg <= {   1'b0,ft_reg[8:1]};
            end // shift 1 bit right
        FT_ZWD_CLKLO:
          begin
            ft_nak  <= 1'b0;
            ft_wcyc <= 1'b0;
          end
        FT_RD_CLKHI: // capture iodata pins end of CLKHI phase
          if (ft_miso_i && (&ft_reg[7:0])) begin
            ft_nak <= 1'b1;
            end // NAK terminate on first cycle
          else if (bwid8) begin
            ft_reg <= (ft_reg[0]) ? {ft_rdmasked[7:0],1'b1} : {ft_reg[8:1],1'b0};
            end // 8-bit read twice
          else if (bwid4) begin
            ft_reg <= {ft_rdmasked[3:0],ft_reg[8:4]};
            end 
          else if (bwid2) begin
            ft_reg <= {ft_rdmasked[1:0],ft_reg[8:2]};
            end 
          else begin
            ft_reg <= {ft_rdmasked[  0],ft_reg[8:1]};
            end 
        FT_RD_CLKLO:
          if (ft_nak) begin
            ft_nak<= 1'b0;
            end // terminate without TX handshake
          else if (ft_reg[0]) begin
            ft_reg[0] <= !(bwid8);
            end // loop until all 8 bits shifted in (or 8-bit read repeated)
          else begin
            end
        default: ;
        endcase
        end
      end
    end

  // Synchronous TX data register update (single assignment block)
  always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      txdata <= 9'b000000000;
    end else if (ft_clken && (ft_state == FT_RD_CLKLO)) begin
      if (ft_nak) begin
        txdata <= 9'b000000000;
      end else if (!ft_reg[0]) begin
        txdata <= {1'b1, ft_reg[8:1]};
      end else begin
        txdata[8] <= txdata[8] & !txd_tready;
      end
    end else begin
      txdata[8] <= txdata[8] & !txd_tready;
    end
  end

endmodule
