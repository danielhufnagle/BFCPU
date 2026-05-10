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

module spi_internal #(
    parameter DATA_W     = 8,
    parameter ADDR_W     = 16,
    parameter ADDR_BIT_W = 4
) (
    input wire              clk,
    input wire              reset_n,
    input wire              in_valid_i,
    input wire              command_i, //0 for read, 1 for write
    input wire [DATA_W-1:0] data_i,
    input wire [ADDR_W-1:0] address_i,
    input wire              miso_i, //data from external mem
    
    output reg               out_valid_o, //for read
    output reg  [DATA_W-1:0] data_o,
    output reg               done_o, //for write, idk if needed
    output wire              sclk_o,
    output reg               cs_o, //active low, activates slave
    output reg               mosi_o //data from asic
);

localparam [2:0]        NUM_STATES = 3'd5;

localparam [DATA_W-1:0] READ_CMD         = 8'h03; // we expect data immeditly after we give address (low spi_clk)
localparam [DATA_W-1:0] FAST_READ_CMD    = 8'h0B; //we give SRAM dmmy cyles so it has time to read (high spi clk)
localparam [DATA_W-1:0] WRITE_CMD        = 8'h02;
localparam [DATA_W-1:0] WRITE_STATUS_CMD = 8'h01;
localparam [DATA_W-1:0] READ_STATUS_CMD  = 8'h05;

localparam [NUM_STATES-1:0] IDLE          = 3'd0;
localparam [NUM_STATES-1:0] SHIFT_COMMAND = 3'd1;
localparam [NUM_STATES-1:0] SHIFT_ADDR    = 3'd2;
localparam [NUM_STATES-1:0] READ          = 3'd3;
localparam [NUM_STATES-1:0] WRITE         = 3'd4;

reg [NUM_STATES-1:0] current_state, next_state;

reg [ADDR_BIT_W-1:0] counter_q, counter_d; //use for both addr, and command
reg [DATA_W-1:0]     command_val_d, command_val_q;
reg [ADDR_W-1:0]     address_q, address_d;
reg [DATA_W-1:0]     data_q, data_d;
reg [DATA_W-1:0]     data_out_d, data_out_q;
reg                  cs_d;
reg                  mosi_d;
reg                  done_d;
reg                  out_valid_d;
reg                  command_q, command_d;

//TODO: Decide if fast read for normal is better

// FSM = IDLE -> READ || WRITE -> IDLE
// On transition idle -> read || write CS = 0
// Then send command & address (shift in both)
// IF read then compact serial-> byte
// out_valid_o/done = 1 on return to idle

//NOTE: once you read it just keeps streaming out data untill you shut it off, 
//so we can techinally get as many bytes as we want, as long as they are consecutive
//non sequential addresses need seperate reads

assign sclk_o = cs_o? 1'b0 : ~clk;

always @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin
        current_state <= IDLE;
        cs_o          <= 1'b0;
        mosi_o        <= 1'b0;
        counter_q     <= {ADDR_BIT_W{1'b0}};
        command_q     <= 1'b0;
        command_val_q <= {DATA_W{1'b0}};
        address_q     <= {ADDR_W{1'b0}};
        data_q        <= {DATA_W{1'b0}};
        data_out_q    <= {DATA_W{1'b0}};
        data_o        <= {DATA_W{1'b0}};
        done_o        <= 1'b0;
        out_valid_o   <= 1'b0;
    end else begin
        current_state <= next_state;
        cs_o          <= cs_d;
        command_q     <= command_d;
        command_val_q <= command_val_d;
        counter_q     <= counter_d;
        mosi_o        <= mosi_d;
        address_q     <= address_d;
        data_q        <= data_d;
        data_out_q    <= data_out_d;
        data_o        <= data_out_d;
        out_valid_o   <= out_valid_d;
        done_o        <= done_d;
    end
end

always @(*) begin
    //defaults
    mosi_d        = 1'b0;
    out_valid_d   = 1'b0;
    done_d        = 1'b0;
    cs_d          = cs_o;
    command_d     = command_q;
    counter_d     = counter_q;
    command_val_d = command_val_q;
    address_d     = address_q;
    next_state    = current_state;
    data_d        = data_q;
    data_out_d    = data_out_q;

    case(current_state)
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
                counter_d  = {ADDR_BIT_W{1'b0}};
                next_state = SHIFT_ADDR;
            end else begin
                counter_d = counter_q + 1;
            end
        end

        SHIFT_ADDR : begin
            mosi_d    = address_q[ADDR_W-1]; 
            address_d = address_q << 1;

            if(counter_q == ADDR_W-1) begin
                counter_d  = {ADDR_BIT_W{1'b0}};
                next_state = command_q ? WRITE : READ;
            end else begin
                counter_d = counter_q + 1;
            end
        end

        READ : begin // listen to data
            data_out_d = {data_out_q[DATA_W-2:0], miso_i};

            if(counter_q == DATA_W-1) begin
                counter_d   = {ADDR_BIT_W{1'b0}};
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
                counter_d  = {ADDR_BIT_W{1'b0}};
                cs_d       = 1'b1; // not listening anymore
                done_d     = 1'b1;
                next_state = IDLE;
            end else begin
                counter_d = counter_q + 1;
            end  
        end
    endcase
end
    
endmodule
