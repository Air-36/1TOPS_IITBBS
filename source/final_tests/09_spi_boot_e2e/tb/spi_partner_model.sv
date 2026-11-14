// =============================================================================
// spi_partner_model.sv - the SPI boot partner (Raspberry Pi Pico / Raspberry Pi 4) in simulation
//
// Holds a boot stream (a flash.bin built by software/make_image.py, read from disk) and serves
// it as an SPI mode-3 slave: while CS is low, the next bit goes onto MISO after every falling
// SCLK edge, MSB first; the SoC samples on the rising edge.
//
// Rules (agreed boot plan, rpi4_spi_boot_options.txt sec. 1.3):
//   R1  a pointer to the next unsent byte; a new CS window continues from it
//   R2  CS going low starts a fresh BYTE (bit position 0), never rewinds the pointer
//   R3  SCLK is ignored while CS is high
//   R4  only reload() (the stand-in for make_image.py --serial) rewinds to byte 0;
//       a SoC reset does not
//   Not armed / past the end: 0xFF (what the SoC sees through the MISO pull-up).
//
// Two flavours (select with the "timed" flag):
//   ideal (timed = 0)  reacts to every edge instantly: isolates SoC-side problems
//   timed (timed = 1)  the Pi 4 firmware algorithm (software/rpi4_spi_slave/src/slave_core.h,
//                      same model as the C1 sim): samples CS/SCLK every poll_ns +/-25 %, and
//                      changes MISO lat_ns after the sample that saw the falling edge
// =============================================================================
`timescale 1ns/1ps
module spi_partner_model (
  input  wire cs_n,
  input  wire sclk,
  output wire miso
);
  localparam integer MAXLEN = 131072;

  reg [7:0] mem [0:MAXLEN-1];
  integer   len     = 0;      // stream length in bytes
  integer   ptr     = 0;      // R1: next unsent byte
  integer   bitn    = 0;      // bits of the current byte already driven (0..8)
  integer   windows = 0;      // number of CS-low windows seen (any state)
  integer   clocked = 0;      // complete bytes clocked out (including 0xFF past the end / unarmed)
  integer   partial = 0;      // bytes cut short by CS going high (R2 restarts)
  reg [7:0] cur     = 8'hFF;  // byte being shifted out
  reg       armed   = 1'b0;

  reg       timed   = 1'b0;
  integer   poll_ns = 200;
  integer   lat_ns  = 300;

  reg miso_i = 1'b1, miso_t = 1'b1;
  assign miso = timed ? miso_t : miso_i;

  // ---------------------------------------------------------------- control (called by the tb)
  task load(input [8*256-1:0] fname);
    integer fd, c;
    begin
      fd = $fopen(fname, "rb");
      if (fd == 0) begin
        $display("[PARTNER] ERROR: cannot open stream file %0s", fname);
        $finish;
      end
      len = 0;
      c = $fgetc(fd);
      while (c != -1 && len < MAXLEN) begin
        mem[len] = c[7:0];
        len = len + 1;
        c = $fgetc(fd);
      end
      $fclose(fd);
      $display("[PARTNER] loaded %0d bytes from %0s", len, fname);
    end
  endtask

  task reload;                                       // R4: the only way back to byte 0
    begin
      armed = 1'b1; ptr = 0; bitn = 0;
      cur = (len > 0) ? mem[0] : 8'hFF;
    end
  endtask

  task disarm;
    begin armed = 1'b0; cur = 8'hFF; end
  endtask

  function [7:0] byte_at(input integer i);
    byte_at = (i >= 0 && i < len) ? mem[i] : 8'hFF;
  endfunction

  task finish_byte;                                  // a full byte was clocked out: advance
    begin
      clocked = clocked + 1;
      if (armed && ptr < len) ptr = ptr + 1;
      bitn = 0;
      cur = (armed && ptr < len) ? mem[ptr] : 8'hFF;
    end
  endtask

  always @(negedge cs_n) windows = windows + 1;

  // ---------------------------------------------------------------- ideal slave
  always @(posedge cs_n) if (!timed) begin
    if (bitn == 8) finish_byte;                      // completed byte: count it
    else begin                                       // R2: an unfinished byte restarts
      if (bitn != 0) partial = partial + 1;
      bitn = 0;
    end
  end

  always @(negedge sclk) if (!timed && !cs_n) begin  // R3: only while CS is low
    if (bitn == 8) finish_byte;
    miso_i <= cur[7 - bitn];
    bitn = bitn + 1;
  end

  // ---------------------------------------------------------------- Pi 4 timed slave
  initial begin : pi_poll
    integer step, r;
    reg c, s, prev;
    prev = 1'b1;
    forever begin
      if (!timed) begin
        #100; prev = sclk;
      end else begin
        r    = $urandom % (poll_ns / 2 + 1);
        step = poll_ns + r - poll_ns / 4;            // poll period +/- 25 %
        #(step);
        c = cs_n; s = sclk;
        if (c) begin                                 // bus idle: R2/R3
          if (bitn == 8) finish_byte;
          else begin if (bitn != 0) partial = partial + 1; bitn = 0; end
          prev = s;
        end else if (prev && !s) begin               // falling edge seen: drive the next bit
          if (bitn == 8) finish_byte;
          miso_t <= #(lat_ns) cur[7 - bitn];
          bitn = bitn + 1;
          prev = s;
        end else begin
          if (bitn == 8) finish_byte;                // advance off the edge path
          prev = s;
        end
      end
    end
  end
endmodule
