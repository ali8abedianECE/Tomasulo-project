# Integer ALU test
# x1=10, x2=3; compute x3=x1+x2, x4=x1-x2, x5=x1*x2 (via shifts), x6=x1 AND x2
ADDI x1, x0, 10       # x1 = 10
ADDI x2, x0, 3        # x2 = 3
ADD  x3, x1, x2       # x3 = 13  (RAW: x3 waits for x1,x2)
SUB  x4, x1, x2       # x4 = 7   (RAW: x4 waits for x1,x2)
AND  x5, x1, x2       # x5 = 2   (bitwise AND)
OR   x6, x1, x2       # x6 = 11  (bitwise OR)
XOR  x7, x1, x2       # x7 = 9   (bitwise XOR)
SLLI x8, x1, 2        # x8 = 40  (shift left 2)
SRLI x9, x1, 1        # x9 = 5   (shift right 1)
ADD  x10, x3, x4      # x10 = 20 (RAW on x3 and x4 — tests forwarding)
HALT
