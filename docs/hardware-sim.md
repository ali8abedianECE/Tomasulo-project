# Hardware Simulator (C++ and SystemVerilog)

[Back to root](../README.md)

The hardware simulator sits between the software model and the real RTL. It runs the C++ pipeline model and the SystemVerilog design together in the same simulation, comparing their outputs cycle by cycle. The goal is to catch RTL bugs early, before taping out, by using the already-validated C++ model as a golden reference.

## Status

> Work in progress. The SystemVerilog entry point is at `sim/sim_hdl/sim.sv`. Co-simulation infrastructure is being set up.

## How It Works

1. The C++ model runs one cycle and records every signal it drives and every output it expects.
2. A DPI-C bridge passes those values into the SystemVerilog testbench.
3. The testbench applies the inputs to the RTL, clocks it, and reads back its outputs.
4. If any output differs from what the C++ model predicted, the testbench prints the cycle number, the signal name, the expected value, and the actual value, then stops.

This means you can develop RTL modules one at a time and immediately verify each one against the software model without waiting for the whole chip to be done.

## Running

> Instructions will be added here once the co-simulation build system is in place.

## Signal Naming

RTL signal names follow the same naming conventions as the C++ class members so that the mapping between software model and hardware is obvious. For example, `rob.head_` in C++ corresponds to `rob_head` in the RTL, and `rs_int.count_` corresponds to `rs_int_count`.
