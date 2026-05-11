# Sample testbench for a Tiny Tapeout project

This is a sample testbench for a Tiny Tapeout project. It uses [cocotb](https://docs.cocotb.org/en/stable/) to drive the DUT and check the outputs.
See below to get started or for more information, check the [website](https://tinytapeout.com/hdl/testing/).

## Setting up

1. Edit [Makefile](Makefile) and modify `PROJECT_SOURCES` to point to your Verilog files.
2. Edit [tb.v](tb.v) and replace `tt_um_example` with your module name.
3. Install the Python test dependencies from this directory:

```sh
python3 -m pip install -r requirements.txt
```

If that command fails with `No module named pip`, install `pip` for your Python first. On Ubuntu/Debian systems:

```sh
sudo apt install python3-pip
```

## How to run

To run the RTL simulation:

```sh
make -B
```

The `make -B` command uses `cocotb-config`, which is installed by the `cocotb` package in `requirements.txt`. If `cocotb-config` is missing, Make will fail before compiling the Verilog.

This testbench now instantiates `spi_internal`, so [test.py](test.py) also needs to drive the SPI testbench signals (`rst_n`, `in_valid_i`, `command_i`, `data_i`, `address_i`, and `miso`) rather than the original Tiny Tapeout sample signals (`ena`, `ui_in`, `uio_in`, and `uo_out`).

To run gatelevel simulation, first harden your project and copy `../runs/wokwi/results/final/verilog/gl/{your_module_name}.v` to `gate_level_netlist.v`.

Then run:

```sh
make -B GATES=yes
```

If you wish to save the waveform in VCD format instead of FST format, edit tb.v to use `$dumpfile("tb.vcd");` and then run:

```sh
make -B FST=
```

This will generate `tb.vcd` instead of `tb.fst`.

## How to view the waveform file

Using GTKWave

```sh
gtkwave tb.fst tb.gtkw
```

Using Surfer

```sh
surfer tb.fst
```
