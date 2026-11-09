// =============================================================================
// Interface: uart_if
// Purpose: Signal interface for UART VIP (Transmitter Sout and Receiver Sin)
// =============================================================================

`timescale 1ns/1ps

interface uart_if (
    input logic clk,
    input logic rst_n
);
    logic sin;   // Driven into DUT UARTSin
    logic sout;  // Monitored from DUT UARTSout

endinterface : uart_if

