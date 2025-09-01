# Sample testbench for a Tiny Tapeout project


This is a sample testbench for a Tiny Tapeout project. It uses [cocotb](https://docs.cocotb.org/en/stable/) to drive the DUT and check the outputs.
Multiple cocotb tests are provided in `test.py` to verify different features of the sprite engine. All tests are run together by default.
See below to get started or for more information, check the [website](https://tinytapeout.com/hdl/testing/).

## Setting up

1. Edit [Makefile](Makefile) and modify `PROJECT_SOURCES` to point to your Verilog files.
2. Edit [tb.v](tb.v) and replace `tt_um_example` with your module name.

## How to run


## Running the tests

To run all cocotb tests (including the integrated full test):

```sh
make -B
```

This will run all cocotb tests defined in `test.py` and print results for each feature (object RAM, bitmap RAM, control register, interrupt, video outputs, multiple sprites).


To run gatelevel simulation, first harden your project and copy `../runs/wokwi/results/final/verilog/gl/{your_module_name}.v` to `gate_level_netlist.v`.

Then run:

```sh
make -B GATES=yes
```


## How to view the VCD file

Using GTKWave
```sh
gtkwave tb.vcd tb.gtkw
```

Using Surfer
```sh
surfer tb.vcd
```
