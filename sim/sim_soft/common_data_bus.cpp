#include "common_data_bus.h"
#include "config.h"
#include <iomanip>

CommonDataBus::CommonDataBus() {
    pending_.reserve(RS_INT_SIZE + RS_FP_SIZE);
}

void CommonDataBus::broadcast(int rob_tag, uint32_t value) {
    pending_.push_back({rob_tag, value});
}

bool CommonDataBus::has_results() const {
    return !pending_.empty();
}

const std::vector<CDBResult>& CommonDataBus::results() const {
    return pending_;
}

void CommonDataBus::flush() {
    pending_.clear();
}

void CommonDataBus::dump(std::ostream& os, int cycle) const {
    os << "[CDB  cycle=" << std::setw(4) << cycle << "]";
    if (pending_.empty()) {
        os << " idle\n";
        return;
    }
    for (const auto& r : pending_)
        os << " ROB" << r.rob_tag << "=0x"
           << std::hex << std::setw(8) << std::setfill('0')
           << r.value << std::dec << std::setfill(' ');
    os << "\n";
}

void CommonDataBus::open_log(const std::string& path) {
    log_.open(path, std::ios::out | std::ios::trunc);
}

void CommonDataBus::log_cycle(int cycle) {
    if (log_.is_open())
        dump(log_, cycle);
}
