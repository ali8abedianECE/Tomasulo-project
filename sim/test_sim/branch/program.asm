# Branch test: simple countdown loop  x1 = sum of 1..5
# x1=0 (accumulator), x2=5 (counter), x3=1 (step)
ADDI x1, x0, 0        # x1 = 0
ADDI x2, x0, 5        # x2 = 5  (loop counter)
ADDI x3, x0, 1        # x3 = 1
loop:
ADD  x1, x1, x2       # x1 += x2
SUB  x2, x2, x3       # x2 -= 1
BNE  x2, x0, loop     # if x2 != 0 goto loop
# x1 should equal 5+4+3+2+1 = 15
HALT
