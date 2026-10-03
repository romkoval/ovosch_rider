extends GutTest
## Тесты ConnectionManager на StubBleBridge (REQ-DEV-06 крит. 1–4, REQ-DEV-07 крит. 1–3,
## REQ-DEV-01 крит. 4, REQ-PRF-04 крит. 2–3).

const A: String = "profile-a"
const B: String = "profile-b"

var _dir: String
var _bridge: StubBleBridge
var _remembered: RememberedDevices
var _cm: ConnectionManager
var _state_events: Array[String] = []
var _timed_out: Array = []


func before_each() -> void:
	_dir = "user://test_cm_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_bridge = StubBleBridge.new()
	_remembered = RememberedDevices.new(_dir)
	_cm = ConnectionManager.new(_bridge, _remembered)
	_state_events = []
	_timed_out = []
	_cm.state_changed.connect(func(id: String) -> void: _state_events.append(id))
	_cm.auto_connect_timed_out.connect(func(ids: Array[String]) -> void: _timed_out.append(ids))
	_cm.set_profile(A)


func after_each() -> void:
	if _cm != null:
		_cm.dispose()
	if _bridge != null:
		_bridge.dispose()
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


# ---------------------------------------------------------------------------
# Ручное подключение и запоминание (REQ-DEV-06 крит. 1, REQ-DEV-07 крит. 1)
# ---------------------------------------------------------------------------

func test_connect_trainer_passes_states_and_remembers_shared_trainer() -> void:
	_cm.start_scan()
	_adv("neo", "Tacx Neo", ["1826", "180F"])
	_cm.connect_trainer("neo")
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.CONNECTING)
	assert_false(_remembered.has_trainer(), "до CONNECTED не запоминается")
	_bridge.pump()
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.CONNECTED)
	assert_true(_cm.is_device_connected("neo"))
	assert_true(_remembered.has_trainer(), "REQ-DEV-06 крит. 1")
	assert_eq(_remembered.trainer()["name"], "Tacx Neo")
	assert_eq(_remembered.trainer()["kind"], RememberedDevices.KIND_TRAINER)
	assert_true(_state_events.has("neo"))
	assert_false(_cm.scanner.is_scanning(), "REQ-DEV-01 крит. 4: сканирование остановлено при подключении")
	var states := _cm.device_states()
	assert_eq(states["neo"]["kind"], RememberedDevices.KIND_TRAINER)
	assert_eq(states["neo"]["state"], TrainerDevice.ConnectionState.CONNECTED)


func test_connect_sensor_remembers_in_profile_only() -> void:
	_cm.connect_sensor("hrm", RememberedDevices.KIND_HR)
	_bridge.pump()
	assert_eq(_cm.state_of("hrm"), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_remembered.sensors(A).size(), 1)
	assert_eq(_remembered.sensors(A)[0]["id"], "hrm")
	assert_eq(_remembered.sensors(B).size(), 0, "REQ-PRF-04 крит. 2: датчик профиля A невидим в B")
	assert_not_null(_cm.sensor(RememberedDevices.KIND_HR))
	assert_eq(_cm.hub.heart_rate_sensor, _cm.sensor(RememberedDevices.KIND_HR), "датчик подключён к хабу")
	assert_eq(_cm.device_states()["hrm"]["kind"], RememberedDevices.KIND_HR)


func test_connect_sensor_unknown_kind_rejected_with_warning() -> void:
	assert_false(_cm.connect_sensor("x", "bananas"))
	assert_push_warning("неизвестный тип датчика")
	assert_false(_cm.connect_sensor("", RememberedDevices.KIND_HR), "пустой id")
	assert_eq(_cm.sensors.size(), 0)
	assert_true(_cm.connect_sensor("hrm", RememberedDevices.KIND_HR))


func test_trainer_battery_read_and_exposed() -> void:
	_bridge.set_device_services("neo", {"1826": ["2AD2", "2AD9", "2ADA"], "180F": ["2A19"]})
	_bridge.set_read_value("2A19", BatteryCodec.encode_level(64))
	_cm.connect_trainer("neo")
	_bridge.pump()
	assert_eq(_cm.battery_of("neo"), 64, "REQ-DEV-07 крит. 2: батарея станка")
	assert_eq(_cm.device_states()["neo"]["battery"], 64)
	_bridge.emit_notification("neo", "2A19", BatteryCodec.encode_level(63))
	assert_eq(_cm.battery_of("neo"), 63, "обновление по нотификации")


func test_trainer_without_battery_service_shows_minus_one() -> void:
	_bridge.set_device_services("neo", {"1826": ["2AD2", "2AD9", "2ADA"]})
	_cm.connect_trainer("neo")
	_bridge.pump()
	assert_eq(_cm.battery_of("neo"), -1, "REQ-DEV-07 крит. 3: «—», не ошибка")
	assert_eq(_bridge.calls_of("read_characteristic").filter(func(c: Dictionary) -> bool: return c["char"] == "2A19").size(), 0)
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.CONNECTED)


func test_sensor_battery_exposed() -> void:
	_bridge.set_read_value("2A19", BatteryCodec.encode_level(90))
	_cm.connect_sensor("hrm", RememberedDevices.KIND_HR)
	_bridge.pump()
	assert_eq(_cm.battery_of("hrm"), 90)
	assert_eq(_cm.battery_of("unknown"), -1)


func test_reconnect_state_visible_and_connect_other_trainer_disconnects_first() -> void:
	_cm.connect_trainer("neo")
	_bridge.pump()
	_bridge.auto_connect = false
	_bridge.emit_disconnected("neo", BleBridge.DisconnectReason.LINK_LOSS)
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.RECONNECTING, "REQ-DEV-07 крит. 1")
	_bridge.auto_connect = true
	_cm.connect_trainer("kickr")
	assert_eq(_bridge.calls_of("disconnect_peripheral").size(), 1, "старый станок отключён")
	_bridge.pump()
	assert_eq(_cm.trainer_id, "kickr")
	assert_eq(_cm.state_of("kickr"), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.DISCONNECTED, "неизвестный id → DISCONNECTED")


# ---------------------------------------------------------------------------
# Автоподключение (REQ-DEV-06 крит. 2, 3)
# ---------------------------------------------------------------------------

func test_auto_connect_connects_remembered_as_they_advertise() -> void:
	_remembered.set_trainer(RememberedDevices.make_device("neo", "Neo", RememberedDevices.KIND_TRAINER))
	_remembered.remember(A, RememberedDevices.make_device("hrm", "HRM", RememberedDevices.KIND_HR))
	_cm.auto_connect(A)
	assert_true(_cm.is_auto_connecting())
	assert_true(_cm.scanner.is_scanning(), "сканирование запущено автоматически")
	assert_eq(_cm.pending_auto_connect_ids().size(), 2)
	_adv("hrm", "HRM", ["180D"])
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1, "REQ-DEV-06 крит. 2: connect сразу после рекламы")
	assert_eq(_bridge.calls_of("connect_peripheral")[0]["id"], "hrm")
	assert_true(_cm.scanner.is_scanning(), "станок ещё ждём")
	_adv("neo", "Neo", ["1826"])
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 2)
	assert_false(_cm.is_auto_connecting())
	assert_false(_cm.scanner.is_scanning(), "все найдены — сканирование остановлено")
	_bridge.pump()
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_cm.state_of("hrm"), TrainerDevice.ConnectionState.CONNECTED)
	assert_gt(int(_remembered.trainer()["last_seen_at"]), 0, "mark_seen")


func test_auto_connect_ignores_unremembered_and_auto_connect_off_devices() -> void:
	_remembered.set_trainer(RememberedDevices.make_device("neo", "Neo", RememberedDevices.KIND_TRAINER))
	_remembered.remember(A, RememberedDevices.make_device("hrm", "HRM", RememberedDevices.KIND_HR, false))
	_cm.auto_connect(A)
	assert_eq(_cm.pending_auto_connect_ids(), ["neo"] as Array[String], "auto_connect=false не кандидат")
	_adv("stranger", "Stranger", ["1826"])
	_adv("hrm", "HRM", ["180D"])
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 0, "незапомненные и выключенные не подключаются")
	_adv("neo", "Neo", ["1826"])
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1)


func test_auto_connect_times_out_after_30s_and_stops_scan() -> void:
	_remembered.set_trainer(RememberedDevices.make_device("neo", "Neo", RememberedDevices.KIND_TRAINER))
	_cm.auto_connect(A)
	for i in 29:
		_cm.tick(1.0)
	assert_true(_cm.is_auto_connecting())
	assert_eq(_timed_out.size(), 0)
	_cm.tick(1.0)
	assert_false(_cm.is_auto_connecting(), "REQ-DEV-06 крит. 3: 30 с без обнаружения")
	assert_eq(_timed_out.size(), 1)
	assert_eq(_timed_out[0], ["neo"] as Array[String])
	assert_false(_cm.scanner.is_scanning())
	_adv("neo", "Neo", ["1826"])
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 0, "после таймаута — только вручную")
	_cm.connect_trainer("neo")
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1)


func test_auto_connect_disabled_flag_and_no_candidates() -> void:
	_cm.auto_connect(A)
	assert_false(_cm.is_auto_connecting(), "нет кандидатов — ничего не делаем")
	assert_false(_cm.scanner.is_scanning())
	_remembered.set_trainer(RememberedDevices.make_device("neo", "Neo", RememberedDevices.KIND_TRAINER))
	_cm.auto_connect_enabled = false
	_cm.auto_connect(A)
	assert_false(_cm.is_auto_connecting())
	assert_eq(_bridge.calls_of("start_scan").size(), 0)


func test_auto_connect_uses_already_seen_device_and_does_not_stop_user_scan() -> void:
	_remembered.set_trainer(RememberedDevices.make_device("neo", "Neo", RememberedDevices.KIND_TRAINER))
	_cm.start_scan()
	_adv("neo", "Neo", ["1826"])
	_cm.auto_connect(A)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1, "уже видимое устройство подключается сразу")
	assert_true(_cm.scanner.is_scanning(), "пользовательское сканирование не трогаем")
	_bridge.pump()
	assert_false(_cm.scanner.is_scanning(), "но при CONNECTED сканирование останавливается")


func test_forget_disconnects_and_removes_and_blocks_auto_connect() -> void:
	_cm.connect_trainer("neo")
	_bridge.pump()
	assert_true(_remembered.has_trainer())
	assert_true(_cm.forget(A, "neo"))
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.DISCONNECTED, "REQ-DEV-06 крит. 4: отключено")
	assert_false(_remembered.has_trainer(), "удалено из реестра")
	assert_false(_cm.device_states().has("neo"), "забытое устройство исчезает из device_states")
	assert_eq(_cm.trainer_id, "")
	_cm.connect_sensor("hrm", RememberedDevices.KIND_HR)
	_bridge.pump()
	_cm.forget(A, "hrm")
	assert_false(_cm.device_states().has("hrm"))
	assert_false(_cm.sensor_ids.has(RememberedDevices.KIND_HR))
	_cm.auto_connect(A)
	assert_false(_cm.is_auto_connecting(), "автоподключение к забытому не выполняется")
	assert_false(_cm.forget(A, "nothing"))


func test_disconnect_all_and_cancel() -> void:
	_remembered.remember(A, RememberedDevices.make_device("cad", "Cad", RememberedDevices.KIND_CADENCE))
	_cm.connect_trainer("neo")
	_cm.connect_sensor("hrm", RememberedDevices.KIND_HR)
	_bridge.pump()
	_cm.auto_connect(A)
	assert_true(_cm.is_auto_connecting())
	_cm.disconnect_all()
	_bridge.pump()
	assert_false(_cm.is_auto_connecting())
	assert_false(_cm.scanner.is_scanning())
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_eq(_cm.state_of("hrm"), TrainerDevice.ConnectionState.DISCONNECTED)


# ---------------------------------------------------------------------------
# Два профиля (REQ-PRF-04 крит. 2, 3)
# ---------------------------------------------------------------------------

func test_two_profiles_share_trainer_but_not_sensors() -> void:
	_cm.connect_trainer("neo")
	_cm.connect_sensor("hrm-a", RememberedDevices.KIND_HR)
	_bridge.pump()
	_cm.disconnect_all()
	_bridge.pump()
	_cm.set_profile(B)
	assert_eq(_remembered.auto_connect_candidates(B).size(), 1, "REQ-PRF-04 крит. 3: станок общий")
	assert_eq(_remembered.auto_connect_candidates(B)[0]["id"], "neo")
	_bridge.clear_calls()
	_cm.auto_connect(B)
	_adv("hrm-a", "HRM A", ["180D"])
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 0, "REQ-PRF-04 крит. 2: датчик A не подключается в B")
	_adv("neo", "Neo", ["1826"])
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1)
	_bridge.pump()
	_cm.connect_sensor("hrm-b", RememberedDevices.KIND_HR)
	_bridge.pump()
	assert_eq(_remembered.sensors(B).size(), 1)
	assert_eq(_remembered.sensors(B)[0]["id"], "hrm-b")
	assert_eq(_remembered.sensors(A).size(), 1)
	assert_eq(_remembered.sensors(A)[0]["id"], "hrm-a")


func test_tick_drives_hub_and_devices_flag() -> void:
	_cm.connect_trainer("neo")
	_bridge.pump()
	var samples: Array[TrainerSample] = []
	_cm.hub.telemetry.connect(func(s: TrainerSample) -> void: samples.append(s))
	_cm.tick(1.0)
	assert_eq(samples.size(), 1, "хаб тикается менеджером")
	_cm.ticks_devices = false
	_cm.tick(1.0)
	assert_eq(samples.size(), 1, "сессия взяла хаб — менеджер устройства не тикает")
	assert_almost_eq(_cm.scanner.get_time_sec(), 2.0, 1e-9, "сканер тикается всегда")


func test_dispose_releases_everything() -> void:
	_cm.connect_trainer("neo")
	_cm.connect_sensor("hrm", RememberedDevices.KIND_HR)
	_bridge.pump()
	var hub := _cm.hub
	var trainer := _cm.trainer
	_cm.dispose()
	assert_null(_cm.hub)
	assert_null(_cm.trainer)
	assert_null(_cm.scanner)
	assert_null(hub.trainer, "хаб отвязан")
	assert_null(trainer.get("bridge"), "станок отвязан от моста")
	_bridge.emit_device_found("x", "X", -50, PackedStringArray(["1826"]))
	assert_eq(_state_events.size() > 0, true)
	_cm = null


func test_fake_trainer_kind_for_dev_mode() -> void:
	var cm := ConnectionManager.new(_bridge, _remembered, TrainerFactory.KIND_FAKE)
	assert_true(cm.trainer is TrainerDevice)
	assert_false(cm.trainer.has_signal("battery_level"), "эмулятор без батареи")
	cm.trainer.set("connect_delay_sec", 0.0)
	cm.connect_trainer("fake-1")
	assert_eq(cm.state_of("fake-1"), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(cm.battery_of("fake-1"), -1)
	assert_true(_remembered.has_trainer())
	cm.dispose()


# ---------------------------------------------------------------------------
# REQ-DEV-01 крит. 7 — Bluetooth недоступен
# ---------------------------------------------------------------------------

func test_start_scan_and_auto_connect_refused_when_ble_unavailable() -> void:
	assert_true(_cm.is_ble_available())
	assert_true(_cm.start_scan())
	_cm.stop_scan()
	_bridge.set_available(false)
	assert_false(_cm.is_ble_available())
	assert_false(_cm.start_scan(), "REQ-DEV-01 крит. 7: сканирование не стартует")
	assert_false(_cm.scanner.is_scanning())
	_remembered.set_trainer(RememberedDevices.make_device("neo", "Neo", RememberedDevices.KIND_TRAINER))
	_cm.auto_connect(A)
	assert_false(_cm.is_auto_connecting(), "автоподключение без Bluetooth не начинается")
	assert_eq(_bridge.calls_of("start_scan").size(), 1, "на мост ушёл только первый, успешный start_scan")


func test_adapter_powered_off_cancels_scan_and_auto_connect() -> void:
	_remembered.set_trainer(RememberedDevices.make_device("neo", "Neo", RememberedDevices.KIND_TRAINER))
	var changed: Array[int] = [0]
	_cm.devices_changed.connect(func() -> void: changed[0] += 1)
	_cm.auto_connect(A)
	assert_true(_cm.is_auto_connecting())
	_bridge.set_adapter_state(BleBridge.AdapterState.POWERED_OFF)
	assert_false(_cm.is_ble_available(), "мост есть, но адаптер выключен")
	assert_false(_cm.is_auto_connecting())
	assert_false(_cm.scanner.is_scanning())
	assert_gt(changed[0], 0, "UI уведомлён об изменении доступности")
	_bridge.set_adapter_state(BleBridge.AdapterState.POWERED_ON)
	assert_true(_cm.is_ble_available())


func test_default_bridge_without_native_module_is_unavailable_for_manager() -> void:
	var cm := ConnectionManager.new(BleBridge.create_default(), _remembered)
	assert_false(cm.is_ble_available(), "UX-3: без нативного модуля фантомных подключений нет")
	assert_false(cm.start_scan())
	cm.dispose()


func test_stop_scan_keeps_auto_connect_scan_running() -> void:
	_remembered.set_trainer(RememberedDevices.make_device("neo", "Neo", RememberedDevices.KIND_TRAINER))
	_cm.start_scan()
	_cm.auto_connect(A)
	_cm.stop_scan()
	assert_true(_cm.scanner.is_scanning(), "D-5: ручной stop не гасит сканирование автоподключения")
	assert_true(_cm.is_auto_connecting())
	_bridge.emit_device_found("neo", "Neo", -50, PackedStringArray(["1826"]))
	assert_false(_cm.scanner.is_scanning(), "автоподключение само остановило сканер")


# ---------------------------------------------------------------------------
# Регрессии финального ревью
# ---------------------------------------------------------------------------

## П.3: на macOS при запуске адаптер в UNKNOWN — автоподключение не теряется,
## а выполняется при переходе в POWERED_ON (REQ-DEV-06 крит. 2, 5).
func test_auto_connect_requested_before_powered_on_runs_on_powered_on() -> void:
	_remembered.set_trainer(RememberedDevices.make_device("neo", "Neo", RememberedDevices.KIND_TRAINER))
	_bridge.set_adapter_state(BleBridge.AdapterState.UNKNOWN)
	_cm.auto_connect(A)
	assert_false(_cm.is_auto_connecting())
	assert_true(_cm.is_auto_connect_deferred(), "запрос запомнен")
	assert_eq(_bridge.calls_of("start_scan").size(), 0, "до POWERED_ON не сканируем")
	_bridge.set_adapter_state(BleBridge.AdapterState.POWERED_OFF)
	assert_true(_cm.is_auto_connect_deferred(), "промежуточные состояния не отменяют ожидание")
	_bridge.set_adapter_state(BleBridge.AdapterState.POWERED_ON)
	assert_false(_cm.is_auto_connect_deferred())
	assert_true(_cm.is_auto_connecting(), "автоподключение запущено")
	assert_true(_cm.scanner.is_scanning())
	_adv("neo", "Neo", ["1826"])
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1, "подключение без действий пользователя")


func test_deferred_auto_connect_cancelled_explicitly_and_by_profile_change() -> void:
	_remembered.set_trainer(RememberedDevices.make_device("neo", "Neo", RememberedDevices.KIND_TRAINER))
	_bridge.set_adapter_state(BleBridge.AdapterState.UNKNOWN)
	_cm.auto_connect(A)
	_cm.cancel_auto_connect()
	assert_false(_cm.is_auto_connect_deferred())
	_bridge.set_adapter_state(BleBridge.AdapterState.POWERED_ON)
	assert_eq(_bridge.calls_of("start_scan").size(), 0, "отменённое ожидание не срабатывает")
	_bridge.set_adapter_state(BleBridge.AdapterState.UNKNOWN)
	_cm.auto_connect(A)
	_cm.set_profile(B)
	_bridge.set_adapter_state(BleBridge.AdapterState.POWERED_ON)
	assert_eq(_bridge.calls_of("start_scan").size(), 0, "смена профиля отменяет ожидание")
	_cm.auto_connect_enabled = false
	_bridge.set_adapter_state(BleBridge.AdapterState.UNKNOWN)
	_cm.auto_connect(A)
	assert_false(_cm.is_auto_connect_deferred(), "выключенное автоподключение не откладывается")


## П.4: устройство, найденное в текущем сеансе сканирования, доступно для автоподключения,
## даже если сканер уже пометил его недоступным/убрал (реклама без дубликатов приходила один раз).
func test_auto_connect_uses_device_seen_earlier_in_current_scan_session() -> void:
	_remembered.set_trainer(RememberedDevices.make_device("neo", "Neo", RememberedDevices.KIND_TRAINER))
	_cm.start_scan()
	_adv("neo", "Neo", ["1826"])
	for i in 35:
		_cm.tick(1.0)
	assert_true(_cm.scanner.find("neo").is_empty(), "сканер убрал запись через 30 с")
	_cm.auto_connect(A)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1, "подключение сразу, без ожидания device_found")
	assert_eq(_bridge.calls_of("connect_peripheral")[0]["id"], "neo")


## П.10: подписка на сигналы датчика — связанными методами: без dispose() менеджер
## освобождается (лямбда держала бы его сильной ссылкой — цикл и утечка).
func test_manager_with_sensor_is_freed_without_dispose() -> void:
	var cm := ConnectionManager.new(_bridge, _remembered)
	cm.connect_sensor("hrm", RememberedDevices.KIND_HR)
	_bridge.pump()
	var states: Array[String] = []
	cm.state_changed.connect(func(id: String) -> void: states.append(id))
	var sensor: SensorDevice = cm.sensor(RememberedDevices.KIND_HR)
	_bridge.emit_disconnected("hrm", BleBridge.DisconnectReason.LINK_LOSS)
	assert_eq(states, ["hrm"] as Array[String], "связанный обработчик получает kind")
	var ref: WeakRef = weakref(cm)
	cm = null
	assert_null(ref.get_ref(), "менеджер освобождён — цикла через датчик нет")
	if sensor.has_method("dispose"):
		sensor.call("dispose")


## П.12: dispose менеджера сбрасывает очередь заглушки (её замыкания держат мост).
func test_dispose_clears_stub_bridge_pending_queue() -> void:
	_cm.connect_trainer("neo")
	assert_gt(_bridge.pending.size(), 0)
	_cm.dispose()
	_cm = null
	assert_eq(_bridge.pending.size(), 0)
