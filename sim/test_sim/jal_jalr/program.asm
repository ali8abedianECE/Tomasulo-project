# JAL / JALR test
#
# Expected final state:
#   x1 = 8   (return address saved by JAL at PC=4)
#   x2 = 99  (set inside the called function)
#   x3 = 12  (return address saved by JAL at PC=8)
#   x10 = 42 (set by JALR-based indirect call)

    ADDI x5, x0, 99          # x5 = 99  (argument to pass)
    JAL  x1, func_a           # call func_a; x1 = PC+4 = 4
    JAL  x3, func_b           # call func_b; x3 = PC+4 = 12
    HALT

func_a:
    ADD  x2, x5, x0           # x2 = x5 = 99
    JALR x0, x1, 0            # return to caller (x1 holds return addr)

func_b:
    ADDI x10, x0, 42          # x10 = 42
    JALR x0, x3, 0            # return to caller (x3 holds return addr)
