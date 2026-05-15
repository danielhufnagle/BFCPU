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
// uio[2] - GPIO23 - MISOS
// uio[3] - GPIO24 - SCK

// If using regular in and out pins, i dont think it really matters
// uo_out[4] - CS
// uo_out[3] - MOSI
// ui_in[2] - MISO
// uo_out[5] - SCK

// FSM = IDLE -> READ || WRITE -> IDLE
// On transition idle -> read || write CS = 0
// Then send command & address (shift in both)
// IF read then compact serial-> byte
// out_valid_o/done = 1 on return to idle

//NOTE: once you read it just keeps streaming out data untill you shut it off, 
//so we can techinally get as many bytes as we want, as long as they are consecutive
//non sequential addresses need seperate reads

// normal READ: RP2040 SYS / 10
// FAST READ:  RP2040 SYS / 8
// WRITE:      RP2040 SYS / 6
// received one reads bit when it hits the SCLK rising edge.
// successfully sends one write bit after the full SCLK cycle completes

import spi_pkg::*;

module spi_internal #(
    parameter int DATA_W             = 8,
    parameter int ADDR_W             = 16,
    parameter int BFCPU_TO_RAM_RATIO = 4,
    parameter int BFCPU_CLK_HZ       = 50_000_000,
    parameter int RP2040_SYS_HZ      = 125_000_000,
    parameter int SYS_GAP_CYCLES     = 50
    
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

localparam int SCLK_DIV      = (8 * BFCPU_CLK_HZ + RP2040_SYS_HZ - 1) / RP2040_SYS_HZ;
localparam int CS_GAP_CYCLES = (BFCPU_CLK_HZ * SYS_GAP_CYCLES + RP2040_SYS_HZ - 1) / RP2040_SYS_HZ;

localparam int SCLK_HALF_DIV  = (SCLK_DIV + 1) / 2;
localparam int SCLK_CNT_W     = (SCLK_HALF_DIV <= 1) ? 1 : $clog2(SCLK_HALF_DIV);
localparam int ADDR_BIT_W     = $clog2(ADDR_W); 
localparam int NUM_DUM_CYCLES = 8;

typedef enum logic [6:0] {IDLE, SHIFT_COMMAND, DUMMY_CYCLES, SHIFT_ADDR, FAST_READ , WRITE, WAIT} state_t;
state_t current_state, next_state;

logic [ADDR_BIT_W-1:0] counter_q, counter_d; //use for both addr, and command
logic [DATA_W-1:0]     command_val_d, command_val_q;
logic [ADDR_W-1:0]     address_q, address_d;
logic [DATA_W-1:0]     data_q, data_d;
logic [DATA_W-1:0]     data_out_d, data_out_q;
logic [SCLK_CNT_W-1:0] sclk_counter_d, sclk_counter_q;
logic                  cs_d;
logic                  sclk_d, sclk_q;
logic                  sclk_toggle_tick;
logic                  sclk_rise_tick;
logic                  sclk_fall_tick;
logic                  mosi_d;
logic                  done_d;
logic                  out_valid_d;

command_t              command_q, command_d;

// Clocked Block 
always_ff @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin
        current_state  <= IDLE;
        spi_bundle.cs  <= '0;
        counter_q      <= '0;
        sclk_counter_q <= '0;
        sclk_q         <= '0;
        done_o         <= '0;
        out_valid_o    <= '0;
    end else begin
        current_state   <= next_state;
        spi_bundle.cs   <= cs_d;
        command_q       <= command_d;
        command_val_q   <= command_val_d;
        counter_q       <= counter_d;
        sclk_counter_q  <= sclk_counter_d;
        sclk_q          <= sclk_d;
        spi_bundle.mosi <= mosi_d;
        address_q       <= address_d;
        data_q          <= data_d;
        data_out_q      <= data_out_d;
        out_valid_o     <= out_valid_d;
        done_o          <= done_d;
    end
end

assign data_o           = data_out_q;
assign spi_bundle.sclk  = spi_bundle.cs ? 1'b0 : sclk_q;
assign sclk_toggle_tick = !spi_bundle.cs && (sclk_counter_q == SCLK_HALF_DIV-1);
assign sclk_rise_tick   = sclk_toggle_tick && (sclk_q == 1'b0);
assign sclk_fall_tick   = sclk_toggle_tick && (sclk_q == 1'b1);


// Combo Clock Division Block
always_comb begin 
    sclk_counter_d = sclk_counter_q;
    sclk_d         = sclk_q;

    if(spi_bundle.cs) begin
        sclk_counter_d = '0;
        sclk_d         = 1'b0;
    end else if(sclk_counter_q == SCLK_HALF_DIV-1) begin
        sclk_counter_d = '0;
        sclk_d         = ~sclk_q;
    end else begin
        sclk_counter_d = sclk_counter_q + 1;
    end
end

// Combo FSM Block
always_comb begin
    //defaults
    mosi_d        = spi_bundle.mosi;
    out_valid_d   = 1'b0;
    done_d        = 1'b0;
    cs_d          = spi_bundle.cs;
    command_d     = command_q;
    counter_d     = sclk_fall_tick ? counter_q + 1 : counter_q;
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
                    command_val_d = ((command_i == WRITE_T) ? WRITE_CMD : FAST_READ_CMD);
                    mosi_d        = ((command_i == WRITE_T) ? WRITE_CMD[DATA_W-1] : FAST_READ_CMD[DATA_W-1]);
                    counter_d     = '0;
                end
            end 
        
        SHIFT_COMMAND : begin
            mosi_d = command_val_q[DATA_W-1];

            if(sclk_fall_tick) begin
                command_val_d = command_val_q << 1;

                if(counter_q == DATA_W-1) begin
                    counter_d  = '0;
                    next_state = SHIFT_ADDR;
                end
            end
        end

        SHIFT_ADDR : begin
            mosi_d = address_q[ADDR_W-1]; 

            if(sclk_fall_tick) begin
                address_d = address_q << 1;

                if(counter_q == ADDR_W-1) begin
                    counter_d  = '0;
                    next_state = (command_q == WRITE_T) ? WRITE : DUMMY_CYCLES;
                end
            end
        end

        DUMMY_CYCLES : begin
            if(sclk_fall_tick) begin
                if(counter_q == NUM_DUM_CYCLES-1) begin
                    counter_d  = '0;
                    next_state = FAST_READ;
                end
            end
        end

        FAST_READ : begin // listen to data
            cs_d = 1'b0;

            if(sclk_rise_tick) begin
                data_out_d = {data_out_q[DATA_W-2:0], spi_bundle.miso};
            end

            if(sclk_fall_tick) begin
                if(counter_q == DATA_W-1) begin
                    counter_d   = '0;
                    cs_d        = 1'b1; // not listening anymore
                    out_valid_d = 1'b1;
                    next_state  = WAIT; 
                end
            end
        end

        WRITE : begin
            cs_d   = 1'b0;
            mosi_d = data_q[DATA_W-1];

            if(sclk_fall_tick) begin
                data_d = data_q << 1;

                if(counter_q == DATA_W-1) begin
                    counter_d  = '0;
                    cs_d       = 1'b1;
                    done_d     = 1'b1;
                    next_state = WAIT;
                end
            end
        end

        WAIT : begin
            cs_d      = 1'b1;
            counter_d = counter_q + 1;

            if(counter_q == CS_GAP_CYCLES-2) begin
                counter_d  = '0;
                next_state = IDLE;
            end
        end
    endcase
end
    
endmodule : spi_internal
