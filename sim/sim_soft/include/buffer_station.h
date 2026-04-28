#pragma once
#include <cassert>
#include <cstdint>
#include <fstream>
#include <ostream>
#include <string>
#include <vector>

/*
 * BufferStation — generic N-stage pipeline shift register for an execution unit.
 *
 * Models the internal pipeline of any FU with fixed latency N.
 * stages_[0] is the input staging area; stages_[depth_] is the output.
 * Each tick() shifts all slots one step toward the output.
 *
 * pipelined=true : accepts one new op per cycle (throughput=1).
 * pipelined=false: rejects new ops while any stage is occupied (throughput=1/N).
 *
 * Caller sequence each cycle:
 *   1. if has_output(): pop_output() → broadcast result
 *   2. accept() new work (if any is ready)
 *   3. tick() to advance all stages
 */
struct BufSlot {
    bool     valid   = false;
    int      rob_tag = -1;
    uint32_t value   = 0;
};

class BufferStation {
public:
    explicit BufferStation(int depth, bool pipelined);

    /* Insert at input stage. Returns false if can't accept this cycle. */
    bool accept(int rob_tag, uint32_t value);

    /* Advance all stages one step toward the output. */
    void tick();

    /* True if the output stage holds a valid result. */
    bool has_output() const;

    /* Return and clear the output stage. */
    BufSlot pop_output();

    /* True if any stage is occupied (for non-pipelined stall detection). */
    bool busy() const;

    void dump(std::ostream& os, int cycle) const;
    void open_log(const std::string& path);
    void log_cycle(int cycle);

private:
    int                  depth_;
    bool                 pipelined_;
    std::vector<BufSlot> stages_;   /* [0]=input staging … [depth_]=output */
    std::ofstream        log_;
};
