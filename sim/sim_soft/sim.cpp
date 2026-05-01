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
static std::vector<Instruction> parse_program(const std::string& path) {}


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
                          bool&                   branch_dispatched) {}


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
int main(int argc, char* argv[]) {}

