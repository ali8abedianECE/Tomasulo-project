#include "buffer_station.h"
#include <iomanip>

/**
 * @brief Construct a BufferStation pipeline with the given depth and pipelining mode.
 *
 * @param[in] depth     Number of pipeline stages (latency in cycles).
 * @param[in] pipelined If @c true, a new value may be accepted every cycle;
 *                      if @c false, no new value is accepted until the station drains.
 */
BufferStation::BufferStation(int depth, bool pipelined)
    : depth_(depth), pipelined_(pipelined) {}


/**
 * @brief Accept a new result into the input stage of the pipeline.
 *
 * @param[in] rob_tag ROB tag identifying the producing instruction.
 * @param[in] value   32-bit result value to pipeline.
 *
 * @return @c true if the value was accepted; @c false if the input port is
 *         already occupied this cycle or (for non-pipelined mode) if any
 *         stage is still busy.
 */
bool BufferStation::accept(int rob_tag, uint32_t value) {}


/**
 * @brief Advance the pipeline by one cycle.
 *
 * Shifts each stage one position toward the output end, then clears the
 * input staging slot so a new value may be accepted next cycle.
 */
void BufferStation::tick() {}


/**
 * @brief Check whether a value has reached the output stage.
 *
 * @return @c true if the last pipeline stage holds a valid result.
 */
bool BufferStation::has_output() const {}


/**
 * @brief Remove and return the value at the output stage.
 *
 * @return A copy of the output BufSlot. The output stage is cleared.
 *
 * @throws Assertion failure if called when has_output() is false.
 */
BufSlot BufferStation::pop_output() {}


/**
 * @brief Check whether any pipeline stage is currently occupied.
 *
 * @return @c true if at least one stage holds a valid slot.
 */
bool BufferStation::busy() const {}


/**
 * @brief Print the contents of all occupied pipeline stages.
 *
 * @param[in,out] os    Output stream to write to.
 * @param[in]     cycle Current simulation cycle number (for the header line).
 */
void BufferStation::dump(std::ostream& os, int cycle) const {}



void BufferStation::open_log(const std::string& path) {}


void BufferStation::log_cycle(int cycle) {}
