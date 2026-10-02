extends GutTest
## Тесты сканера BLE и модели списка устройств (REQ-DEV-01 крит. 1–4).

var _bridge: StubBleBridge
var _scanner: BleScanner
var _changed: int = 0
var _found: Array[Dictionary] = []


func before_each() -> void:
	_changed = 0
	_found = []
	_bridge = StubBleBridge.new()
	_scanner = BleScanner.new(_bridge)
	_scanner.devices_changed.connect(func() -> void: _changed += 1)
	_scanner.device_found.connect(func(d: Dictionary) -> void: _found.append(d))


func _adv(id: String, name: String, rssi: int, services: Array) -> void:
	_bridge.emit_device_found(id, name, rssi, PackedStringArray(services))


func test_start_scans_required_services_and_stop_stops() -> void:
	_scanner.start()
	assert_true(_scanner.is_scanning())
	var calls := _bridge.calls_of("start_scan")
	assert_eq(calls.size(), 1)
	assert_eq(calls[0]["service_uuids"], PackedStringArray(["1826", "180D", "1816", "1818"]), "REQ-DEV-01 крит. 1")
	_scanner.start()
	assert_eq(_bridge.calls_of("start_scan").size(), 1, "повторный start — без второго вызова")
	_scanner.stop()
	assert_false(_scanner.is_scanning())
	assert_eq(_bridge.calls_of("stop_scan").size(), 1, "REQ-DEV-01 крит. 4")
	_scanner.stop()
	assert_eq(_bridge.calls_of("stop_scan").size(), 1)


func test_device_found_adds_row_with_kind_and_emits() -> void:
	_scanner.start()
	_adv("neo", "Tacx Neo 2T", -60, ["1826", "180F"])
	assert_eq(_scanner.devices.size(), 1)
	var d := _scanner.devices[0]
	assert_eq(d["id"], "neo")
	assert_eq(d["name"], "Tacx Neo 2T")
	assert_eq(d["rssi"], -60)
	assert_eq(d["kind"], RememberedDevices.KIND_TRAINER, "REQ-DEV-01 крит. 2: тип по сервисам")
	assert_true(d["available"])
	assert_eq(_changed, 1)
	assert_eq(_found.size(), 1)
	assert_eq(_found[0]["id"], "neo")


func test_kind_mapping_for_all_services() -> void:
	assert_eq(BleScanner.kind_from_services(PackedStringArray(["180d"])), RememberedDevices.KIND_HR)
	assert_eq(BleScanner.kind_from_services(PackedStringArray(["1816"])), RememberedDevices.KIND_CADENCE)
	assert_eq(BleScanner.kind_from_services(PackedStringArray(["1818"])), RememberedDevices.KIND_POWER)
	assert_eq(BleScanner.kind_from_services(PackedStringArray(["1826", "1818"])), RememberedDevices.KIND_TRAINER)
	assert_eq(BleScanner.kind_from_services(PackedStringArray(["180F"])), BleScanner.KIND_UNKNOWN)
	assert_eq(BleScanner.kind_from_services(PackedStringArray()), BleScanner.KIND_UNKNOWN)


func test_duplicate_advertisement_updates_instead_of_adding() -> void:
	_scanner.start()
	_adv("hrm", "", -80, ["180D"])
	_scanner.tick(2.0)
	_adv("hrm", "Polar H10", -70, ["180D"])
	assert_eq(_scanner.devices.size(), 1, "дедупликация по id")
	var d := _scanner.find("hrm")
	assert_eq(d["name"], "Polar H10", "имя обновлено")
	assert_eq(d["rssi"], -70, "RSSI обновлён")
	assert_almost_eq(float(d["last_seen_sec"]), 2.0, 1e-9)
	_adv("hrm", "", -75, [])
	assert_eq(_scanner.find("hrm")["name"], "Polar H10", "пустое имя не затирает известное")
	assert_eq(_scanner.find("hrm")["kind"], RememberedDevices.KIND_HR, "unknown не затирает известный тип")
	assert_eq(_changed, 3)


func test_unavailable_after_10s_and_removed_after_30s() -> void:
	_scanner.start()
	_adv("neo", "Neo", -60, ["1826"])
	_changed = 0
	_scanner.tick(9.9)
	assert_true(_scanner.find("neo")["available"])
	assert_eq(_changed, 0)
	_scanner.tick(0.1)
	assert_false(_scanner.find("neo")["available"], "REQ-DEV-01 крит. 3: 10 с без рекламы")
	assert_eq(_changed, 1)
	_scanner.tick(19.9)
	assert_true(_scanner.has("neo"))
	_scanner.tick(0.1)
	assert_false(_scanner.has("neo"), "через 30 с — удалено")
	assert_eq(_changed, 2)


func test_advertisement_restores_availability() -> void:
	_scanner.start()
	_adv("neo", "Neo", -60, ["1826"])
	_scanner.tick(12.0)
	assert_false(_scanner.find("neo")["available"])
	_adv("neo", "Neo", -65, ["1826"])
	assert_true(_scanner.find("neo")["available"])
	_scanner.tick(9.0)
	assert_true(_scanner.find("neo")["available"], "отсчёт идёт от последней рекламы")


func test_sorting_trainers_first_then_rssi_then_name() -> void:
	_scanner.start()
	_adv("hrm", "HRM", -50, ["180D"])
	_adv("cad", "Cadence", -40, ["1816"])
	_adv("neo", "Neo", -90, ["1826"])
	_adv("pm", "Assioma", -50, ["1818"])
	var ids: Array[String] = []
	for d in _scanner.devices:
		ids.append(d["id"])
	assert_eq(ids, ["neo", "cad", "pm", "hrm"] as Array[String], "станок первым, далее по RSSI, при равенстве — по имени")


func test_events_ignored_when_not_scanning_and_clear() -> void:
	_adv("neo", "Neo", -60, ["1826"])
	assert_eq(_scanner.devices.size(), 0, "до start() реклама игнорируется")
	_scanner.start()
	_adv("neo", "Neo", -60, ["1826"])
	_scanner.stop()
	_adv("hrm", "HRM", -60, ["180D"])
	assert_eq(_scanner.devices.size(), 1, "после stop() — игнорируется")
	_adv("", "Ghost", -60, ["180D"])
	_scanner.clear()
	assert_eq(_scanner.devices.size(), 0)
	assert_true(_scanner.find("neo").is_empty())


func test_tick_without_devices_and_negative_delta_are_harmless() -> void:
	_scanner.tick(100.0)
	_scanner.tick(-1.0)
	assert_eq(_changed, 0)
	assert_almost_eq(_scanner.get_time_sec(), 100.0, 1e-9)
