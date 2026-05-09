//Internal Interface for SPI
//Take in data (8 bytes, paramterizable) & address
//Seralizes that data and sends to to the external memory

// It can just take an address 
// - It then fetches the data from that adress, compacts the serial data to a byte and returns it
// Data is usually shifted out with the most-significant bit (MSB) first

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

import spi_pkg::*;

module spi_internal #(
    parameter DATA_W = 8,
    parameter ADDR_W = 16
) (
    input logic              clk,
    input logic              reset_n,
    input logic              in_valid_i,
    input logic [DATA_W-1:0] data_i,
    input logic [ADDR_W-1:0] address_i,

    input command_t          command_i, //0 for read, 1 for write
    
    output logic              out_valid_o, //for read
    output logic [DATA_W-1:0] data_o,
    output logic              done_o, //for write, idk if needed

    spi_if.master             spi_bundle
);

localparam logic [DATA_W-1:0] READ_CMD         = 8'h03; // we expect data immeditly after we give address (low spi_clk)
localparam logic [DATA_W-1:0] FAST_READ_CMD    = 8'h0B; //we give SRAM dmmy cyles so it has time to read (high spi clk)
localparam logic [DATA_W-1:0] WRITE_CMD        = 8'h02;
localparam logic [DATA_W-1:0] WRITE_STATUS_CMD = 8'h01;
localparam logic [DATA_W-1:0] READ_STATUS_CMD  = 8'h05;

localparam int ADDR_BIT_W = $clog2(ADDR_W); 

typedef enum logic [4:0] {IDLE, SHIFT_COMMAND, SHIFT_ADDR, READ , WRITE} state_t;
state_t current_state, next_state;

logic [ADDR_BIT_W-1:0] counter_q, counter_d; //use for both addr, and command
logic [DATA_W-1:0]     command_val_d, command_val_q;
logic [ADDR_W-1:0]     address_q, address_d;
logic [DATA_W-1:0]     data_q, data_d;
logic [DATA_W-1:0]     data_out_d, data_out_q;
logic                  cs_d;
logic                  mosi_d;
logic                  done_d;
logic                  out_valid_d;

command_t              command_q, command_d;


//TODO: If valid & command_i = 0, then do fast read & send data out
//TODO: If valid & command_i = 1, then do write
//TODO: Decide if fast read for normal is better

// FSM = IDLE -> READ || WRITE -> IDLE
// On transition idle -> read || write CS = 0
// Then send command & address (shift in both)
// IF read then compact serial-> byte
// out_valid_o/done = 1 on return to idle

//NOTE: once you read it just keeps streaming out data untill you shut it off, 
//so we can techinally get as many bytes as we want, as long as they are consecutive
//non sequential addresses need seperate reads

assign spi_bundle.sclk = clk;

always_ff @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin
        current_state <= IDLE;
        spi_bundle.cs <= '0;
        counter_q     <= '0;
        done_o        <= '0;
        out_valid_o   <= '0;
    end else begin
        current_state   <= next_state;
        spi_bundle.cs   <= cs_d;
        command_q       <= command_d;
        command_val_q   <= command_val_d;
        counter_q       <= counter_d;
        spi_bundle.mosi <= mosi_d;
        address_q       <= address_d;
        data_q          <= data_d;
        data_out_q      <= data_out_d;
        out_valid_o     <= out_valid_d;
        done_o          <= done_d;
    end
end

assign data_o = data_out_q;

always_comb begin
    //defaults
    mosi_d        = 1'b0;
    out_valid_d   = 1'b0;
    done_d        = 1'b0;
    cs_d          = spi_bundle.cs;
    command_d     = command_q;
    counter_d     = counter_q;
    command_val_d = command_val_q;
    address_d     = address_q;
    next_state    = current_state;
    data_d        = data_q;
    data_out_d    = data_out_q;

    unique case(current_state)
        IDLE : begin
                cs_d = 1'b1;
                if(in_valid_i) begin
                    cs_d          = 1'b0;
                    next_state    = SHIFT_COMMAND;
                    command_d     = command_i;
                    address_d     = address_i;
                    data_d        = data_i;
                    command_val_d = command_i ? WRITE_CMD : READ_CMD;
                end
            end 
        
        SHIFT_COMMAND : begin
            mosi_d        = command_val_q[DATA_W-1];
            command_val_d = command_val_q << 1;

            if(counter_q == DATA_W-1) begin
                counter_d  = '0;
                next_state = SHIFT_ADDR;
            end else begin
                counter_d = counter_q + 1;
            end
        end

        SHIFT_ADDR : begin
            mosi_d    = address_q[ADDR_W-1]; 
            address_d = address_q << 1;

            if(counter_q == ADDR_W-1) begin
                counter_d  = '0;
                next_state = (command_q == WRITE_T) ? WRITE : READ;
            end else begin
                counter_d = counter_q + 1;
            end
        end

        READ : begin // listen to data
            data_out_d = {data_out_q[DATA_W-1:1], spi_bundle.miso};

            if(counter_q == DATA_W-1) begin
                counter_d   = '0;
                cs_d        = 1'b1; // not listening anymore
                out_valid_d = 1'b1;
                next_state  = IDLE; 
            end else begin
                counter_d = counter_q + 1;
            end
        end

        WRITE : begin 
            mosi_d = data_q[DATA_W-1]; 
            data_d = data_q << 1;

            if(counter_q == DATA_W-1) begin
                counter_d  = '0;
                cs_d       = 1'b1; // not listening anymore
                done_d     = 1'b1;
                next_state = IDLE;
            end else begin
                counter_d = counter_q + 1;
            end  
        end
    endcase
end
    
endmodule : spi_internal
