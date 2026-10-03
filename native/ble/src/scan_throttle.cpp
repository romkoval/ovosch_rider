#include "scan_throttle.h"

namespace ovosch {

ScanThrottle::ScanThrottle(int64_t interval_ms) :
		interval_ms_(interval_ms < 0 ? 0 : interval_ms) {}

bool ScanThrottle::should_emit(const std::string &id, const std::string &name,
		const std::vector<std::string> &service_uuids, int64_t now_ms) {
	auto it = entries_.find(id);
	if (it == entries_.end()) {
		Entry entry;
		entry.last_emit_ms = now_ms;
		entry.name = name;
		entry.service_uuids = service_uuids;
		entries_.emplace(id, entry);
		return true;
	}
	Entry &entry = it->second;
	const bool new_name = !name.empty() && name != entry.name;
	const bool new_services = !service_uuids.empty() && service_uuids != entry.service_uuids;
	// now_ms < last_emit_ms (часы пошли назад) — тоже пропускаем, чтобы не залипнуть.
	const bool due = now_ms - entry.last_emit_ms >= interval_ms_ || now_ms < entry.last_emit_ms;
	if (!due && !new_name && !new_services) {
		return false;
	}
	entry.last_emit_ms = now_ms;
	if (!name.empty()) {
		entry.name = name;
	}
	if (!service_uuids.empty()) {
		entry.service_uuids = service_uuids;
	}
	return true;
}

void ScanThrottle::reset() {
	entries_.clear();
}

} // namespace ovosch
