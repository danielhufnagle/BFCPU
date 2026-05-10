`default_nettype none
`timescale 1ns / 1ps

/* This testbench just instantiates the module and makes some convenient wires
   that can be driven / tested by the cocotb test.py.
*/
module tb ();
  import spi_pkg::*;
  spi_if spi_bundle();

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
  logic [7:0]  data_i;
  logic [15:0] address_i;
  logic        out_valid_o;
  logic [7:0]  data_o;
  logic        done_o;
  
  command_t command_i;

  spi_internal #(
    .DATA_W(8),
    .ADDR_W(16)
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
