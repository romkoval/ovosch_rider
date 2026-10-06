extends GutTest
## T-165: экран «BLE-отладка» в оболочке (инструмент для REQ-DEV-01, REQ-DEV-02, REQ-DEV-03,
## REQ-DEV-07). Release-сборка имитируется `AppMain.debug_build = false`:
## - строка «BLE-отладка» скрыта до пятого нажатия на «Версию» и доступна в release;
## - «Открыть» показывает экран поверх настроек на общем мосту приложения;
## - пока экран открыт, сканирование `ConnectionManager` остановлено, при закрытии — возвращено;
## - скан без фильтра → устройство → подключение → дерево → пресет — через кнопки экрана;
## - «Назад» оболочки (Esc) закрывает экран, а не уходит с настроек.

const MAIN_SCENE: String = "res://src/app/main.tscn"
const NEO: String = "NEO-ID"
const FEC_SERVICE: String = "6E40FEC1-B5A3-F393-E0A9-E50E24DCCA9E"
const FEC_NOTIFY: String = "6E40FEC2-B5A3-F393-E0A9-E50E24DCCA9E"
const FEC_WRITE: String = "6E40FEC3-B5A3-F393-E0A9-E50E24DCCA9E"

var _dir: String
var _previous_locale: String


func before_each() -> void:
	_dir = "user://test_ble_debug_screen_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_each() -> void:
	DiagLog.uninstall()
	TranslationServer.set_locale(_previous_locale)
	_remove_tree(ProjectSettings.globalize_path(_dir))


static func _remove_tree(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	var d := DirAccess.open(abs_path)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(abs_path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(abs_path.path_join(sub))
	DirAccess.remove_absolute(abs_path)


func _main() -> AppMain:
	var repo := ProfileRepository.new(_dir + "profiles/")
	if repo.list().is_empty():
		repo.create("Solo")
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.debug_build = false
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	main.env_reader = Callable()
	add_child_autofree(main)
	return main


static func _click() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	return e


func _tap_version(main: AppMain, taps: int) -> AboutDiagnostics:
	var settings := main.settings_screen()
	var version_row := (settings.get_node("%VersionLabel") as Control).get_parent() as Control
	for i in taps:
		version_row.gui_input.emit(_click())
	return settings.diagnostics()


## Мост приложения в тестах — заглушка без нативного модуля; включаем её, как будто адаптер есть.
func _stub(main: AppMain) -> StubBleBridge:
	var stub := main.bridge as StubBleBridge
	stub.set_available(true)
	return stub


func _open(main: AppMain) -> BleDebugScreen:
	assert_true(main.app_state.navigate(AppState.Screen.SETTINGS))
	var diag := _tap_version(main, AboutDiagnostics.UNLOCK_TAPS)
	diag.ble_debug_button().pressed.emit()
	return main.settings_screen().ble_debug_screen()


func test_row_hidden_until_fifth_tap_and_available_in_release() -> void:
	var main := _main()
	assert_false(main.debug_build, "имитация release-сборки")
	assert_true(main.app_state.navigate(AppState.Screen.SETTINGS))
	var diag := main.settings_screen().diagnostics()
	assert_false(diag.ble_debug_button().is_visible_in_tree(), "строка скрыта в обычном меню")
	_tap_version(main, AboutDiagnostics.UNLOCK_TAPS - 1)
	assert_false(diag.ble_debug_button().is_visible_in_tree(), "четырёх нажатий мало")
	_tap_version(main, 1)
	assert_true(diag.ble_debug_button().is_visible_in_tree(), "пятое нажатие открывает строку")
	assert_eq(diag.ble_debug_button().text, "Open")
	diag.ble_debug_button().pressed.emit()
	var screen := main.settings_screen().ble_debug_screen()
	assert_not_null(screen, "экран открыт")
	assert_true(screen.is_visible_in_tree(), "экран виден поверх настроек")
	var title := screen.get_node("Margin/Root/TopRow/Title") as Label
	assert_eq(String(title.tr(title.text)), "BLE debug", "заголовок переведён")


func test_screen_pauses_manager_scanning_and_restores_on_back() -> void:
	var main := _main()
	_stub(main)
	assert_true(main.connections.start_scan(), "ручной скан приложения идёт")
	var screen := _open(main)
	assert_true(screen.is_manager_suspended())
	assert_false(main.connections.scanner.is_scanning(), "скан менеджера остановлен на входе")
	assert_false(main.connections.auto_connect_enabled, "автоподключение на паузе")
	assert_true(main.handle_back(), "«Назад» оболочки обработан экраном")
	assert_null(main.settings_screen().ble_debug_screen(), "экран закрыт")
	assert_eq(main.app_state.current_screen, AppState.Screen.SETTINGS, "остались в настройках")
	assert_true(main.connections.scanner.is_scanning(), "скан менеджера возвращён")
	assert_true(main.connections.auto_connect_enabled, "автоподключение возвращено")


func test_scan_connect_tree_and_presets_through_screen_buttons() -> void:
	var main := _main()
	var stub := _stub(main)
	stub.set_device_services(NEO, {"180A": ["2A26"], "1818": ["2A63"], FEC_SERVICE: [FEC_NOTIFY, FEC_WRITE]})
	var screen := _open(main)
	stub.clear_calls()
	screen.scan_button().pressed.emit()
	assert_eq(Array(stub.calls_of("start_scan")[0]["service_uuids"]), [], "скан без фильтра")
	stub.emit_device_found(NEO, "Tacx Neo 11565", -50, PackedStringArray(["1816", "1818"]))
	assert_false(main.connections.scanner.has(NEO), "сканер приложения устройство не видит — он на паузе")
	screen.render_now()
	assert_eq(screen.device_list().item_count, 1)
	screen.device_list().select(0)
	screen.device_list().item_selected.emit(0)
	(screen.get_node("%ConnectButton") as Button).pressed.emit()
	stub.pump()
	screen.render_now()
	assert_eq(screen.link_text(), "Connected: Tacx Neo 11565")
	var root := screen.service_tree().get_root()
	assert_not_null(root)
	assert_eq(root.get_child_count(), 3, "три сервиса в дереве")
	screen.select_characteristic(FEC_SERVICE, FEC_NOTIFY)
	(screen.get_node("%SubscribeButton") as Button).pressed.emit()
	assert_true(stub.is_subscribed(NEO, FEC_SERVICE, FEC_NOTIFY))
	var page := BleDebugModel.fec_message(PackedByteArray([0x19, 1, 90, 0, 0, 0x96, 0, 0x30]), BleDebugModel.ANT_BROADCAST_DATA)
	stub.emit_notification(NEO, FEC_NOTIFY, page)
	screen.render_now()
	assert_string_contains(screen.value_text(), BleBytes.to_hex(page))
	assert_string_contains(screen.value_text(), "power 150 W")
	screen.preset_button(BleDebugModel.PRESET_FEC_TARGET_POWER_150).pressed.emit()
	var w := stub.writes_to(FEC_WRITE)
	assert_eq(w.size(), 1)
	assert_eq(BleBytes.to_hex(w[0]["bytes"]), "A4 09 4F 05 31 FF FF FF FF FF 58 02 73")
	(screen.get_node("%CopyLogButton") as Button).pressed.emit()
	screen.render_now()
	assert_string_contains(screen.log_view_text(), "services_discovered")
	screen.back_button().pressed.emit()
	assert_null(main.settings_screen().ble_debug_screen(), "«Назад» экрана закрывает его")
	assert_eq(stub.calls_of("disconnect_peripheral").size(), 1, "своё устройство отключено при выходе")
	assert_false(stub.scanning, "скан отладки остановлен")


func test_service_tree_keeps_room_for_characteristics_after_connect() -> void:
	# Владелец 2026-10-06: дерево сжималось до одной строки — пресеты и поле записи забирали
	# высоту колонки, характеристики FEC2/FEC3 нельзя было выбрать, «Subscribe» оставалась серой.
	var previous_size := get_tree().root.size
	get_tree().root.size = Vector2i(1000, 555)  # окно владельца (снимок 2000×1110 на Retina)
	var main := _main()
	var stub := _stub(main)
	stub.set_device_services(NEO, {"180A": ["2A29", "2A24", "2A25", "2A27", "2A26"], "1816": ["2A5B", "2A5C", "2A5D"],
			"1818": ["2A63", "2A65", "2A5D", "2A64", "2A66"], FEC_SERVICE: [FEC_NOTIFY, FEC_WRITE],
			"669AA501-0C08-969E-E211-86AD5062675F": ["669AAC01-0C08-969E-E211-86AD5062675F"]})
	var screen := _open(main)
	screen.scan_button().pressed.emit()
	stub.emit_device_found(NEO, "Tacx Neo 11565", -50, PackedStringArray(["1816", "1818", "180A", FEC_SERVICE]))
	screen.render_now()
	screen.device_list().select(0)
	screen.device_list().item_selected.emit(0)
	(screen.get_node("%ConnectButton") as Button).pressed.emit()
	stub.pump()
	screen.render_now()
	await wait_process_frames(3)
	var tree := screen.service_tree()
	assert_eq(tree.get_root().get_child_count(), 5, "пять сервисов Neo в дереве")
	assert_gte(tree.size.y, 300.0, "дерево не сжимается до одной строки: видны сервисы и характеристики")
	get_tree().root.size = previous_size
