class_name BleDebugModel
extends RefCounted
## Модель экрана «BLE-отладка» (T-165; инструмент для REQ-DEV-01, REQ-DEV-02, REQ-DEV-03,
## REQ-DEV-07): что устройство реально рекламирует и отдаёт — без интерпретации приложения.
## Без UI, работает поверх контракта `BleBridge` (в тестах — заглушка моста). Лежит в слое
## устройств: путь чтения характеристик — только в `src/devices/` (REQ-NFR-06 крит. 5); экран —
## `src/ui/ble_debug/`.
##
## - Сканирование без фильтра (`start_scan([])` — все устройства) или с фильтром приложения
##   (`BleUuids.SCAN_SERVICES`, `use_app_filter`). Список: имя, полный id, RSSI, UUID последнего
##   пакета (как пришли и нормализованные), объединение UUID за сеанс сканирования, тип по
##   `BleScanner.kind_from_services`.
## - Подключение одного устройства; после `connected` — `discover_services`, дерево
##   «сервис → характеристики» с известными именами (FTMS, CPS, CSC, HRS, Battery, Device
##   Information, Tacx FE-C over BLE), неизвестные — как есть.
## - Характеристика: чтение, подписка, последнее значение (hex, время, источник) и
##   расшифровка, где есть кодек проекта или разбор ниже (ANT FE-C, Device Information — текст);
##   запись hex и пресеты (FTMS Control Point, FE-C Target Power).
## - Журнал всех событий моста с меткой времени (`device_found` — не чаще раза в секунду на
##   устройство, кроме первого пакета и пакета с новыми UUID). Каждое событие уходит и в
##   `DiagLog` (категория `ble_debug`), id устройства там — метка (первые символы SHA-256),
##   как у датчиков (T-154). В журнале экрана id полный: экран локальный.
##
## Сигналы моста подключены связанными методами; `dispose()` отключает их (без него —
## цикл мост → сигнал → модель).

signal devices_changed()
signal link_changed()
signal tree_changed()
signal value_changed(char_uuid: String)
signal log_added(entry: Dictionary)

## Состояние связи с выбранным устройством.
enum LinkState { IDLE, CONNECTING, DISCOVERING, READY }

const DIAG_CATEGORY: String = "ble_debug"
const DEVICE_LOG_INTERVAL_SEC: float = 1.0
const MAX_LOG_ENTRIES: int = 5000
const DEVICE_TAG_LENGTH: int = 8

## Tacx FE-C over BLE: сервис, нотификации (FEC2) и запись (FEC3) ANT-сообщений.
const FEC_SERVICE: String = "6E40FEC1-B5A3-F393-E0A9-E50E24DCCA9E"
const FEC_NOTIFY: String = "6E40FEC2-B5A3-F393-E0A9-E50E24DCCA9E"
const FEC_WRITE: String = "6E40FEC3-B5A3-F393-E0A9-E50E24DCCA9E"
const DEVICE_INFO_SERVICE: String = "180A"
## Строковые характеристики Device Information: производитель, модель, серийный номер,
## аппаратная, программная ревизии, прошивка.
const DEVICE_INFO_TEXT_CHARS: Array[String] = ["2A29", "2A24", "2A25", "2A27", "2A26", "2A28", "2A00"]

## ANT: синхробайт, длина данных сообщения, Broadcast / Acknowledged Data, канал FE-C over BLE.
const ANT_SYNC: int = 0xA4
const ANT_DATA_LENGTH: int = 0x09
const ANT_BROADCAST_DATA: int = 0x4E
const ANT_ACKNOWLEDGED_DATA: int = 0x4F
const ANT_FEC_CHANNEL: int = 0x05
## Страницы ANT FE-C.
const FEC_PAGE_GENERAL_FE: int = 0x10
const FEC_PAGE_GENERAL_SETTINGS: int = 0x11
const FEC_PAGE_TRAINER_DATA: int = 0x19
const FEC_PAGE_BASIC_RESISTANCE: int = 0x30
const FEC_PAGE_TARGET_POWER: int = 0x31
const FEC_PAGE_COMMAND_STATUS: int = 0x47
const FEC_PAGE_MANUFACTURER: int = 0x50
const FEC_PAGE_PRODUCT: int = 0x51

## Пресеты записи: id → цель. Байты — `preset_bytes(id)`.
const PRESET_FTMS_REQUEST_CONTROL: String = "ftms_request_control"
const PRESET_FTMS_START: String = "ftms_start"
const PRESET_FTMS_TARGET_POWER_150: String = "ftms_target_power_150"
const PRESET_FTMS_RESET: String = "ftms_reset"
const PRESET_FEC_TARGET_POWER_150: String = "fec_target_power_150"
const PRESET_IDS: Array[String] = [
	PRESET_FTMS_REQUEST_CONTROL, PRESET_FTMS_START, PRESET_FTMS_TARGET_POWER_150, PRESET_FTMS_RESET,
	PRESET_FEC_TARGET_POWER_150,
]
const PRESET_POWER_W: int = 150

const SERVICE_NAMES: Dictionary = {
	"1826": "Fitness Machine (FTMS)",
	"1818": "Cycling Power",
	"1816": "Cycling Speed and Cadence",
	"180D": "Heart Rate",
	"180F": "Battery",
	"180A": "Device Information",
	"1800": "Generic Access",
	"1801": "Generic Attribute",
	"FE59": "Nordic Semiconductor (DFU)",
	"FE51": "SRAM",
	FEC_SERVICE: "Tacx FE-C over BLE",
}

const CHAR_NAMES: Dictionary = {
	"2AD2": "Indoor Bike Data",
	"2AD9": "Fitness Machine Control Point",
	"2ADA": "Fitness Machine Status",
	"2ACC": "Fitness Machine Feature",
	"2AD8": "Supported Power Range",
	"2AD6": "Supported Resistance Level Range",
	"2AD5": "Supported Inclination Range",
	"2AD3": "Training Status",
	"2A63": "Cycling Power Measurement",
	"2A65": "Cycling Power Feature",
	"2A66": "Cycling Power Control Point",
	"2A5D": "Sensor Location",
	"2A5B": "CSC Measurement",
	"2A5C": "CSC Feature",
	"2A55": "SC Control Point",
	"2A37": "Heart Rate Measurement",
	"2A38": "Body Sensor Location",
	"2A19": "Battery Level",
	"2A29": "Manufacturer Name String",
	"2A24": "Model Number String",
	"2A25": "Serial Number String",
	"2A27": "Hardware Revision String",
	"2A26": "Firmware Revision String",
	"2A28": "Software Revision String",
	"2A23": "System ID",
	"2A50": "PnP ID",
	"2A00": "Device Name",
	"2A01": "Appearance",
	FEC_NOTIFY: "FE-C notify (FEC2)",
	FEC_WRITE: "FE-C write (FEC3)",
}

var bridge: BleBridge
## Фильтр приложения (`BleUuids.SCAN_SERVICES`) вместо скана всех устройств.
var use_app_filter: bool = false
var scanning: bool = false
## id → запись устройства: `{id, name, rssi, raw, norm, union, kind, packets, last_seen,
## last_logged}`.
var devices: Dictionary = {}
## Устройство, с которым работает экран ("" — нет).
var link_id: String = ""
var link_state: int = LinkState.IDLE
## Нормализованный сервис → PackedStringArray нормализованных характеристик (порядок моста).
var services: Dictionary = {}
## Нормализованная характеристика → `{bytes, hex, time, source, decoded}`.
var values: Dictionary = {}
## Ключи "SERVICE/CHAR" подписок выбранного устройства.
var subscriptions: Dictionary = {}
## Часы: unix-время в секундах (float). Тесты подставляют свои.
var clock: Callable = Callable()
## Смещение местного времени для меток журнала, с.
var utc_offset_sec: int = 0

var _log: Array[Dictionary] = []


func _init(ble_bridge: BleBridge) -> void:
	bridge = ble_bridge
	clock = Callable(Time, "get_unix_time_from_system")
	utc_offset_sec = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	if bridge == null:
		return
	bridge.adapter_state_changed.connect(_on_adapter_state_changed)
	bridge.device_found.connect(_on_device_found)
	bridge.connected.connect(_on_connected)
	bridge.disconnected.connect(_on_disconnected)
	bridge.services_discovered.connect(_on_services_discovered)
	bridge.notification.connect(_on_notification)
	bridge.characteristic_read.connect(_on_characteristic_read)
	bridge.write_done.connect(_on_write_done)
	bridge.error.connect(_on_error)


## Отключиться от моста: остановить скан, отключить своё устройство (если `disconnect_link`).
func dispose(disconnect_link: bool = true) -> void:
	if bridge == null:
		return
	if scanning:
		stop_scan()
	if disconnect_link and not link_id.is_empty():
		disconnect_device()
	for pair: Array in [
			[bridge.adapter_state_changed, _on_adapter_state_changed], [bridge.device_found, _on_device_found],
			[bridge.connected, _on_connected], [bridge.disconnected, _on_disconnected],
			[bridge.services_discovered, _on_services_discovered], [bridge.notification, _on_notification],
			[bridge.characteristic_read, _on_characteristic_read], [bridge.write_done, _on_write_done],
			[bridge.error, _on_error]]:
		var sig: Signal = pair[0]
		var cb: Callable = pair[1]
		if sig.is_connected(cb):
			sig.disconnect(cb)
	bridge = null


func is_available() -> bool:
	return bridge != null and bridge.is_available()


func adapter_state() -> int:
	return bridge.get_adapter_state() if bridge != null else BleBridge.AdapterState.UNSUPPORTED


# ---------------------------------------------------------------------------
# Сканирование
# ---------------------------------------------------------------------------

## Начать сеанс сканирования: список и объединение UUID сбрасываются. false — моста нет.
func start_scan() -> bool:
	if not is_available():
		_add_log("scan_unavailable", "bridge unavailable, adapter %s" % BleBridge.adapter_state_name(adapter_state()), {})
		return false
	var filter: PackedStringArray = BleUuids.SCAN_SERVICES.duplicate() if use_app_filter else PackedStringArray()
	devices.clear()
	scanning = true
	bridge.start_scan(filter)
	_add_log("scan_started", "filter %s" % (_join(filter) if not filter.is_empty() else "none (all devices)"),
			{"filter": Array(filter)})
	devices_changed.emit()
	return true


func stop_scan() -> void:
	if not scanning:
		return
	scanning = false
	if bridge != null:
		bridge.stop_scan()
	_add_log("scan_stopped", "", {})


## Переключить фильтр приложения; идущий скан перезапускается с новым фильтром.
func set_use_app_filter(enabled: bool) -> void:
	if enabled == use_app_filter:
		return
	use_app_filter = enabled
	if scanning:
		scanning = false
		start_scan()


## id найденных устройств: по убыванию RSSI, затем по имени.
func device_ids() -> Array[String]:
	var list: Array = devices.values()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["rssi"]) != int(b["rssi"]):
			return int(a["rssi"]) > int(b["rssi"])
		return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
	var out: Array[String] = []
	for d: Dictionary in list:
		out.append(str(d["id"]))
	return out


## Запись устройства (копия) или {}.
func device(id: String) -> Dictionary:
	return (devices.get(id, {}) as Dictionary).duplicate()


# ---------------------------------------------------------------------------
# Подключение
# ---------------------------------------------------------------------------

## Подключить устройство; текущее (другое) отключается. Сервисы ищутся после `connected`.
func connect_device(id: String) -> void:
	if bridge == null or id.is_empty():
		return
	if not link_id.is_empty() and link_id != id:
		disconnect_device()
	link_id = id
	_reset_link_data()
	_set_link_state(LinkState.CONNECTING)
	_add_log("connect_requested", "%s %s" % [_name_of(id), id], _dev(id))
	bridge.connect_peripheral(id)


func disconnect_device() -> void:
	if bridge == null or link_id.is_empty():
		return
	var id := link_id
	_add_log("disconnect_requested", "%s %s" % [_name_of(id), id], _dev(id))
	bridge.disconnect_peripheral(id)
	link_id = ""
	subscriptions.clear()
	_set_link_state(LinkState.IDLE)


func is_ready() -> bool:
	return link_state == LinkState.READY and not link_id.is_empty()


## Дерево сервисов: `[{uuid, name, chars: [{uuid, name, service}]}]` в порядке моста.
func service_tree() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: String in services:
		var chars: Array[Dictionary] = []
		for c: String in services[s]:
			chars.append({"uuid": c, "name": char_name(c), "service": s})
		out.append({"uuid": s, "name": service_name(s), "chars": chars})
	return out


func has_service(service_uuid: String) -> bool:
	return services.has(BleUuids.normalize(service_uuid))


## Сервис, в котором есть характеристика ("" — нет).
func service_of(char_uuid: String) -> String:
	var c := BleUuids.normalize(char_uuid)
	for s: String in services:
		if (services[s] as PackedStringArray).has(c):
			return s
	return ""


# ---------------------------------------------------------------------------
# Характеристики
# ---------------------------------------------------------------------------

func read(service_uuid: String, char_uuid: String) -> bool:
	if not _require_ready("read"):
		return false
	var s := BleUuids.normalize(service_uuid)
	var c := BleUuids.normalize(char_uuid)
	_add_log("read_requested", "%s/%s %s" % [_short(s), _short(c), char_name(c)], _dev(link_id, {"service": s, "char": c}))
	bridge.read_characteristic(link_id, s, c)
	return true


## Прочитать все строковые характеристики Device Information, которые есть у устройства.
func read_device_info() -> int:
	if not _require_ready("read_device_info"):
		return 0
	var chars: PackedStringArray = services.get(DEVICE_INFO_SERVICE, PackedStringArray())
	var n := 0
	for c in chars:
		if DEVICE_INFO_TEXT_CHARS.has(c) or c == "2A23" or c == "2A50":
			read(DEVICE_INFO_SERVICE, c)
			n += 1
	if n == 0:
		_add_log("note", "no Device Information (180A) characteristics to read", _dev(link_id))
	return n


func is_subscribed(service_uuid: String, char_uuid: String) -> bool:
	return subscriptions.has(_key(service_uuid, char_uuid))


func set_subscribed(service_uuid: String, char_uuid: String, enabled: bool) -> bool:
	if not _require_ready("subscribe" if enabled else "unsubscribe"):
		return false
	var s := BleUuids.normalize(service_uuid)
	var c := BleUuids.normalize(char_uuid)
	var data := _dev(link_id, {"service": s, "char": c})
	if enabled:
		subscriptions[_key(s, c)] = true
		_add_log("subscribe", "%s/%s %s" % [_short(s), _short(c), char_name(c)], data)
		bridge.subscribe(link_id, s, c)
	else:
		subscriptions.erase(_key(s, c))
		_add_log("unsubscribe", "%s/%s %s" % [_short(s), _short(c), char_name(c)], data)
		bridge.unsubscribe(link_id, s, c)
	tree_changed.emit()
	return true


## Записать hex-строку ("05 96 00", "059600", "0x05,0x96"). false — не подключено или hex неверен.
func write_hex(service_uuid: String, char_uuid: String, hex: String, with_response: bool = true) -> bool:
	var parsed := parse_hex(hex)
	if not parsed["ok"]:
		_add_log("write_rejected", "invalid hex '%s'" % hex, {"reason": "invalid_hex"})
		return false
	return write_bytes(service_uuid, char_uuid, parsed["bytes"], with_response)


func write_bytes(service_uuid: String, char_uuid: String, bytes: PackedByteArray, with_response: bool = true) -> bool:
	if not _require_ready("write"):
		return false
	var s := BleUuids.normalize(service_uuid)
	var c := BleUuids.normalize(char_uuid)
	var hex := BleBytes.to_hex(bytes)
	var decoded := describe_write(c, bytes)
	_add_log("write", "%s/%s %s [%s]%s%s" % [_short(s), _short(c), char_name(c), hex,
			" with response" if with_response else " without response", (" = " + decoded) if not decoded.is_empty() else ""],
			_dev(link_id, {"service": s, "char": c, "hex": hex, "with_response": with_response}))
	bridge.write(link_id, s, c, bytes, with_response)
	return true


## Записать пресет. FTMS — в Control Point `1826/2AD9` с ответом; FE-C — в `FEC3`
## (`with_response` — по выбору на экране).
func write_preset(preset_id: String, with_response: bool = true) -> bool:
	var target := preset_target(preset_id)
	if target.is_empty():
		_add_log("write_rejected", "unknown preset %s" % preset_id, {"reason": "unknown_preset"})
		return false
	if is_ready() and not has_service(target["service"]):
		_add_log("note", "service %s not discovered on this device; writing anyway" % _short(target["service"]), _dev(link_id))
	var ftms := str(target["service"]) == BleUuids.FTMS_SERVICE
	return write_bytes(target["service"], target["char"], preset_bytes(preset_id), true if ftms else with_response)


## `{service, char}` пресета или {}.
static func preset_target(preset_id: String) -> Dictionary:
	if preset_id == PRESET_FEC_TARGET_POWER_150:
		return {"service": FEC_SERVICE, "char": FEC_WRITE}
	if PRESET_IDS.has(preset_id):
		return {"service": BleUuids.FTMS_SERVICE, "char": BleUuids.FTMS_CONTROL_POINT}
	return {}


static func preset_bytes(preset_id: String) -> PackedByteArray:
	match preset_id:
		PRESET_FTMS_REQUEST_CONTROL:
			return FtmsCodec.encode_request_control()
		PRESET_FTMS_START:
			return FtmsCodec.encode_start()
		PRESET_FTMS_TARGET_POWER_150:
			return FtmsCodec.encode_set_target_power(PRESET_POWER_W)
		PRESET_FTMS_RESET:
			return FtmsCodec.encode_reset()
		PRESET_FEC_TARGET_POWER_150:
			return fec_target_power_message(PRESET_POWER_W)
	return PackedByteArray()


## Последнее значение характеристики (копия) или {}.
func value_of(char_uuid: String) -> Dictionary:
	return (values.get(BleUuids.normalize(char_uuid), {}) as Dictionary).duplicate()


# ---------------------------------------------------------------------------
# Журнал
# ---------------------------------------------------------------------------

func log_entries() -> Array[Dictionary]:
	return _log.duplicate()


func log_size() -> int:
	return _log.size()


func log_lines(last: int = -1) -> PackedStringArray:
	var out := PackedStringArray()
	var from := 0 if last < 0 else maxi(_log.size() - last, 0)
	for i in range(from, _log.size()):
		out.append(format_entry(_log[i]))
	return out


## Журнал целиком — для буфера обмена.
func log_text() -> String:
	return "\n".join(log_lines())


func clear_log() -> void:
	_log.clear()


## Записи журнала с событием `event`.
func entries_of(event: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _log:
		if e["event"] == event:
			out.append(e)
	return out


## Свободная заметка в журнал (например, предупреждение экрана).
func note(text: String) -> void:
	_add_log("note", text, {"text": text})


static func format_entry(entry: Dictionary) -> String:
	var text: String = entry["text"]
	return "%s %s%s" % [entry["time"], entry["event"], (" " + text) if not text.is_empty() else ""]


# ---------------------------------------------------------------------------
# Имена и расшифровка
# ---------------------------------------------------------------------------

static func service_name(uuid: String) -> String:
	return str(SERVICE_NAMES.get(BleUuids.normalize(uuid), ""))


static func char_name(uuid: String) -> String:
	return str(CHAR_NAMES.get(BleUuids.normalize(uuid), ""))


## Расшифровка значения характеристики ("" — разбора нет).
static func decode(char_uuid: String, bytes: PackedByteArray) -> String:
	var c := BleUuids.normalize(char_uuid)
	if DEVICE_INFO_TEXT_CHARS.has(c):
		return "\"%s\"" % bytes.get_string_from_utf8()
	match c:
		BleUuids.INDOOR_BIKE_DATA:
			return _decode_indoor_bike_data(bytes)
		BleUuids.CYCLING_POWER_MEASUREMENT:
			return _decode_cps(bytes)
		BleUuids.CSC_MEASUREMENT:
			return _decode_csc(bytes)
		BleUuids.HEART_RATE_MEASUREMENT:
			return _decode_hr(bytes)
		BleUuids.BATTERY_LEVEL:
			var b := BatteryCodec.decode_level(bytes)
			return "battery %d %%" % int(b["level_pct"]) if b["ok"] else "battery: invalid"
		BleUuids.FTMS_CONTROL_POINT:
			var r := FtmsCodec.decode_control_point_response(bytes)
			if r["ok"]:
				return "response to %s: %s" % [FtmsCodec.opcode_name(r["request_opcode"]), FtmsCodec.result_name(r["result"])]
			return ""
		BleUuids.FTMS_STATUS:
			var st := FtmsCodec.decode_machine_status(bytes)
			if not st["ok"]:
				return ""
			return str(st["name"]) + ((" %s" % str(st["value"])) if st.has("value") else "")
		BleUuids.FITNESS_MACHINE_FEATURE:
			var f := FtmsCodec.decode_fitness_machine_feature(bytes)
			if not f["ok"]:
				return ""
			return "power %s, resistance %s, inclination %s, simulation %s" % [f["power_supported"],
					f["resistance_supported"], f["inclination_supported"], f["simulation_supported"]]
		BleUuids.SUPPORTED_RESISTANCE_RANGE:
			var rr := FtmsCodec.decode_resistance_range(bytes)
			return "%.1f..%.1f step %.1f" % [rr["min_level"], rr["max_level"], rr["increment"]] if rr["ok"] else ""
		BleUuids.SUPPORTED_INCLINATION_RANGE:
			var ir := FtmsCodec.decode_supported_inclination_range(bytes)
			return "%.1f..%.1f %% step %.1f" % [ir["min_pct"], ir["max_pct"], ir["increment_pct"]] if ir["ok"] else ""
		BleUuids.SUPPORTED_POWER_RANGE:
			if bytes.size() < 6:
				return ""
			return "%d..%d W step %d" % [BleBytes.s16(bytes, 0), BleBytes.s16(bytes, 2), BleBytes.u16(bytes, 4)]
		FEC_NOTIFY, FEC_WRITE:
			return decode_fec(bytes)
	return ""


## Расшифровка записываемых байт (FTMS Control Point, FE-C) — для журнала.
static func describe_write(char_uuid: String, bytes: PackedByteArray) -> String:
	var c := BleUuids.normalize(char_uuid)
	if c == BleUuids.FTMS_CONTROL_POINT and not bytes.is_empty():
		var name := FtmsCodec.opcode_name(bytes[0])
		if bytes[0] == FtmsCodec.OP_SET_TARGET_POWER and bytes.size() >= 3:
			return "%s %d W" % [name, BleBytes.s16(bytes, 1)]
		return name
	if c == FEC_WRITE:
		return decode_fec(bytes)
	return ""


# ---------------------------------------------------------------------------
# ANT FE-C over BLE
# ---------------------------------------------------------------------------

## ANT-сообщение FE-C для FEC3: `A4 09 <msg_id> 05 <8 байт страницы> <XOR всех предыдущих>`.
static func fec_message(page: PackedByteArray, msg_id: int = ANT_ACKNOWLEDGED_DATA) -> PackedByteArray:
	var out := PackedByteArray([ANT_SYNC, ANT_DATA_LENGTH, msg_id & 0xFF, ANT_FEC_CHANNEL])
	for i in 8:
		out.append(page[i] if i < page.size() else 0xFF)
	out.append(ant_checksum(out))
	return out


## Контрольная сумма ANT: XOR всех байт сообщения от синхробайта.
static func ant_checksum(bytes: PackedByteArray) -> int:
	var x := 0
	for b in bytes:
		x ^= b
	return x


## Страница 0x31 Target Power: байты 1–5 зарезервированы (0xFF), 6–7 — мощность в 0.25 Вт.
## 150 Вт → `A4 09 4F 05 31 FF FF FF FF FF 58 02 73`.
static func fec_target_power_message(watts: int) -> PackedByteArray:
	var v: int = clampi(watts * 4, 0, 4000 * 4)
	return fec_message(PackedByteArray([FEC_PAGE_TARGET_POWER, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, v & 0xFF, (v >> 8) & 0xFF]))


## Разбор ANT-сообщения FE-C (или голой 8-байтной страницы): заголовок, контрольная сумма,
## страницы 0x10, 0x11, 0x19, 0x30, 0x31, 0x47, 0x50, 0x51; остальные — номер страницы.
static func decode_fec(bytes: PackedByteArray) -> String:
	var page := PackedByteArray()
	var prefix := ""
	if bytes.size() >= 13 and bytes[0] == ANT_SYNC:
		var length: int = bytes[1]
		var total: int = length + 4
		if bytes.size() < total or length < 9:
			return "ANT: short message"
		var cs_ok := ant_checksum(bytes.slice(0, total - 1)) == bytes[total - 1]
		var kind := "broadcast" if bytes[2] == ANT_BROADCAST_DATA else ("ack" if bytes[2] == ANT_ACKNOWLEDGED_DATA else "msg 0x%02X" % bytes[2])
		prefix = "ANT %s ch%d%s, " % [kind, bytes[3], "" if cs_ok else " CHECKSUM BAD"]
		page = bytes.slice(4, 12)
	elif bytes.size() == 8:
		page = bytes
	else:
		return ""
	return prefix + _decode_fec_page(page)


static func _decode_fec_page(p: PackedByteArray) -> String:
	var n: int = p[0]
	match n:
		FEC_PAGE_GENERAL_FE:
			var speed_raw: int = BleBytes.u16(p, 4)
			var hr: int = p[6]
			return "page 0x10 General FE: type %s, elapsed %.2f s, distance %d m, speed %.2f km/h, HR %s, state %s" % [
				_fec_equipment(p[1] & 0x1F), p[2] * 0.25, p[3], speed_raw * 0.001 * 3.6,
				"n/a" if hr == 0xFF else str(hr), _fec_state((p[7] >> 4) & 0x07)]
		FEC_PAGE_GENERAL_SETTINGS:
			return "page 0x11 General Settings: incline %.2f %%, resistance %.1f %%, state %s" % [
				BleBytes.s16(p, 4) * 0.01, p[6] * 0.5, _fec_state((p[7] >> 4) & 0x07)]
		FEC_PAGE_TRAINER_DATA:
			var power: int = p[5] | ((p[6] & 0x0F) << 8)
			return "page 0x19 Trainer Data: cadence %s rpm, power %s W, accumulated %d W, events %d, status 0x%X, target %s, state %s" % [
				"n/a" if p[2] == 0xFF else str(p[2]), "n/a" if power == 0xFFF else str(power), BleBytes.u16(p, 3),
				p[1], (p[6] >> 4) & 0x0F, _fec_target_flag(p[7] & 0x03), _fec_state((p[7] >> 4) & 0x07)]
		FEC_PAGE_BASIC_RESISTANCE:
			return "page 0x30 Basic Resistance: %.1f %%" % (p[7] * 0.5)
		FEC_PAGE_TARGET_POWER:
			return "page 0x31 Target Power: %.2f W" % (BleBytes.u16(p, 6) * 0.25)
		FEC_PAGE_COMMAND_STATUS:
			return "page 0x47 Command Status: last command 0x%02X, sequence %d, status %s, data %s" % [
				p[1], p[2], _fec_command_status(p[3]), BleBytes.to_hex(p.slice(4, 8))]
		FEC_PAGE_MANUFACTURER:
			return "page 0x50 Manufacturer: HW rev %d, manufacturer %d, model %d" % [p[3], BleBytes.u16(p, 4), BleBytes.u16(p, 6)]
		FEC_PAGE_PRODUCT:
			return "page 0x51 Product: SW rev %d.%d, serial %d" % [p[3], p[2], BleBytes.u32(p, 4)]
	return "page 0x%02X" % n


static func _fec_equipment(t: int) -> String:
	match t:
		16:
			return "general"
		19:
			return "treadmill"
		20:
			return "elliptical"
		22:
			return "rower"
		23:
			return "climber"
		24:
			return "nordic_skier"
		25:
			return "trainer"
	return str(t)


static func _fec_state(s: int) -> String:
	match s:
		1:
			return "asleep"
		2:
			return "ready"
		3:
			return "in_use"
		4:
			return "finished"
	return "reserved_%d" % s


static func _fec_target_flag(f: int) -> String:
	match f:
		0:
			return "at_target"
		1:
			return "speed_too_low"
		2:
			return "speed_too_high"
	return "limit_reached"


static func _fec_command_status(s: int) -> String:
	match s:
		0:
			return "pass"
		1:
			return "fail"
		2:
			return "not_supported"
		3:
			return "rejected"
		4:
			return "pending"
		0xFF:
			return "uninitialized"
	return "0x%02X" % s


# ---------------------------------------------------------------------------
# Hex
# ---------------------------------------------------------------------------

## `{ok, bytes}`: пробелы, двоеточия, запятые, дефисы и префиксы 0x допускаются; пусто или
## нечётное число цифр — `ok == false`.
static func parse_hex(text: String) -> Dictionary:
	var clean := text.strip_edges().to_upper().replace("0X", "")
	for sep in [" ", ":", ",", "-", "\t"]:
		clean = clean.replace(sep, "")
	var out := PackedByteArray()
	if clean.is_empty() or clean.length() % 2 != 0:
		return {"ok": false, "bytes": out}
	for ch in clean:
		if not "0123456789ABCDEF".contains(ch):
			return {"ok": false, "bytes": PackedByteArray()}
	for i in range(0, clean.length(), 2):
		out.append(clean.substr(i, 2).hex_to_int())
	return {"ok": true, "bytes": out}


# ---------------------------------------------------------------------------
# Сигналы моста
# ---------------------------------------------------------------------------

func _on_adapter_state_changed(state: int) -> void:
	_add_log("adapter_state_changed", BleBridge.adapter_state_name(state), {"state": BleBridge.adapter_state_name(state)})
	link_changed.emit()


func _on_device_found(id: String, name: String, rssi: int, service_uuids: PackedStringArray) -> void:
	if not scanning or id.is_empty():
		return
	var now := _now()
	var entry: Dictionary = devices.get(id, {})
	var is_new := entry.is_empty()
	if is_new:
		entry = {"id": id, "name": name, "rssi": rssi, "raw": PackedStringArray(), "norm": PackedStringArray(),
				"union": PackedStringArray(), "kind": BleScanner.KIND_UNKNOWN, "packets": 0, "last_seen": now,
				"last_logged": -INF}
		devices[id] = entry
	if not name.is_empty():
		entry["name"] = name
	entry["rssi"] = rssi
	entry["raw"] = service_uuids.duplicate()
	var norm := PackedStringArray()
	for s in service_uuids:
		norm.append(BleUuids.normalize(s))
	entry["norm"] = norm
	var union: PackedStringArray = entry["union"]
	var grew := false
	for u in norm:
		if not union.has(u):
			union.append(u)
			grew = true
	entry["union"] = union
	entry["kind"] = BleScanner.kind_from_services(union)
	entry["packets"] = int(entry["packets"]) + 1
	entry["last_seen"] = now
	if is_new or grew or now - float(entry["last_logged"]) >= DEVICE_LOG_INTERVAL_SEC:
		entry["last_logged"] = now
		_add_log("device_found", "'%s' %s rssi %d raw [%s] norm [%s] union [%s] kind %s" % [
				entry["name"], id, rssi, _join(service_uuids), _join(norm), _join(union), entry["kind"]],
				_dev(id, {"name": entry["name"], "rssi": rssi, "raw": Array(service_uuids), "union": Array(union),
					"kind": entry["kind"]}))
	devices_changed.emit()


func _on_connected(id: String) -> void:
	_add_log("connected", "%s %s" % [_name_of(id), id], _dev(id))
	if id != link_id or link_id.is_empty():
		return
	_set_link_state(LinkState.DISCOVERING)
	bridge.discover_services(id)


func _on_disconnected(id: String, reason: int) -> void:
	var why := _reason_name(reason)
	_add_log("disconnected", "%s %s reason %s" % [_name_of(id), id, why], _dev(id, {"reason": why}))
	if id != link_id or link_id.is_empty():
		return
	link_id = ""
	subscriptions.clear()
	_set_link_state(LinkState.IDLE)
	tree_changed.emit()


func _on_services_discovered(id: String, found: Dictionary) -> void:
	var lines: Array[String] = []
	var plain: Dictionary = {}
	var norm: Dictionary = {}
	for s in found:
		var chars := PackedStringArray()
		for c in found[s]:
			chars.append(BleUuids.normalize(str(c)))
		var ns := BleUuids.normalize(str(s))
		norm[ns] = chars
		plain[ns] = Array(chars)
		var name := service_name(ns)
		lines.append("%s%s: [%s]" % [ns, (" (%s)" % name) if not name.is_empty() else "", _join(chars)])
	_add_log("services_discovered", "%s %s; %s" % [_name_of(id), id, "; ".join(lines)], _dev(id, {"services": plain}))
	if id != link_id or link_id.is_empty():
		return
	services = norm
	_set_link_state(LinkState.READY)
	tree_changed.emit()


func _on_notification(id: String, char_uuid: String, bytes: PackedByteArray) -> void:
	_store_value(id, char_uuid, bytes, "notify")


func _on_characteristic_read(id: String, char_uuid: String, bytes: PackedByteArray) -> void:
	_store_value(id, char_uuid, bytes, "read")


func _on_write_done(id: String, char_uuid: String, ok: bool) -> void:
	var c := BleUuids.normalize(char_uuid)
	_add_log("write_done", "%s %s %s" % [_short(c), char_name(c), "ok" if ok else "FAILED"], _dev(id, {"char": c, "ok": ok}))


func _on_error(id: String, code: int, message: String) -> void:
	var code_name := _error_name(code)
	_add_log("error", "%s%s code %d %s: %s" % [_name_of(id) + " " if not id.is_empty() else "", id, code, code_name, message],
			_dev(id, {"code": code, "code_name": code_name, "message": _redact(message, id)}))
	if id == link_id and not link_id.is_empty() and link_state == LinkState.CONNECTING \
			and code in [BleBridge.ErrorCode.CONNECTION_FAILED, BleBridge.ErrorCode.DEVICE_NOT_FOUND,
				BleBridge.ErrorCode.TIMEOUT, BleBridge.ErrorCode.ADAPTER_UNAVAILABLE]:
		link_id = ""
		_set_link_state(LinkState.IDLE)


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _store_value(id: String, char_uuid: String, bytes: PackedByteArray, source: String) -> void:
	var c := BleUuids.normalize(char_uuid)
	var hex := BleBytes.to_hex(bytes)
	var decoded := decode(c, bytes)
	var time := _format_time(_now())
	var event := "notification" if source == "notify" else "characteristic_read"
	_add_log(event, "%s %s [%s]%s" % [_short(c), char_name(c), hex, (" = " + decoded) if not decoded.is_empty() else ""],
			_dev(id, {"char": c, "hex": hex, "decoded": decoded}))
	if id != link_id:
		return
	values[c] = {"bytes": bytes.duplicate(), "hex": hex, "time": time, "source": source, "decoded": decoded}
	value_changed.emit(c)


func _require_ready(action: String) -> bool:
	if bridge != null and is_ready():
		return true
	_add_log("action_rejected", "%s: not connected" % action, {"action": action})
	return false


func _set_link_state(state: int) -> void:
	link_state = state
	link_changed.emit()


func _reset_link_data() -> void:
	services.clear()
	values.clear()
	subscriptions.clear()
	tree_changed.emit()


func _add_log(event: String, text: String, data: Dictionary) -> void:
	var now := _now()
	var entry := {"t": now, "time": _format_time(now), "event": event, "text": text}
	_log.append(entry)
	if _log.size() > MAX_LOG_ENTRIES:
		_log.remove_at(0)
	DiagLog.event(DIAG_CATEGORY, event, data)
	log_added.emit(entry)


func _now() -> float:
	return float(clock.call()) if clock.is_valid() else 0.0


func _format_time(unix_sec: float) -> String:
	var local := unix_sec + utc_offset_sec
	var whole := floori(local)
	var ms := int((local - whole) * 1000.0)
	return "%s.%03d" % [Time.get_time_string_from_unix_time(whole), clampi(ms, 0, 999)]


func _name_of(id: String) -> String:
	return "'%s'" % str((devices.get(id, {}) as Dictionary).get("name", ""))


## Поля журнала `DiagLog`: метка устройства вместо id (+ `extra`).
func _dev(id: String, extra: Dictionary = {}) -> Dictionary:
	var out := {"dev": device_tag(id)}
	var name := str((devices.get(id, {}) as Dictionary).get("name", ""))
	if not name.is_empty():
		out["name"] = name
	out.merge(extra)
	return out


static func device_tag(id: String) -> String:
	return id.sha256_text().substr(0, DEVICE_TAG_LENGTH) if not id.is_empty() else ""


static func _redact(message: String, id: String) -> String:
	return message.replace(id, device_tag(id)) if not id.is_empty() else message


static func _key(service_uuid: String, char_uuid: String) -> String:
	return BleUuids.normalize(service_uuid) + "/" + BleUuids.normalize(char_uuid)


## Короткая запись UUID для журнала: 16-битные как есть, 128-битные — первые 8 символов.
static func _short(uuid: String) -> String:
	return uuid if uuid.length() <= 8 else uuid.substr(0, 8)


static func _join(list: PackedStringArray) -> String:
	return ", ".join(list)


static func _reason_name(reason: int) -> String:
	match reason:
		BleBridge.DisconnectReason.REQUESTED:
			return "requested"
		BleBridge.DisconnectReason.LINK_LOSS:
			return "link_loss"
		BleBridge.DisconnectReason.TIMEOUT:
			return "timeout"
		BleBridge.DisconnectReason.ERROR:
			return "error"
	return "reason_%d" % reason


static func _error_name(code: int) -> String:
	var keys: Array = BleBridge.ErrorCode.keys()
	for k: String in keys:
		if int(BleBridge.ErrorCode[k]) == code:
			return k
	return "UNKNOWN"


static func _decode_indoor_bike_data(bytes: PackedByteArray) -> String:
	var r := FtmsCodec.decode_indoor_bike_data(bytes)
	var parts: Array[String] = ["flags 0x%04X" % int(r["flags"])]
	if r["has_speed"]:
		parts.append("speed %.2f km/h" % float(r["speed_kmh"]))
	if r["has_cadence"]:
		parts.append("cadence %.1f rpm" % float(r["cadence_rpm"]))
	if r["has_power"]:
		parts.append("power %d W" % int(r["power_w"]))
	if r["has_heart_rate"]:
		parts.append("HR %d" % int(r["heart_rate_bpm"]))
	if not r["ok"]:
		parts.append("incomplete")
	return ", ".join(parts)


static func _decode_cps(bytes: PackedByteArray) -> String:
	var r := CpsCodec.decode_cycling_power_measurement(bytes)
	if bytes.size() < 4:
		return "incomplete"
	var parts: Array[String] = ["flags 0x%04X" % int(r["flags"]), "power %d W" % int(r["power_w"])]
	if r["has_balance"]:
		parts.append("balance %.1f %%" % float(r["pedal_balance_pct"]))
	if r["has_wheel"]:
		parts.append("wheel %d @ %d" % [int(r["wheel_revolutions"]), int(r["wheel_event_time"])])
	if r["has_crank"]:
		parts.append("crank %d @ %d" % [int(r["crank_revolutions"]), int(r["crank_event_time"])])
	if not r["ok"]:
		parts.append("incomplete")
	return ", ".join(parts)


static func _decode_csc(bytes: PackedByteArray) -> String:
	var r := CscCodec.decode_csc_measurement(bytes)
	if not r["ok"]:
		return "incomplete"
	var parts: Array[String] = []
	if r["has_wheel"]:
		parts.append("wheel %d @ %d" % [int(r["wheel_revolutions"]), int(r["wheel_event_time"])])
	if r["has_crank"]:
		parts.append("crank %d @ %d" % [int(r["crank_revolutions"]), int(r["crank_event_time"])])
	return ", ".join(parts) if not parts.is_empty() else "no data"


static func _decode_hr(bytes: PackedByteArray) -> String:
	var r := HrsCodec.decode_heart_rate_measurement(bytes)
	if not r["ok"]:
		return "incomplete"
	return "HR %d bpm, contact %s" % [int(r["bpm"]), "ok" if r["contact_ok"] else "lost"]
