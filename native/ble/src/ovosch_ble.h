// OvoschBle — GDExtension-класс, реализующий контракт BleBridge (src/devices/ble/ble_bridge.gd).
// Имена методов и сигналов, порядок и типы аргументов — 1:1 с контрактом; NativeBleBridge
// вызывает их через Object.call и пробрасывает сигналы.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <memory>

#include "ble_backend.h"

namespace ovosch {

class OvoschBle : public godot::RefCounted, private BleListener {
	GDCLASS(OvoschBle, godot::RefCounted)

public:
	OvoschBle();
	~OvoschBle() override;

	// --- контракт BleBridge ---
	bool is_available() const;
	int get_adapter_state() const;
	void start_scan(const godot::PackedStringArray &service_uuids);
	void stop_scan();
	void connect_peripheral(const godot::String &id);
	void disconnect_peripheral(const godot::String &id);
	void discover_services(const godot::String &id);
	void subscribe(const godot::String &id, const godot::String &service_uuid, const godot::String &char_uuid);
	void unsubscribe(const godot::String &id, const godot::String &service_uuid, const godot::String &char_uuid);
	void write(const godot::String &id, const godot::String &service_uuid, const godot::String &char_uuid,
			const godot::PackedByteArray &bytes, bool with_response);
	void read_characteristic(const godot::String &id, const godot::String &service_uuid, const godot::String &char_uuid);

protected:
	static void _bind_methods();

private:
	// --- BleListener: события backend'а (любой поток) → сигналы в главном потоке ---
	void on_adapter_state_changed(AdapterState state) override;
	void on_device_found(const std::string &id, const std::string &name, int rssi,
			const std::vector<std::string> &service_uuids) override;
	void on_connected(const std::string &id) override;
	void on_disconnected(const std::string &id, DisconnectReason reason) override;
	void on_services_discovered(const std::string &id, const std::vector<ServiceInfo> &services) override;
	void on_notification(const std::string &id, const std::string &char_uuid, const std::vector<uint8_t> &bytes) override;
	void on_characteristic_read(const std::string &id, const std::string &char_uuid, const std::vector<uint8_t> &bytes) override;
	void on_write_done(const std::string &id, const std::string &char_uuid, bool ok) override;
	void on_error(const std::string &id, ErrorCode code, const std::string &message) override;

	// Испустить сигнал в главном потоке (call_deferred), откуда бы ни пришло событие.
	void emit_deferred(const godot::StringName &signal, const godot::Array &args);

	static godot::String to_gd(const std::string &s);
	static std::string to_std(const godot::String &s);
	static godot::PackedByteArray to_gd(const std::vector<uint8_t> &bytes);
	static std::vector<uint8_t> to_std(const godot::PackedByteArray &bytes);
	static std::vector<std::string> to_std(const godot::PackedStringArray &strings);

	std::unique_ptr<BleBackend> backend_;
};

} // namespace ovosch
