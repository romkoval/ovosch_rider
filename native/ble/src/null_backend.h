// Заглушка backend'а: платформенной реализации нет, is_available() == false.
#pragma once

#include "ble_backend.h"

namespace ovosch {

class NullBackend final : public BleBackend {
public:
	void set_listener(BleListener *listener) override { listener_ = listener; }
	bool is_available() const override { return false; }
	AdapterState get_adapter_state() const override { return AdapterState::UNSUPPORTED; }
	void start_scan(const std::vector<std::string> &) override { unavailable(""); }
	void stop_scan() override {}
	void connect_peripheral(const std::string &id) override { unavailable(id); }
	void disconnect_peripheral(const std::string &) override {}
	void discover_services(const std::string &id) override { unavailable(id); }
	void subscribe(const std::string &id, const std::string &, const std::string &) override { unavailable(id); }
	void unsubscribe(const std::string &, const std::string &, const std::string &) override {}
	void write(const std::string &id, const std::string &, const std::string &, const std::vector<uint8_t> &, bool) override {
		unavailable(id);
	}
	void read_characteristic(const std::string &id, const std::string &, const std::string &) override { unavailable(id); }

private:
	void unavailable(const std::string &id);
	BleListener *listener_ = nullptr;
};

} // namespace ovosch
