extends GutTest
## T-164: причина срыва подключения станка — как у датчиков (REQ-DEV-07 п.1): `BleTrainer.last_failure()`
## (`SensorDevice.FailureReason`), `ConnectionManager.device_states()`/`failure_of()` и текст на экране
## устройств (слот и строка списка).

const SCENE: String = "res://src/ui/devices/devices_screen.tscn"
const NEO: String = "neo"

var _dir: String
var _bridge: StubBleBridge
var _remembered: RememberedDevices
var _cm: ConnectionManager
var _locale: String


func before_each() -> void:
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_dir = "user://test_t164_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_bridge = StubBleBridge.new()
	_bridge.set_device_services(NEO, {"1826": ["2AD2", "2AD9", "2ADA"]})
	_remembered = RememberedDevices.new(_dir + "devices/")
	_cm = ConnectionManager.new(_bridge, _remembered)
	_cm.set_profile("p1")


func after_each() -> void:
	TranslationServer.set_locale(_locale)
	_cm.dispose()
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


func test_bridge_error_codes_map_to_failure_reasons() -> void:
	var cases: Array = [
		[BleBridge.ErrorCode.CONNECTION_FAILED, SensorDevice.FailureReason.REFUSED],
		[BleBridge.ErrorCode.DEVICE_NOT_FOUND, SensorDevice.FailureReason.NO_RESPONSE],
		[BleBridge.ErrorCode.TIMEOUT, SensorDevice.FailureReason.NO_RESPONSE],
		[BleBridge.ErrorCode.ADAPTER_UNAVAILABLE, SensorDevice.FailureReason.BLUETOOTH_OFF],
		[BleBridge.ErrorCode.SERVICE_NOT_FOUND, SensorDevice.FailureReason.NO_SERVICE],
		[BleBridge.ErrorCode.SUBSCRIBE_FAILED, SensorDevice.FailureReason.REFUSED],
		[BleBridge.ErrorCode.NOT_CONNECTED, SensorDevice.FailureReason.LINK_LOST],
	]
	for c in cases:
		var b := StubBleBridge.new()
		b.auto_connect = false
		var t := BleTrainer.new(b)
		t.connect_device(NEO)
		b.emit_error(NEO, int(c[0]), "fail")
		assert_eq(t.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED, "код %d" % int(c[0]))
		assert_eq(t.last_failure(), int(c[1]), "код %d → причина %d" % [int(c[0]), int(c[1])])
		t.dispose()
		b.dispose()


func test_connect_timeout_is_no_response_and_new_attempt_clears_reason() -> void:
	var t := BleTrainer.new(_bridge)
	_bridge.auto_connect = false
	t.connect_device(NEO)
	t.tick(BleTrainer.CONNECT_TIMEOUT_SEC)
	assert_eq(t.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_eq(t.last_failure(), SensorDevice.FailureReason.NO_RESPONSE)
	t.connect_device(NEO)
	assert_eq(t.last_failure(), SensorDevice.FailureReason.NONE, "новая попытка сбрасывает причину")
	t.disconnect_device()
	assert_eq(t.last_failure(), SensorDevice.FailureReason.NONE, "ручное отключение — без причины")
	t.dispose()


func test_request_control_rejected_is_refused() -> void:
	var t := BleTrainer.new(_bridge)
	_bridge.fail_next_control_point()
	t.connect_device(NEO)
	_bridge.pump()
	_bridge.pump()
	assert_eq(t.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_eq(t.last_failure(), SensorDevice.FailureReason.REFUSED)
	t.dispose()


func test_connected_trainer_has_no_reason() -> void:
	var t := BleTrainer.new(_bridge)
	t.connect_device(NEO)
	_bridge.pump()
	_bridge.pump()
	assert_eq(t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(t.last_failure(), SensorDevice.FailureReason.NONE)
	t.dispose()


func test_manager_exposes_trainer_failure_and_screen_shows_it() -> void:
	_bridge.fail_next_connect()
	_cm.connect_trainer(NEO)
	_bridge.pump()
	assert_eq(_cm.state_of(NEO), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_eq(_cm.failure_of(NEO), SensorDevice.FailureReason.REFUSED, "причина в device_states")
	var repo := ProfileRepository.new(_dir + "profiles/")
	repo.create("Rider")
	var state := AppState.new(repo)
	state.start()
	var s: DevicesScreen = load(SCENE).instantiate()
	s.setup(_cm, repo, state)
	add_child_autofree(s)
	var reason := tr(DevicesScreen.failure_key(RememberedDevices.KIND_TRAINER, SensorDevice.FailureReason.REFUSED))
	assert_ne(reason, "", "текст причины есть")
	assert_eq(s.failure_text(NEO), reason, "причина в строке списка")
	assert_eq(s.slot(RememberedDevices.KIND_TRAINER).empty_text(), reason, "причина в слоте станка")


func test_emulator_trainer_has_no_failure_reason() -> void:
	var cm := ConnectionManager.new(_bridge, _remembered, TrainerFactory.KIND_FAKE)
	cm.set_profile("p1")
	cm.connect_trainer("emu")
	assert_eq(cm.failure_of("emu"), SensorDevice.FailureReason.NONE)
	cm.dispose()


func test_services_without_ftms_is_no_service_and_bridge_cancelled() -> void:
	_bridge.set_device_services(NEO, {"180F": ["2A19"], "6E40FEC1-B5A3-F393-E0A9-E50E24DCCA9E": ["6E40FEC2-B5A3-F393-E0A9-E50E24DCCA9E"]})
	var t := BleTrainer.new(_bridge)
	t.connect_device(NEO)
	_bridge.pump()
	_bridge.pump()
	assert_eq(t.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED, "без 0x1826 станок не подключён")
	assert_eq(t.last_failure(), SensorDevice.FailureReason.NO_SERVICE)
	assert_gt(_bridge.calls_of("disconnect_peripheral").size(), 0, "подключение отменено в мосте")
	assert_eq(_bridge.calls_of("subscribe").size(), 0, "ни одной подписки")
	t.dispose()


func test_empty_service_list_keeps_legacy_unknown_path() -> void:
	_bridge.set_device_services(NEO, {})
	var t := BleTrainer.new(_bridge)
	t.connect_device(NEO)
	_bridge.pump()
	_bridge.pump()
	assert_eq(t.last_failure(), SensorDevice.FailureReason.NONE, "пустой список — «неизвестен», не NO_SERVICE (строже — T-161)")
	t.dispose()
