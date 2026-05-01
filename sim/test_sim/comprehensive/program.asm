# Comprehensive test: exercises every instruction type
# Covers: int ALU chain, shift, memory store/load forwarding,
#         taken branch with flush, FP load/store/arith, multi-cycle deps

# === Integer setup ===
ADDI x1, x0, 10        # x1 = 10
ADDI x2, x0, 3         # x2 = 3

# === Dependent integer chain ===
ADD  x3, x1, x2        # x3 = 13   RAW on x1, x2
SUB  x4, x1, x2        # x4 = 7    RAW on x1, x2
AND  x5, x3, x4        # x5 = 5    (13 & 7 = 0101)   RAW chain
OR   x6, x3, x4        # x6 = 15   (13 | 7 = 1111)
XOR  x7, x3, x4        # x7 = 10   (13 ^ 7 = 1010)
SLLI x8, x3, 1         # x8 = 26   RAW on x3
SRLI x9, x8, 2         # x9 = 6    RAW chain on x8

# === Integer store + load (store-to-load forwarding) ===
ADDI x20, x0, 200      # x20 = 200 (byte base = word 50)
SW   x3, 0(x20)        # mem[50] = 13
SW   x4, 4(x20)        # mem[51] = 7
LW   x10, 0(x20)       # x10 = 13  (forwarded from SW x3)
LW   x11, 4(x20)       # x11 = 7   (forwarded from SW x4)

# === Branch taken: BNE x1(10) != x2(3) => skip one instruction ===
BNE  x1, x2, after_skip
ADDI x12, x0, 99       # SKIPPED (branch taken)
after_skip:
ADDI x12, x0, 1        # x12 = 1

# === Verify post-branch forwarding ===
ADD  x13, x10, x11     # x13 = 20  RAW on x10, x11

# === FP: load via integer stores, operate, store back ===
ADDI x21, x0, 160      # x21 = 160 (byte base = word 40)
SW   x1, 0(x21)        # mem[40] = 10 (raw bits for f0)
SW   x2, 4(x21)        # mem[41] = 3  (raw bits for f1)
FLW  f0, 0(x21)        # f0 = bits_to_float(10)  tiny denormal
FLW  f1, 4(x21)        # f1 = bits_to_float(3)   tiny denormal
FADD.S f2, f0, f1      # f2 = f0+f1 = bits_to_float(13)   RAW on f0, f1
FSUB.S f3, f2, f1      # f3 = f2-f1 = f0         RAW chain
FMUL.S f4, f0, f1      # f4 = f0*f1 = 0.0        underflows
FSW  f2, 8(x21)        # mem[42] = bits(f2)
FLW  f5, 8(x21)        # f5 = f2  (FP store-to-load forward)

HALT
