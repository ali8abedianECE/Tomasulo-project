# Software Simulator

[Back to root](../README.md)

The software simulator is a cycle-accurate C++ model of the full Tomasulo pipeline. Every unit has its own class, every class has its own log file, and the main clock loop steps through them in the right order each cycle. It is not meant to be fast; it is meant to be readable and correct so you can trace exactly what the hardware should do.

## Pipeline Units

| Unit | Class | What it does |
|---|---|---|
| Instruction Queue | `InstructionQueue` | Fetches up to `IQ_FETCH_WIDTH` instructions per cycle into a buffer, dispatches one at a time to RS or LSB |
| Reservation Stations (x2) | `ReservationStation` | Holds waiting instructions, watches the CDB for operands, executes when ready |
| Load/Store Buffer | `LoadStoreBuffer` | Orders all memory ops, computes addresses, forwards store data to dependent loads |
| Common Data Bus | `CommonDataBus` | Broadcasts results from RS and LSB to everyone who is waiting |
| Reorder Buffer | `ReorderBuffer` | Tracks all in-flight instructions and retires them in program order |
| Register Renaming Table | `RegisterRemappingTable` | Maps architectural register names to the ROB slot that will produce their next value |
| Register File | `RegisterFile` | Holds the committed architectural state (32 int + 32 FP) |
| Commit Unit | `CommitUnit` | Pops the head of the ROB each cycle when it is ready, writes results to RF and RAT |
| Buffer Station | `BufferStation` | Generic pipelined delay element used by each functional unit |

## Configuration

Everything tunable lives in [`sim_soft/include/config.h`](../sim/sim_soft/include/config.h). You change a number and recompile.

```cpp
constexpr int  IQ_FETCH_WIDTH = 1;    // instructions fetched and dispatched per cycle
constexpr int  IQ_CAPACITY    = 8;    // fetch buffer depth
constexpr int  ROB_SIZE       = 16;   // reorder buffer entries
constexpr int  RS_INT_SIZE    = 6;    // integer reservation stations
constexpr int  RS_FP_SIZE     = 4;    // FP reservation stations
constexpr int  LSB_SIZE       = 8;    // load/store buffer entries

constexpr int  LAT_INT_ALU    = 1;    // ADD/SUB/AND/OR etc.
constexpr int  LAT_FP_ADDSUB  = 2;    // FADD.S / FSUB.S
constexpr int  LAT_FP_MUL     = 4;    // FMUL.S
constexpr int  LAT_FP_DIV     = 8;    // FDIV.S
constexpr int  LAT_INT_LS     = 2;    // LW / SW
```

## Building and Running

```bash
cd sim/sim_soft/make
make -j8
./tomasulo_sim <program.asm> <output_dir/>
```

Or just use the helper script from the repo root which rebuilds and runs every test:

```bash
bash sim/run_tests.sh
```

## Writing a Test Program

Assembly files are plain text. Comments start with `#`. Labels end with `:`. Branch targets are label names.

```asm
# simple example
ADDI x1, x0, 10
ADDI x2, x0, 3
ADD  x3, x1, x2       # x3 = 13
BNE  x1, x2, done     # taken
ADDI x3, x0, 99       # skipped
done:
HALT
```

Put the file anywhere under `sim/test_sim/<name>/program.asm` and `run_tests.sh` will pick it up automatically.

## Output Files

Running the simulator writes two folders.

### `logs/`

One log file per pipeline unit. Each line is one cycle. This is the main thing you look at when debugging.

| File | Unit |
|---|---|
| `iq.log` | Instruction Queue |
| `rob.log` | Reorder Buffer |
| `rs_int.log` | Integer Reservation Stations |
| `rs_fp.log` | FP Reservation Stations |
| `lsb.log` | Load/Store Buffer |
| `cdb.log` | Common Data Bus |
| `rat.log` | Register Renaming Table |
| `rf.log` | Register File |
| `cu.log` | Commit Unit |
| `trace.txt` | All units together, one block per cycle |

### `final/final_regs.txt`

Architectural register state at HALT. Integer registers, then FP registers (with both the hex bit pattern and the float value), then any non-zero memory words.

```
[INT_REGS]
x01 0x0000000a
x02 0x00000003
...
[FP_REGS]
f02 0x0000000d (1.82169e-44f)
...
[MEM_NONZERO]
mem[  50] 0x0000000d
```

## Reading the Logs Step by Step

The example below uses the `comprehensive` test which exercises every instruction type. The program starts like this:

```asm
ADDI x1, x0, 10
ADDI x2, x0, 3
ADD  x3, x1, x2    # depends on x1 and x2
SUB  x4, x1, x2    # depends on x1 and x2
...
```

### Instruction Queue (`iq.log`)

```
[IQ  cycle=   1] fetched=0 buf=0/8
[IQ  cycle=   2] fetched=1 buf=0/8
[IQ  cycle=   3] fetched=2 buf=0/8
```

`fetched` is a running total of how many instructions have been fetched so far (it is the next index to fetch, not how many were grabbed this cycle). The IQ grabs `IQ_FETCH_WIDTH` instructions per cycle and immediately dispatches them to an RS or LSB slot. `buf` shows how many are sitting in the fetch buffer right now waiting to be dispatched. It stays at 0 when dispatch keeps up.

When a branch is taken and the pipeline flushes, `fetched` jumps back to the instruction index at the branch target. You can see this in the `branch` test where `fetched` goes 6, 4, 5, 6, 4, 5, 6... as the loop repeats.

### Reorder Buffer (`rob.log`)

```
[ROB  cycle=   2] head=0 tail=1 count=1/16
  [ 0] INFLT ADDI rd=x1 PC=0x0000
[ROB  cycle=   3] head=1 tail=2 count=1/16
  [ 1] INFLT ADDI rd=x2 PC=0x0004
[ROB  cycle=   4] head=2 tail=3 count=1/16
  [ 2] INFLT ADD rd=x3 PC=0x0008
```

Each line inside a cycle block is one in-flight instruction. `INFLT` means it is executing. The slot number `[ 0]` is the ROB tag that the CDB and RS use to talk about this instruction. `count=1/16` tells you how backlogged the ROB is. In this test it is always 1 because simple 1-cycle instructions commit as fast as they are issued. If you raise the FP multiply latency to 8 cycles you will see `count` climb.

### Common Data Bus (`cdb.log`)

```
[CDB  cycle=   2] ROB0=0x0000000a
[CDB  cycle=   3] ROB1=0x00000003
[CDB  cycle=   4] ROB2=0x0000000d
[CDB  cycle=   5] ROB3=0x00000007
```

The CDB log is written after execution, so it shows what was broadcast this cycle. `ROB0=0x0000000a` means the instruction in ROB slot 0 (the `ADDI x1, x0, 10`) finished and put the value `10` on the bus. Any RS entry that was waiting on ROB0 latches that value immediately in the same cycle.

Cycles where nothing finished show `idle`. For stores and branches the commit goes through the ROB directly, not the CDB, so you may see gaps.

### Reservation Stations (`rs_int.log`)

```
[RS   cycle=   2]
  [ 0] ADDI ROB=0 vj=0x0 vk=0x0
[RS   cycle=   5]
  [ 0] ADD ROB=2 vj=0xa vk=0x3
```

Each occupied RS slot shows the instruction, its ROB tag, and its source operands. `vj` and `vk` are resolved values. If an operand is still waiting the field would show `qj=ROB<n>` instead, meaning "I need the value from ROB slot n before I can execute." Once both operands are values (not tags) the instruction fires.

### Load/Store Buffer (`lsb.log`)

```
[LSB  cycle=  12] head=0 tail=1 count=1/8
  [ 0] WAIT SW ROB=10 vj=0xc8 vk=0xd PC=0x0028
[LSB  cycle=  13] head=1 tail=2 count=1/8
  [ 1] WAIT SW ROB=11 vj=0xc8 vk=0x7 PC=0x002c
[LSB  cycle=  14] head=2 tail=3 count=1/8
  [ 2] WAIT LW ROB=12 vj=0xc8 PC=0x0030
```

`WAIT` means the entry is waiting for its base address register to resolve. `vj` is the base address (already resolved here since it shows a value not a tag). `vk` is the store data. Once `vj` is known the effective address is computed. For loads, the LSB checks whether any older store to the same address is already done and forwards that value directly instead of hitting memory.

States go: `WAIT` -> `ARDY` (address ready) -> `EXEC` (multi-cycle load in progress) -> `DONE`.

### Register Renaming Table (`rat.log`)

```
[RAT  cycle=   4]
  INT: x3->ROB2 x4->ROB3
```

This shows which architectural registers are currently renamed. `x3->ROB2` means the next writer to x3 is the instruction in ROB slot 2, so any instruction that reads x3 right now gets tag `ROB2` instead of a value. Once ROB2 commits, the RAT entry for x3 clears.

### Commit Unit (`cu.log`)

```
[CU   cycle=   3] COMMIT ADDI PC=0x0000 x1=0xa
[CU   cycle=   4] COMMIT ADDI PC=0x0004 x2=0x3
[CU   cycle=   5] COMMIT ADD  PC=0x0008 x3=0xd
```

One line per cycle showing exactly what retired. This is the ground truth for whether your program ran correctly. The value after the register name is what got written to the architectural register file.
