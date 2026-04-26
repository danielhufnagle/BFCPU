//TODO: this moduel needs to be an internal interface for SPI
// It can take in data (8 bytes, paramterizable) & address
// - it then seralizes that data and sends to to the external memory

// It can just take an address 
// - It then fetches the data from that adress, compacts the serial data to a byte and returns it

// Basic transaction flow
// 1. Set CS low (listening)
// 2. send command byte
// 3. send address (16 bits)
// 4. read/write stream
// 5. CS high

// Suggested pinout from the tiny tapeout website
// IF using In_out pins:
// uio[0] - GPIO21 - CS
// uio[1] - GPIO22 - MOSI
// uio[2] - GPIO23 - MISO
// uio[3] - GPIO24 - SCK

// If using regular in and out pins, i dont think it really matters
// uo_out[4] - CS
// uo_out[3] - MOSI
// ui_in[2] - MISO
// uo_out[5] - SCK

module spi_internal #(
    parameter DATA_W = 8,
    parameter ADDR_W = 16
) (
    input               clk,
    input               reset_n,
    input               in_valid_i,
    input               command_i, //0 for read, 1 for write
    input  [DATA_W-1:0] data_i,
    input  [ADDR_W-1:0] address_i,
    output              out_valid_o, //for read
    output [DATA_W-1:0] data_o,
    output              done_o, //for write, idk if needed

    spi_if.master       spi_bundle
);

localparam logic [DATA_W-1:0] READ         = 8'h03; // we expect data immeditly after we give address (low spi_clk)
localparam logic [DATA_W-1:0] FAST_READ    = 8'h0B; //we give SRAM dmmy cyles so it has time to read (high spi clk)
localparam logic [DATA_W-1:0] WRITE        = 8'h02;
localparam logic [DATA_W-1:0] WRITE_STATUS = 8'h01;
localparam logic [DATA_W-1:0] READ_STATUS  = 8'h05;

//TODO: If valid & 0, then do fast read & send data out
//TODO: If valid & 1, then do write
//TODO: decide if fast read for normal is better

// FSM = IDLE -> READ || WRITE -> IDLE
// On transition idle -> read || write CS = 1
// Then send command & address (shift in both)
// IF read then compact serial-> byte
// out_valid_o/done = 1 on return to idle

//NOTE: once you read it jst keeps streaming out data untill you shut it off, 
//so we can techinally get as many bytes as we want, as long as they are consecutive
//non sequential addresses need seperate reads

always_ff @(posedge clk) begin
    if(!reset_n) begin

    end else begin

    end
end

always_comb begin
    spi_bundle.cs = 1'b0;
end
    
endmodule : spi_internal