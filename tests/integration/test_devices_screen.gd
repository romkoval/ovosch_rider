extends GutTest
## Интеграционные тесты экрана устройств (REQ-DEV-01 крит. 2–4, REQ-DEV-06 крит. 2–4,
## REQ-DEV-07 крит. 1–3): список обновляется по сигналам менеджера, кнопки вызывают менеджер.

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
	_dir = "user://test_devscreen_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_bridge = StubBleBridge.new()
	_remembered = RememberedDevices.new(_dir + "devices/")
	_repo = ProfileRepository.new(_dir + "profiles/")
	_profile = _repo.create("Rider")
	_state = AppState.new(_repo)
	_state.start()
	_cm = ConnectionManager.new(_bridge, _remembered)


func after_each() -> void:
	if _cm != null:
		_cm.dispose()
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


func test_initial_state_idle_and_lists_empty() -> void:
	var s := _screen()
	assert_eq(s.status_text(), "Not scanning")
	assert_eq(s.row_ids().size(), 0)
	assert_eq((s.get_node("%ScanButton") as Button).text, "Scan")
	assert_true((s.get_node("%AutoConnectCheck") as CheckButton).button_pressed)


func test_scan_button_toggles_scanning_and_found_rows_appear_by_signal() -> void:
	var s := _screen()
	(s.get_node("%ScanButton") as Button).pressed.emit()
	assert_true(_cm.scanner.is_scanning())
	assert_eq(s.status_text(), "Scanning for devices…")
	assert_eq((s.get_node("%ScanButton") as Button).text, "Stop scanning")
	_adv("neo", "Tacx Neo", ["1826"], -55)
	_adv("hrm", "", ["180D"], -70)
	assert_eq(s.row_ids().size(), 2, "REQ-DEV-01 крит. 2: строки появляются по device_found")
	assert_string_contains(s.row_text("neo"), "Tacx Neo")
	assert_string_contains(s.row_text("neo"), "trainer")
	assert_string_contains(s.row_text("neo"), "-55 dBm")
	assert_string_contains(s.row_text("neo"), "not connected")
	assert_string_contains(s.row_text("neo"), "battery —")
	assert_string_contains(s.row_text("hrm"), "Unnamed")
	assert_string_contains(s.row_text("hrm"), "heart rate")
	(s.get_node("%ScanButton") as Button).pressed.emit()
	assert_false(_cm.scanner.is_scanning(), "REQ-DEV-01 крит. 4")
	assert_eq(s.status_text(), "Not scanning")


func test_unavailable_marker_after_10s() -> void:
	var s := _screen()
	_cm.start_scan()
	_adv("neo", "Neo", ["1826"])
	_cm.tick(10.0)
	assert_string_contains(s.row_text("neo"), "unavailable", "REQ-DEV-01 крит. 3")
	_cm.tick(20.0)
	assert_eq(s.row_ids().size(), 0, "удалено через 30 с")


func test_connect_button_connects_and_row_moves_to_remembered_with_state_and_battery() -> void:
	var s := _screen()
	_bridge.set_device_services("neo", {"1826": ["2AD2", "2AD9", "2ADA"], "180F": ["2A19"]})
	_bridge.set_read_value("2A19", BatteryCodec.encode_level(77))
	_cm.start_scan()
	_adv("neo", "Tacx Neo", ["1826"])
	(s.row("neo")["connect_button"] as Button).pressed.emit()
	assert_eq(_cm.trainer_id, "neo", "кнопка вызвала менеджер")
	assert_string_contains(s.row_text("neo"), "connecting")
	_bridge.pump()
	assert_string_contains(s.row_text("neo"), "connected")
	assert_string_contains(s.row_text("neo"), "battery 77 %", "REQ-DEV-07 крит. 2")
	assert_not_null(s.row("neo")["forget_button"], "теперь это запомненное устройство")
	assert_eq((s.row("neo")["connect_button"] as Button).text, "Disconnect")
	assert_eq(s.get_node("%FoundList").get_child_count(), 0, "из найденных убрано")
	assert_eq(s.get_node("%RememberedList").get_child_count(), 1)


func test_disconnect_and_forget_buttons() -> void:
	var s := _screen()
	_cm.start_scan()
	_adv("neo", "Neo", ["1826"])
	(s.row("neo")["connect_button"] as Button).pressed.emit()
	_bridge.pump()
	(s.row("neo")["connect_button"] as Button).pressed.emit()
	_bridge.pump()
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.DISCONNECTED, "вторая кнопка — отключить")
	assert_string_contains(s.row_text("neo"), "not connected")
	assert_true(_remembered.has_trainer())
	(s.row("neo")["forget_button"] as Button).pressed.emit()
	assert_false(_remembered.has_trainer(), "REQ-DEV-06 крит. 4")
	assert_eq(s.get_node("%RememberedList").get_child_count(), 0, "из запомненных убрано")
	assert_null(s.row("neo")["forget_button"], "устройство всё ещё в эфире — осталось в найденных без «Забыть»")


func test_remembered_devices_listed_with_forget_and_unknown_kind_disabled() -> void:
	_remembered.set_trainer(RememberedDevices.make_device("neo", "Neo", RememberedDevices.KIND_TRAINER))
	_remembered.remember(_profile.id, RememberedDevices.make_device("hrm", "Polar", RememberedDevices.KIND_HR))
	var s := _screen()
	assert_eq(s.row_ids().size(), 2)
	assert_not_null(s.row("hrm")["forget_button"])
	assert_string_contains(s.row_text("hrm"), "Polar")
	_cm.start_scan()
	_adv("misc", "Thing", ["180F"])
	assert_true((s.row("misc")["connect_button"] as Button).disabled, "неизвестный тип подключить нельзя")
	assert_null(s.row("misc")["forget_button"])


func test_auto_connect_toggle_and_not_found_status() -> void:
	_remembered.set_trainer(RememberedDevices.make_device("neo", "Neo", RememberedDevices.KIND_TRAINER))
	var s := _screen()
	var check := s.get_node("%AutoConnectCheck") as CheckButton
	check.button_pressed = false
	assert_false(_cm.auto_connect_enabled)
	check.button_pressed = true
	assert_true(_cm.auto_connect_enabled)
	assert_true(_cm.is_auto_connecting(), "включение запускает автоподключение")
	assert_eq(s.status_text(), "Waiting for remembered devices: 1")
	_cm.tick(30.0)
	assert_eq(s.status_text(), "Device not found: Neo. Connect manually.", "REQ-DEV-06 крит. 3")
	(s.row("neo")["connect_button"] as Button).pressed.emit()
	assert_eq(_cm.trainer_id, "neo", "ручное подключение доступно")


func test_reconnecting_state_shown() -> void:
	var s := _screen()
	_cm.connect_trainer("neo")
	_bridge.pump()
	_bridge.auto_connect = false
	_bridge.emit_disconnected("neo", BleBridge.DisconnectReason.LINK_LOSS)
	assert_string_contains(s.row_text("neo"), "reconnecting", "REQ-DEV-07 крит. 1")


func test_back_navigates_home_and_main_builds_devices_screen() -> void:
	var s := _screen()
	_state.navigate(AppState.Screen.DEVICES)
	assert_eq(_state.current_screen, AppState.Screen.DEVICES)
	(s.get_node("%BackButton") as Button).pressed.emit()
	assert_eq(_state.current_screen, AppState.Screen.HOME)
	assert_eq(AppState.screen_name(AppState.Screen.DEVICES), "devices")


func test_ble_unavailable_shows_status_and_disables_scan_and_connect() -> void:
	_remembered.set_trainer(RememberedDevices.make_device("neo", "Neo", RememberedDevices.KIND_TRAINER))
	var s := _screen()
	assert_false((s.get_node("%ScanButton") as Button).disabled)
	_bridge.set_available(false)
	assert_eq(s.status_text(), "Bluetooth unavailable: native module not loaded or adapter is off", "REQ-DEV-01 крит. 7")
	assert_true((s.get_node("%ScanButton") as Button).disabled)
	assert_true((s.row("neo")["connect_button"] as Button).disabled, "подключение недоступно")
	(s.get_node("%ScanButton") as Button).pressed.emit()
	assert_false(_cm.scanner.is_scanning())
	_bridge.set_available(true)
	assert_eq(s.status_text(), "Not scanning")
	assert_false((s.get_node("%ScanButton") as Button).disabled)
	assert_false((s.row("neo")["connect_button"] as Button).disabled)


func test_back_stops_manual_scan_but_not_auto_connect_scan() -> void:
	var s := _screen()
	(s.get_node("%ScanButton") as Button).pressed.emit()
	assert_true(_cm.scanner.is_scanning())
	(s.get_node("%BackButton") as Button).pressed.emit()
	assert_false(_cm.scanner.is_scanning(), "REQ-DEV-01 крит. 4 / D-5")
	assert_eq(_bridge.calls_of("stop_scan").size(), 1)
	_remembered.set_trainer(RememberedDevices.make_device("neo", "Neo", RememberedDevices.KIND_TRAINER))
	_cm.auto_connect(_profile.id)
	assert_true(_cm.scanner.is_scanning())
	(s.get_node("%BackButton") as Button).pressed.emit()
	assert_true(_cm.scanner.is_scanning(), "сканирование автоподключения продолжается")


# ---------------------------------------------------------------------------
# Ревью: текст «Забыть» по языку, сброс списка «не найдено»
# ---------------------------------------------------------------------------

func test_forget_button_text_follows_locale_on_refresh() -> void:
	# LOW-6: текст кнопки «Забыть» обновляется при смене языка (main → refresh).
	_remembered.set_trainer(RememberedDevices.make_device("neo", "Neo", RememberedDevices.KIND_TRAINER))
	var s := _screen()
	var forget: Button = s.row("neo")["forget_button"]
	assert_eq(forget.text, "Forget")
	TranslationServer.set_locale("ru")
	s.refresh()
	assert_eq(forget.text, "Забыть")
	TranslationServer.set_locale("en")
	s.refresh()
	assert_eq(forget.text, "Forget")


## Таймаут автоподключения запомненного станка «Neo»: статус «не найдено».
func _timed_out_screen() -> DevicesScreen:
	_remembered.set_trainer(RememberedDevices.make_device("neo", "Neo", RememberedDevices.KIND_TRAINER))
	var s := _screen()
	s.set_auto_connect(true)
	_cm.tick(30.0)
	assert_eq(s.status_text(), "Device not found: Neo. Connect manually.")
	return s


func test_not_found_cleared_on_manual_scan() -> void:
	# LOW-7: новый поиск (сканирование) сбрасывает устаревший список «не найдено».
	var s := _timed_out_screen()
	(s.get_node("%ScanButton") as Button).pressed.emit()
	assert_eq(s.status_text(), "Scanning for devices…")
	(s.get_node("%ScanButton") as Button).pressed.emit()
	assert_eq(s.status_text(), "Not scanning")


func test_not_found_cleared_on_successful_connection() -> void:
	# LOW-7: устройство подключено — оно больше не «не найдено».
	var s := _timed_out_screen()
	(s.row("neo")["connect_button"] as Button).pressed.emit()
	_bridge.pump()
	assert_string_contains(s.row_text("neo"), "connected")
	assert_false(s.status_text().contains("not found"), "статус без устаревшего «не найдено»: " + s.status_text())


func test_not_found_cleared_by_new_auto_connect() -> void:
	# LOW-7: новое автоподключение (например, при выборе профиля в main) — список прежнего неактуален.
	var s := _timed_out_screen()
	_cm.auto_connect(_profile.id)
	s.refresh()
	assert_eq(s.status_text(), "Waiting for remembered devices: 1")
	_cm.cancel_auto_connect()
	s.refresh()
	assert_eq(s.status_text(), "Not scanning", "после отмены нового автоподключения — без прежнего списка")


func test_not_found_kept_when_entering_screen_after_timeout() -> void:
	# LOW-7 (решение менеджера): таймаут, истёкший на другом экране, виден при входе
	# на экран устройств (REQ-DEV-06 крит. 3).
	var s := _timed_out_screen()
	s.hide()
	s.show()
	s.refresh()
	assert_eq(s.status_text(), "Device not found: Neo. Connect manually.")


func test_not_found_cleared_on_profile_change() -> void:
	# LOW-7: «не найдено» профиля A не показывается профилю B.
	_remembered.remember(_profile.id, RememberedDevices.make_device("hrm", "Polar", RememberedDevices.KIND_HR))
	var s := _screen()
	s.set_auto_connect(true)
	_cm.tick(30.0)
	assert_eq(s.status_text(), "Device not found: Polar. Connect manually.")
	var other := _repo.create("Other")
	_repo.active_profile_id = other.id
	s.refresh()
	assert_eq(s.status_text(), "Not scanning")


func test_removed_row_is_freed_immediately_without_orphans() -> void:
	# Ревью инфраструктуры: отсоединённая строка освобождается сразу, а не через queue_free.
	_remembered.remember(_profile.id, RememberedDevices.make_device("hrm", "Polar", RememberedDevices.KIND_HR))
	_remembered.remember(_profile.id, RememberedDevices.make_device("cad", "Cadence", RememberedDevices.KIND_CADENCE))
	var s := _screen()
	var hbox: HBoxContainer = s.row("hrm")["hbox"]
	var orphans_before := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	s.forget_device("hrm")
	assert_eq(s.row("hrm"), {}, "строки нет")
	assert_false(is_instance_valid(hbox), "строка освобождена сразу")
	assert_eq(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), orphans_before, "без узлов-сирот")
	# Нажатие «Забыть» на самой строке: её кнопка ещё в обработке сигнала — освобождение
	# откладывается до конца кадра, без падения.
	var own: HBoxContainer = s.row("cad")["hbox"]
	(s.row("cad")["forget_button"] as Button).pressed.emit()
	assert_eq(s.row("cad"), {})
	await get_tree().process_frame
	assert_false(is_instance_valid(own), "строка освобождена к следующему кадру")
