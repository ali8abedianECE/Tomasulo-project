#pragma once
#include <cstdint>
#include <fstream>
#include <ostream>
#include <string>
#include <vector>

/*
 * CommonDataBus (CDB) — result broadcast bus for Tomasulo's algorithm.
 *
 * When an execution unit finishes it calls broadcast(rob_tag, value).
 * At the end of the same cycle every listening unit (RS entries, ROB)
 * iterates results() and captures any value whose tag matches.
 * flush() is then called once to clear the bus for the next cycle.
 *
 * Multiple results can land on the CDB in one cycle because pipelined
 * FUs (e.g. FMUL, FADD) can all complete simultaneously. Each RS entry
 * scans the full results list rather than checking a single slot.
 *
 * result.value is stored as uint32_t bits.
 * The consumer uses the corresponding ROBEntry.rd_fp to reinterpret as
 * int32_t (integer) or float (FP) at writeback time.
 */
struct CDBResult {
    int      rob_tag;  /* ROB index that produced this value   */
    uint32_t value;    /* result bits — int32_t or float bits  */
};

class CommonDataBus {
public:
    CommonDataBus();
    /* Called by an execution unit when it completes. */
    void broadcast(int rob_tag, uint32_t value);

    /* True if at least one result is pending this cycle. */
    bool has_results() const;

    /* All pending results — RS entries and ROB snoop this each cycle. */
    const std::vector<CDBResult>& results() const;

    /* Clear all pending results. Call once per cycle after all snooping is done. */
    void flush();

    void dump(std::ostream& os, int cycle) const;
    void open_log(const std::string& path);
    void log_cycle(int cycle);

private:
    std::vector<CDBResult> pending_;
    std::ofstream          log_;
};
