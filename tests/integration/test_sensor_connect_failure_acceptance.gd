extends GutTest
## Приёмка T-154 (tester): пульсометр «not connected» без причины.
## REQ-DEV-07 п.1 («сигнал error в состоянии „подключение“ возвращает в „не подключено“ с
## сообщением»), REQ-DEV-03 (Н-55 (б): без `0x180D` нет «подключено»), регрессия REQ-DEV-08 п.1,
## REQ-DEV-06 п.1, REQ-NFR-05 п.1. Критерии авто карточки T-154.
## Проверяется то, чего нет в тестах разработчика (`test_sensor_connect_failures.gd`,
## `test_devices_connect_failure.gd`):
## - пустой список сервисов (так нативный мост Apple отдаёт устройство без сервисов) — не CONNECTED;
## - тот же случай с асинхронной ошибкой моста при подписке (`SERVICE_NOT_FOUND`) — итог не «подключено»;
## - поздние `connected`/`services_discovered` после тайм-аута не «воскрешают» датчик;
## - переподключение каждые 5 с после обрыва подключённого датчика, успех сбрасывает причину;
## - журнал сценария (б) «обрыв до services_discovered» по порядку; секрета нет;
## - причина видна после повторного открытия экрана устройств; автоподключение запомненных;
## - станок: REQ-DEV-07 п.1 «с сообщением» на экране устройств.

const SCENE: String = "res://src/ui/devices/devices_screen.tscn"
const HRM: String = "AB12CD34-0000-4000-8000-0000000ACC54"
const HRM_NAME: String = "MARQ Aviat"
const TRAINER: String = "TRAINER-ACC-154"
const SECRET: String = "acc-secret-T154-strava-token"

var _dir: String
var _bridge: StubBleBridge
var _remembered: RememberedDevices
var _repo: ProfileRepository
var _state: AppState
var _cm: ConnectionManager
var _journal: DiagLog
var _locale: String


func before_each() -> void:
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_dir = "user://acc_t154_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_bridge = StubBleBridge.new()
	_remembered = RememberedDevices.new(_dir + "devices/")
	_repo = ProfileRepository.new(_dir + "profiles/")
	_repo.create("Rider")
	_state = AppState.new(_repo)
	_state.start()
	_journal = DiagLog.new(_dir + "logs/")
	assert_eq(_journal.open(), OK)
	var store := MemorySecureStore.new()
	store.set_secret(SecureStore.key_for(_repo.active_profile_id, SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY), SECRET)
	_journal.filter().set_store(store)
	DiagLog.install(_journal)
	_cm = ConnectionManager.new(_bridge, _remembered)
	_cm.set_profile(_repo.active_profile_id)


func after_each() -> void:
	TranslationServer.set_locale(_locale)
	if _cm != null:
		_cm.dispose()
	DiagLog.uninstall(_journal)
	_journal.close()
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


func _screen() -> DevicesScreen:
	var s: DevicesScreen = load(SCENE).instantiate()
	s.setup(_cm, _repo, _state)
	add_child_autofree(s)
	return s


func _find(s: DevicesScreen, id: String, dev_name: String, services: Array[String]) -> void:
	(s.get_node("%ScanButton") as Button).pressed.emit()
	_bridge.emit_device_found(id, dev_name, -53, PackedStringArray(services))


func _press_connect(s: DevicesScreen, id: String) -> void:
	(s.row(id)["connect_button"] as Button).pressed.emit()


func _ble_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line in FileAccess.get_file_as_string(_journal.file_path()).split("\n", false):
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary and str((parsed as Dictionary).get("cat", "")) == DiagLog.CAT_BLE:
			out.append(parsed)
	return out


static func _index_of(events: Array[Dictionary], ev: String, from: int = 0) -> int:
	for i in range(from, events.size()):
		if str(events[i]["ev"]) == ev:
			return i
	return -1


# ---------------------------------------------------------------------------
# REQ-DEV-03 / Н-55 (б): без 0x180D нет «подключено»
# ---------------------------------------------------------------------------

func test_dev_03_empty_service_list_does_not_enter_connected() -> void:
	# Нативный мост Apple (`apple_backend.mm`, handle_services_discovered) отдаёт пустой словарь,
	# когда у устройства нет ни одного сервиса: это «нет 0x180D», а не «неизвестно».
	var s := BleHeartRateSensor.new(_bridge)
	s.connect_device(HRM)
	_bridge.pump()  # connected → discover_services → services_discovered({})
	assert_ne(s.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED,
		"карточка T-154: «без 0x180D датчик не входит в CONNECTED» — пустой список сервисов даёт CONNECTED")
	s.dispose()


func test_dev_07_c1_empty_services_then_bridge_service_not_found_is_not_left_connected() -> void:
	# Реальный путь на Mac: пустой список → подписка 180D/2A37 → мост отвечает SERVICE_NOT_FOUND
	# (characteristic_or_error). Пользователь не должен видеть «подключено» без пульса и без причины.
	_bridge.set_device_services(HRM, {})
	var s := _screen()
	_find(s, HRM, HRM_NAME, ["180D"])
	_press_connect(s, HRM)
	_bridge.pump()
	_bridge.emit_error(HRM, BleBridge.ErrorCode.SERVICE_NOT_FOUND, "CoreBluetooth: service 180D not found (call discover_services first)")
	assert_ne(_cm.state_of(HRM), TrainerDevice.ConnectionState.CONNECTED,
		"после отказа моста в подписке на 0x180D пульсометр остаётся «подключено» без данных")
	assert_ne(s.slot(RememberedDevices.KIND_HR).chip_text(), "connected", "слот не «connected»")


# ---------------------------------------------------------------------------
# REQ-DEV-07 п.1: поздние события моста после срыва
# ---------------------------------------------------------------------------

func test_dev_07_c1_late_connected_after_timeout_does_not_revive_sensor() -> void:
	_bridge.set_device_services(HRM, {"180D": ["2A37"]})
	_bridge.auto_connect = false
	var s := BleHeartRateSensor.new(_bridge)
	s.connect_device(HRM)
	s.tick(BleSensorBase.CONNECT_TIMEOUT_SEC)
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_eq(s.last_failure(), SensorDevice.FailureReason.NO_RESPONSE)
	_bridge.pump()  # отмена в мосте
	_bridge.clear_calls()
	_bridge.emit_connected(HRM)
	_bridge.pump()
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED, "поздний connected игнорируется")
	assert_eq(s.last_failure(), SensorDevice.FailureReason.NO_RESPONSE, "причина сохранена")
	assert_eq(_bridge.calls_of("subscribe").size(), 0, "подписок после срыва нет")
	s.dispose()


# ---------------------------------------------------------------------------
# Регрессия REQ-DEV-08 п.1
# ---------------------------------------------------------------------------

func test_dev_08_c1_drop_after_connected_retries_every_5s_and_success_clears_reason() -> void:
	_bridge.set_device_services(HRM, {"180D": ["2A37"]})
	var s := BleHeartRateSensor.new(_bridge)
	s.connect_device(HRM)
	_bridge.pump()
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	_bridge.auto_connect = false
	_bridge.clear_calls()
	_bridge.emit_disconnected(HRM, BleBridge.DisconnectReason.LINK_LOSS)
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING)
	var first := _bridge.calls_of("connect_peripheral").size()
	assert_eq(first, 1, "первая попытка сразу")
	s.tick(4.9)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1, "до 5 с повторов нет")
	s.tick(0.1)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 2, "через 5 с — повтор")
	s.tick(5.0)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 3, "ещё через 5 с — повтор")
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING, "без отказа «не подключено»")
	_bridge.auto_connect = true
	_bridge.emit_connected(HRM)
	_bridge.pump()
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "связь восстановлена")
	assert_eq(s.last_failure(), SensorDevice.FailureReason.NONE, "причина сброшена после CONNECTED")
	s.dispose()


# ---------------------------------------------------------------------------
# Журнал сценария (б): попытка → обрыв с причиной → «не подключено»; секретов нет
# ---------------------------------------------------------------------------

func test_log_scenario_b_link_drop_before_services_in_order_without_secret() -> void:
	var s := _screen()
	_find(s, HRM, HRM_NAME, ["180D"])
	_bridge.auto_connect = false
	_press_connect(s, HRM)
	_bridge.emit_connected(HRM)
	_bridge.emit_error(HRM, BleBridge.ErrorCode.NOT_CONNECTED, "peer gone token=%s" % SECRET)
	var events := _ble_events()
	var i_connect := _index_of(events, "sensor_connect")
	var i_error := _index_of(events, "sensor_error", maxi(i_connect, 0))
	var i_failed := _index_of(events, "sensor_failed", maxi(i_error, 0))
	var i_state := -1
	for i in range(maxi(i_failed, 0), events.size()):
		if str(events[i]["ev"]) == "sensor_state" and str(events[i]["data"].get("to", "")) == "disconnected":
			i_state = i
			break
	assert_true(i_connect >= 0, "попытка в журнале")
	assert_true(i_error > i_connect, "ошибка после попытки")
	assert_true(i_failed > i_error, "срыв после ошибки")
	assert_true(i_state > i_failed, "переход в «не подключено» после срыва")
	if i_error >= 0:
		assert_eq(str(events[i_error]["data"].get("code", "")), "not_connected", "код ошибки моста")
	if i_state >= 0:
		assert_eq(str(events[i_state]["data"].get("reason", "")), "link_lost", "причина в переходе")
	var text := FileAccess.get_file_as_string(_journal.file_path())
	assert_false(text.contains(SECRET), "REQ-NFR-05 п.1: секрета в журнале нет")
	assert_eq(s.slot(RememberedDevices.KIND_HR).empty_text(), "Connection lost")


# ---------------------------------------------------------------------------
# Экран устройств: причина до следующей попытки, автоподключение
# ---------------------------------------------------------------------------

func test_reason_still_shown_after_devices_screen_reopened() -> void:
	var s := _screen()
	_find(s, HRM, HRM_NAME, ["180D"])
	_bridge.set_device_services(HRM, {"1800": ["2A00"]})
	_press_connect(s, HRM)
	_bridge.pump()
	var reason := "No heart-rate service — turn on heart-rate broadcast on your watch (Broadcast Heart Rate)"
	assert_eq(s.slot(RememberedDevices.KIND_HR).empty_text(), reason)
	s.queue_free()
	await wait_process_frames(1)
	var again := _screen()
	assert_eq(again.slot(RememberedDevices.KIND_HR).empty_text(), reason, "причина хранится до следующей попытки, а не до закрытия экрана")
	assert_true(again.slot(RememberedDevices.KIND_HR).is_failed())


func test_row_offers_connect_again_after_failure_and_slot_offers_find() -> void:
	var s := _screen()
	_find(s, HRM, HRM_NAME, ["180D"])
	_bridge.fail_next_connect()
	_press_connect(s, HRM)
	_bridge.pump()
	var button := s.row(HRM)["connect_button"] as Button
	assert_not_null(button)
	if button != null:
		assert_eq(button.text, tr("ui.devices.connect"), "в строке снова «Подключить»")
		assert_false(button.disabled, "повторная попытка доступна")


func test_auto_connect_of_remembered_hr_without_hrs_shows_reason_and_keeps_record() -> void:
	var pid := _repo.active_profile_id
	assert_true(_remembered.remember(pid, {"id": HRM, "name": HRM_NAME, "kind": RememberedDevices.KIND_HR}))
	_bridge.set_device_services(HRM, {"1800": ["2A00"], "180A": ["2A29"]})
	var s := _screen()
	_cm.auto_connect(pid)
	_bridge.emit_device_found(HRM, HRM_NAME, -60, PackedStringArray(["180D"]))
	_bridge.pump()
	assert_eq(_cm.state_of(HRM), TrainerDevice.ConnectionState.DISCONNECTED, "автоподключение без 0x180D — не «подключено»")
	assert_eq(_cm.failure_of(HRM), SensorDevice.FailureReason.NO_SERVICE)
	s.refresh()
	assert_string_contains(s.slot(RememberedDevices.KIND_HR).empty_text(), "No heart-rate service")
	assert_false(_remembered.find(pid, HRM).is_empty(), "запомненное устройство не забывается из-за срыва")


# ---------------------------------------------------------------------------
# REQ-DEV-07 п.1 для станка
# ---------------------------------------------------------------------------

func test_dev_07_c1_trainer_connect_failure_shows_message_on_devices_screen() -> void:
	var s := _screen()
	_find(s, TRAINER, "Tacx Neo 2T", ["1826"])
	_bridge.fail_next_connect()
	_press_connect(s, TRAINER)
	_bridge.pump()
	assert_eq(_cm.state_of(TRAINER), TrainerDevice.ConnectionState.DISCONNECTED, "отказ — «не подключено»")
	var slot := s.slot(RememberedDevices.KIND_TRAINER)
	assert_ne(slot.empty_text(), tr("ui.devices.slot.not_connected"),
		"REQ-DEV-07 п.1 «возвращает в „не подключено“ с сообщением»: у станка под статусом голое «Not connected»")
	assert_ne(s.failure_text(TRAINER), "", "причина отказа станка в строке списка")
