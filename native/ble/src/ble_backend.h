// Платформенный backend BLE — чистый C++ интерфейс без godot-cpp.
// Реализации: null_backend.cpp (заглушка, везде), platform/apple (CoreBluetooth, T-022).
#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace ovosch {

// Значения совпадают с enum'ами BleBridge (src/devices/ble/ble_bridge.gd).
enum class AdapterState : int { UNKNOWN = 0, UNSUPPORTED = 1, UNAUTHORIZED = 2, POWERED_OFF = 3, POWERED_ON = 4 };
enum class DisconnectReason : int { REQUESTED = 0, LINK_LOSS = 1, TIMEOUT = 2, ERROR = 3 };
enum class ErrorCode : int {
	NONE = 0,
	ADAPTER_UNAVAILABLE = 1,
	DEVICE_NOT_FOUND = 2,
	CONNECTION_FAILED = 3,
	SERVICE_NOT_FOUND = 4,
	CHARACTERISTIC_NOT_FOUND = 5,
	WRITE_FAILED = 6,
	READ_FAILED = 7,
	SUBSCRIBE_FAILED = 8,
	NOT_CONNECTED = 9,
	TIMEOUT = 10,
};

struct ServiceInfo {
	std::string uuid;
	std::vector<std::string> characteristic_uuids;
};

// Получатель событий backend'а. Методы могут вызываться из любого потока —
// реализация (OvoschBle) обязана переправить их в главный поток.
class BleListener {
public:
	virtual ~BleListener() = default;
	virtual void on_adapter_state_changed(AdapterState state) = 0;
	virtual void on_device_found(const std::string &id, const std::string &name, int rssi,
			const std::vector<std::string> &service_uuids) = 0;
	virtual void on_connected(const std::string &id) = 0;
	virtual void on_disconnected(const std::string &id, DisconnectReason reason) = 0;
	virtual void on_services_discovered(const std::string &id, const std::vector<ServiceInfo> &services) = 0;
	virtual void on_notification(const std::string &id, const std::string &char_uuid, const std::vector<uint8_t> &bytes) = 0;
	virtual void on_characteristic_read(const std::string &id, const std::string &char_uuid, const std::vector<uint8_t> &bytes) = 0;
	virtual void on_write_done(const std::string &id, const std::string &char_uuid, bool ok) = 0;
	virtual void on_error(const std::string &id, ErrorCode code, const std::string &message) = 0;
};

// Операции контракта BleBridge. Все асинхронные: результат приходит в BleListener.
class BleBackend {
public:
	virtual ~BleBackend() = default;
	virtual void set_listener(BleListener *listener) = 0;
	virtual bool is_available() const = 0;
	virtual AdapterState get_adapter_state() const = 0;
	virtual void start_scan(const std::vector<std::string> &service_uuids) = 0;
	virtual void stop_scan() = 0;
	virtual void connect_peripheral(const std::string &id) = 0;
	virtual void disconnect_peripheral(const std::string &id) = 0;
	virtual void discover_services(const std::string &id) = 0;
	virtual void subscribe(const std::string &id, const std::string &service_uuid, const std::string &char_uuid) = 0;
	virtual void unsubscribe(const std::string &id, const std::string &service_uuid, const std::string &char_uuid) = 0;
	virtual void write(const std::string &id, const std::string &service_uuid, const std::string &char_uuid,
			const std::vector<uint8_t> &bytes, bool with_response) = 0;
	virtual void read_characteristic(const std::string &id, const std::string &service_uuid, const std::string &char_uuid) = 0;
};

// Фабрика backend'а текущей платформы. Определена в null_backend.cpp, если не задан
// OVOSCH_BLE_HAS_PLATFORM_BACKEND, иначе — в платформенном модуле.
std::unique_ptr<BleBackend> create_platform_backend();

} // namespace ovosch
