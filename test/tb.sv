`default_nettype none
`timescale 1ns / 1ps

/* This testbench just instantiates the module and makes some convenient wires
   that can be driven / tested by the cocotb test.py.
*/
module tb ();
  import spi_pkg::*;
  spi_if spi_bundle();

  localparam int DATA_W             = 8;
  localparam int ADDR_W             = 16;
  localparam int BFCPU_TO_RAM_RATIO = 4;
  localparam int BFCPU_CLK_HZ       = 50_000_000;
  localparam int RP2040_SYS_HZ      = 125_000_000;
  localparam int SYS_GAP_CYCLES     = 50;

  // Dump the signals to a FST file. You can view it with gtkwave or surfer.
  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end

  // Wire up the inputs and outputs
  logic        clk;
  logic        rst_n;
  logic        in_valid_i;
  logic [DATA_W-1:0] data_i;
  logic [ADDR_W-1:0] address_i;
  logic        out_valid_o;
  logic [DATA_W-1:0] data_o;
  logic        done_o;
  
  command_t command_i;

  spi_internal #(
    .DATA_W(DATA_W),
    .ADDR_W(ADDR_W),
    .BFCPU_TO_RAM_RATIO(BFCPU_TO_RAM_RATIO),
    .BFCPU_CLK_HZ(BFCPU_CLK_HZ),
    .RP2040_SYS_HZ(RP2040_SYS_HZ),
    .SYS_GAP_CYCLES(SYS_GAP_CYCLES)
  ) spi_interface (
    .clk(clk),
    .reset_n(rst_n),
    .in_valid_i(in_valid_i),
    .data_i(data_i),
    .address_i(address_i),
    .command_i(command_i),
    .out_valid_o(out_valid_o),
    .data_o(data_o),
    .done_o(done_o),
    .spi_bundle(spi_bundle)
  );
endmodule
