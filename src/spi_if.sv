// ASIC = SPI master controller
// RP2040 = SPI RAM slave
// Serial protocols will often send the least significant bits first 

// Drives the clock (SCLK)
// Selects the device, active low (CS)
// ASIC sends data (MOSI)
// SRAM sends data (MISO)

interface spi_if #(
  parameter int DATA_W = 1
);

  logic [DATA_W-1:0] data;
  logic              valid;

  modport spi_slave ( // external memeory
    input  sclk,
    input  cs,
    input  mosi,
    output miso
  );

  modport spi_master ( // ASIC
    output sclk,
    output cs, //active low, activates slave
    output mosi, //data from asic
    input  miso //data from external mem
  );

endinterface : spi_if