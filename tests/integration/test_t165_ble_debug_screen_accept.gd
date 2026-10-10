extends GutTest
## Приёмка T-165 (tester): экран «BLE-отладка» в оболочке, п.6 и связанное с ним из п.3, п.5
## (инструмент для REQ-DEV-01, REQ-DEV-02, REQ-DEV-03, REQ-DEV-07; регрессия REQ-DEV-06,
## REQ-NFR-08). Release имитируется `debug_build = false`.
## - окно владельца 1000×555 (правка c4b463c): характеристика FEC2 выбирается щелчком в дереве,
##   «Подписаться» доступна и нажимается настоящим щелчком мыши; колонки не вылезают за окно (ru, en);
## - «с ответом» снят на экране — запись hex уходит без ответа;
## - автоподключение приложения (отложенное до готовности адаптера) на паузе и возвращается;
## - устройство, подключённое и приложением, при выходе не отключается;
## - DiagLog оболочки не содержит полного id устройства (п.5) — в том числе при подключении
##   к устройству, которое уже подключено приложением;
## - все строки `ui.ble_debug.*` есть на ru и en.

const MAIN_SCENE: String = "res://src/app/main.tscn"
const NEO: String = "8D2C61A0-ACC4-4165-9E0B-0000TACXNEO1"
const HRM: String = "1B7F0C3E-ACC4-4165-9E0B-0000000HRM01"
const FEC_SERVICE: String = "6E40FEC1-B5A3-F393-E0A9-E50E24DCCA9E"
const FEC_NOTIFY: String = "6E40FEC2-B5A3-F393-E0A9-E50E24DCCA9E"
const FEC_WRITE: String = "6E40FEC3-B5A3-F393-E0A9-E50E24DCCA9E"

var _dir: String
var _previous_locale: String
var _previous_size: Vector2i


func before_each() -> void:
	_dir = "user://test_t165_accept_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_previous_locale = TranslationServer.get_locale()
	_previous_size = get_tree().root.size
	TranslationServer.set_locale("en")


func after_each() -> void:
	get_tree().root.size = _previous_size
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


static func _click_event() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	return e


func _open(main: AppMain) -> BleDebugScreen:
	assert_true(main.app_state.navigate(AppState.Screen.SETTINGS))
	var settings := main.settings_screen()
	var version_row := (settings.get_node("%VersionLabel") as Control).get_parent() as Control
	for i in AboutDiagnostics.UNLOCK_TAPS:
		version_row.gui_input.emit(_click_event())
	settings.diagnostics().ble_debug_button().pressed.emit()
	return settings.ble_debug_screen()


func _neo_services() -> Dictionary:
	return {"180A": ["2A29", "2A24", "2A25", "2A27", "2A26"], "1816": ["2A5B", "2A5C", "2A5D"],
			"1818": ["2A63", "2A65", "2A5D", "2A64", "2A66"], FEC_SERVICE: [FEC_NOTIFY, FEC_WRITE],
			"669AA501-0C08-969E-E211-86AD5062675F": ["669AAC01-0C08-969E-E211-86AD5062675F"]}


func _connect_neo_via_screen(screen: BleDebugScreen, stub: StubBleBridge) -> void:
	screen.scan_button().pressed.emit()
	stub.emit_device_found(NEO, "Tacx Neo 11565", -50, PackedStringArray(["1816", "1818", "180A", FEC_SERVICE]))
	screen.render_now()
	screen.device_list().select(0)
	screen.device_list().item_selected.emit(0)
	(screen.get_node("%ConnectButton") as Button).pressed.emit()
	stub.pump()
	screen.render_now()


func _find_item(tree: Tree, char_uuid: String) -> TreeItem:
	var stack: Array[TreeItem] = [tree.get_root()]
	while not stack.is_empty():
		var it: TreeItem = stack.pop_back()
		var meta: Variant = it.get_metadata(0)
		if meta is Dictionary and str((meta as Dictionary).get("char", "")) == char_uuid:
			return it
		for ch in it.get_children():
			stack.append(ch)
	return null


func _mouse_click(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	get_viewport().push_input(motion, true)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		get_viewport().push_input(e, true)
		await wait_process_frames(1)


func _owner_window_subscribe_case(locale: String) -> void:
	TranslationServer.set_locale(locale)
	get_tree().root.size = Vector2i(1000, 555)
	var main := _main()
	var stub := main.bridge as StubBleBridge
	stub.set_available(true)
	stub.set_device_services(NEO, _neo_services())
	var screen := _open(main)
	await wait_process_frames(3)
	_connect_neo_via_screen(screen, stub)
	await wait_process_frames(3)
	var window := screen.get_viewport_rect()
	for col in ["Margin/Root/Body/DevicesColumn", "Margin/Root/Body/ServicesScroll", "Margin/Root/Body/LogColumn"]:
		var r := (screen.get_node(col) as Control).get_global_rect()
		assert_true(window.grow(0.5).encloses(r), "%s: колонка %s %s внутри окна %s" % [locale, col, r, window])
	# Щелчок по FEC2 в дереве: строка видна в дереве и выбирается мышью.
	var tree := screen.service_tree()
	var item := _find_item(tree, FEC_NOTIFY)
	assert_not_null(item, "FEC2 в дереве")
	tree.scroll_to_item(item)
	await wait_process_frames(2)
	var item_rect := tree.get_item_area_rect(item)
	var at := tree.get_global_rect().position + item_rect.position + Vector2(30, item_rect.size.y * 0.5)
	assert_true(tree.get_global_rect().has_point(at), "%s: строка FEC2 видна в дереве" % locale)
	await _mouse_click(at)
	screen.render_now()
	var sub := screen.get_node("%SubscribeButton") as Button
	assert_false(sub.disabled, "%s: после выбора FEC2 щелчком «Подписаться» активна" % locale)
	var scroll := screen.get_node("Margin/Root/Body/ServicesScroll") as ScrollContainer
	scroll.ensure_control_visible(sub)
	await wait_process_frames(2)
	var sr := sub.get_global_rect()
	assert_true(window.encloses(sr), "%s: «Подписаться» %s в окне %s (с прокруткой колонки)" % [locale, sr, window])
	assert_true(scroll.get_global_rect().encloses(sr), "%s: «Подписаться» в видимой части колонки" % locale)
	await _mouse_click(sr.get_center())
	assert_true(stub.is_subscribed(NEO, FEC_SERVICE, FEC_NOTIFY), "%s: щелчок по «Подписаться» подписал FEC2" % locale)
	assert_gte(tree.size.y, 300.0, "%s: дерево не схлопнулось" % locale)


func test_owner_window_1000x555_fec2_select_and_subscribe_by_mouse_en() -> void:
	await _owner_window_subscribe_case("en")


func test_owner_window_1000x555_fec2_select_and_subscribe_by_mouse_ru() -> void:
	await _owner_window_subscribe_case("ru")


func test_write_without_response_when_toggle_is_off() -> void:
	var main := _main()
	var stub := main.bridge as StubBleBridge
	stub.set_available(true)
	stub.set_device_services(NEO, _neo_services())
	var screen := _open(main)
	_connect_neo_via_screen(screen, stub)
	screen.select_characteristic(FEC_SERVICE, FEC_WRITE)
	screen.render_now()
	(screen.get_node("%ResponseCheck") as CheckButton).button_pressed = false
	(screen.get_node("%HexEdit") as LineEdit).text = "A4 09 4F 05 30 FF FF FF FF FF FF 50 7A"
	stub.clear_calls()
	(screen.get_node("%WriteButton") as Button).pressed.emit()
	var w := stub.writes_to(FEC_WRITE)
	assert_eq(w.size(), 1)
	assert_false(bool(w[0]["with_response"]), "«с ответом» снят — запись без ответа")
	(screen.get_node("%HexEdit") as LineEdit).text = "A4 0"
	(screen.get_node("%WriteButton") as Button).pressed.emit()
	assert_eq(stub.writes_to(FEC_WRITE).size(), 1, "нечётный hex не записан")
	screen.render_now()
	assert_ne((screen.get_node("%StatusLabel") as Label).text, "", "сообщение о неверном hex")


func test_deferred_auto_connect_paused_and_restored() -> void:
	var main := _main()
	var stub := main.bridge as StubBleBridge
	stub.set_available(false)
	main.connections.auto_connect(main.connections.profile_id)
	assert_true(main.connections.is_auto_connect_deferred(), "предусловие: автоподключение ждёт адаптер")
	var screen := _open(main)
	assert_false(main.connections.is_auto_connect_deferred(), "на паузе, пока экран открыт")
	assert_false(main.connections.auto_connect_enabled)
	screen.back_button().pressed.emit()
	assert_true(main.connections.auto_connect_enabled, "автоподключение возвращено")
	assert_true(main.connections.is_auto_connect_deferred(), "отложенное автоподключение возобновлено")


func test_device_connected_by_app_stays_connected_after_exit() -> void:
	var main := _main()
	var stub := main.bridge as StubBleBridge
	stub.set_available(true)
	stub.set_device_services(HRM, {"180D": ["2A37"], "180F": ["2A19"]})
	assert_true(main.connections.connect_sensor(HRM, RememberedDevices.KIND_HR))
	for i in 4:
		stub.pump()
	assert_true(main.connections.is_device_connected(HRM), "предусловие: пульсометр подключён приложением")
	var screen := _open(main)
	screen.scan_button().pressed.emit()
	stub.emit_device_found(HRM, "HRM Pro", -40, PackedStringArray(["180D"]))
	screen.render_now()
	screen.select_device(HRM)
	screen.connect_selected()
	for i in 4:
		stub.pump()
	stub.clear_calls()
	screen.back_button().pressed.emit()
	for i in 4:
		stub.pump()
	assert_eq(stub.calls_of("disconnect_peripheral").size(), 0, "общий линк не разорван")
	assert_true(main.connections.is_device_connected(HRM), "пульсометр приложения подключён после выхода")


func test_shell_diag_log_has_no_full_device_id() -> void:
	var main := _main()
	var stub := main.bridge as StubBleBridge
	stub.set_available(true)
	stub.set_device_services(HRM, {"180D": ["2A37"], "180F": ["2A19"]})
	stub.set_device_services(NEO, _neo_services())
	assert_true(main.connections.connect_sensor(HRM, RememberedDevices.KIND_HR))
	for i in 4:
		stub.pump()
	var screen := _open(main)
	_connect_neo_via_screen(screen, stub)
	screen.select_characteristic(FEC_SERVICE, FEC_NOTIFY)
	screen.toggle_subscription()
	screen.write_preset(BleDebugModel.PRESET_FEC_TARGET_POWER_150)
	stub.pump()
	# Устройство, которое уже подключено приложением, — тоже через экран.
	screen.disconnect_device()
	stub.pump()
	stub.emit_device_found(HRM, "HRM Pro", -40, PackedStringArray(["180D"]))
	screen.select_device(HRM)
	screen.connect_selected()
	for i in 4:
		stub.pump()
	screen.back_button().pressed.emit()
	stub.pump()
	assert_not_null(main.journal, "журнал оболочки открыт")
	var content := FileAccess.get_file_as_string(main.journal.file_path())
	assert_string_contains(content, "\"cat\":\"ble_debug\"")
	var leaked: Array[String] = []
	for line in content.split("\n"):
		if line.contains("ble_debug") and (line.contains(NEO) or line.contains(HRM)):
			leaked.append(line)
	for l in leaked:
		gut.p("утечка id: " + l)
	assert_eq(leaked.size(), 0, "записи ble_debug с полным id: %d" % leaked.size())


func test_all_ble_debug_strings_translated_ru_en() -> void:
	var keys: Array[String] = []
	var f := FileAccess.open("res://assets/i18n/strings_menu.csv", FileAccess.READ)
	assert_not_null(f)
	var header := f.get_csv_line()
	var ru := header.find("ru")
	var en := header.find("en")
	var missing: Array[String] = []
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 2 or not (row[0].begins_with("ui.ble_debug.") or row[0].begins_with("ui.settings.ble_debug")):
			continue
		keys.append(row[0])
		for col in [ru, en]:
			if col < 0 or col >= row.size() or row[col].strip_edges().is_empty():
				missing.append("%s/%s" % [row[0], header[col] if col >= 0 else "?"])
	# Ключи, на которые ссылаются сцена и скрипт экрана, — все в таблице.
	var sources := FileAccess.get_file_as_string("res://src/ui/ble_debug/ble_debug_screen.tscn") \
			+ FileAccess.get_file_as_string("res://src/ui/ble_debug/ble_debug_screen.gd")
	var re := RegEx.create_from_string("ui\\.ble_debug\\.[a-z_]+")
	for m in re.search_all(sources):
		if not keys.has(m.get_string()):
			missing.append("нет строки %s" % m.get_string())
	assert_gt(keys.size(), 20)
	assert_eq(missing.size(), 0, "непереведённые: %s" % ", ".join(missing))
