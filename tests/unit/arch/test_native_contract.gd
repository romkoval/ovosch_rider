extends GutTest
## Статическая сверка нативного моста с контрактом без компиляции (REQ-DEV-01 крит. 6,
## REQ-NFR-06 крит. 2, REQ-DEV-02 крит. 1 — контракт для станка):
## - `OvoschBle` (native/ble/src/ovosch_ble.cpp) биндит все методы `BleBridge` и объявляет
##   все его сигналы с тем же числом аргументов;
## - `AppleBackend` (apple_backend.mm) и `NullBackend` реализуют все чистые виртуальные
##   методы `BleBackend` (по сигнатурам с `override`);
## - фабрика платформенного backend'а, entry symbol и список пробрасываемых сигналов согласованы.

const BRIDGE_GD: String = "res://src/devices/ble/ble_bridge.gd"
const NATIVE_BRIDGE_GD: String = "res://src/devices/ble/native_ble_bridge.gd"
const OVOSCH_CPP: String = "res://native/ble/src/ovosch_ble.cpp"
const OVOSCH_H: String = "res://native/ble/src/ovosch_ble.h"
const BACKEND_H: String = "res://native/ble/src/ble_backend.h"
const NULL_BACKEND_H: String = "res://native/ble/src/null_backend.h"
const APPLE_MM: String = "res://native/ble/src/platform/apple/apple_backend.mm"
const REGISTER_CPP: String = "res://native/ble/src/register_types.cpp"
const GDEXTENSION: String = "res://native/ble/ovosch_ble.gdextension"
const SCONSTRUCT: String = "res://native/ble/SConstruct"

## Статические методы контракта — не часть нативного интерфейса.
const STATIC_METHODS: Array[String] = ["create_default", "adapter_state_name"]


func _read(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	assert_true(FileAccess.file_exists(path), "файл существует: %s" % path)
	return text


## Строки GDScript без комментариев.
func _gd_code(text: String) -> String:
	var kept: Array[String] = []
	for line in text.split("\n"):
		var idx := line.find("#")
		kept.append(line.substr(0, idx) if idx != -1 else line)
	return "\n".join(kept)


## Число параметров в списке "a: T, b: T = x" (0 для пустого).
func _param_count(params: String) -> int:
	var p := params.strip_edges()
	if p.is_empty():
		return 0
	return p.split(",").size()


## Методы контракта `BleBridge`: имя → число аргументов (без статических).
func _bridge_methods() -> Dictionary:
	var out: Dictionary = {}
	var re := RegEx.create_from_string("(?m)^(static\\s+)?func\\s+(\\w+)\\(([^)]*)\\)")
	for m in re.search_all(_gd_code(_read(BRIDGE_GD))):
		var name := m.get_string(2)
		if m.get_string(1).strip_edges() == "static" or STATIC_METHODS.has(name) or name.begins_with("_"):
			continue
		out[name] = _param_count(m.get_string(3))
	return out


## Сигналы контракта: имя → число аргументов.
func _bridge_signals() -> Dictionary:
	var out: Dictionary = {}
	var re := RegEx.create_from_string("(?m)^signal\\s+(\\w+)\\(([^)]*)\\)")
	for m in re.search_all(_gd_code(_read(BRIDGE_GD))):
		out[m.get_string(1)] = _param_count(m.get_string(2))
	return out


## Забинденные методы OvoschBle: D_METHOD("name", "arg", ...) → имя → число аргументов.
func _bound_methods() -> Dictionary:
	var out: Dictionary = {}
	var re := RegEx.create_from_string("D_METHOD\\(([^)]*)\\)")
	var str_re := RegEx.create_from_string("\"(\\w+)\"")
	for m in re.search_all(_read(OVOSCH_CPP)):
		var names: Array[String] = []
		for sm in str_re.search_all(m.get_string(1)):
			names.append(sm.get_string(1))
		assert_gt(names.size(), 0, "D_METHOD без имени")
		out[names[0]] = names.size() - 1
	return out


## Объявленные сигналы OvoschBle: ADD_SIGNAL(MethodInfo("name", PropertyInfo(...)...)).
func _declared_signals() -> Dictionary:
	var out: Dictionary = {}
	var text := _read(OVOSCH_CPP).replace("\n", " ")
	var re := RegEx.create_from_string("ADD_SIGNAL\\(MethodInfo\\(\"(\\w+)\"(.*?)\\)\\);")
	for m in re.search_all(text):
		var body := m.get_string(2)
		out[m.get_string(1)] = body.count("PropertyInfo(")
	return out


## Чистые виртуальные методы класса `name` в ble_backend.h.
func _pure_virtuals(class_name_: String) -> Array[String]:
	var text := _read(BACKEND_H)
	var start := text.find("class %s {" % class_name_)
	assert_gt(start, -1, "класс %s в ble_backend.h" % class_name_)
	var end := text.find("};", start)
	var body := text.substr(start, end - start)
	var out: Array[String] = []
	var re := RegEx.create_from_string("virtual\\s+[\\w:<>&\\s]+?\\b(\\w+)\\s*\\([^;]*?\\)\\s*(const\\s*)?=\\s*0;")
	for m in re.search_all(body.replace("\n", " ")):
		out.append(m.get_string(1))
	return out


## Имена методов, помеченных `override` в файле.
func _overrides_in(path: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.create_from_string("\\b(\\w+)\\s*\\([^;{]*?\\)\\s*(const\\s*)?override")
	for m in re.search_all(_read(path).replace("\n", " ")):
		if not out.has(m.get_string(1)):
			out.append(m.get_string(1))
	return out


# ---------------------------------------------------------------------------
# OvoschBle ⇔ BleBridge
# ---------------------------------------------------------------------------

func test_contract_has_expected_shape() -> void:
	var methods := _bridge_methods()
	var signals_ := _bridge_signals()
	assert_eq(methods.size(), 11, "11 методов контракта: %s" % str(methods.keys()))
	assert_eq(signals_.size(), 9, "9 сигналов контракта: %s" % str(signals_.keys()))
	assert_eq(methods["write"], 5)
	assert_eq(methods["read_characteristic"], 3)
	assert_eq(signals_["device_found"], 4)
	assert_eq(signals_["error"], 3)


func test_ovosch_ble_binds_every_bridge_method_with_same_arity() -> void:
	var contract := _bridge_methods()
	var bound := _bound_methods()
	for name in contract:
		assert_true(bound.has(name), "OvoschBle биндит %s" % name)
		if bound.has(name):
			assert_eq(bound[name], contract[name], "число аргументов %s" % name)
	for name in bound:
		assert_true(contract.has(name), "лишний бинд вне контракта: %s" % name)


func test_ovosch_ble_declares_every_bridge_signal_with_same_arity() -> void:
	var contract := _bridge_signals()
	var declared := _declared_signals()
	assert_eq(declared.size(), contract.size(), "сигналов столько же: %s" % str(declared.keys()))
	for name in contract:
		assert_true(declared.has(name), "OvoschBle объявляет сигнал %s" % name)
		if declared.has(name):
			assert_eq(declared[name], contract[name], "число аргументов сигнала %s" % name)


func test_native_ble_bridge_forwards_exactly_the_contract_signals() -> void:
	var contract := _bridge_signals()
	var text := _gd_code(_read(NATIVE_BRIDGE_GD))
	var start := text.find("FORWARDED_SIGNALS")
	assert_gt(start, -1)
	start = text.find("= [", start)
	var end := text.find("]", start)
	var block := text.substr(start, end - start)
	var re := RegEx.create_from_string("&\"(\\w+)\"")
	var forwarded: Array[String] = []
	for m in re.search_all(block):
		forwarded.append(m.get_string(1))
	assert_eq(forwarded.size(), contract.size())
	for name in contract:
		assert_has(forwarded, name, "NativeBleBridge пробрасывает %s" % name)
		assert_true(text.contains("func _fwd_%s(" % name), "есть обработчик _fwd_%s" % name)


func test_ovosch_ble_header_declares_contract_methods_and_listener_overrides() -> void:
	var header := _read(OVOSCH_H).replace("\n", " ")
	for name in _bridge_methods():
		assert_true(RegEx.create_from_string("\\b%s\\s*\\(" % name).search(header) != null, "ovosch_ble.h: %s" % name)
	var listener := _pure_virtuals("BleListener")
	assert_eq(listener.size(), 9)
	var overrides := _overrides_in(OVOSCH_H)
	for name in listener:
		assert_has(overrides, name, "OvoschBle переопределяет BleListener::%s" % name)


# ---------------------------------------------------------------------------
# Backends ⇔ BleBackend
# ---------------------------------------------------------------------------

func test_ble_backend_interface_matches_contract_operations() -> void:
	var virtuals := _pure_virtuals("BleBackend")
	assert_eq(virtuals.size(), 12, "set_listener + 11 методов контракта: %s" % str(virtuals))
	for name in _bridge_methods():
		assert_has(virtuals, name, "BleBackend::%s" % name)
	assert_has(virtuals, "set_listener")


func test_apple_backend_implements_every_ble_backend_method() -> void:
	var virtuals := _pure_virtuals("BleBackend")
	var overrides := _overrides_in(APPLE_MM)
	for name in virtuals:
		assert_has(overrides, name, "apple_backend.mm: %s(...) override" % name)
	var text := _read(APPLE_MM)
	assert_true(text.contains("class AppleBackend final : public BleBackend"))
	assert_true(text.contains("#ifdef OVOSCH_BLE_HAS_PLATFORM_BACKEND"), "фабрика под макросом")
	assert_true(text.contains("std::unique_ptr<BleBackend> create_platform_backend()"))
	assert_true(text.contains("CBCentralManagerScanOptionAllowDuplicatesKey : @YES"),
		"сканирование с дубликатами рекламы: иначе устройство сообщается один раз за сеанс")
	assert_false(text.contains("AllowDuplicatesKey : @NO"))
	assert_true(text.contains("retrievePeripheralsWithIdentifiers"), "запомненные устройства по id")
	assert_true(text.contains("pendingReads"), "чтение отличается от нотификации по флагу ожидания")
	for cb in ["centralManagerDidUpdateState", "didDiscoverPeripheral", "didConnectPeripheral",
			"didFailToConnectPeripheral", "didDisconnectPeripheral", "didDiscoverServices",
			"didDiscoverCharacteristicsForService", "didUpdateValueForCharacteristic",
			"didWriteValueForCharacteristic", "didUpdateNotificationStateForCharacteristic"]:
		assert_true(text.contains(cb), "делегат реализует %s" % cb)


func test_null_backend_implements_every_ble_backend_method_and_owns_default_factory() -> void:
	var virtuals := _pure_virtuals("BleBackend")
	var overrides := _overrides_in(NULL_BACKEND_H)
	for name in virtuals:
		assert_has(overrides, name, "null_backend.h: %s override" % name)
	var cpp := _read("res://native/ble/src/null_backend.cpp")
	assert_true(cpp.contains("#ifndef OVOSCH_BLE_HAS_PLATFORM_BACKEND"), "фабрика заглушки только без платформенного backend'а")


func test_backend_enums_match_bridge_values() -> void:
	var header := _read(BACKEND_H)
	var gd := _gd_code(_read(BRIDGE_GD))
	for enum_name in ["AdapterState", "DisconnectReason", "ErrorCode"]:
		var gd_start := gd.find("enum %s" % enum_name)
		var gd_block := gd.substr(gd_start, gd.find("}", gd_start) - gd_start)
		var gd_names: Array[String] = []
		for m in RegEx.create_from_string("\\b([A-Z][A-Z_]+)\\b").search_all(gd_block):
			if not gd_names.has(m.get_string(1)):
				gd_names.append(m.get_string(1))
		var h_start := header.find("enum class %s" % enum_name)
		var h_block := header.substr(h_start, header.find("};", h_start) - h_start)
		for i in gd_names.size():
			assert_true(RegEx.create_from_string("\\b%s\\s*=\\s*%d\\b" % [gd_names[i], i]).search(h_block) != null,
				"%s::%s == %d в ble_backend.h" % [enum_name, gd_names[i], i])


# ---------------------------------------------------------------------------
# Сборка и регистрация
# ---------------------------------------------------------------------------

func test_entry_symbol_and_class_name_are_consistent() -> void:
	var gdext := _read(GDEXTENSION)
	var re := RegEx.create_from_string("entry_symbol\\s*=\\s*\"(\\w+)\"")
	var m := re.search(gdext)
	assert_not_null(m)
	var symbol := m.get_string(1)
	assert_true(_read(REGISTER_CPP).contains("GDE_EXPORT %s(" % symbol), "register_types.cpp экспортирует %s" % symbol)
	assert_true(_read(REGISTER_CPP).contains("GDREGISTER_CLASS(ovosch::OvoschBle)"))
	assert_true(_read(OVOSCH_H).contains("GDCLASS(OvoschBle, godot::RefCounted)"))
	assert_eq(String(NativeBleBridge.NATIVE_CLASS), "OvoschBle", "GDScript ищет тот же класс")
	for section in ["macos.debug", "ios.debug", "linux.debug.x86_64", "windows.debug.x86_64", "android.debug.arm64"]:
		assert_true(gdext.contains(section), ".gdextension: секция %s" % section)


func test_sconstruct_wires_apple_backend_and_ci_builds_both_platforms() -> void:
	var scons := _read(SCONSTRUCT)
	assert_true(scons.contains("src/platform/apple/*.mm"))
	assert_true(scons.contains("OVOSCH_BLE_HAS_PLATFORM_BACKEND"))
	assert_true(scons.contains("CoreBluetooth"))
	assert_true(scons.contains("-fobjc-arc"))
	var ci := _read("res://.github/workflows/ci.yml")
	assert_true(ci.contains("native-linux:"))
	assert_true(ci.contains("native-macos:"))
	assert_true(ci.contains("scons platform=macos target=${{ matrix.target }} arch=universal"), "macOS: универсальная сборка debug и release")
	assert_true(ci.contains("check_native_ble.gd"), "CI проверяет загрузку расширения и контракт BleBridge")
	assert_true(ci.contains("macos-app:"), "CI экспортирует macOS-приложение")
	assert_true(FileAccess.file_exists("res://native/.gdignore"), "каталог native скрыт от Godot до сборки")
	assert_true(scons.contains("godot-cpp"), "SConstruct ищет godot-cpp")
	var readme := _read("res://native/ble/README.md")
	assert_true(readme.contains("native/ble/godot-cpp"), "README описывает layout native/ble/godot-cpp")
	assert_true(readme.contains("NSBluetoothAlwaysUsageDescription"), "README: Info.plist")
	assert_true(readme.contains("com.apple.security.device.bluetooth"), "README: entitlement")
	assert_true(readme.contains("bluetooth-central"), "README: фоновый режим iOS (вопрос владельцу)")


# ---------------------------------------------------------------------------
# Регрессии финального ревью (дубли событий, прореживание рекламы)
# ---------------------------------------------------------------------------

## Отказ записи — ровно одно событие `write_done(false)`: второе (`error(WRITE_FAILED)`)
## BleTrainer принимал за отказ повтора.
func test_apple_write_failure_is_single_write_done_event() -> void:
	var text := _read(APPLE_MM)
	var start := text.find("void AppleBackend::handle_write_done(")
	assert_gt(start, -1)
	var body := text.substr(start, text.find("\n}\n", start) - start)
	assert_true(body.contains("on_write_done(id, ch, ok)"))
	assert_false(body.contains("ErrorCode::WRITE_FAILED"), "в handle_write_done нет error(WRITE_FAILED)")
	assert_false(body.contains("emit_error"), "в handle_write_done нет второго события")


## Дубликаты рекламы прореживаются в общем слое: не чаще раза в секунду на устройство,
## сброс на новом сеансе сканирования.
func test_ovosch_ble_throttles_device_found_and_resets_on_start_scan() -> void:
	var cpp := _read(OVOSCH_CPP)
	var header := _read("res://native/ble/src/scan_throttle.h")
	assert_true(header.contains("DEFAULT_INTERVAL_MS = 1000"), "интервал 1 с")
	assert_true(_read(OVOSCH_H).contains("ScanThrottle scan_throttle_"))
	var found := cpp.substr(cpp.find("void OvoschBle::on_device_found("))
	found = found.substr(0, found.find("\n}\n"))
	assert_true(found.contains("scan_throttle_.should_emit("), "on_device_found проходит через прореживание")
	var scan := cpp.substr(cpp.find("void OvoschBle::start_scan("))
	scan = scan.substr(0, scan.find("\n}\n"))
	assert_true(scan.contains("scan_throttle_.reset()"), "новый сеанс — устройства снова «первые»")
