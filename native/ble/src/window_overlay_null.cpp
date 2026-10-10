// No-op overlay helpers for platforms without a native implementation (T-177 spike).
#include "window_overlay.h"

#if !defined(OVOSCH_BLE_HAS_PLATFORM_BACKEND)

namespace ovosch {
namespace window_overlay {

bool available() {
	return false;
}

bool set_overlay(void *, bool, SavedWindowState &) {
	return false;
}

void *begin_activity(const std::string &) {
	return nullptr;
}

void end_activity(void *) {
}

} // namespace window_overlay
} // namespace ovosch

#endif
