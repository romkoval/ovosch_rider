#include "null_backend.h"

namespace ovosch {

void NullBackend::unavailable(const std::string &id) {
	if (listener_ != nullptr) {
		listener_->on_error(id, ErrorCode::ADAPTER_UNAVAILABLE, "ovosch_ble: no BLE backend for this platform");
	}
}

#ifndef OVOSCH_BLE_HAS_PLATFORM_BACKEND
std::unique_ptr<BleBackend> create_platform_backend() {
	return std::unique_ptr<BleBackend>(new NullBackend());
}
#endif

} // namespace ovosch
