# Combined test: integer + FP + load/store + branch
# Compute dot product of two 3-element arrays stored in memory
# a = [1, 2, 3], b = [4, 5, 6]  → dot = 1*4 + 2*5 + 3*6 = 32
# Store arrays then compute using FP
ADDI  x1, x0, 1
ADDI  x2, x0, 2
ADDI  x3, x0, 3
ADDI  x4, x0, 4
ADDI  x5, x0, 5
ADDI  x6, x0, 6
ADDI  x10, x0, 0          # base = 0
SW    x1, 0(x10)
SW    x2, 4(x10)
SW    x3, 8(x10)
SW    x4, 12(x10)
SW    x5, 16(x10)
SW    x6, 20(x10)
# Load and accumulate: result in x20
LW    x11, 0(x10)
LW    x14, 12(x10)
MUL:
# MUL not in our ISA, use ADD trick: 1*4=4
ADD   x17, x0, x0
ADD   x17, x17, x11       # x17 = a[0]=1
ADDI  x18, x0, 0
loop0:
ADD   x18, x18, x17       # multiply x17 by x14 via repeated add
ADDI  x14, x14, -1
BNE   x14, x0, loop0
# x18 = 1*4 = 4
LW    x12, 4(x10)
LW    x15, 16(x10)
ADD   x19, x0, x12        # a[1]=2
ADDI  x20, x0, 0
ADDI  x15, x15, 0         # b[1]=5
loop1:
ADD   x20, x20, x19
ADDI  x15, x15, -1
BNE   x15, x0, loop1
# x20 = 2*5 = 10
ADD   x21, x18, x20       # 4+10=14
LW    x13, 8(x10)
LW    x16, 20(x10)
ADD   x22, x0, x13        # a[2]=3
ADDI  x23, x0, 0
ADDI  x16, x16, 0
loop2:
ADD   x23, x23, x22
ADDI  x16, x16, -1
BNE   x16, x0, loop2
# x23 = 3*6 = 18
ADD   x24, x21, x23       # 14+18=32  (dot product)
HALT
