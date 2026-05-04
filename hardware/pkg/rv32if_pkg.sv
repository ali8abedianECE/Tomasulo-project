/**
 * @file rv32if_pkg.sv
 * @brief Shared types, parameters, and helper functions for the RV32IF Tomasulo pipeline.
 *
 * Every hardware module imports this package with:
 *   import rv32if_pkg::*;
 *
 */
package rv32if_pkg;

  // Structural sizes 
  /** @defgroup sizes Structural Sizes
   *  Entry counts for each pipeline buffer. Change here and every module picks
   *  up the new value automatically.  Mirrors config.h.
   *  @{
   */
  parameter  IQ_DEPTH = 8; ///< Instruction queue depth (entries).
  parameter  ROB_SIZE = 16; ///< Reorder buffer entries.
  parameter  RS_ALU_SIZE = 6; ///< Integer ALU RS slots (ADD/SUB/logic/shift/imm).
  parameter  RS_BRANCH_SIZE = 2; ///< Branch RS slots (BEQ/BNE/BLT/BGE/JAL/JALR).
  parameter  RS_FP_ADDSUB_SIZE = 3; ///< FP add/sub RS slots (FADD.S, FSUB.S).
  parameter  RS_FP_MUL_SIZE = 2; ///< FP multiply RS slots (FMUL.S).
  parameter  RS_FP_DIV_SIZE = 2; ///< FP divide RS slots (FDIV.S - unpipelined).
  parameter  RS_FP_CVT_SIZE = 2; ///< FP conversion RS slots (FCVT.W.S, FCVT.S.W).
  parameter  LSB_SIZE = 8; ///< Load/store buffer entries.
  /**
   * Number of functional units that can broadcast a result on the CDB.
   * One slot per unit: INT ALU, Branch, FP add/sub, FP mul, FP div, Load, FP cvt.
   * Increase this if a new execution unit is added; the CDB arbiter scales automatically.
   */
  parameter  NUM_FU = 7;
  parameter  NUM_INT_REGS = 32; ///< Integer architectural registers (x0-x31).
  parameter  NUM_FP_REGS = 32; ///< FP architectural registers (f0-f31).
  parameter  MEM_SIZE = 1024; ///< Data memory capacity in 32-bit words.
  /** @} */

  // Bit widths 
  parameter  DATA_W = 32; ///< Data path width in bits.
  parameter  ARCH_W = 5; ///< Architectural register index width (log2 of 32).
  parameter  TAG_W = 4; ///< ROB tag width - 4 bits supports ROB_SIZE up to 16.
  parameter  PC_W = 32; ///< Program counter width in bits.

  // Execution latencies 
  /** @defgroup latencies Execution Latencies
   *  Pipeline depth for each functional unit, in cycles.  Mirrors config.h.
   *  @{
   */
  parameter  LAT_INT_ALU = 1; ///< ADD, SUB, AND, OR, XOR, shifts, ADDI variants.
  parameter  LAT_INT_LS = 2; ///< LW, SW - single memory-access stage.
  parameter  LAT_BRANCH = 1; ///< BEQ, BNE, BLT, BGE, JAL, JALR.
  parameter  LAT_FP_ADDSUB = 2; ///< FADD.S, FSUB.S.
  parameter  LAT_FP_MUL = 4; ///< FMUL.S.
  parameter  LAT_FP_DIV = 8; ///< FDIV.S - unpipelined; stalls the FP divide unit.
  parameter  LAT_FP_LS= 2; ///< FLW, FSW.
  parameter  LAT_FP_CVT = 2; ///< FCVT.W.S, FCVT.S.W.
  /** @} */

  //  Opcode enum 
  /**
   * @brief All opcodes supported by the RV32IF pipeline.
   *
   * Explicit encoding values keep the mapping stable across tools and match the
   * Raw RISC-V bit fields (opcode/funct3/funct7) are not preserved after decode; 
   * only this enum flows downstream.
   */
  typedef enum logic [5:0] {
    OP_ADD = 6'd0, ///< rd = rs1 + rs2
    OP_SUB = 6'd1, ///< rd = rs1 - rs2
    OP_AND = 6'd2, ///< rd = rs1 & rs2
    OP_OR = 6'd3, ///< rd = rs1 | rs2
    OP_XOR = 6'd4, ///< rd = rs1 ^ rs2
    OP_SLL = 6'd5, ///< rd = rs1 << rs2[4:0]
    OP_SRL = 6'd6, ///< rd = rs1 >> rs2[4:0]  (logical)
    OP_SRA = 6'd7, ///< rd = rs1 >>> rs2[4:0] (arithmetic)
    OP_ADDI = 6'd8, ///< rd = rs1 + imm
    OP_ANDI = 6'd9, ///< rd = rs1 & imm
    OP_ORI = 6'd10, ///< rd = rs1 | imm
    OP_XORI = 6'd11, ///< rd = rs1 ^ imm
    OP_SLLI = 6'd12, ///< rd = rs1 << imm[4:0]
    OP_SRLI = 6'd13, ///< rd = rs1 >> imm[4:0]  (logical)
    OP_LW = 6'd14, ///< rd = Mem[rs1 + imm]
    OP_SW = 6'd15, ///< Mem[rs1 + imm] = rs2
    OP_BEQ = 6'd16, ///< if rs1 == rs2: PC += imm
    OP_BNE = 6'd17, ///< if rs1 != rs2: PC += imm
    OP_BLT = 6'd18, ///< if rs1 <  rs2 (signed): PC += imm
    OP_BGE = 6'd19, ///< if rs1 >= rs2 (signed): PC += imm
    OP_JAL  = 6'd20, ///< rd = PC+4;  PC = PC + imm           (J-type, PC-relative)
    OP_JALR = 6'd21, ///< rd = PC+4;  PC = (rs1 + imm) & ~1   (I-type, register-indirect)
    OP_LUI  = 6'd22, ///< rd = imm << 12                       (U-type, no source registers)
    OP_FADD_S = 6'd23, ///< fd = fs1 + fs2
    OP_FSUB_S = 6'd24, ///< fd = fs1 - fs2
    OP_FMUL_S = 6'd25, ///< fd = fs1 * fs2
    OP_FDIV_S = 6'd26, ///< fd = fs1 / fs2  (unpipelined)
    OP_FLW = 6'd27, ///< fd = Mem[rs1 + imm]  (float load)
    OP_FSW = 6'd28, ///< Mem[rs1 + imm] = fs2  (float store)
    OP_FCVT_W_S = 6'd29, ///< rd = (int32_t) fs1   - f-reg src, x-reg dst
    OP_FCVT_S_W = 6'd30, ///< fd = (float)   rs1   - x-reg src, f-reg dst
    OP_NOP = 6'd62, ///< No operation.
    OP_HALT= 6'd63 ///< Stop simulation / pipeline drain.
  } opcode_e;

  //  Decoded instruction 
  /**
   * @brief Post-decode pipeline word flowing from decode to dispatch.
   *
   * The raw 32-bit encoding is cracked in decode.sv and forwarded past that stage.
   * Register indices are 0-31 for both integer (x) and FP (f) register files;
   * the @c *_fp flags tell each downstream stage which file to use.
   */
  typedef struct packed {
    opcode_e op; ///< Decoded opcode.
    logic [ARCH_W-1:0] rd; ///< Destination register index (0-31).
    logic [ARCH_W-1:0] rs1; ///< Source register 1 index (0-31).
    logic [ARCH_W-1:0] rs2; ///< Source register 2 index (0-31).
    logic [DATA_W-1:0] imm; ///< Sign-extended 32-bit immediate.
    logic rd_fp; ///< 1 -> rd  lives in the FP register file.
    logic rs1_fp; ///< 1 -> rs1 lives in the FP register file.
    logic rs2_fp; ///< 1 -> rs2 lives in the FP register file.
    logic rd_valid; ///< 0 -> no writeback (stores, branches, NOP).
    logic [PC_W-1:0] pc;  ///< Byte address of this instruction.
  } instr_t;

  // CDB broadcast 
  /**
   * @brief One result broadcast on the Common Data Bus in a single cycle.
   *
   * Every RS entry and the ROB snoop this struct each cycle; a match on @c tag 
   * captures @c value as an operand. Multiple CDB ports can be instantiated as 
   * an array: @c cdb_t cdb[N].
   */
  typedef struct packed {
    logic [TAG_W-1:0]  tag; ///< ROB index of the completing instruction.
    logic [DATA_W-1:0] value; ///< Result bits - int32 or float, reinterpreted at writeback.
    logic valid; ///< 1 -> this slot carries a live result this cycle.
  } cdb_t;

  // ROB entry state 
  /**
   * @brief Lifecycle state for one reorder buffer slot.
   *
   * ROBState.
   */
  typedef enum logic [1:0] {
    ROB_IDLE = 2'd0, ///< Slot is free and available for allocation.
    ROB_IN_FLIGHT = 2'd1, ///< Instruction dispatched; result not yet available.
    ROB_DONE = 2'd2 ///< Result written by CDB; waiting for in-order commit.
  } rob_state_e;

  // ROB entry
  /**
   * @brief One entry in the reorder buffer.
   *
   * The result is stored as raw bits; commit_unit reads @c rd_fp to 
   * decide whether to write the integer or FP register file at retirement.
   */
  typedef struct packed {
    rob_state_e state; ///< Current lifecycle state of this slot.
    opcode_e op; ///< Opcode of the in-flight instruction.
    logic [ARCH_W-1:0] rd;  ///< Destination architectural register.
    logic rd_fp; ///< 1 -> rd lives in the FP register file.
    logic rd_valid; ///< 0 -> no writeback (stores, branches).
    logic [DATA_W-1:0] result; ///< Result bits; valid only when state == ROB_DONE.
    logic [PC_W-1:0] pc;  ///< Instruction byte address (for trace output).
    logic is_branch;///< 1 -> this entry is a branch instruction.
    logic branch_taken; ///< Branch outcome resolved by the branch unit.
    logic [PC_W-1:0]branch_target; ///< Resolved branch target PC.
  } rob_entry_t;

  // RS dispatch entry
  /**
   * @brief Payload written into a reservation station slot at dispatch.
   *
   * Dispatch resolves each source register against the RAT: if the register
   * is ready (no in-flight write) rs1_ready/rs2_ready is set and the value is
   * read from the register file. Otherwise the ROB tag is stored and the RS
   * snoops the CDB each cycle until the tag matches.
   */
  typedef struct packed {
    opcode_e           op;        ///< Decoded opcode.
    logic [TAG_W-1:0]  rob_tag;   ///< ROB slot assigned to this instruction.
    logic              rs1_ready; ///< 1 -> rs1_val is valid now; 0 -> waiting on rs1_tag.
    logic [DATA_W-1:0] rs1_val;   ///< Source 1 value (valid when rs1_ready).
    logic [TAG_W-1:0]  rs1_tag;   ///< ROB tag to snoop for source 1 (valid when !rs1_ready).
    logic              rs2_ready; ///< 1 -> rs2_val is valid now; 0 -> waiting on rs2_tag.
    logic [DATA_W-1:0] rs2_val;   ///< Source 2 value (valid when rs2_ready).
    logic [TAG_W-1:0]  rs2_tag;   ///< ROB tag to snoop for source 2 (valid when !rs2_ready).
    logic [DATA_W-1:0] imm;       ///< Sign-extended immediate.
    logic [PC_W-1:0]   pc;        ///< Instruction byte address.
  } rs_entry_t;

  // Helper functions

  /** @brief True if @p op is a conditional branch (BEQ, BNE, BLT, BGE). */
  function automatic logic is_branch_op(input opcode_e op);
    return (op == OP_BEQ || op == OP_BNE || op == OP_BLT || op == OP_BGE);
  endfunction

  /** @brief True if @p op is an unconditional jump-and-link (JAL, JALR). */
  function automatic logic is_jump_op(input opcode_e op);
    return (op == OP_JAL || op == OP_JALR);
  endfunction

  /** @brief True if @p op reads from memory (LW, FLW). */
  function automatic logic is_load_op(input opcode_e op);
    return (op == OP_LW || op == OP_FLW);
  endfunction

  /** @brief True if @p op writes to memory (SW, FSW). */
  function automatic logic is_store_op(input opcode_e op);
    return (op == OP_SW || op == OP_FSW);
  endfunction

  /**
   * @brief True if @p op belongs to the FP instruction set.
   *
   * Covers FADD.S, FSUB.S, FMUL.S, FDIV.S, FLW, FSW, FCVT.W.S, FCVT.S.W.
   */
  function automatic logic is_fp_op(input opcode_e op);
    return (op == OP_FADD_S || op == OP_FSUB_S   ||
            op == OP_FMUL_S || op == OP_FDIV_S   ||
            op == OP_FLW || op == OP_FSW  ||
            op == OP_FCVT_W_S || op == OP_FCVT_S_W);
  endfunction

endpackage
