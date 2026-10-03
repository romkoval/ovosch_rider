#include "ovosch_ble.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <chrono>

using namespace godot;

namespace ovosch {

OvoschBle::OvoschBle() :
		backend_(create_platform_backend()) {
	if (backend_) {
		backend_->set_listener(this);
	}
}

OvoschBle::~OvoschBle() {
	if (backend_) {
		backend_->set_listener(nullptr);
	}
}

void OvoschBle::_bind_methods() {
	ClassDB::bind_method(D_METHOD("is_available"), &OvoschBle::is_available);
	ClassDB::bind_method(D_METHOD("get_adapter_state"), &OvoschBle::get_adapter_state);
	ClassDB::bind_method(D_METHOD("start_scan", "service_uuids"), &OvoschBle::start_scan);
	ClassDB::bind_method(D_METHOD("stop_scan"), &OvoschBle::stop_scan);
	ClassDB::bind_method(D_METHOD("connect_peripheral", "id"), &OvoschBle::connect_peripheral);
	ClassDB::bind_method(D_METHOD("disconnect_peripheral", "id"), &OvoschBle::disconnect_peripheral);
	ClassDB::bind_method(D_METHOD("discover_services", "id"), &OvoschBle::discover_services);
	ClassDB::bind_method(D_METHOD("subscribe", "id", "service_uuid", "char_uuid"), &OvoschBle::subscribe);
	ClassDB::bind_method(D_METHOD("unsubscribe", "id", "service_uuid", "char_uuid"), &OvoschBle::unsubscribe);
	ClassDB::bind_method(D_METHOD("write", "id", "service_uuid", "char_uuid", "bytes", "with_response"), &OvoschBle::write);
	ClassDB::bind_method(D_METHOD("read_characteristic", "id", "service_uuid", "char_uuid"), &OvoschBle::read_characteristic);

	ADD_SIGNAL(MethodInfo("adapter_state_changed", PropertyInfo(Variant::INT, "state")));
	ADD_SIGNAL(MethodInfo("device_found", PropertyInfo(Variant::STRING, "id"), PropertyInfo(Variant::STRING, "name"),
			PropertyInfo(Variant::INT, "rssi"), PropertyInfo(Variant::PACKED_STRING_ARRAY, "service_uuids")));
	ADD_SIGNAL(MethodInfo("connected", PropertyInfo(Variant::STRING, "id")));
	ADD_SIGNAL(MethodInfo("disconnected", PropertyInfo(Variant::STRING, "id"), PropertyInfo(Variant::INT, "reason")));
	ADD_SIGNAL(MethodInfo("services_discovered", PropertyInfo(Variant::STRING, "id"), PropertyInfo(Variant::DICTIONARY, "services")));
	ADD_SIGNAL(MethodInfo("notification", PropertyInfo(Variant::STRING, "id"), PropertyInfo(Variant::STRING, "char_uuid"),
			PropertyInfo(Variant::PACKED_BYTE_ARRAY, "bytes")));
	ADD_SIGNAL(MethodInfo("characteristic_read", PropertyInfo(Variant::STRING, "id"), PropertyInfo(Variant::STRING, "char_uuid"),
			PropertyInfo(Variant::PACKED_BYTE_ARRAY, "bytes")));
	ADD_SIGNAL(MethodInfo("write_done", PropertyInfo(Variant::STRING, "id"), PropertyInfo(Variant::STRING, "char_uuid"),
			PropertyInfo(Variant::BOOL, "ok")));
	ADD_SIGNAL(MethodInfo("error", PropertyInfo(Variant::STRING, "id"), PropertyInfo(Variant::INT, "code"),
			PropertyInfo(Variant::STRING, "message")));
}

// ---------------------------------------------------------------------------
// Контракт
// ---------------------------------------------------------------------------

bool OvoschBle::is_available() const {
	return backend_ && backend_->is_available();
}

int OvoschBle::get_adapter_state() const {
	return backend_ ? static_cast<int>(backend_->get_adapter_state()) : static_cast<int>(AdapterState::UNSUPPORTED);
}

void OvoschBle::start_scan(const PackedStringArray &service_uuids) {
	{
		// Новый сеанс: первое событие каждого устройства доставляется сразу.
		std::lock_guard<std::mutex> lock(scan_throttle_mutex_);
		scan_throttle_.reset();
	}
	if (backend_) {
		backend_->start_scan(to_std(service_uuids));
	}
}

void OvoschBle::stop_scan() {
	if (backend_) {
		backend_->stop_scan();
	}
}

void OvoschBle::connect_peripheral(const String &id) {
	if (backend_) {
		backend_->connect_peripheral(to_std(id));
	}
}

void OvoschBle::disconnect_peripheral(const String &id) {
	if (backend_) {
		backend_->disconnect_peripheral(to_std(id));
	}
}

void OvoschBle::discover_services(const String &id) {
	if (backend_) {
		backend_->discover_services(to_std(id));
	}
}

void OvoschBle::subscribe(const String &id, const String &service_uuid, const String &char_uuid) {
	if (backend_) {
		backend_->subscribe(to_std(id), to_std(service_uuid), to_std(char_uuid));
	}
}

void OvoschBle::unsubscribe(const String &id, const String &service_uuid, const String &char_uuid) {
	if (backend_) {
		backend_->unsubscribe(to_std(id), to_std(service_uuid), to_std(char_uuid));
	}
}

void OvoschBle::write(const String &id, const String &service_uuid, const String &char_uuid,
		const PackedByteArray &bytes, bool with_response) {
	if (backend_) {
		backend_->write(to_std(id), to_std(service_uuid), to_std(char_uuid), to_std(bytes), with_response);
	}
}

void OvoschBle::read_characteristic(const String &id, const String &service_uuid, const String &char_uuid) {
	if (backend_) {
		backend_->read_characteristic(to_std(id), to_std(service_uuid), to_std(char_uuid));
	}
}

// ---------------------------------------------------------------------------
// События backend'а → сигналы (всегда через главный поток)
// ---------------------------------------------------------------------------

void OvoschBle::emit_deferred(const StringName &signal, const Array &args) {
	// emit_signal(signal, args...) в главном потоке: аргументы привязываются через bindv,
	// затем вызов откладывается до следующей итерации главного цикла.
	Array call_args;
	call_args.push_back(signal);
	for (int i = 0; i < args.size(); ++i) {
		call_args.push_back(args[i]);
	}
	Callable(this, "emit_signal").bindv(call_args).call_deferred();
}

void OvoschBle::on_adapter_state_changed(AdapterState state) {
	Array a;
	a.push_back(static_cast<int>(state));
	emit_deferred("adapter_state_changed", a);
}

void OvoschBle::on_device_found(const std::string &id, const std::string &name, int rssi,
		const std::vector<std::string> &service_uuids) {
	{
		// Не чаще раза в секунду на устройство (кроме нового имени/сервисов).
		const int64_t now_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
				std::chrono::steady_clock::now().time_since_epoch())
									   .count();
		std::lock_guard<std::mutex> lock(scan_throttle_mutex_);
		if (!scan_throttle_.should_emit(id, name, service_uuids, now_ms)) {
			return;
		}
	}
	PackedStringArray uuids;
	for (const auto &u : service_uuids) {
		uuids.push_back(to_gd(u));
	}
	Array a;
	a.push_back(to_gd(id));
	a.push_back(to_gd(name));
	a.push_back(rssi);
	a.push_back(uuids);
	emit_deferred("device_found", a);
}

void OvoschBle::on_connected(const std::string &id) {
	Array a;
	a.push_back(to_gd(id));
	emit_deferred("connected", a);
}

void OvoschBle::on_disconnected(const std::string &id, DisconnectReason reason) {
	Array a;
	a.push_back(to_gd(id));
	a.push_back(static_cast<int>(reason));
	emit_deferred("disconnected", a);
}

void OvoschBle::on_services_discovered(const std::string &id, const std::vector<ServiceInfo> &services) {
	Dictionary dict;
	for (const auto &s : services) {
		PackedStringArray chars;
		for (const auto &c : s.characteristic_uuids) {
			chars.push_back(to_gd(c));
		}
		dict[to_gd(s.uuid)] = chars;
	}
	Array a;
	a.push_back(to_gd(id));
	a.push_back(dict);
	emit_deferred("services_discovered", a);
}

void OvoschBle::on_notification(const std::string &id, const std::string &char_uuid, const std::vector<uint8_t> &bytes) {
	Array a;
	a.push_back(to_gd(id));
	a.push_back(to_gd(char_uuid));
	a.push_back(to_gd(bytes));
	emit_deferred("notification", a);
}

void OvoschBle::on_characteristic_read(const std::string &id, const std::string &char_uuid, const std::vector<uint8_t> &bytes) {
	Array a;
	a.push_back(to_gd(id));
	a.push_back(to_gd(char_uuid));
	a.push_back(to_gd(bytes));
	emit_deferred("characteristic_read", a);
}

void OvoschBle::on_write_done(const std::string &id, const std::string &char_uuid, bool ok) {
	Array a;
	a.push_back(to_gd(id));
	a.push_back(to_gd(char_uuid));
	a.push_back(ok);
	emit_deferred("write_done", a);
}

void OvoschBle::on_error(const std::string &id, ErrorCode code, const std::string &message) {
	Array a;
	a.push_back(to_gd(id));
	a.push_back(static_cast<int>(code));
	a.push_back(to_gd(message));
	emit_deferred("error", a);
}

// ---------------------------------------------------------------------------
// Конвертация
// ---------------------------------------------------------------------------

String OvoschBle::to_gd(const std::string &s) {
	return String::utf8(s.c_str(), static_cast<int>(s.size()));
}

std::string OvoschBle::to_std(const String &s) {
	CharString utf8 = s.utf8();
	return std::string(utf8.get_data(), static_cast<size_t>(utf8.length()));
}

PackedByteArray OvoschBle::to_gd(const std::vector<uint8_t> &bytes) {
	PackedByteArray out;
	out.resize(static_cast<int64_t>(bytes.size()));
	if (!bytes.empty()) {
		memcpy(out.ptrw(), bytes.data(), bytes.size());
	}
	return out;
}

std::vector<uint8_t> OvoschBle::to_std(const PackedByteArray &bytes) {
	const uint8_t *ptr = bytes.ptr();
	return std::vector<uint8_t>(ptr, ptr + bytes.size());
}

std::vector<std::string> OvoschBle::to_std(const PackedStringArray &strings) {
	std::vector<std::string> out;
	out.reserve(static_cast<size_t>(strings.size()));
	for (int i = 0; i < strings.size(); ++i) {
		out.push_back(to_std(strings[i]));
	}
	return out;
}

} // namespace ovosch
