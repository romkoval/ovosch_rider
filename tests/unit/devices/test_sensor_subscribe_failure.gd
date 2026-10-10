extends GutTest
## Дефекты приёмки T-154: датчик без своего сервиса не входит в CONNECTED (пустой список — тоже
## «нет сервиса»), ошибка подписки на измерение в CONNECTED — срыв с причиной, и датчик, впервые
## запомненный этим подключением, из реестра снимается (REQ-DEV-03, REQ-DEV-07 п.1, REQ-DEV-06 п.1).

const PROFILE: String = "p1"

var _dir: String
var _bridge: StubBleBridge
var _remembered: RememberedDevices
var _cm: ConnectionManager


func before_each() -> void:
	_dir = "user://test_t154_subscribe_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_bridge = StubBleBridge.new()
	_remembered = RememberedDevices.new(_dir)
	_cm = ConnectionManager.new(_bridge, _remembered)
	_cm.set_profile(PROFILE)


func after_each() -> void:
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


func test_empty_service_list_is_not_connected_and_not_remembered() -> void:
	_bridge.set_device_services("hrm", {})
	_cm.connect_sensor("hrm", RememberedDevices.KIND_HR)
	_bridge.pump()
	assert_eq(_cm.state_of("hrm"), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_eq(_cm.failure_of("hrm"), SensorDevice.FailureReason.NO_SERVICE)
	assert_true(_remembered.find(PROFILE, "hrm").is_empty(), "в реестр не попал")


func test_new_sensor_failing_measurement_subscribe_is_forgotten_with_reason() -> void:
	_bridge.set_device_services("hrm", {"180D": ["2A37"]})
	_cm.connect_sensor("hrm", RememberedDevices.KIND_HR)
	_bridge.pump()
	assert_eq(_cm.state_of("hrm"), TrainerDevice.ConnectionState.CONNECTED)
	assert_false(_remembered.find(PROFILE, "hrm").is_empty(), "после CONNECTED запомнен")
	_bridge.emit_error("hrm", BleBridge.ErrorCode.SERVICE_NOT_FOUND, "CoreBluetooth: service 180D not found (call discover_services first)")
	assert_eq(_cm.state_of("hrm"), TrainerDevice.ConnectionState.DISCONNECTED, "не «подключено» без данных")
	assert_eq(_cm.failure_of("hrm"), SensorDevice.FailureReason.NO_SERVICE, "с причиной")
	assert_true(_remembered.find(PROFILE, "hrm").is_empty(), "без запоминания")


func test_previously_remembered_sensor_is_kept_after_subscribe_failure() -> void:
	assert_true(_remembered.remember(PROFILE, RememberedDevices.make_device("hrm", "HRM", RememberedDevices.KIND_HR)))
	_bridge.set_device_services("hrm", {"180D": ["2A37"]})
	_cm.connect_sensor("hrm", RememberedDevices.KIND_HR)
	_bridge.pump()
	_bridge.emit_error("hrm", BleBridge.ErrorCode.SERVICE_NOT_FOUND, "service 180D not found")
	assert_eq(_cm.state_of("hrm"), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_false(_remembered.find(PROFILE, "hrm").is_empty(), "запомненное раньше не забывается из-за срыва")


func test_battery_subscribe_failure_keeps_sensor_connected_and_remembered() -> void:
	_bridge.set_device_services("hrm", {"180D": ["2A37"], "180F": ["2A19"]})
	_cm.connect_sensor("hrm", RememberedDevices.KIND_HR)
	_bridge.pump()
	_bridge.emit_error("hrm", BleBridge.ErrorCode.SUBSCRIBE_FAILED, "setNotifyValue 180F/2A19: not permitted")
	_bridge.emit_error("hrm", BleBridge.ErrorCode.CHARACTERISTIC_NOT_FOUND, "characteristic 2A19 not found")
	assert_eq(_cm.state_of("hrm"), TrainerDevice.ConnectionState.CONNECTED, "батарея подключение не роняет")
	assert_false(_remembered.find(PROFILE, "hrm").is_empty())


func test_link_loss_after_working_connection_keeps_new_record() -> void:
	_bridge.set_device_services("hrm", {"180D": ["2A37"]})
	_cm.connect_sensor("hrm", RememberedDevices.KIND_HR)
	_bridge.pump()
	_bridge.auto_connect = false
	_bridge.emit_disconnected("hrm", BleBridge.DisconnectReason.LINK_LOSS)
	assert_eq(_cm.state_of("hrm"), TrainerDevice.ConnectionState.RECONNECTING)
	_cm.disconnect_device("hrm")
	assert_false(_remembered.find(PROFILE, "hrm").is_empty(), "обрыв рабочей связи — запись остаётся")
