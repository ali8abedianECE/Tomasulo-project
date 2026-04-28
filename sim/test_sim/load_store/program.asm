# Load/store test
# Store values to memory, load them back, verify forwarding
ADDI x1, x0, 42       # x1 = 42
ADDI x2, x0, 100      # x2 = 100  (base address word 25 = byte 100)
SW   x1, 0(x2)        # mem[25] = 42
LW   x3, 0(x2)        # x3 = 42  (load after store — tests ordering)
ADDI x4, x0, 7
SW   x4, 4(x2)        # mem[26] = 7
LW   x5, 4(x2)        # x5 = 7
ADD  x6, x3, x5       # x6 = 49
HALT
