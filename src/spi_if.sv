// ASIC = SPI master controller
// RP2040 = SPI RAM slave

interface spi_if #(
  parameter int DATA_W = 1
);
  logic cs;
  logic sclk;
  logic mosi;
  logic miso;
  
  modport slave ( // external memeory
    input  sclk,
    input  cs,
    input  mosi,
    output miso
  );

  modport master ( // ASIC
    output sclk,
    output cs, //active low, activates slave
    output mosi, //data from asic
    input  miso //data from external mem
  );

endinterface : spi_if
