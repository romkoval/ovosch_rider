extends GutTest
## T-154: пульсометр «not connected» без причины. Сценарии карточки на `StubBleBridge` через
## `ConnectionManager` и экран устройств: (а) успех, (б) отказ / мгновенный разрыв, (в) нет
## `0x180D`. Слот «Пульсометр» и строка устройства в списке показывают одно и то же состояние и
## одну и ту же причину (ru/en); неудачная попытка устройство не запоминает (DEV-06 крит. 1).
## REQ-DEV-07 крит. 1, REQ-DEV-03 (Н-55 (б)), регрессия REQ-DEV-06 крит. 1, REQ-DEV-08 крит. 1.

const SCENE: String = "res://src/ui/devices/devices_screen.tscn"
const HRM: String = "hrm-garmin"
const HRM_NAME: String = "MARQ Aviat"

var _dir: String
var _bridge: StubBleBridge
var _remembered: RememberedDevices
var _repo: ProfileRepository
var _state: AppState
var _cm: ConnectionManager
var _locale: String


func before_each() -> void:
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_dir = "user://test_t154_devices_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_bridge = StubBleBridge.new()
	_remembered = RememberedDevices.new(_dir + "devices/")
	_repo = ProfileRepository.new(_dir + "profiles/")
	_repo.create("Rider")
	_state = AppState.new(_repo)
	_state.start()
	_cm = ConnectionManager.new(_bridge, _remembered)
	_cm.set_profile(_repo.active_profile_id)


func after_each() -> void:
	TranslationServer.set_locale(_locale)
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


## Часы найдены сканированием как пульсометр (реклама с 0x180D).
func _find_watch(s: DevicesScreen) -> void:
	(s.get_node("%ScanButton") as Button).pressed.emit()
	_bridge.emit_device_found(HRM, HRM_NAME, -53, PackedStringArray(["180D"]))


func _press_connect(s: DevicesScreen) -> void:
	(s.row(HRM)["connect_button"] as Button).pressed.emit()


func _profile_id() -> String:
	return _repo.active_profile_id


## Слот и строка согласованы: одна и та же надпись состояния и причина.
func _assert_slot_and_row_agree(s: DevicesScreen, state_text: String, reason_text: String) -> void:
	var slot := s.slot(RememberedDevices.KIND_HR)
	assert_eq(slot.chip_text(), state_text, "фишка слота")
	assert_string_contains(s.row_text(HRM), state_text, "строка списка")
	if reason_text.is_empty():
		assert_false(slot.is_failed())
		return
	assert_eq(slot.empty_text(), reason_text, "под статусом слота — причина")
	assert_true(slot.is_failed())
	assert_eq(slot.dot_color(), UiTokens.DANGER_TEXT, "ui.md 8.7: точка — danger_text при ошибке подключения")
	assert_string_contains(s.row_text(HRM), reason_text, "та же причина в строке списка")
	assert_eq(slot.name_text(), HRM_NAME, "под причиной — имя подключавшегося устройства")


# ---------------------------------------------------------------------------
# (а) Успех
# ---------------------------------------------------------------------------

func test_a_success_slot_and_row_connected_and_remembered() -> void:
	_bridge.set_device_services(HRM, {"180D": ["2A37"]})
	var s := _screen()
	_find_watch(s)
	_press_connect(s)
	assert_eq(_cm.state_of(HRM), TrainerDevice.ConnectionState.CONNECTING)
	assert_eq(s.slot(RememberedDevices.KIND_HR).chip_text(), "connecting")
	assert_string_contains(s.row_text(HRM), "connecting")
	_bridge.pump()
	assert_eq(_cm.state_of(HRM), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_cm.failure_of(HRM), SensorDevice.FailureReason.NONE)
	_assert_slot_and_row_agree(s, "connected", "")
	assert_true(s.slot(RememberedDevices.KIND_HR).is_connected_view())
	assert_false(_remembered.find(_profile_id(), HRM).is_empty(), "DEV-06 крит. 1: запомнено после успеха")


# ---------------------------------------------------------------------------
# (б) Отказ / мгновенный разрыв
# ---------------------------------------------------------------------------

func test_b_refused_shows_reason_in_slot_and_row_and_is_not_remembered() -> void:
	var s := _screen()
	_find_watch(s)
	_bridge.fail_next_connect()
	_press_connect(s)
	_bridge.pump()
	assert_eq(_cm.state_of(HRM), TrainerDevice.ConnectionState.DISCONNECTED, "REQ-DEV-07 крит. 1")
	assert_eq(_cm.failure_of(HRM), SensorDevice.FailureReason.REFUSED)
	_assert_slot_and_row_agree(s, "not connected", "The device refused the connection")
	assert_true(_remembered.find(_profile_id(), HRM).is_empty(), "DEV-06 крит. 1: неудача не запоминается")
	assert_eq(s.row(HRM)["forget_button"], null, "строка остаётся в «найденных»")


func test_b_link_drop_before_services_shows_connection_lost() -> void:
	var s := _screen()
	_find_watch(s)
	_bridge.auto_connect = false
	_press_connect(s)
	_bridge.emit_connected(HRM)
	_bridge.emit_disconnected(HRM, BleBridge.DisconnectReason.LINK_LOSS)
	assert_eq(_cm.state_of(HRM), TrainerDevice.ConnectionState.DISCONNECTED)
	_assert_slot_and_row_agree(s, "not connected", "Connection lost")


func test_b_timeout_shows_device_did_not_respond() -> void:
	var s := _screen()
	_find_watch(s)
	_bridge.auto_connect = false
	_press_connect(s)
	_cm.tick(BleSensorBase.CONNECT_TIMEOUT_SEC)
	assert_eq(_cm.state_of(HRM), TrainerDevice.ConnectionState.DISCONNECTED)
	_assert_slot_and_row_agree(s, "not connected", "The device did not respond")


func test_b_drop_after_connected_is_reconnecting_in_slot_and_row_without_failure_text() -> void:
	_bridge.set_device_services(HRM, {"180D": ["2A37"]})
	var s := _screen()
	_find_watch(s)
	_press_connect(s)
	_bridge.pump()
	_bridge.auto_connect = false
	_bridge.emit_disconnected(HRM, BleBridge.DisconnectReason.LINK_LOSS)
	assert_eq(_cm.state_of(HRM), TrainerDevice.ConnectionState.RECONNECTING, "REQ-DEV-08 крит. 1")
	assert_eq(_cm.failure_of(HRM), SensorDevice.FailureReason.LINK_LOST)
	assert_eq(s.slot(RememberedDevices.KIND_HR).chip_text(), "reconnecting")
	assert_string_contains(s.row_text(HRM), "reconnecting")
	assert_eq(s.failure_text(HRM), "", "причина под статусом — только в «не подключено»")


func test_b_reason_cleared_by_new_attempt() -> void:
	var s := _screen()
	_find_watch(s)
	_bridge.fail_next_connect()
	_press_connect(s)
	_bridge.pump()
	assert_eq(s.slot(RememberedDevices.KIND_HR).empty_text(), "The device refused the connection")
	_bridge.auto_connect = false
	_press_connect(s)
	assert_eq(_cm.failure_of(HRM), SensorDevice.FailureReason.NONE, "до следующей попытки")
	assert_eq(s.slot(RememberedDevices.KIND_HR).chip_text(), "connecting")
	assert_false(s.slot(RememberedDevices.KIND_HR).is_failed())
	assert_false(s.row_text(HRM).contains("refused"))


# ---------------------------------------------------------------------------
# (в) Нет 0x180D
# ---------------------------------------------------------------------------

func test_c_no_hrs_service_not_connected_with_broadcast_hint_en_and_ru() -> void:
	_bridge.set_device_services(HRM, {"1800": ["2A00"], "180A": ["2A29"]})
	var s := _screen()
	_find_watch(s)
	_press_connect(s)
	_bridge.pump()
	assert_eq(_cm.state_of(HRM), TrainerDevice.ConnectionState.DISCONNECTED, "REQ-DEV-03: без 0x180D не «подключено»")
	assert_eq(_cm.failure_of(HRM), SensorDevice.FailureReason.NO_SERVICE)
	assert_eq(_bridge.calls_of("disconnect_peripheral").size(), 1, "мост отключается")
	assert_true(_remembered.find(_profile_id(), HRM).is_empty(), "не запомнено")
	_assert_slot_and_row_agree(s, "not connected",
		"No heart-rate service — turn on heart-rate broadcast on your watch (Broadcast Heart Rate)")
	TranslationServer.set_locale("ru")
	s.refresh()
	_assert_slot_and_row_agree(s, "не подключено",
		"Нет сервиса пульса — включите на часах трансляцию пульса (Broadcast Heart Rate)")


# ---------------------------------------------------------------------------
# Тексты причин ru/en
# ---------------------------------------------------------------------------

func test_failure_texts_exist_in_ru_and_en_for_every_reason_and_kind() -> void:
	var kinds: Array[String] = [RememberedDevices.KIND_HR, RememberedDevices.KIND_CADENCE, RememberedDevices.KIND_POWER]
	for locale in ["ru", "en"]:
		TranslationServer.set_locale(locale)
		for reason: int in SensorDevice.FailureReason.values():
			for kind in kinds:
				var key := DevicesScreen.failure_key(kind, reason)
				if reason == SensorDevice.FailureReason.NONE:
					assert_eq(key, "", "NONE — без текста")
					continue
				assert_true(key.begins_with("ui.devices.reason."), key)
				var text := TranslationServer.translate(key)
				assert_ne(text, key, "%s: перевод %s есть" % [locale, key])
				assert_false(text.is_empty())
	TranslationServer.set_locale("en")
	assert_eq(tr(DevicesScreen.failure_key(RememberedDevices.KIND_HR, SensorDevice.FailureReason.LINK_LOST)), "Connection lost")
	assert_eq(tr(DevicesScreen.failure_key(RememberedDevices.KIND_HR, SensorDevice.FailureReason.NO_RESPONSE)), "The device did not respond")
	TranslationServer.set_locale("ru")
	assert_eq(tr(DevicesScreen.failure_key(RememberedDevices.KIND_HR, SensorDevice.FailureReason.REFUSED)), "Устройство отклонило подключение")
	assert_eq(tr(DevicesScreen.failure_key(RememberedDevices.KIND_HR, SensorDevice.FailureReason.LINK_LOST)), "Связь прервалась")
	assert_eq(tr(DevicesScreen.failure_key(RememberedDevices.KIND_HR, SensorDevice.FailureReason.NO_RESPONSE)), "Устройство не ответило")


func test_power_meter_failure_reason_visible_in_row() -> void:
	# У измерителя мощности слота нет — причина видна в строке списка.
	_bridge.set_device_services("pm", {"180D": ["2A37"]})
	var s := _screen()
	(s.get_node("%ScanButton") as Button).pressed.emit()
	_bridge.emit_device_found("pm", "Assioma", -60, PackedStringArray(["1818"]))
	(s.row("pm")["connect_button"] as Button).pressed.emit()
	_bridge.pump()
	assert_eq(_cm.state_of("pm"), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_string_contains(s.row_text("pm"), "No cycling power service (CPS)")
