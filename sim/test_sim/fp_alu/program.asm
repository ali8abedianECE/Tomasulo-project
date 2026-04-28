# FP ALU test
# Load two floats from memory, add/mul them
ADDI  x1, x0, 0          # x1 = base address 0
ADDI  x2, x0, 100        # x2 = integer 100
FCVT.S.W f1, x2          # f1 = 100.0
ADDI  x3, x0, 25
FCVT.S.W f2, x3          # f2 = 25.0
FADD.S f3, f1, f2         # f3 = 125.0
FMUL.S f4, f1, f2         # f4 = 2500.0  (pipelined, lat=4)
FSUB.S f5, f1, f2         # f5 = 75.0    (runs concurrently with FMUL)
FCVT.W.S x4, f3           # x4 = 125
HALT
