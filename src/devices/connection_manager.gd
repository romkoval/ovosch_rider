class_name ConnectionManager
extends RefCounted
## Менеджер подключений: владеет мостом, сканером, станком, датчиками и `SensorHub`
## (REQ-DEV-01 крит. 4, REQ-DEV-06 крит. 1–4, REQ-DEV-07 крит. 1–3, REQ-PRF-04 крит. 2–3).
##
## - `connect_trainer(id)` / `connect_sensor(id, kind)` — подключение; при CONNECTED
##   устройство запоминается (`RememberedDevices.remember`, станок — общий) и помечается
##   `mark_seen`; сканирование останавливается, когда ждать больше некого (DEV-01 крит. 4).
## - `auto_connect(profile_id)` — запоминает кандидатов `auto_connect_candidates`, запускает
##   сканирование и подключает каждого сразу после его рекламы (DEV-06 крит. 2);
##   через `AUTO_CONNECT_TIMEOUT_SEC` (30 с) без рекламы — `auto_connect_timed_out(ids)`
##   («устройство не найдено», крит. 3). Незапомненные устройства не подключаются.
## - `forget(profile_id, id)` — отключение и удаление из реестра (крит. 4).
## - `device_states()` — `id → {state, battery, kind}` для UI, `state_changed(id)`.
## - Станок создаётся через `TrainerFactory`: `"ble"` → `BleTrainer` поверх моста,
##   иначе (`"fake"`) — эмулятор для режима разработки.
## - REQ-DEV-01 крит. 7: при `bridge.is_available() == false` или адаптере не POWERED_ON
##   сканирование и автоподключение не стартуют (`start_scan()` → false, `is_ble_available()`).
##   Автоподключение, запрошенное до готовности адаптера (на macOS при запуске состояние
##   UNKNOWN), запоминается (`is_auto_connect_deferred()`) и выполняется при переходе
##   адаптера в POWERED_ON (REQ-DEV-06 крит. 2, 5). Отменяется `cancel_auto_connect()`,
##   сменой профиля и `dispose()`.
## - Устройство, рекламировавшееся в текущем сеансе сканирования, считается доступным
##   для автоподключения, даже если сканер уже пометил его недоступным или убрал из списка
##   (`BleScanner.seen_in_session`).
## - `stop_scan()` гасит только ручное сканирование: если идёт автоподключение, сканер
##   остаётся у него и остановится сам по успеху/таймауту (D-5).
## - `tick(delta)` продвигает сканер, таймер автоподключения и — пока `ticks_devices`
##   истинно — `SensorHub` (станок + датчики). Когда сессия тренировки берёт хаб под
##   свой `SessionTicker`, владелец ставит `ticks_devices = false`, иначе устройства
##   получат время дважды.

const AUTO_CONNECT_TIMEOUT_SEC: float = 30.0

## Состояние/заряд устройства изменилось.
signal state_changed(id: String)
## Список найденных или запомненных устройств изменился.
signal devices_changed()
## Автоподключение прекращено по таймауту; `ids` — не найденные устройства.
signal auto_connect_timed_out(ids: Array[String])

var bridge: BleBridge
var scanner: BleScanner
var remembered: RememberedDevices
var trainer: TrainerDevice
var hub: SensorHub
## kind ("hr"|"cadence"|"power") → датчик (создаётся при первом подключении).
var sensors: Dictionary = {}
## id станка, которому отдана команда подключения ("" — нет).
var trainer_id: String = ""
## kind → id подключаемого датчика.
var sensor_ids: Dictionary = {}
var profile_id: String = ""
## Глобальный переключатель автоподключения (экран устройств).
var auto_connect_enabled: bool = true
var ticks_devices: bool = true

var _time_sec: float = 0.0
var _auto_pending: Dictionary = {}
var _auto_deadline_sec: float = -1.0
var _auto_started_scan: bool = false
var _battery: Dictionary = {}
## Профиль, автоподключение которого ждёт POWERED_ON ("" — не ждёт).
var _deferred_auto_profile: String = ""
var _auto_connect_deferred: bool = false
## kind → [Callable состояния, Callable батареи] — связанные обработчики датчика.
var _sensor_handlers: Dictionary = {}


func _init(ble_bridge: BleBridge, remembered_devices: RememberedDevices,
		trainer_kind: String = TrainerFactory.KIND_BLE) -> void:
	bridge = ble_bridge
	remembered = remembered_devices
	scanner = BleScanner.new(bridge)
	scanner.device_found.connect(_on_scanner_device_found)
	scanner.devices_changed.connect(_forward_devices_changed)
	remembered.changed.connect(_forward_devices_changed)
	bridge.adapter_state_changed.connect(_on_adapter_state_changed)
	if trainer_kind == TrainerFactory.KIND_BLE:
		trainer = TrainerFactory.create_ble(bridge)
	else:
		trainer = TrainerFactory.create(trainer_kind)
	hub = SensorHub.new(trainer)
	trainer.connection_state_changed.connect(_on_trainer_state)
	if trainer.has_signal("battery_level"):
		trainer.connect("battery_level", _on_trainer_battery)


## Освободить всё: отключить обработчики, `dispose()` у хаба, станка, датчиков и сканера.
## Вызывается владельцем при закрытии приложения; после этого менеджер неработоспособен.
func dispose() -> void:
	cancel_auto_connect()
	if scanner != null:
		if scanner.device_found.is_connected(_on_scanner_device_found):
			scanner.device_found.disconnect(_on_scanner_device_found)
		if scanner.devices_changed.is_connected(_forward_devices_changed):
			scanner.devices_changed.disconnect(_forward_devices_changed)
		scanner.dispose()
	if remembered != null and remembered.changed.is_connected(_forward_devices_changed):
		remembered.changed.disconnect(_forward_devices_changed)
	if bridge != null and bridge.adapter_state_changed.is_connected(_on_adapter_state_changed):
		bridge.adapter_state_changed.disconnect(_on_adapter_state_changed)
	if hub != null:
		hub.dispose()
	if trainer != null:
		if trainer.connection_state_changed.is_connected(_on_trainer_state):
			trainer.connection_state_changed.disconnect(_on_trainer_state)
		if trainer.has_signal("battery_level") and trainer.is_connected("battery_level", _on_trainer_battery):
			trainer.disconnect("battery_level", _on_trainer_battery)
		if trainer.has_method("dispose"):
			trainer.call("dispose")
	for kind in sensors:
		var s: SensorDevice = sensors[kind]
		if _sensor_handlers.has(kind):
			var cbs: Array = _sensor_handlers[kind]
			if s.connection_state_changed.is_connected(cbs[0]):
				s.connection_state_changed.disconnect(cbs[0])
			if s.battery_level.is_connected(cbs[1]):
				s.battery_level.disconnect(cbs[1])
		if s.has_method("dispose"):
			s.call("dispose")
	sensors.clear()
	_sensor_handlers.clear()
	if bridge is StubBleBridge:
		(bridge as StubBleBridge).dispose()
	trainer = null
	hub = null
	scanner = null


func _forward_devices_changed() -> void:
	devices_changed.emit()


func _on_adapter_state_changed(_state: int) -> void:
	if not is_ble_available():
		var deferred: bool = _auto_connect_deferred
		var deferred_profile: String = _deferred_auto_profile
		cancel_auto_connect()
		# Ожидание POWERED_ON переживает промежуточные состояния (UNKNOWN → POWERED_OFF → …).
		_auto_connect_deferred = deferred
		_deferred_auto_profile = deferred_profile
		scanner.stop()
	elif _auto_connect_deferred:
		_auto_connect_deferred = false
		auto_connect(_deferred_auto_profile)
	devices_changed.emit()


func _on_trainer_battery(percent: int) -> void:
	_on_battery(trainer_id, percent)


func get_time_sec() -> float:
	return _time_sec


# ---------------------------------------------------------------------------
# Подключение
# ---------------------------------------------------------------------------

func set_profile(id: String) -> void:
	if id == profile_id:
		return
	profile_id = id
	cancel_auto_connect()
	devices_changed.emit()


## Bluetooth доступен: мост загружен и адаптер включён (REQ-DEV-01 крит. 7).
func is_ble_available() -> bool:
	return bridge != null and bridge.is_available() \
		and bridge.get_adapter_state() == BleBridge.AdapterState.POWERED_ON


## Запустить ручное сканирование; false — Bluetooth недоступен (REQ-DEV-01 крит. 7).
func start_scan() -> bool:
	if not is_ble_available():
		return false
	scanner.start()
	return true


## Остановить ручное сканирование. Идущее автоподключение забирает сканер себе
## и останавливает его само (успех или таймаут 30 с).
func stop_scan() -> void:
	if is_auto_connecting():
		_auto_started_scan = true
		return
	scanner.stop()


func connect_trainer(id: String) -> void:
	if id.is_empty():
		return
	if trainer_id != id and trainer.get_connection_state() != TrainerDevice.ConnectionState.DISCONNECTED:
		trainer.disconnect_device()
	trainer_id = id
	_auto_pending.erase(id)
	trainer.connect_device(id)
	state_changed.emit(id)


## false — пустой id или неизвестный тип датчика (предупреждение, без ошибки).
func connect_sensor(id: String, kind: String) -> bool:
	if id.is_empty() or not _is_sensor_kind(kind):
		push_warning("ConnectionManager.connect_sensor: неизвестный тип датчика '%s' (id '%s')" % [kind, id])
		return false
	var sensor: SensorDevice = _sensor(kind)
	if str(sensor_ids.get(kind, "")) != id and sensor.get_connection_state() != TrainerDevice.ConnectionState.DISCONNECTED:
		sensor.disconnect_device()
	sensor_ids[kind] = id
	_auto_pending.erase(id)
	sensor.connect_device(id)
	state_changed.emit(id)
	return true


## Подключить устройство по записи реестра/сканера (`kind` решает, станок это или датчик).
func connect_record(record: Dictionary) -> void:
	var id: String = str(record.get("id", ""))
	var kind: String = str(record.get("kind", ""))
	if kind == RememberedDevices.KIND_TRAINER:
		connect_trainer(id)
	elif _is_sensor_kind(kind):
		connect_sensor(id, kind)
	else:
		push_warning("ConnectionManager: устройство %s неизвестного типа '%s' не подключается" % [id, kind])


func disconnect_device(id: String) -> void:
	if id == trainer_id:
		trainer.disconnect_device()
		state_changed.emit(id)
	for kind in sensor_ids:
		if str(sensor_ids[kind]) == id:
			(sensors[kind] as SensorDevice).disconnect_device()
			state_changed.emit(id)


func disconnect_all() -> void:
	cancel_auto_connect()
	scanner.stop()
	if not trainer_id.is_empty():
		trainer.disconnect_device()
		state_changed.emit(trainer_id)
	for kind in sensors:
		(sensors[kind] as SensorDevice).disconnect_device()
		if sensor_ids.has(kind):
			state_changed.emit(str(sensor_ids[kind]))


## «Забыть»: отключить и удалить из реестра; автоподключение к нему больше не выполняется.
## Забытое устройство исчезает и из `device_states()` (сбрасываются `trainer_id`/`sensor_ids`).
func forget(for_profile_id: String, id: String) -> bool:
	disconnect_device(id)
	_auto_pending.erase(id)
	_battery.erase(id)
	if id == trainer_id:
		trainer_id = ""
	for kind in sensor_ids.keys():
		if str(sensor_ids[kind]) == id:
			sensor_ids.erase(kind)
	var removed: bool = remembered.forget(for_profile_id, id)
	devices_changed.emit()
	return removed


# ---------------------------------------------------------------------------
# Автоподключение (REQ-DEV-06)
# ---------------------------------------------------------------------------

## Начать автоподключение запомненных устройств профиля (с `auto_connect == true`).
## Уже видимые в сканере — подключаются сразу, остальные — по мере рекламы.
func auto_connect(for_profile_id: String) -> void:
	profile_id = for_profile_id
	if not auto_connect_enabled:
		return
	if not is_ble_available():
		# Адаптер ещё не готов (UNKNOWN при запуске) — выполнить при POWERED_ON.
		_auto_connect_deferred = bridge != null
		_deferred_auto_profile = for_profile_id
		return
	_auto_connect_deferred = false
	var candidates := remembered.auto_connect_candidates(profile_id)
	if candidates.is_empty():
		return
	for c in candidates:
		var id: String = str(c["id"])
		if _is_connected_or_connecting(id):
			continue
		_auto_pending[id] = c
	if _auto_pending.is_empty():
		return
	_auto_deadline_sec = _time_sec + AUTO_CONNECT_TIMEOUT_SEC
	if not scanner.is_scanning():
		_auto_started_scan = true
		scanner.start()
	for id in _auto_pending.keys():
		var seen := scanner.find(id)
		if (not seen.is_empty() and seen["available"]) or scanner.seen_in_session(id):
			_connect_pending(id)


func cancel_auto_connect() -> void:
	_auto_connect_deferred = false
	_deferred_auto_profile = ""
	_auto_pending.clear()
	_auto_deadline_sec = -1.0
	if _auto_started_scan:
		_auto_started_scan = false
		scanner.stop()


func is_auto_connecting() -> bool:
	return not _auto_pending.is_empty()


## Автоподключение запрошено до готовности адаптера и ждёт POWERED_ON.
func is_auto_connect_deferred() -> bool:
	return _auto_connect_deferred


func pending_auto_connect_ids() -> Array[String]:
	var out: Array[String] = []
	for id in _auto_pending:
		out.append(str(id))
	return out


# ---------------------------------------------------------------------------
# Время и состояния
# ---------------------------------------------------------------------------

func tick(delta_sec: float) -> void:
	if delta_sec <= 0.0:
		return
	_time_sec += delta_sec
	if ticks_devices:
		hub.tick(delta_sec)
	scanner.tick(delta_sec)
	if not _auto_pending.is_empty() and _time_sec >= _auto_deadline_sec:
		var ids := pending_auto_connect_ids()
		cancel_auto_connect()
		auto_connect_timed_out.emit(ids)


## `id → {state, battery, kind}` для всех устройств, которым отдавалась команда подключения.
func device_states() -> Dictionary:
	var out: Dictionary = {}
	if not trainer_id.is_empty():
		out[trainer_id] = {"state": trainer.get_connection_state(), "battery": battery_of(trainer_id),
			"kind": RememberedDevices.KIND_TRAINER}
	for kind in sensor_ids:
		var id: String = str(sensor_ids[kind])
		out[id] = {"state": (sensors[kind] as SensorDevice).get_connection_state(), "battery": battery_of(id), "kind": kind}
	return out


## Состояние устройства (`TrainerDevice.ConnectionState`); DISCONNECTED, если неизвестно.
func state_of(id: String) -> int:
	var states := device_states()
	return int(states[id]["state"]) if states.has(id) else TrainerDevice.ConnectionState.DISCONNECTED


## Заряд, %; -1 — неизвестен («—», REQ-DEV-07 крит. 3).
func battery_of(id: String) -> int:
	return int(_battery.get(id, -1))


func is_device_connected(id: String) -> bool:
	return state_of(id) == TrainerDevice.ConnectionState.CONNECTED


func sensor(kind: String) -> SensorDevice:
	return sensors.get(kind, null)


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

static func _is_sensor_kind(kind: String) -> bool:
	return kind == RememberedDevices.KIND_HR or kind == RememberedDevices.KIND_CADENCE \
		or kind == RememberedDevices.KIND_POWER


func _sensor(kind: String) -> SensorDevice:
	if sensors.has(kind):
		return sensors[kind]
	var s: SensorDevice
	match kind:
		RememberedDevices.KIND_HR:
			s = BleHeartRateSensor.new(bridge)
			hub.set_heart_rate_sensor(s)
		RememberedDevices.KIND_CADENCE:
			s = BleCadenceSensor.new(bridge)
			hub.set_cadence_sensor(s)
		RememberedDevices.KIND_POWER:
			s = BlePowerMeter.new(bridge)
			hub.set_power_meter(s)
	sensors[kind] = s
	# Связанные методы, не лямбды: лямбда держала бы менеджер сильной ссылкой
	# (цикл менеджер → датчик → сигнал → лямбда → менеджер).
	var on_state: Callable = _on_sensor_state.bind(kind)
	var on_battery: Callable = _on_sensor_battery.bind(kind)
	_sensor_handlers[kind] = [on_state, on_battery]
	s.connection_state_changed.connect(on_state)
	s.battery_level.connect(on_battery)
	return s


func _is_connected_or_connecting(id: String) -> bool:
	var st := state_of(id)
	return st == TrainerDevice.ConnectionState.CONNECTED or st == TrainerDevice.ConnectionState.CONNECTING


func _connect_pending(id: String) -> void:
	var record: Dictionary = _auto_pending.get(id, {})
	_auto_pending.erase(id)
	if record.is_empty():
		return
	connect_record(record)
	if _auto_pending.is_empty():
		_auto_deadline_sec = -1.0
		if _auto_started_scan:
			_auto_started_scan = false
			scanner.stop()


func _on_scanner_device_found(device: Dictionary) -> void:
	var id: String = str(device["id"])
	if _auto_pending.has(id):
		_connect_pending(id)


func _on_trainer_state(state: int) -> void:
	if trainer_id.is_empty():
		return
	if state == TrainerDevice.ConnectionState.CONNECTED:
		_remember_connected(trainer_id, RememberedDevices.KIND_TRAINER)
		_stop_scan_if_idle()
	state_changed.emit(trainer_id)


func _on_sensor_battery(percent: int, kind: String) -> void:
	_on_battery(str(sensor_ids.get(kind, "")), percent)


func _on_sensor_state(state: int, kind: String) -> void:
	var id: String = str(sensor_ids.get(kind, ""))
	if id.is_empty():
		return
	if state == TrainerDevice.ConnectionState.CONNECTED:
		_remember_connected(id, kind)
		_stop_scan_if_idle()
	state_changed.emit(id)


func _on_battery(id: String, percent: int) -> void:
	if id.is_empty():
		return
	_battery[id] = percent
	state_changed.emit(id)


## REQ-DEV-01 крит. 4: при подключении сканирование останавливается, если больше никого не ждём.
func _stop_scan_if_idle() -> void:
	if _auto_pending.is_empty():
		_auto_started_scan = false
		scanner.stop()


## После успешного подключения: запомнить (DEV-06 крит. 1) или отметить «видели».
func _remember_connected(id: String, kind: String) -> void:
	var seen := scanner.find(id)
	var name: String = str(seen.get("name", ""))
	var existing := remembered.find(profile_id, id)
	if existing.is_empty():
		remembered.remember(profile_id, RememberedDevices.make_device(id, name, kind))
	else:
		if not name.is_empty() and str(existing.get("name", "")).is_empty():
			existing["name"] = name
			remembered.remember(profile_id, existing)
		remembered.mark_seen(profile_id, id)
