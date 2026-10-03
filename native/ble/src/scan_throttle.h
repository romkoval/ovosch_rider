// Прореживание событий сканирования (REQ-DEV-01, REQ-DEV-06 крит. 2).
//
// Платформенные backend'ы сканируют с дубликатами рекламы (CoreBluetooth:
// CBCentralManagerScanOptionAllowDuplicatesKey = YES), иначе устройство сообщается один
// раз за сеанс, и GDScript-сканер через 10 с считает его пропавшим. Дубликаты идут
// десятками в секунду — ScanThrottle пропускает одно событие на устройство не чаще
// раза в interval_ms, но сразу — первое событие устройства в сеансе и событие,
// принёсшее новое имя или новый список сервисов (имя часто приходит отдельным
// scan response). Чистый C++ без godot-cpp; потокобезопасность — забота владельца.
#pragma once

#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

namespace ovosch {

class ScanThrottle {
public:
	static constexpr int64_t DEFAULT_INTERVAL_MS = 1000;

	explicit ScanThrottle(int64_t interval_ms = DEFAULT_INTERVAL_MS);

	// true — событие нужно доставить (и оно запоминается как последнее для id).
	bool should_emit(const std::string &id, const std::string &name, const std::vector<std::string> &service_uuids,
			int64_t now_ms);
	// Новый сеанс сканирования: все устройства снова «первые».
	void reset();
	size_t tracked_count() const { return entries_.size(); }

private:
	struct Entry {
		int64_t last_emit_ms = 0;
		std::string name;
		std::vector<std::string> service_uuids;
	};

	int64_t interval_ms_;
	std::unordered_map<std::string, Entry> entries_;
};

} // namespace ovosch
