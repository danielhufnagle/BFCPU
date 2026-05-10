`default_nettype none
`timescale 1ns / 1ps

/* This testbench just instantiates the module and makes some convenient wires
   that can be driven / tested by the cocotb test.py.
*/
module tb ();

  // Dump the signals to a FST file. You can view it with gtkwave or surfer.
  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end

  // Wire up the inputs and outputs:
  reg        clk;
  reg        rst_n;
  reg        in_valid_i;
  reg        command_i;
  reg [7:0]  data_i;
  reg [15:0] address_i;
  reg        miso;

  wire       out_valid_o;
  wire [7:0] data_o;
  wire       done_o;
  wire       sclk;
  wire       cs;
  wire       mosi;


  // Replace tt_um_example with your module name:
  spi_internal #(
    .DATA_W(8),
    .ADDR_W(16),
    .ADDR_BIT_W(4)
  ) spi_interface (
    .clk(clk),
    .reset_n(rst_n),
    .in_valid_i(in_valid_i),
    .command_i(command_i), //0 for read, 1 for write
    .data_i(data_i),
    .address_i(address_i),
    .miso_i(miso), //data from external mem
    .out_valid_o(out_valid_o), //for read
    .data_o(data_o),
    .done_o(done_o), //for write, idk if needed
    .sclk_o(sclk),
    .cs_o(cs), //active low, activates slave
    .mosi_o(mosi) //data from asic
  );
endmodule
