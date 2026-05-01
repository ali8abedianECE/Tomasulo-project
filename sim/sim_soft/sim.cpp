#include "buffer_station.h"
#include "commit_unit.h"
#include "common_data_bus.h"
#include "config.h"
#include "instruction.h"
#include "instruction_queue.h"
#include "load_store_buffer.h"
#include "regfile.h"
#include "register_remapping_table.h"
#include "reorder_buffer.h"
#include "reservation_station.h"
#include "utils.h"
#include <cassert>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

/* text helpers */

/**
 * @brief Split an assembly source line into tokens, stripping comments and commas.
 *
 * Text from the first @c # character to the end of the line is discarded.
 * Commas are treated as whitespace so operands like @c x1,x2 are split correctly.
 *
 * @param[in] line Raw source line.
 *
 * @return Vector of whitespace-separated tokens with no comments or commas.
 */
static std::vector<std::string> tokenize(const std::string& line) {
    std::string s = line;
    auto hash = s.find('#');
    if (hash != std::string::npos) s = s.substr(0, hash);
    for (char& c : s) if (c == ',') c = ' ';
    std::vector<std::string> toks;
    std::istringstream iss(s);
    std::string t;
    while (iss >> t) toks.push_back(t);
    return toks;
}


/**
 * @brief Parse a register name token into its numeric index.
 *
 * Accepts both integer (@c xN) and floating-point (@c fN) register names.
 *
 * @param[in] s Register name token (e.g. @c "x5" or @c "f3").
 *
 * @return Zero-based register index.
 */
static int preg(const std::string& s) { return std::stoi(s.substr(1)); }


/**
 * @brief Parse a memory operand of the form @c imm(xN).
 *
 * @param[in]  s    Operand token (e.g. @c "8(x2)").
 * @param[out] imm  Signed byte offset extracted from the token.
 * @param[out] base Integer register index of the base address register.
 */
static void parse_mem(const std::string& s, int32_t& imm, int& base) {
    auto lp = s.find('(');
    auto rp = s.find(')', lp);
    imm  = static_cast<int32_t>(std::stoi(s.substr(0, lp)));
    base = preg(s.substr(lp + 1, rp - lp - 1));
}


/**
 * @brief Resolve a branch target to a signed byte offset relative to @p cur_pc.
 *
 * The target may be specified as a literal numeric byte offset or as a label
 * name defined earlier in the same source file.
 *
 * @param[in] s       Target operand token (numeric string or label name).
 * @param[in] labels  Map of label names to their byte addresses.
 * @param[in] cur_pc  Byte address of the branch instruction itself.
 *
 * @return Signed byte offset from @p cur_pc to the target.
 */
static int32_t branch_offset(const std::string& s,
                              const std::unordered_map<std::string, int>& labels,
                              uint32_t cur_pc) {
    try { return static_cast<int32_t>(std::stoi(s)); }
    catch (...) {}
    auto it = labels.find(s);
    if (it == labels.end()) { std::cerr << "Unknown label: " << s << "\n"; return 0; }
    return static_cast<int32_t>(it->second) - static_cast<int32_t>(cur_pc);
}


/* assembly parser */

/**
 * @brief Read and decode an assembly source file into a flat instruction list.
 *
 * Makes two passes over the file: the first pass collects label-to-address
 * mappings; the second pass decodes each mnemonic into an Instruction struct.
 * PC values are assigned as sequential word addresses (index × 4).
 *
 * @param[in] path File-system path to the @c .asm source file.
 *
 * @return Decoded instruction list in program order, or an empty vector on error.
 */
static std::vector<Instruction> parse_program(const std::string& path) {
    std::ifstream f(path);
    if (!f) { std::cerr << "Cannot open program: " << path << "\n"; return {}; }

    std::vector<std::string> raw;
    std::string line;
    while (std::getline(f, line)) raw.push_back(line);

    /* First pass: map label names to byte addresses */
    std::unordered_map<std::string, int> labels;
    int wpc = 0;
    for (const auto& l : raw) {
        auto toks = tokenize(l);
        if (toks.empty()) continue;
        if (toks[0].back() == ':')
            labels[toks[0].substr(0, toks[0].size() - 1)] = wpc * 4;
        else
            ++wpc;
    }

    /* Second pass: decode instructions */
    std::vector<Instruction> prog;
    wpc = 0;
    for (const auto& l : raw) {
        auto toks = tokenize(l);
        if (toks.empty() || toks[0].back() == ':') continue;

        Instruction in;
        in.pc = static_cast<uint32_t>(wpc * 4);
        const std::string& op = toks[0];

        if      (op=="ADD")  { in.op=Opcode::ADD;  in.rd=preg(toks[1]); in.rs1=preg(toks[2]); in.rs2=preg(toks[3]); }
        else if (op=="SUB")  { in.op=Opcode::SUB;  in.rd=preg(toks[1]); in.rs1=preg(toks[2]); in.rs2=preg(toks[3]); }
        else if (op=="AND")  { in.op=Opcode::AND;  in.rd=preg(toks[1]); in.rs1=preg(toks[2]); in.rs2=preg(toks[3]); }
        else if (op=="OR")   { in.op=Opcode::OR;   in.rd=preg(toks[1]); in.rs1=preg(toks[2]); in.rs2=preg(toks[3]); }
        else if (op=="XOR")  { in.op=Opcode::XOR;  in.rd=preg(toks[1]); in.rs1=preg(toks[2]); in.rs2=preg(toks[3]); }
        else if (op=="SLL")  { in.op=Opcode::SLL;  in.rd=preg(toks[1]); in.rs1=preg(toks[2]); in.rs2=preg(toks[3]); }
        else if (op=="SRL")  { in.op=Opcode::SRL;  in.rd=preg(toks[1]); in.rs1=preg(toks[2]); in.rs2=preg(toks[3]); }
        else if (op=="SRA")  { in.op=Opcode::SRA;  in.rd=preg(toks[1]); in.rs1=preg(toks[2]); in.rs2=preg(toks[3]); }
        else if (op=="ADDI") { in.op=Opcode::ADDI; in.rd=preg(toks[1]); in.rs1=preg(toks[2]); in.imm=std::stoi(toks[3]); }
        else if (op=="ANDI") { in.op=Opcode::ANDI; in.rd=preg(toks[1]); in.rs1=preg(toks[2]); in.imm=std::stoi(toks[3]); }
        else if (op=="ORI")  { in.op=Opcode::ORI;  in.rd=preg(toks[1]); in.rs1=preg(toks[2]); in.imm=std::stoi(toks[3]); }
        else if (op=="XORI") { in.op=Opcode::XORI; in.rd=preg(toks[1]); in.rs1=preg(toks[2]); in.imm=std::stoi(toks[3]); }
        else if (op=="SLLI") { in.op=Opcode::SLLI; in.rd=preg(toks[1]); in.rs1=preg(toks[2]); in.imm=std::stoi(toks[3]); }
        else if (op=="SRLI") { in.op=Opcode::SRLI; in.rd=preg(toks[1]); in.rs1=preg(toks[2]); in.imm=std::stoi(toks[3]); }
        /* LW / FLW: rd, imm(rs1) */
        else if (op=="LW")   { in.op=Opcode::LW;  in.rd=preg(toks[1]); parse_mem(toks[2], in.imm, in.rs1); }
        else if (op=="FLW")  { in.op=Opcode::FLW; in.rd=preg(toks[1]); in.rd_fp=true; parse_mem(toks[2], in.imm, in.rs1); }
        /* SW / FSW: rs2, imm(rs1)   — rs2=data, rs1=base, rd=-1 */
        else if (op=="SW")   { in.op=Opcode::SW;  in.rs2=preg(toks[1]); parse_mem(toks[2], in.imm, in.rs1); }
        else if (op=="FSW")  { in.op=Opcode::FSW; in.rs2=preg(toks[1]); in.rs2_fp=true; parse_mem(toks[2], in.imm, in.rs1); }
        /* Branches: rs1, rs2, offset-or-label */
        else if (op=="BEQ")  { in.op=Opcode::BEQ; in.rs1=preg(toks[1]); in.rs2=preg(toks[2]); in.imm=branch_offset(toks[3],labels,in.pc); }
        else if (op=="BNE")  { in.op=Opcode::BNE; in.rs1=preg(toks[1]); in.rs2=preg(toks[2]); in.imm=branch_offset(toks[3],labels,in.pc); }
        else if (op=="BLT")  { in.op=Opcode::BLT; in.rs1=preg(toks[1]); in.rs2=preg(toks[2]); in.imm=branch_offset(toks[3],labels,in.pc); }
        else if (op=="BGE")  { in.op=Opcode::BGE; in.rs1=preg(toks[1]); in.rs2=preg(toks[2]); in.imm=branch_offset(toks[3],labels,in.pc); }
        /* FP ALU */
        else if (op=="FADD.S") { in.op=Opcode::FADD_S; in.rd=preg(toks[1]); in.rd_fp=true; in.rs1=preg(toks[2]); in.rs1_fp=true; in.rs2=preg(toks[3]); in.rs2_fp=true; }
        else if (op=="FSUB.S") { in.op=Opcode::FSUB_S; in.rd=preg(toks[1]); in.rd_fp=true; in.rs1=preg(toks[2]); in.rs1_fp=true; in.rs2=preg(toks[3]); in.rs2_fp=true; }
        else if (op=="FMUL.S") { in.op=Opcode::FMUL_S; in.rd=preg(toks[1]); in.rd_fp=true; in.rs1=preg(toks[2]); in.rs1_fp=true; in.rs2=preg(toks[3]); in.rs2_fp=true; }
        else if (op=="FDIV.S") { in.op=Opcode::FDIV_S; in.rd=preg(toks[1]); in.rd_fp=true; in.rs1=preg(toks[2]); in.rs1_fp=true; in.rs2=preg(toks[3]); in.rs2_fp=true; }
        /* FP conversions */
        else if (op=="FCVT.W.S") { in.op=Opcode::FCVT_W_S; in.rd=preg(toks[1]); in.rd_fp=false; in.rs1=preg(toks[2]); in.rs1_fp=true; }
        else if (op=="FCVT.S.W") { in.op=Opcode::FCVT_S_W; in.rd=preg(toks[1]); in.rd_fp=true;  in.rs1=preg(toks[2]); in.rs1_fp=false; }
        else if (op=="NOP")  { in.op=Opcode::NOP; }
        else if (op=="HALT") { in.op=Opcode::HALT; }
        else { std::cerr << "Unknown opcode '" << op << "' at word " << wpc << "\n"; }

        prog.push_back(in);
        ++wpc;
    }
    return prog;
}


/* dispatch helper */

/**
 * @brief Attempt to dispatch the front IQ instruction into the appropriate execution unit.
 *
 * Operands are resolved against the current RAT before the RAT entry is updated,
 * so a self-referential instruction (e.g. @c ADD x1,x1,x1) reads the old mapping.
 * The instruction is routed to the integer RS, FP RS, or LSB based on its opcode.
 *
 * @param[in,out] iq                  Instruction queue to dispatch from.
 * @param[in,out] rob                 Reorder buffer to allocate a slot in.
 * @param[in,out] rat                 Register-renaming table to update after dispatch.
 * @param[in]     rf                  Architectural register file for operand lookup.
 * @param[in,out] rs_int              Integer reservation station.
 * @param[in,out] rs_fp               Floating-point reservation station.
 * @param[in,out] lsb                 Load/store buffer.
 * @param[out]    branch_dispatched   Set to @c true if the dispatched instruction is a branch.
 *
 * @return @c true if an instruction was dispatched; @c false if the IQ is empty
 *         or all required buffers are full.
 */
static bool try_dispatch(InstructionQueue&       iq,
                          ReorderBuffer&          rob,
                          RegisterRemappingTable& rat,
                          const RegisterFile&     rf,
                          ReservationStation&     rs_int,
                          ReservationStation&     rs_fp,
                          LoadStoreBuffer&        lsb,
                          bool&                   branch_dispatched) {
    if (!iq.can_dispatch()) return false;
    const Instruction instr = iq.peek();  /* copy before any mutation */

    bool full_rob = rob.full();
    bool issued   = false;

    if (is_load(instr.op) || is_store(instr.op)) {
        if (!full_rob && !lsb.full()) {
            int rob_tag = rob.allocate(instr);
            lsb.issue(instr, rob_tag, rat, rf, rob);        /* resolve on old RAT */
            if (instr.rd >= 0) rat.map(instr.rd, instr.rd_fp, rob_tag);
            iq.dispatch();
            issued = true;
        }
    } else if (is_fp_op(instr.op)) {
        if (!full_rob && !rs_fp.full()) {
            int rob_tag = rob.allocate(instr);
            rs_fp.issue(instr, rob_tag, rat, rf, rob);
            if (instr.rd >= 0) rat.map(instr.rd, instr.rd_fp, rob_tag);
            iq.dispatch();
            issued = true;
        }
    } else {
        if (!full_rob && !rs_int.full()) {
            int rob_tag = rob.allocate(instr);
            rs_int.issue(instr, rob_tag, rat, rf, rob);
            if (instr.rd >= 0) rat.map(instr.rd, instr.rd_fp, rob_tag);
            iq.dispatch();
            issued = true;
        }
    }

    if (issued && is_branch(instr.op))
        branch_dispatched = true;
    return issued;
}


/* main */

/**
 * @brief Simulator entry point: parse, run, and emit results.
 *
 * Expects exactly two command-line arguments:
 *   1. Path to the assembly source file (@c .asm).
 *   2. Output directory; @c logs/ and @c final/ subdirectories are created inside it.
 *
 * Runs the Tomasulo out-of-order pipeline until a HALT commits, the program
 * exhausts all instructions, or the cycle limit is reached.  Per-unit cycle logs
 * are written to @c logs/ and the final register/memory state to @c final/.
 *
 * @param[in] argc Argument count (must be 3).
 * @param[in] argv Argument vector: @c argv[1] = asm path, @c argv[2] = output dir.
 *
 * @return 0 on success, 1 on usage or load error.
 */
int main(int argc, char* argv[]) {
    if (argc < 3) {
        std::cerr << "Usage: " << argv[0] << " <program.asm> <output_dir/>\n";
        return 1;
    }

    const std::string asm_path = argv[1];
    const std::string out_dir  = argv[2];

    /* Create output subdirectories */
    const std::string logs_dir  = out_dir + "/logs";
    const std::string final_dir = out_dir + "/final";
    std::filesystem::create_directories(logs_dir);
    std::filesystem::create_directories(final_dir);

    std::vector<Instruction> program = parse_program(asm_path);
    if (program.empty()) { std::cerr << "No instructions loaded.\n"; return 1; }

    auto log_path   = [&](const std::string& name) { return logs_dir  + "/" + name; };
    auto final_path = [&](const std::string& name) { return final_dir + "/" + name; };

    /* Instantiate pipeline units */
    std::vector<uint32_t>  mem(MEM_SIZE, 0);
    RegisterFile           rf;
    RegisterRemappingTable rat;
    ReorderBuffer          rob(ROB_SIZE);
    CommonDataBus          cdb;
    ReservationStation     rs_int(RS_INT_SIZE);
    ReservationStation     rs_fp(RS_FP_SIZE);
    LoadStoreBuffer        lsb(LSB_SIZE);
    InstructionQueue       iq(IQ_CAPACITY);
    CommitUnit             cu;

    /* Open per-unit cycle logs */
    iq.open_log(log_path("iq.log"));
    rob.open_log(log_path("rob.log"));
    rs_int.open_log(log_path("rs_int.log"));
    rs_fp.open_log(log_path("rs_fp.log"));
    lsb.open_log(log_path("lsb.log"));
    cdb.open_log(log_path("cdb.log"));
    rat.open_log(log_path("rat.log"));
    rf.open_log(log_path("rf.log"));
    cu.open_log(log_path("cu.log"));

    /* Combined per-cycle trace goes in logs/ */
    std::ofstream trace(log_path("trace.txt"));

    iq.load_program(program);

    bool     halted           = false;
    bool     branch_in_flight = false;
    int      cycle            = 1;
    constexpr int MAX_CYCLES  = 200000;

    while (!halted && cycle <= MAX_CYCLES) {

        /* dump state at start of cycle */
        trace << "\n=== CYCLE " << cycle << " ===\n";
        iq.dump(trace, cycle);
        rob.dump(trace, cycle);
        rs_int.dump(trace, cycle);
        rs_fp.dump(trace, cycle);
        lsb.dump(trace, cycle);
        cdb.dump(trace, cycle);
        rat.dump(trace, cycle);
        cu.dump(trace, cycle);

        /* per-unit logs */
        iq.log_cycle(cycle);
        rob.log_cycle(cycle);
        rs_int.log_cycle(cycle);
        rs_fp.log_cycle(cycle);
        lsb.log_cycle(cycle);
        cdb.log_cycle(cycle);
        rat.log_cycle(cycle);
        rf.log_cycle(cycle);
        cu.log_cycle(cycle);

        /* Phase 1: execute one cycle */
        rs_int.tick();
        rs_fp.tick();
        lsb.tick(mem);

        /* Phase 2: notify ROB about DONE stores (so commit can retire them) */
        lsb.update_rob(rob);

        /* Phase 3: broadcast execution results → CDB + ROB */
        while (rs_int.has_result()) {
            RSEntry r = rs_int.pop_result();
            rob.write_result(r.rob_tag, r.result);
            cdb.broadcast(r.rob_tag, r.result);
        }
        while (rs_fp.has_result()) {
            RSEntry r = rs_fp.pop_result();
            rob.write_result(r.rob_tag, r.result);
            cdb.broadcast(r.rob_tag, r.result);
        }
        while (lsb.has_load_result()) {
            LSBEntry r = lsb.pop_load_result();
            rob.write_result(r.rob_tag, r.result);
            cdb.broadcast(r.rob_tag, r.result);
        }

        /* Phase 4: snoop CDB — RS entries capture results broadcast this cycle */
        rs_int.snoop(cdb);
        rs_fp.snoop(cdb);
        lsb.snoop(cdb);

        /* Phase 5: in-order commit */
        uint32_t next_pc = 0;
        if (cu.tick(rob, rf, rat, lsb, mem, next_pc, halted)) {
            if (is_branch(cu.last().op)) {
                /* Seek IQ to the resolved branch target */
                branch_in_flight = false;
                iq.seek(next_pc);
            }
        }

        /* Phase 6: fetch then dispatch (stall while a branch is in-flight) */
        if (!branch_in_flight && !halted) {
            iq.tick();
            /* Save front-of-IQ PC before dispatch consumes the instruction */
            uint32_t peek_pc = iq.can_dispatch() ? iq.peek().pc : 0u;
            bool branch_dispatched = false;
            if (try_dispatch(iq, rob, rat, rf, rs_int, rs_fp, lsb, branch_dispatched)) {
                if (branch_dispatched) {
                    branch_in_flight = true;
                    /* Discard any instructions prefetched past the branch */
                    iq.seek(peek_pc + 4u);  /* will be overridden to real target at commit */
                }
            }
        }

        /* Phase 7: flush CDB for the next cycle */
        cdb.flush();

        ++cycle;

        if (!halted && iq.done() && rob.empty()) break;
    }

    /* final register state */
    const int final_cycle = cycle - 1;
    std::ofstream final_f(final_path("final_regs.txt"));
    final_f << "# Tomasulo simulation: " << asm_path << "\n";
    final_f << "# Total cycles: " << final_cycle << "\n\n";

    /* Integer registers — one per line for easy Verilog parsing */
    final_f << "[INT_REGS]\n";
    for (int i = 0; i < NUM_INT_REGS; ++i)
        final_f << "x" << std::setw(2) << std::setfill('0') << i
                << " 0x" << std::hex << std::setw(8) << std::setfill('0')
                << static_cast<uint32_t>(rf.read_int(i))
                << std::dec << std::setfill(' ') << "\n";

    final_f << "\n[FP_REGS]\n";
    for (int i = 0; i < NUM_FP_REGS; ++i)
        final_f << "f" << std::setw(2) << std::setfill('0') << i
                << " 0x" << std::hex << std::setw(8) << std::setfill('0')
                << float_to_bits(rf.read_fp(i))
                << std::dec << std::setfill(' ')
                << " (" << rf.read_fp(i) << "f)\n";

    final_f << "\n[MEM_NONZERO]\n";
    for (int i = 0; i < MEM_SIZE; ++i) {
        if (mem[i] == 0) continue;
        final_f << "mem[" << std::setw(4) << i << "] 0x"
                << std::hex << std::setw(8) << std::setfill('0')
                << mem[i] << std::dec << std::setfill(' ') << "\n";
    }

    /* Also append final state to trace */
    trace << "\n=== FINAL STATE (cycle " << final_cycle << ") ===\n";
    rf.dump(trace, final_cycle);

    std::cout << "Done. " << final_cycle << " cycles.\n"
              << "  logs/  -> " << logs_dir  << "/\n"
              << "  final/ -> " << final_dir << "/\n";
    return 0;
}

