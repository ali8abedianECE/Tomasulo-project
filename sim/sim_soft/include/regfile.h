#pragma once
#include "config.h"
#include <cstdint>
#include <fstream>
#include <ostream>
#include <string>

/**
 * @brief Architectural register file - holds committed state only.
 *
 * Two separate banks:
 *   - @c int_regs_[0..31]  maps to x0-x31 (int32_t).  x0 is hardwired to 0; writes are ignored.
 *   - @c fp_regs_ [0..31]  maps to f0-f31 (float, single-precision RV32F).
 *
 * During out-of-order execution operand values come from the ROB and CDB.
 * The register file is authoritative only after an instruction commits.
 */
class RegisterFile {
public:
    RegisterFile();

    /**
     * @brief Read an integer register.
     * @param[in] idx  Register index (0-31).  Reading x0 always returns 0.
     * @return         Signed 32-bit integer value of register @p idx.
     */
    int32_t read_int(int idx) const;

    /**
     * @brief Write an integer register.
     * @param[in] idx  Register index (0-31).  Writes to x0 are silently ignored.
     * @param[in] val  Value to store.
     */
    void    write_int(int idx, int32_t val);

    /**
     * @brief Read a single-precision FP register.
     * @param[in] idx  Register index (0-31).
     * @return         Float value of register f@p idx.
     */
    float   read_fp(int idx) const;

    /**
     * @brief Write a single-precision FP register.
     * @param[in] idx  Register index (0-31).
     * @param[in] val  Float value to store.
     */
    void    write_fp(int idx, float val);

    /** @brief Print current register state to @p os annotated with @p cycle. */
    void dump(std::ostream& os, int cycle) const;

    /** @brief Open (or create) the cycle-trace log file at @p path. */
    void open_log(const std::string& path);

    /** @brief Append a one-line state snapshot for @p cycle to the log file. */
    void log_cycle(int cycle);

private:
    int32_t       int_regs_[NUM_INT_REGS];  /* x0-x31, x0 kept at 0 */
    float         fp_regs_[NUM_FP_REGS];   /* f0-f31                 */
    std::ofstream log_;
};
