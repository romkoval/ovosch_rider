extends GutTest
## Независимая приёмка экрана устройств (T-020, `src/ui/devices/devices_screen.tscn`):
## REQ-DEV-01 к2–4 (строки по сигналам, «Без имени», недоступность, остановка сканирования при уходе
## с экрана и при подключении), REQ-DEV-06 к2–4 (автоподключение, «не найдено», «забыть»),
## REQ-DEV-07 к1–3 (состояния и заряд на экране), REQ-PRF-04 к2–3 (два профиля на экране).

const SCENE: String = "res://src/ui/devices/devices_screen.tscn"

var _dir: String
var _bridge: StubBleBridge
var _remembered: RememberedDevices
var _repo: ProfileRepository
var _state: AppState
var _cm: ConnectionManager
var _profile: Profile


func before_each() -> void:
	TranslationServer.set_locale("en")
	_dir = "user://test_devscreen_acc_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_bridge = StubBleBridge.new()
	_remembered = RememberedDevices.new(_dir + "devices/")
	_repo = ProfileRepository.new(_dir + "profiles/")
	_profile = _repo.create("Rider")
	_state = AppState.new(_repo)
	_state.start()
	_cm = ConnectionManager.new(_bridge, _remembered)
	_cm.set_profile(_profile.id)


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


func _screen() -> DevicesScreen:
	var s: DevicesScreen = load(SCENE).instantiate()
	s.setup(_cm, _repo, _state)
	add_child_autofree(s)
	return s


func _adv(id: String, name: String, services: Array, rssi: int = -60) -> void:
	_bridge.emit_device_found(id, name, rssi, PackedStringArray(services))


func _hex(s: String) -> PackedByteArray:
	var clean := s.replace(" ", "")
	var out := PackedByteArray()
	var i := 0
	while i + 1 < clean.length():
		out.append(("0x" + clean.substr(i, 2)).hex_to_int())
		i += 2
	return out


func _button(s: DevicesScreen, unique_name: String) -> Button:
	return s.get_node("%" + unique_name) as Button


# ---------------------------------------------------------------------------
# REQ-DEV-01 крит. 2, 3 — строки списка
# ---------------------------------------------------------------------------

func test_req_dev_01_c2_rows_appear_and_update_by_device_found_with_name_rssi_kind() -> void:
	var s := _screen()
	assert_eq(s.row_ids().size(), 0)
	_cm.start_scan()
	_adv("neo", "Tacx Neo", ["1826"], -55)
	assert_eq(s.row_ids(), ["neo"] as Array[String], "строка появилась по device_found без ручного refresh")
	var text := s.row_text("neo")
	assert_string_contains(text, "Tacx Neo")
	assert_string_contains(text, "trainer")
	assert_string_contains(text, "-55 dBm")
	assert_string_contains(text, "not connected")
	assert_string_contains(text, "battery —")
	assert_eq(s.get_node("%FoundList").get_child_count(), 1, "найденное — в списке найденных")
	assert_eq(s.get_node("%RememberedList").get_child_count(), 0)
	assert_null(s.row("neo")["forget_button"], "у незапомненного нет «Забыть»")
	assert_eq((s.row("neo")["connect_button"] as Button).text, "Connect")
	# Повторная реклама обновляет строку, не добавляет.
	_adv("neo", "Tacx Neo", ["1826"], -40)
	assert_eq(s.row_ids().size(), 1)
	assert_string_contains(s.row_text("neo"), "-40 dBm", "RSSI обновлён")
	# Типы.
	_adv("hrm", "Polar", ["180D"])
	_adv("csc", "RPM", ["1816"])
	_adv("pm", "Assioma", ["1818"])
	assert_eq(s.row_ids().size(), 4)
	assert_string_contains(s.row_text("hrm"), "heart rate")
	assert_string_contains(s.row_text("csc"), "cadence")
	assert_string_contains(s.row_text("pm"), "power meter")
	assert_eq(s.get_node("%FoundList").get_child(0).name, "Row_neo", "станок — первым")


func test_req_dev_01_c2_edge_unnamed_two_kinds_unknown_kind_disabled() -> void:
	var s := _screen()
	_cm.start_scan()
	_adv("x1", "", ["180D"])
	assert_string_contains(s.row_text("x1"), "Unnamed", "без имени — «Без имени»")
	_adv("x1", "HRM Pro", ["180D"])
	assert_string_contains(s.row_text("x1"), "HRM Pro")
	_adv("combo", "Kickr", ["180D", "1826"])
	assert_string_contains(s.row_text("combo"), "trainer", "два типа — станок")
	_adv("odd", "Odd", ["180A"])
	assert_string_contains(s.row_text("odd"), "unknown")
	assert_true((s.row("odd")["connect_button"] as Button).disabled, "неизвестный тип — подключить нельзя")
	assert_false((s.row("combo")["connect_button"] as Button).disabled)


func test_req_dev_01_c3_unavailable_after_10s_and_row_removed_after_30s() -> void:
	var s := _screen()
	_cm.start_scan()
	_adv("neo", "Neo", ["1826"])
	_cm.tick(9.9)
	assert_false(s.row_text("neo").contains("unavailable"))
	_cm.tick(0.1)
	assert_string_contains(s.row_text("neo"), "unavailable", "10 с без событий — пометка")
	_adv("neo", "Neo", ["1826"])
	assert_false(s.row_text("neo").contains("unavailable"), "реклама снимает пометку")
	_cm.tick(30.0)
	assert_eq(s.row_ids().size(), 0, "30 с — строка удалена")
	assert_eq(s.get_node("%FoundList").get_child_count(), 0, "узел строки убран")


# ---------------------------------------------------------------------------
# REQ-DEV-01 крит. 4 — остановка сканирования
# ---------------------------------------------------------------------------

func test_req_dev_01_c4_scan_button_toggles_and_connect_stops_scan() -> void:
	var s := _screen()
	_button(s, "ScanButton").pressed.emit()
	assert_true(_cm.scanner.is_scanning())
	assert_eq(_button(s, "ScanButton").text, "Stop scanning")
	assert_eq(s.status_text(), "Scanning for devices…")
	_adv("neo", "Neo", ["1826"])
	(s.row("neo")["connect_button"] as Button).pressed.emit()
	_bridge.pump()
	assert_false(_cm.scanner.is_scanning(), "при подключении сканирование остановлено")
	assert_eq(_bridge.calls_of("stop_scan").size(), 1)
	assert_eq(_button(s, "ScanButton").text, "Scan", "кнопка отражает остановку")
	assert_eq(s.status_text(), "Not scanning")
	_button(s, "ScanButton").pressed.emit()
	assert_true(_cm.scanner.is_scanning())
	_button(s, "ScanButton").pressed.emit()
	assert_false(_cm.scanner.is_scanning(), "кнопка останавливает")


func test_req_dev_01_c4_leaving_devices_screen_stops_scan() -> void:
	var s := _screen()
	assert_true(_state.navigate(AppState.Screen.DEVICES), "открыт экран устройств")
	_button(s, "ScanButton").pressed.emit()
	assert_true(_cm.scanner.is_scanning())
	_button(s, "BackButton").pressed.emit()
	assert_eq(_state.current_screen, AppState.Screen.HOME, "возврат на главный")
	assert_false(_cm.scanner.is_scanning(), "уход с экрана устройств останавливает сканирование")
	assert_eq(_bridge.calls_of("stop_scan").size(), 1, "stop_scan() ушёл на мост")


# ---------------------------------------------------------------------------
# REQ-DEV-07 крит. 1–3 и REQ-DEV-06 крит. 1 — подключение с экрана
# ---------------------------------------------------------------------------

func test_req_dev_07_c1_c2_connect_button_shows_states_and_battery_row_moves_to_remembered() -> void:
	var s := _screen()
	_bridge.set_device_services("neo", {"1826": ["2AD2", "2AD9", "2ADA"], "180F": ["2A19"]})
	_bridge.set_read_value("2A19", _hex("4D"))
	_cm.start_scan()
	_adv("neo", "Tacx Neo", ["1826"])
	(s.row("neo")["connect_button"] as Button).pressed.emit()
	assert_eq(_cm.trainer_id, "neo", "кнопка вызвала менеджер")
	assert_string_contains(s.row_text("neo"), "connecting", "состояние «подключение»")
	_bridge.pump()
	assert_string_contains(s.row_text("neo"), "connected")
	assert_string_contains(s.row_text("neo"), "battery 77 %", "заряд станка")
	assert_eq((s.row("neo")["connect_button"] as Button).text, "Disconnect")
	assert_not_null(s.row("neo")["forget_button"], "запомнено — есть «Забыть»")
	assert_eq(s.get_node("%RememberedList").get_child_count(), 1, "строка переехала в запомненные")
	assert_eq(s.get_node("%FoundList").get_child_count(), 0)
	assert_true(_remembered.has_trainer(), "REQ-DEV-06 крит. 1")
	_bridge.emit_notification("neo", "2A19", _hex("30"))
	assert_string_contains(s.row_text("neo"), "battery 48 %", "заряд обновился по нотификации")
	_bridge.emit_disconnected("neo", BleBridge.DisconnectReason.LINK_LOSS)
	assert_string_contains(s.row_text("neo"), "reconnecting", "состояние «переподключение»")
	_bridge.pump()
	assert_string_contains(s.row_text("neo"), "connected")


func test_req_dev_07_c3_sensor_without_battery_shows_dash_and_sensor_row_in_remembered() -> void:
	var s := _screen()
	_bridge.set_device_services("hrm", {"180D": ["2A37"]})
	_cm.start_scan()
	_adv("hrm", "Polar H10", ["180D"])
	(s.row("hrm")["connect_button"] as Button).pressed.emit()
	_bridge.pump()
	assert_string_contains(s.row_text("hrm"), "connected")
	assert_string_contains(s.row_text("hrm"), "battery —", "нет Battery Service — «—»")
	assert_string_contains(s.row_text("hrm"), "heart rate")
	assert_eq(s.get_node("%RememberedList").get_child_count(), 1)
	assert_eq(_remembered.sensors(_profile.id).size(), 1, "датчик запомнен в профиле")


# ---------------------------------------------------------------------------
# REQ-DEV-06 крит. 2–4 — автоподключение, «не найдено», «забыть»
# ---------------------------------------------------------------------------

func test_req_dev_06_c2_c3_auto_connect_toggle_status_timeout_and_manual_connect() -> void:
	_remembered.remember(_profile.id, RememberedDevices.make_device("neo", "Tacx Neo", RememberedDevices.KIND_TRAINER))
	_remembered.remember(_profile.id, RememberedDevices.make_device("hrm", "Polar", RememberedDevices.KIND_HR))
	var s := _screen()
	assert_eq(s.get_node("%RememberedList").get_child_count(), 2, "запомненные показаны сразу")
	assert_true(_button(s, "AutoConnectCheck").button_pressed, "автоподключение включено по умолчанию")
	# Включение переключателя запускает автоподключение.
	(s.get_node("%AutoConnectCheck") as CheckButton).toggled.emit(true)
	assert_true(_cm.is_auto_connecting())
	assert_eq(s.status_text(), "Waiting for remembered devices: 2")
	_adv("hrm", "Polar", ["180D"])
	_bridge.pump()
	assert_string_contains(s.row_text("hrm"), "connected", "запомненный подключился по рекламе без действий")
	assert_eq(s.status_text(), "Waiting for remembered devices: 1")
	_cm.tick(30.0)
	assert_eq(s.status_text(), "Device not found: Tacx Neo. Connect manually.", "таймаут 30 с → сообщение с именем")
	assert_false(_cm.is_auto_connecting())
	# Ручное подключение с экрана после таймаута.
	(s.row("neo")["connect_button"] as Button).pressed.emit()
	_bridge.pump()
	assert_string_contains(s.row_text("neo"), "connected")
	# Выключение переключателя отменяет автоподключение.
	_bridge.emit_disconnected("neo", BleBridge.DisconnectReason.REQUESTED)
	_cm.disconnect_all()
	_bridge.pump()
	(s.get_node("%AutoConnectCheck") as CheckButton).toggled.emit(false)
	assert_false(_cm.auto_connect_enabled)
	assert_false(_cm.is_auto_connecting())
	_adv("neo", "Tacx Neo", ["1826"])
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.DISCONNECTED, "при выключенном автоподключении — не подключается")


func test_req_dev_06_c4_forget_button_disconnects_removes_and_blocks_auto_connect() -> void:
	var s := _screen()
	_cm.start_scan()
	_adv("neo", "Neo", ["1826"])
	(s.row("neo")["connect_button"] as Button).pressed.emit()
	_bridge.pump()
	assert_true(_remembered.has_trainer())
	(s.row("neo")["forget_button"] as Button).pressed.emit()
	_bridge.pump()
	assert_false(_remembered.has_trainer(), "удалено из реестра")
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.DISCONNECTED, "отключено")
	assert_eq(s.get_node("%RememberedList").get_child_count(), 0)
	assert_true(s.row_ids().has("neo"), "устройство ещё в эфире — осталось среди найденных")
	assert_null(s.row("neo")["forget_button"])
	assert_string_contains(s.row_text("neo"), "not connected")
	(s.get_node("%AutoConnectCheck") as CheckButton).toggled.emit(true)
	assert_false(_cm.is_auto_connecting(), "забытое не предлагается к автоподключению")
	_adv("neo", "Neo", ["1826"])
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.DISCONNECTED)


# ---------------------------------------------------------------------------
# REQ-PRF-04 крит. 2, 3 — два профиля на экране
# ---------------------------------------------------------------------------

func test_req_prf_04_c2_c3_second_profile_sees_shared_trainer_but_not_sensor() -> void:
	var s := _screen()
	_cm.start_scan()
	_adv("neo", "Neo", ["1826"])
	_adv("hrm", "Polar", ["180D"])
	(s.row("neo")["connect_button"] as Button).pressed.emit()
	(s.row("hrm")["connect_button"] as Button).pressed.emit()
	_bridge.pump()
	assert_eq(s.get_node("%RememberedList").get_child_count(), 2, "в профиле A запомнены оба")
	var b := _repo.create("Second")
	_state.select_profile(b.id)
	_cm.set_profile(b.id)
	s.refresh()
	assert_eq(s.profile_id(), b.id)
	var remembered_rows: Array[String] = []
	for child in s.get_node("%RememberedList").get_children():
		remembered_rows.append(child.name)
	assert_eq(remembered_rows, ["Row_neo"] as Array[String], "в профиле B запомнен только общий станок")
	assert_true(s.row_ids().has("hrm"), "датчик A виден лишь как найденный")
	assert_null(s.row("hrm")["forget_button"], "без «Забыть» — он не запомнен в B")
	_state.select_profile(_profile.id)
	_cm.set_profile(_profile.id)
	s.refresh()
	assert_eq(s.get_node("%RememberedList").get_child_count(), 2, "обратно в A — снова оба")


# ---------------------------------------------------------------------------
# Границы экрана
# ---------------------------------------------------------------------------

func test_screen_without_manager_is_inert() -> void:
	var s: DevicesScreen = load(SCENE).instantiate()
	add_child_autofree(s)
	assert_eq(s.row_ids().size(), 0)
	s.toggle_scan()
	s.set_auto_connect(true)
	s.set_auto_connect(false)
	s.connect_device({"id": "neo", "kind": "trainer"})
	s.forget_device("neo")
	s.refresh()
	s.back()
	assert_eq(s.profile_id(), "", "без репозитория — пустой профиль")
	assert_eq(s.row_ids().size(), 0, "ничего не упало, строк нет")
	_button(s, "ScanButton").pressed.emit()
	assert_eq(s.row_ids().size(), 0)


func test_screen_back_navigates_home_and_rebind_to_other_manager() -> void:
	var s := _screen()
	_state.navigate(AppState.Screen.DEVICES)
	s.back()
	assert_eq(_state.current_screen, AppState.Screen.HOME)
	# Повторный setup с другим менеджером — обработчики переключаются, старый не влияет.
	var bridge2 := StubBleBridge.new()
	var remembered2 := RememberedDevices.new(_dir + "devices2/")
	var cm2 := ConnectionManager.new(bridge2, remembered2)
	cm2.set_profile(_profile.id)
	s.setup(cm2, _repo, _state)
	_cm.start_scan()
	_adv("old", "Old", ["1826"])
	assert_false(s.row_ids().has("old"), "реклама у прежнего менеджера экран не трогает")
	cm2.start_scan()
	bridge2.emit_device_found("new", "New", -50, PackedStringArray(["1826"]))
	assert_true(s.row_ids().has("new"))
	cm2.dispose()
