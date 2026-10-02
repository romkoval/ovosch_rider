extends GutTest
## Независимая приёмка T-019/T-020/T-021 (коммит 851c724+): `BleScanner`, `ConnectionManager`,
## батарея станка в `BleTrainer`, статическая сверка контракта `OvoschBle` (native/ble) с `BleBridge`.
## Критерии: REQ-DEV-01 к1–4, к6 (статически); REQ-DEV-06 к1–4; REQ-DEV-07 к1–3; REQ-DEV-02 к1 (батарея);
## REQ-PRF-04 к2–3; REQ-NFR-06 к2. Экран устройств — в tests/integration/test_devices_screen_acceptance.gd.

const A: String = "profile-a"
const B: String = "profile-b"
const SCAN_SERVICES: Array[String] = ["1826", "180D", "1816", "1818"]

var _dir: String
var _bridge: StubBleBridge
var _remembered: RememberedDevices
var _cm: ConnectionManager
var _state_events: Array[String] = []
var _timed_out: Array = []
var _devices_changed: int = 0


func before_each() -> void:
	_dir = "user://test_conn_acc_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_bridge = StubBleBridge.new()
	_remembered = RememberedDevices.new(_dir)
	_cm = ConnectionManager.new(_bridge, _remembered)
	_state_events = []
	_timed_out = []
	_devices_changed = 0
	_cm.state_changed.connect(func(id: String) -> void: _state_events.append(id))
	_cm.auto_connect_timed_out.connect(func(ids: Array[String]) -> void: _timed_out.append(ids.duplicate()))
	_cm.devices_changed.connect(func() -> void: _devices_changed += 1)
	_cm.set_profile(A)


func after_each() -> void:
	if _cm != null:
		_cm.dispose()
		_cm = null
	_remove_tree(ProjectSettings.globalize_path(_dir))


static func _remove_tree(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	var d := DirAccess.open(abs_path)
	for f in d.get_files():
		DirAccess.remove_absolute(abs_path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(abs_path.path_join(sub))
	DirAccess.remove_absolute(abs_path)


func _adv(id: String, name: String, services: Array, rssi: int = -60) -> void:
	_bridge.emit_device_found(id, name, rssi, PackedStringArray(services))


func _connects_to(id: String) -> int:
	var n := 0
	for c in _bridge.calls_of("connect_peripheral"):
		if c["id"] == id:
			n += 1
	return n


func _hex(s: String) -> PackedByteArray:
	var clean := s.replace(" ", "")
	var out := PackedByteArray()
	var i := 0
	while i + 1 < clean.length():
		out.append(("0x" + clean.substr(i, 2)).hex_to_int())
		i += 2
	return out


# ===========================================================================
# REQ-DEV-01 — сканирование и модель списка
# ===========================================================================

func test_req_dev_01_c1_start_scan_requests_ftms_hrs_csc_cps() -> void:
	_cm.start_scan()
	var calls := _bridge.calls_of("start_scan")
	assert_eq(calls.size(), 1, "один вызов start_scan")
	var arg: PackedStringArray = calls[0]["service_uuids"]
	assert_eq(arg.size(), 4)
	for u in SCAN_SERVICES:
		assert_true(arg.has(u), "в аргументах есть %s" % u)
	assert_true(_cm.scanner.is_scanning())
	_cm.start_scan()
	assert_eq(_bridge.calls_of("start_scan").size(), 1, "повторный start — без второго вызова моста")
	_cm.stop_scan()
	assert_false(_cm.scanner.is_scanning())
	assert_eq(_bridge.calls_of("stop_scan").size(), 1)
	_cm.stop_scan()
	assert_eq(_bridge.calls_of("stop_scan").size(), 1, "повторный stop — без второго вызова")


func test_req_dev_01_c2_device_found_adds_or_updates_row_with_name_rssi_kind() -> void:
	_cm.start_scan()
	_adv("neo", "Tacx Neo", ["1826"], -55)
	var sc := _cm.scanner
	assert_eq(sc.devices.size(), 1)
	var row := sc.find("neo")
	assert_eq(row["name"], "Tacx Neo")
	assert_eq(row["rssi"], -55)
	assert_eq(row["kind"], RememberedDevices.KIND_TRAINER, "тип по сервисам: станок")
	assert_true(row["available"])
	# Повторная реклама — обновление, а не вторая строка.
	_adv("neo", "Tacx Neo 2T", ["1826"], -48)
	assert_eq(sc.devices.size(), 1, "дедупликация по id")
	assert_eq(sc.find("neo")["name"], "Tacx Neo 2T")
	assert_eq(sc.find("neo")["rssi"], -48)
	# Типы по сервисам.
	_adv("hrm", "Polar H10", ["180D"])
	_adv("csc", "Wahoo RPM", ["1816"])
	_adv("pm", "Assioma", ["1818"])
	assert_eq(sc.find("hrm")["kind"], RememberedDevices.KIND_HR)
	assert_eq(sc.find("csc")["kind"], RememberedDevices.KIND_CADENCE)
	assert_eq(sc.find("pm")["kind"], RememberedDevices.KIND_POWER)
	assert_eq(sc.devices.size(), 4)
	assert_eq(sc.devices[0]["id"], "neo", "станки — первыми в списке")
	assert_gt(_devices_changed, 0, "менеджер пробрасывает devices_changed")


func test_req_dev_01_c2_edge_unnamed_device_two_kinds_unknown_services_empty_id() -> void:
	_cm.start_scan()
	# Реклама без имени: строка есть, имя пустое (экран покажет «Без имени»), позже имя заполняется.
	_adv("x1", "", ["180D"])
	assert_eq(_cm.scanner.find("x1")["name"], "")
	assert_eq(_cm.scanner.find("x1")["kind"], RememberedDevices.KIND_HR)
	_adv("x1", "HRM Pro", ["180D"])
	assert_eq(_cm.scanner.find("x1")["name"], "HRM Pro", "имя появилось — обновлено")
	_adv("x1", "", ["180D"])
	assert_eq(_cm.scanner.find("x1")["name"], "HRM Pro", "пустое имя в следующей рекламе не стирает известное")
	# Одно устройство с двумя типами (станок с пульсом): приоритет — станок.
	_adv("combo", "Kickr", ["180D", "1826", "180F"])
	assert_eq(_cm.scanner.find("combo")["kind"], RememberedDevices.KIND_TRAINER)
	# Сначала без известных сервисов, затем с HRS — тип уточняется; обратно не затирается.
	_adv("late", "Dev", ["180A"])
	assert_eq(_cm.scanner.find("late")["kind"], BleScanner.KIND_UNKNOWN)
	_adv("late", "Dev", ["180D"])
	assert_eq(_cm.scanner.find("late")["kind"], RememberedDevices.KIND_HR)
	_adv("late", "Dev", [])
	assert_eq(_cm.scanner.find("late")["kind"], RememberedDevices.KIND_HR, "unknown не затирает известный тип")
	# Пустой id — игнор.
	_adv("", "Ghost", ["1826"])
	assert_false(_cm.scanner.has(""))
	# Без сканирования события не принимаются.
	_cm.stop_scan()
	_adv("after", "After stop", ["1826"])
	assert_false(_cm.scanner.has("after"), "после stop_scan реклама игнорируется")


func test_req_dev_01_c3_device_unavailable_after_10s_removed_after_30s_restored_by_advert() -> void:
	_cm.start_scan()
	_adv("neo", "Neo", ["1826"])
	_adv("hrm", "HRM", ["180D"])
	_cm.tick(9.9)
	assert_true(_cm.scanner.find("neo")["available"], "9.9 с — ещё доступно")
	_cm.tick(0.1)
	assert_false(_cm.scanner.find("neo")["available"], "10 с без событий → недоступно")
	assert_false(_cm.scanner.find("hrm")["available"])
	_adv("hrm", "HRM", ["180D"])
	assert_true(_cm.scanner.find("hrm")["available"], "реклама возвращает доступность")
	assert_false(_cm.scanner.find("neo")["available"])
	_cm.tick(19.9)
	assert_true(_cm.scanner.has("neo"), "29.9 с — строка ещё есть")
	_cm.tick(0.1)
	assert_false(_cm.scanner.has("neo"), "30 с без событий → строка удалена")
	assert_true(_cm.scanner.has("hrm"), "второе устройство (видели 20 с назад) остаётся")
	assert_false(_cm.scanner.find("hrm")["available"])


func test_req_dev_01_c4_scan_stops_on_connect_when_nobody_else_expected() -> void:
	_cm.start_scan()
	_adv("neo", "Neo", ["1826"])
	_cm.connect_trainer("neo")
	assert_true(_cm.scanner.is_scanning(), "пока только CONNECTING — сканирование идёт")
	_bridge.pump()
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.CONNECTED)
	assert_false(_cm.scanner.is_scanning(), "при подключении сканирование остановлено")
	assert_eq(_bridge.calls_of("stop_scan").size(), 1, "stop_scan() ушёл на мост")


func test_req_dev_01_c4_scan_continues_while_auto_connect_still_waits_for_others() -> void:
	_remembered.remember(A, RememberedDevices.make_device("neo", "Neo", RememberedDevices.KIND_TRAINER))
	_remembered.remember(A, RememberedDevices.make_device("hrm", "HRM", RememberedDevices.KIND_HR))
	_cm.auto_connect(A)
	assert_true(_cm.scanner.is_scanning())
	_adv("neo", "Neo", ["1826"])
	_bridge.pump()
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.CONNECTED)
	assert_true(_cm.scanner.is_scanning(), "ждём ещё датчик — сканирование продолжается")
	_adv("hrm", "HRM", ["180D"])
	_bridge.pump()
	assert_eq(_cm.state_of("hrm"), TrainerDevice.ConnectionState.CONNECTED)
	assert_false(_cm.scanner.is_scanning(), "все запомненные подключены — сканирование остановлено")
	assert_false(_cm.is_auto_connecting())


# ===========================================================================
# REQ-DEV-06 — запоминание и автоподключение
# ===========================================================================

func test_req_dev_06_c1_trainer_remembered_only_after_connected_as_shared_device() -> void:
	_cm.start_scan()
	_adv("neo", "Tacx Neo", ["1826"])
	_cm.connect_trainer("neo")
	assert_false(_remembered.has_trainer(), "до CONNECTED не запоминается")
	assert_eq(_connects_to("neo"), 1, "connect_peripheral(neo)")
	_bridge.pump()
	assert_true(_remembered.has_trainer())
	var t := _remembered.trainer()
	assert_eq(t["id"], "neo")
	assert_eq(t["name"], "Tacx Neo", "имя — из рекламы")
	assert_eq(t["kind"], RememberedDevices.KIND_TRAINER)
	assert_true(FileAccess.file_exists(_remembered.trainer_file_path()), "станок — на устройстве (общий файл)")
	assert_false(_remembered.has_profile_devices(A), "в файл датчиков профиля станок не пишется")
	assert_eq(_remembered.list(B)[0]["id"], "neo", "общий станок виден и в профиле B")


func test_req_dev_06_c1_sensor_remembered_in_profile_file_only() -> void:
	_cm.start_scan()
	_adv("hrm", "Polar H10", ["180D"])
	_cm.connect_sensor("hrm", RememberedDevices.KIND_HR)
	assert_eq(_remembered.sensors(A).size(), 0, "до CONNECTED не запоминается")
	_bridge.pump()
	assert_eq(_cm.state_of("hrm"), TrainerDevice.ConnectionState.CONNECTED)
	var sensors := _remembered.sensors(A)
	assert_eq(sensors.size(), 1)
	assert_eq(sensors[0]["id"], "hrm")
	assert_eq(sensors[0]["name"], "Polar H10")
	assert_eq(sensors[0]["kind"], RememberedDevices.KIND_HR)
	assert_true(_remembered.has_profile_devices(A), "датчик — в файле профиля")
	assert_eq(_remembered.sensors(B).size(), 0, "в профиле B датчика нет")
	assert_false(_remembered.has_trainer())
	assert_eq(_cm.hub.heart_rate_sensor, _cm.sensor(RememberedDevices.KIND_HR), "датчик подключён к хабу")


func test_req_dev_06_c1_edge_connect_trainer_unknown_id_connects_and_remembers_without_name() -> void:
	_cm.connect_trainer("never-advertised")
	assert_eq(_connects_to("never-advertised"), 1, "команда подключения уходит и без рекламы")
	_bridge.pump()
	assert_eq(_cm.state_of("never-advertised"), TrainerDevice.ConnectionState.CONNECTED)
	assert_true(_remembered.has_trainer())
	assert_eq(_remembered.trainer()["name"], "", "имени нет — пустое")
	_cm.connect_trainer("")
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1, "пустой id — ничего")


func test_req_dev_06_c2_auto_connect_connects_remembered_right_after_advert() -> void:
	_remembered.remember(A, RememberedDevices.make_device("neo", "Neo", RememberedDevices.KIND_TRAINER))
	_remembered.remember(A, RememberedDevices.make_device("hrm", "HRM", RememberedDevices.KIND_HR))
	_remembered.remember(A, RememberedDevices.make_device("csc", "CSC", RememberedDevices.KIND_CADENCE, false))
	_cm.auto_connect(A)
	assert_true(_cm.is_auto_connecting())
	assert_eq(_bridge.calls_of("start_scan").size(), 1, "автоподключение запускает сканирование")
	var pending := _cm.pending_auto_connect_ids()
	assert_true(pending.has("neo") and pending.has("hrm"))
	assert_false(pending.has("csc"), "auto_connect == false — не кандидат")
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 0, "до рекламы никого не подключаем")
	# Незапомненное устройство — не подключается.
	_adv("stranger", "Someone's Kickr", ["1826"])
	assert_eq(_connects_to("stranger"), 0, "незапомненное не подключается")
	# Запомненное — сразу после device_found, без действий пользователя.
	_adv("hrm", "HRM", ["180D"])
	assert_eq(_connects_to("hrm"), 1, "connect_peripheral(hrm) сразу после рекламы")
	_adv("neo", "Neo", ["1826"])
	assert_eq(_connects_to("neo"), 1)
	_adv("csc", "CSC", ["1816"])
	assert_eq(_connects_to("csc"), 0, "выключенное автоподключение — не подключается даже при рекламе")
	_bridge.pump()
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_cm.state_of("hrm"), TrainerDevice.ConnectionState.CONNECTED)
	assert_false(_cm.is_auto_connecting())
	assert_eq(_timed_out.size(), 0)
	# Повторная реклама подключённого — не вторая попытка.
	_adv("neo", "Neo", ["1826"])
	assert_eq(_connects_to("neo"), 1)


func test_req_dev_06_c2_auto_connect_uses_device_already_seen_by_scanner() -> void:
	_remembered.remember(A, RememberedDevices.make_device("neo", "Neo", RememberedDevices.KIND_TRAINER))
	_cm.start_scan()
	_adv("neo", "Neo", ["1826"])
	assert_eq(_connects_to("neo"), 0, "без автоподключения просто виден")
	_cm.auto_connect(A)
	assert_eq(_connects_to("neo"), 1, "уже видимое запомненное подключается сразу")
	_bridge.pump()
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.CONNECTED)
	assert_false(_cm.scanner.is_scanning(), "DEV-01 крит. 4: при подключении сканирование останавливается, кто бы его ни запустил")
	assert_false(_cm.is_auto_connecting())


func test_req_dev_06_c3_auto_connect_times_out_after_30s_without_advert() -> void:
	_remembered.remember(A, RememberedDevices.make_device("neo", "Neo", RememberedDevices.KIND_TRAINER))
	_remembered.remember(A, RememberedDevices.make_device("hrm", "HRM", RememberedDevices.KIND_HR))
	_cm.auto_connect(A)
	_adv("hrm", "HRM", ["180D"])
	_bridge.pump()
	for i in 299:
		_cm.tick(0.1)
	assert_true(_cm.is_auto_connecting(), "29.9 с — ещё ждём")
	assert_eq(_timed_out.size(), 0)
	_cm.tick(0.1)
	assert_eq(_timed_out.size(), 1, "30 с → сигнал «не найдено»")
	assert_eq(_timed_out[0], ["neo"] as Array[String], "в сигнале — только не найденные")
	assert_false(_cm.is_auto_connecting())
	assert_false(_cm.scanner.is_scanning(), "сканирование, запущенное автоподключением, остановлено")
	assert_eq(_cm.state_of("hrm"), TrainerDevice.ConnectionState.CONNECTED, "найденный остаётся подключённым")
	# Ручное подключение после таймаута возможно.
	_cm.connect_trainer("neo")
	_bridge.pump()
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.CONNECTED)
	_cm.tick(60.0)
	assert_eq(_timed_out.size(), 1, "повторного таймаута нет")


func test_req_dev_06_c3_edge_auto_connect_with_empty_registry_does_nothing() -> void:
	_cm.auto_connect(A)
	assert_false(_cm.is_auto_connecting())
	assert_eq(_bridge.calls_of("start_scan").size(), 0, "сканирование не запускается")
	_cm.tick(31.0)
	assert_eq(_timed_out.size(), 0, "без кандидатов таймаута нет")
	# Глобально выключено — тоже ничего.
	_remembered.remember(A, RememberedDevices.make_device("neo", "Neo", RememberedDevices.KIND_TRAINER))
	_cm.auto_connect_enabled = false
	_cm.auto_connect(A)
	assert_false(_cm.is_auto_connecting())
	assert_eq(_bridge.calls_of("start_scan").size(), 0)
	_cm.auto_connect_enabled = true
	_cm.auto_connect(A)
	assert_true(_cm.is_auto_connecting())
	_cm.cancel_auto_connect()
	assert_false(_cm.is_auto_connecting())
	assert_false(_cm.scanner.is_scanning())


func test_req_dev_06_c4_forget_disconnects_removes_and_blocks_auto_connect() -> void:
	_cm.start_scan()
	_adv("neo", "Neo", ["1826"])
	_cm.connect_trainer("neo")
	_bridge.pump()
	assert_true(_remembered.has_trainer())
	var removed := _cm.forget(A, "neo")
	assert_true(removed)
	_bridge.pump()
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.DISCONNECTED, "«забыть» отключает")
	assert_false(_remembered.has_trainer(), "и удаляет из реестра")
	assert_false(FileAccess.file_exists(_remembered.trainer_file_path()))
	_cm.auto_connect(A)
	assert_false(_cm.is_auto_connecting(), "кандидатов нет")
	_cm.start_scan()
	var before := _connects_to("neo")
	_adv("neo", "Neo", ["1826"])
	assert_eq(_connects_to("neo"), before, "после «забыть» реклама не ведёт к подключению")
	assert_false(_cm.forget(A, "neo"), "повторное «забыть» — нечего удалять")


func test_req_dev_06_c4_edge_forget_during_reconnecting_stops_attempts() -> void:
	_cm.connect_trainer("neo")
	_bridge.pump()
	_bridge.auto_connect = false
	_bridge.emit_disconnected("neo", BleBridge.DisconnectReason.LINK_LOSS)
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.RECONNECTING)
	var attempts := _bridge.calls_of("connect_peripheral").size()
	_cm.forget(A, "neo")
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_false(_remembered.has_trainer())
	_cm.tick(20.0)
	_bridge.pump()
	assert_eq(_bridge.calls_of("connect_peripheral").size(), attempts, "после «забыть» попыток переподключения нет")
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.DISCONNECTED)


func test_req_dev_06_c4_forget_sensor_only_from_its_profile() -> void:
	_cm.connect_sensor("hrm", RememberedDevices.KIND_HR)
	_bridge.pump()
	assert_eq(_remembered.sensors(A).size(), 1)
	assert_false(_cm.forget(B, "hrm"), "из чужого профиля не удаляется")
	assert_eq(_remembered.sensors(A).size(), 1)
	assert_true(_cm.forget(A, "hrm"))
	assert_eq(_remembered.sensors(A).size(), 0)
	_bridge.pump()
	assert_eq(_cm.state_of("hrm"), TrainerDevice.ConnectionState.DISCONNECTED)


# ===========================================================================
# REQ-DEV-07 — состояния и заряд через device_states()
# ===========================================================================

func test_req_dev_07_c1_device_states_follow_connection_events_for_trainer_and_sensor() -> void:
	assert_eq(_cm.device_states().size(), 0, "до команд подключения — пусто")
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.DISCONNECTED, "неизвестное — «не подключено»")
	_cm.connect_trainer("neo")
	_cm.connect_sensor("hrm", RememberedDevices.KIND_HR)
	var st := _cm.device_states()
	assert_eq(st["neo"]["state"], TrainerDevice.ConnectionState.CONNECTING)
	assert_eq(st["neo"]["kind"], RememberedDevices.KIND_TRAINER)
	assert_eq(st["hrm"]["state"], TrainerDevice.ConnectionState.CONNECTING)
	assert_eq(st["hrm"]["kind"], RememberedDevices.KIND_HR)
	assert_true(_state_events.has("neo") and _state_events.has("hrm"), "state_changed с id")
	_bridge.pump()
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_cm.state_of("hrm"), TrainerDevice.ConnectionState.CONNECTED)
	_state_events.clear()
	_bridge.emit_disconnected("neo", BleBridge.DisconnectReason.LINK_LOSS)
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.RECONNECTING, "обрыв → «переподключение»")
	assert_eq(_cm.state_of("hrm"), TrainerDevice.ConnectionState.CONNECTED, "датчик не затронут")
	assert_eq(_state_events, ["neo"] as Array[String])
	_bridge.pump()
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.CONNECTED)
	_cm.disconnect_device("hrm")
	_bridge.pump()
	assert_eq(_cm.state_of("hrm"), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.CONNECTED, "станок не затронут отключением датчика")


func test_req_dev_07_c2_battery_of_trainer_and_sensor_read_and_updated() -> void:
	_bridge.set_device_services("neo", {"1826": ["2AD2", "2AD9", "2ADA"], "180F": ["2A19"]})
	_bridge.set_device_services("hrm", {"180D": ["2A37"], "180F": ["2A19"]})
	_bridge.set_read_value("2A19", _hex("4D"))  # 77 %
	_cm.connect_trainer("neo")
	_cm.connect_sensor("hrm", RememberedDevices.KIND_HR)
	assert_eq(_cm.battery_of("neo"), -1, "до чтения — неизвестно")
	_bridge.pump()
	var reads := _bridge.calls_of("read_characteristic")
	var battery_reads := reads.filter(func(c: Dictionary) -> bool: return c["char"] == "2A19" and c["service"] == "180F")
	assert_eq(battery_reads.size(), 2, "read_characteristic(id, 180F, 2A19) для станка и датчика")
	assert_eq(_cm.battery_of("neo"), 77, "заряд станка")
	assert_eq(_cm.battery_of("hrm"), 77, "заряд датчика")
	assert_eq(_cm.device_states()["neo"]["battery"], 77)
	assert_eq(_cm.device_states()["hrm"]["battery"], 77)
	_state_events.clear()
	_bridge.emit_notification("neo", "2A19", _hex("30"))
	assert_eq(_cm.battery_of("neo"), 48, "обновление по нотификации Battery Level")
	assert_eq(_cm.battery_of("hrm"), 77, "датчик не затронут")
	assert_true(_state_events.has("neo"), "state_changed при смене заряда")
	_bridge.emit_notification("hrm", "2A19", _hex("0A"))
	assert_eq(_cm.battery_of("hrm"), 10)
	_bridge.emit_notification("hrm", "2A19", _hex("FF"))
	assert_eq(_cm.battery_of("hrm"), 10, "255 (зарезервировано) не принимается")


func test_req_dev_07_c3_no_battery_service_gives_minus_one_without_error() -> void:
	_bridge.set_device_services("neo", {"1826": ["2AD2", "2AD9", "2ADA", "2AD6"]})
	_bridge.set_device_services("csc", {"1816": ["2A5B"]})
	var errors: Array[int] = []
	_cm.trainer.error.connect(func(c: int, _m: String) -> void: errors.append(c))
	_cm.connect_trainer("neo")
	_cm.connect_sensor("csc", RememberedDevices.KIND_CADENCE)
	_bridge.pump()
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_cm.state_of("csc"), TrainerDevice.ConnectionState.CONNECTED)
	var battery_reads := _bridge.calls_of("read_characteristic").filter(func(c: Dictionary) -> bool: return c["char"] == "2A19")
	assert_eq(battery_reads.size(), 0, "без 180F чтение батареи не запрашивается")
	assert_eq(_cm.battery_of("neo"), -1, "«—»")
	assert_eq(_cm.battery_of("csc"), -1)
	assert_eq(_cm.device_states()["neo"]["battery"], -1)
	assert_eq(errors.size(), 0, "не ошибка")


# ===========================================================================
# REQ-DEV-02 крит. 1 — батарея станка в BleTrainer
# ===========================================================================

func test_req_dev_02_c1_ble_trainer_reads_and_subscribes_battery_when_180f_present() -> void:
	var bridge := StubBleBridge.new()
	var t := BleTrainer.new(bridge)
	var levels: Array[int] = []
	t.battery_level.connect(func(p: int) -> void: levels.append(p))
	bridge.set_device_services("neo", {"1826": ["2AD2", "2AD9", "2ADA"], "180F": ["2A19"]})
	bridge.set_read_value("2A19", _hex("5A"))
	assert_eq(t.battery_percent, -1)
	t.connect_device("neo")
	bridge.pump()
	assert_eq(t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	var reads := bridge.calls_of("read_characteristic")
	assert_eq(reads.size(), 1)
	assert_eq(reads[0]["service"], "180F")
	assert_eq(reads[0]["char"], "2A19")
	assert_true(bridge.is_subscribed("neo", "180F", "2A19"), "подписка на Battery Level")
	assert_eq(t.battery_percent, 90)
	assert_eq(levels, [90] as Array[int])
	bridge.emit_notification("neo", "2A19", _hex("2D"))
	assert_eq(t.battery_percent, 45)
	assert_eq(levels, [90, 45] as Array[int])
	# Подписки FTMS и Request Control при этом на месте.
	assert_true(bridge.is_subscribed("neo", "1826", "2AD2"))
	assert_true(bridge.is_subscribed("neo", "1826", "2ADA"))
	assert_true(bridge.is_subscribed("neo", "1826", "2AD9"))
	assert_eq(bridge.writes_to("2AD9").size(), 1)
	t.dispose()


func test_req_dev_02_c1_ble_trainer_without_180f_skips_battery_unknown_services_tolerates_missing() -> void:
	var bridge := StubBleBridge.new()
	var t := BleTrainer.new(bridge)
	var errors: Array[int] = []
	t.error.connect(func(c: int, _m: String) -> void: errors.append(c))
	bridge.set_device_services("neo", {"1826": ["2AD2", "2AD9", "2ADA"]})
	t.connect_device("neo")
	bridge.pump()
	assert_eq(bridge.calls_of("read_characteristic").size(), 0, "180F не заявлен — не читаем")
	assert_eq(t.battery_percent, -1)
	assert_false(bridge.is_subscribed("neo", "180F", "2A19"))
	t.dispose()
	# Список сервисов неизвестен — чтение пробуется, отсутствие характеристики — не ошибка.
	var bridge2 := StubBleBridge.new()
	var t2 := BleTrainer.new(bridge2)
	t2.error.connect(func(c: int, _m: String) -> void: errors.append(c))
	t2.connect_device("neo")
	bridge2.pump()
	assert_eq(t2.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	var battery_reads := bridge2.calls_of("read_characteristic").filter(func(c: Dictionary) -> bool: return c["char"] == "2A19")
	assert_eq(battery_reads.size(), 1)
	assert_eq(t2.battery_percent, -1)
	assert_eq(errors.size(), 0, "CHARACTERISTIC_NOT_FOUND по батарее — не ошибка станка")
	t2.dispose()


# ===========================================================================
# REQ-PRF-04 крит. 2, 3 — два профиля через менеджер
# ===========================================================================

func test_req_prf_04_c2_c3_sensor_private_to_profile_trainer_shared_for_auto_connect() -> void:
	_cm.start_scan()
	_adv("neo", "Neo", ["1826"])
	_adv("hrm", "HRM", ["180D"])
	_cm.connect_trainer("neo")
	_cm.connect_sensor("hrm", RememberedDevices.KIND_HR)
	_bridge.pump()
	assert_eq(_remembered.auto_connect_candidates(A).size(), 2, "в A — станок и датчик")
	var b_candidates := _remembered.auto_connect_candidates(B)
	assert_eq(b_candidates.size(), 1, "в B — только общий станок")
	assert_eq(b_candidates[0]["id"], "neo")
	# Переключаемся на профиль B (как новый запуск: список найденных пуст): автоподключение ждёт только станок.
	_cm.disconnect_all()
	_bridge.pump()
	_bridge.clear_calls()
	_cm.scanner.clear()
	_cm.set_profile(B)
	_cm.auto_connect(B)
	assert_eq(_cm.pending_auto_connect_ids(), ["neo"] as Array[String], "датчик профиля A в B не предлагается")
	_adv("hrm", "HRM", ["180D"])
	assert_eq(_connects_to("hrm"), 0, "датчик A в профиле B не подключается автоматически")
	_adv("neo", "Neo", ["1826"])
	assert_eq(_connects_to("neo"), 1, "общий станок автоподключается в B")
	_bridge.pump()
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.CONNECTED)
	# Подключение датчика в B запоминает его в B, не трогая A.
	_cm.connect_sensor("hrm2", RememberedDevices.KIND_HR)
	_bridge.pump()
	assert_eq(_remembered.sensors(B).size(), 1)
	assert_eq(_remembered.sensors(B)[0]["id"], "hrm2")
	assert_eq(_remembered.sensors(A).size(), 1)
	assert_eq(_remembered.sensors(A)[0]["id"], "hrm", "датчики A не изменились")
	# Обратно в A — оба кандидата.
	_cm.set_profile(A)
	assert_eq(_remembered.auto_connect_candidates(A).size(), 2)


# ===========================================================================
# Границы менеджера
# ===========================================================================

func test_manager_edge_dispose_twice_and_connect_other_trainer_disconnects_first() -> void:
	_cm.connect_trainer("neo")
	_bridge.pump()
	_cm.connect_trainer("kickr")
	assert_eq(_bridge.calls_of("disconnect_peripheral").size(), 1, "смена станка отключает прежний")
	assert_eq(_cm.trainer_id, "kickr")
	_bridge.pump()
	assert_eq(_cm.state_of("kickr"), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_cm.device_states().size(), 1, "в состояниях — только текущий станок")
	_cm.dispose()
	_cm.dispose()  # повторный dispose — без падения
	assert_null(_cm.trainer)
	assert_null(_cm.hub)
	assert_null(_cm.scanner)
	_cm = null


func test_manager_edge_dev_mode_fake_trainer_kind() -> void:
	var cm := ConnectionManager.new(_bridge, _remembered, TrainerFactory.KIND_FAKE)
	assert_true(cm.trainer is FakeTrainer, "режим разработки — эмулятор")
	cm.connect_trainer("fake")
	(cm.trainer as FakeTrainer).tick(1.0)
	assert_eq(cm.state_of("fake"), TrainerDevice.ConnectionState.CONNECTED)
	assert_true(_remembered.has_trainer(), "эмулятор тоже запоминается как станок")
	cm.dispose()


# ===========================================================================
# REQ-DEV-01 крит. 6 (статически) и REQ-NFR-06 крит. 2 — нативный каркас
# ===========================================================================

func _script_methods(script_path: String) -> Dictionary:
	var out: Dictionary = {}
	var script: Script = load(script_path)
	for m in script.get_script_method_list():
		var name: String = m["name"]
		if name.begins_with("_"):
			continue
		if (m["flags"] & METHOD_FLAG_STATIC) != 0:
			continue
		out[name] = (m["args"] as Array).size()
	return out


func _script_signals(script_path: String) -> Dictionary:
	var out: Dictionary = {}
	var script: Script = load(script_path)
	for s in script.get_script_signal_list():
		out[s["name"]] = (s["args"] as Array).size()
	return out


func test_req_dev_01_c6_native_ovosch_ble_binds_exactly_the_ble_bridge_contract() -> void:
	var cpp := FileAccess.get_file_as_string("res://native/ble/src/ovosch_ble.cpp")
	assert_gt(cpp.length(), 0, "native/ble/src/ovosch_ble.cpp читается")
	# Методы: D_METHOD("name", "arg", ...) → имя и число аргументов.
	var re_m := RegEx.create_from_string("D_METHOD\\(\"(\\w+)\"((?:\\s*,\\s*\"\\w+\")*)\\)")
	var native_methods: Dictionary = {}
	for m in re_m.search_all(cpp):
		var args_str: String = m.get_string(2)
		var n_args := 0
		if not args_str.strip_edges().is_empty():
			n_args = args_str.count("\"") / 2
		native_methods[m.get_string(1)] = n_args
	var contract := _script_methods("res://src/devices/ble/ble_bridge.gd")
	assert_gt(contract.size(), 8)
	for name in contract:
		assert_true(native_methods.has(name), "OvoschBle объявляет метод контракта %s" % name)
		if native_methods.has(name):
			assert_eq(native_methods[name], contract[name], "число аргументов %s совпадает" % name)
	for name in native_methods:
		assert_true(contract.has(name), "у OvoschBle нет методов вне контракта: %s" % name)
	# Сигналы: ADD_SIGNAL(MethodInfo("name", PropertyInfo(...), ...)).
	var native_signals: Dictionary = {}
	var re_s := RegEx.create_from_string("MethodInfo\\(\"(\\w+)\"")
	for s in re_s.search_all(cpp):
		var start := s.get_end()
		var depth := 1
		var i := start
		while i < cpp.length() and depth > 0:
			var ch := cpp[i]
			if ch == "(":
				depth += 1
			elif ch == ")":
				depth -= 1
			i += 1
		native_signals[s.get_string(1)] = cpp.substr(start, i - start).count("PropertyInfo(")
	var contract_signals := _script_signals("res://src/devices/ble/ble_bridge.gd")
	assert_gt(contract_signals.size(), 5)
	for name in contract_signals:
		assert_true(native_signals.has(name), "OvoschBle объявляет сигнал контракта %s" % name)
		if native_signals.has(name):
			assert_eq(native_signals[name], contract_signals[name], "число аргументов сигнала %s совпадает" % name)
	for name in native_signals:
		assert_true(contract_signals.has(name), "у OvoschBle нет сигналов вне контракта: %s" % name)
	for sig in NativeBleBridge.FORWARDED_SIGNALS:
		assert_true(native_signals.has(String(sig)), "пробрасываемый сигнал %s есть в нативном классе" % sig)
	# Регистрация класса и точка входа GDExtension.
	assert_true(cpp.contains("OvoschBle::_bind_methods"))
	var reg := FileAccess.get_file_as_string("res://native/ble/src/register_types.cpp")
	assert_true(reg.contains("OvoschBle"), "класс регистрируется")
	var ext := FileAccess.get_file_as_string("res://native/ble/ovosch_ble.gdextension")
	var re_entry := RegEx.create_from_string("entry_symbol\\s*=\\s*\"(\\w+)\"")
	var entry := re_entry.search(ext)
	assert_not_null(entry, "в .gdextension задан entry_symbol")
	if entry != null:
		assert_true(reg.contains(entry.get_string(1)), "entry_symbol %s определён в register_types.cpp" % entry.get_string(1))
	assert_true(ext.contains("macos.") and ext.contains("ios."), "библиотеки для macOS и iOS перечислены (сборка — вне контейнера)")
	assert_eq(String(NativeBleBridge.NATIVE_CLASS), "OvoschBle", "обёртка ищет тот же класс")


## Сторонние нативные зависимости (клон/симлинк godot-cpp разработчика): в репозитории их нет
## (`.gitignore`), в обход не входят — критерий касается только собственного кода.
const THIRD_PARTY_NATIVE_PREFIXES: Array[String] = ["res://native/godot-cpp/", "res://native/ble/godot-cpp/"]


func _is_third_party(path: String) -> bool:
	var p := path if path.ends_with("/") else path + "/"
	for prefix in THIRD_PARTY_NATIVE_PREFIXES:
		if p.begins_with(prefix):
			return true
	return false


func _collect_files(dir_path: String, exts: Array[String], out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.include_hidden = true
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			if name != ".git" and name != ".godot" and not _is_third_party(full) \
					and not dir.is_link(ProjectSettings.globalize_path(full)):
				_collect_files(full, exts, out)
		else:
			for e in exts:
				if name.to_lower().ends_with(e):
					out.append(full)
					break
		name = dir.get_next()
	dir.list_dir_end()


func test_req_nfr_06_c2_all_native_code_lives_in_native_ble() -> void:
	var exts: Array[String] = [".cpp", ".cc", ".cxx", ".c", ".h", ".hpp", ".mm", ".m", ".java", ".kt", ".swift"]
	var files: Array[String] = []
	_collect_files("res://", exts, files)
	var outside: Array[String] = []
	var inside := 0
	for f in files:
		if f.begins_with("res://native/ble/"):
			inside += 1
		else:
			outside.append(f)
	assert_eq(outside.size(), 0, "нативный код вне native/ble/: %s" % str(outside))
	assert_gt(inside, 3, "в native/ble/ есть исходники (%d файлов)" % inside)
	for required in ["res://native/ble/src/ovosch_ble.cpp", "res://native/ble/src/ovosch_ble.h",
			"res://native/ble/src/ble_backend.h", "res://native/ble/src/null_backend.cpp",
			"res://native/ble/SConstruct", "res://native/ble/ovosch_ble.gdextension", "res://native/ble/README.md"]:
		assert_true(FileAccess.file_exists(required), "есть %s" % required)
	var gitignore := FileAccess.get_file_as_string("res://.gitignore")
	assert_true(gitignore.contains("native/godot-cpp") and gitignore.contains("native/ble/godot-cpp"),
		"godot-cpp — сторонняя зависимость: оба её расположения исключены из репозитория через .gitignore")
	# Платформенных реализаций (CoreBluetooth и т.п.) в src/ нет; в контейнере класс не зарегистрирован.
	assert_false(ClassDB.class_exists("OvoschBle"), "в контейнере GDExtension не загружен (native/.gdignore)")
