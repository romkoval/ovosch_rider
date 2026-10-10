class_name FecControl
extends RefCounted
## Управление станком по FE-C over BLE (REQ-DEV-11 п.6–9): запись страниц в FEC3, повтор,
## подтверждение страницей 0x47 и возможности страницы 0x36. Владелец — `BleTrainer` (протокол
## FE-C); он решает, что и когда писать, и передаёт сюда принятые из FEC2 страницы и события
## записи. Время — извне (`tick(now_sec)`).
##
## - Запись: `write(id, FEC1, FEC3, bytes, true)`. Отказ доставки (`write_done(ok = false)` или
##   `error(WRITE_FAILED)` моста) → один немедленный повтор тех же байт (п.7 (а)); второй отказ →
##   `command_error(WRITE_FAILED)`. Записи в полёте — очередь в порядке отправки (ответы
##   `write_done` приходят в том же порядке).
## - Подтверждение (п.7 (б)): после каждой 0x31 — запрос 0x47 страницей 0x46 и ожидание не дольше
##   `STATUS_TIMEOUT_SEC`. 0x47 с байтом 1 = `31`: Pass — цель применена; Fail / Rejected —
##   `command_error(CONTROL_POINT_REJECTED)`; Not supported — ERG недоступен до конца подключения
##   (`erg_unsupported`, дальнейших 0x31 нет) и `command_error(CONTROL_POINT_REJECTED)` с
##   сообщением. Нет ответа или байт 1 ≠ `31` — одна запись в лог, цель считается отправленной.
## - Возможности (п.8): `request_capabilities()` — запрос 0x36 и ожидание не дольше
##   `CAPABILITIES_TIMEOUT_SEC`; `capabilities_resolved` — ответ пришёл или время вышло (тогда все
##   режимы доступны).
## - Команда режима, совпадающая с последней командой режима, которая ещё ждёт `write_done`, не
##   дублируется. Без бита 1 (Target Power) 0x31 не пишется, без бита 2 (Simulation) — 0x33;
##   бит 0 (Basic Resistance) не учитывается до ответа по Н-61 (в).
## - SIM (п.9 (б)): при входе в SIM перед первой 0x33 один раз уходит 0x32 (`reset_simulation_entry`
##   — после смены режима и переподключения).

## Ожидание страниц 0x47 и 0x36, с.
const STATUS_TIMEOUT_SEC: float = 2.0
const CAPABILITIES_TIMEOUT_SEC: float = 2.0

## Ошибка команды или записи (`TrainerDevice.ErrorCode`) — владелец передаёт её дальше.
signal command_error(code: int, message: String)
## The trainer answered "not supported" to 0x31: ERG is unavailable until the end of the
## connection (DEV-11 p.7 (b), U-36) — a capability change (followed by `command_error`).
signal erg_unsupported_detected()
## Возможности станка определены (ответ 0x36 или тайм-аут).
signal capabilities_resolved()

var bridge: BleBridge
var device_id: String = ""
## Ответ 0x36 (`FecCodec.decode_capabilities`); пустой — ответа не было.
var capabilities: Dictionary = {}
## Возможности определены (ответ или тайм-аут) — для этого устройства больше не запрашиваются.
var capabilities_known: bool = false
## Станок ответил Not supported на 0x31: ERG недоступен до конца подключения.
var erg_unsupported: bool = false

var _now: float = 0.0
var _caps_deadline: float = -1.0
var _status_deadline: float = -1.0
## Записи, ждущие `write_done`: `{bytes, retried}`.
var _inflight: Array[Dictionary] = []
var _wind_sent: bool = false
## Последняя записанная страница режима (0x30 / 0x31 / 0x33).
var _last_mode := PackedByteArray()


func _init(ble_bridge: BleBridge) -> void:
	bridge = ble_bridge


## Новое устройство: возможности и признаки прежнего не действуют.
func set_device(id: String) -> void:
	if id != device_id:
		reset_capabilities()
	device_id = id
	reset_link()


## Forget the trainer's capabilities: they are determined again on every connection
## (DEV-10 p.5 (e), N-77 (a)).
func reset_capabilities() -> void:
	capabilities = {}
	capabilities_known = false
	erg_unsupported = false


## Связь (пере)установлена или разорвана: записи в полёте и ожидания сбрасываются, следующий вход
## в SIM снова начинается с 0x32. Возможности устройства сохраняются.
func reset_link() -> void:
	_inflight.clear()
	_last_mode = PackedByteArray()
	_status_deadline = -1.0
	_caps_deadline = -1.0
	_wind_sent = false


func tick(now_sec: float) -> void:
	_now = now_sec
	if _caps_deadline >= 0.0 and _now >= _caps_deadline - BleReconnectPolicy.TIME_EPSILON:
		_caps_deadline = -1.0
		push_warning("FecControl: станок не ответил на запрос возможностей (0x36) за %.0f с — все режимы считаются доступными" % CAPABILITIES_TIMEOUT_SEC)
		_resolve_capabilities()
	if _status_deadline >= 0.0 and _now >= _status_deadline - BleReconnectPolicy.TIME_EPSILON:
		_status_deadline = -1.0
		push_warning("FecControl: нет подтверждения 0x47 на цель 0x31 за %.0f с — цель считается отправленной" % STATUS_TIMEOUT_SEC)


## Запросить 0x36; если возможности уже известны — сразу `capabilities_resolved`.
func request_capabilities() -> void:
	if capabilities_known:
		capabilities_resolved.emit()
		return
	_write(FecCodec.encode_request_page(FecCodec.PAGE_CAPABILITIES))
	_caps_deadline = _now + CAPABILITIES_TIMEOUT_SEC


func is_waiting_capabilities() -> bool:
	return _caps_deadline >= 0.0


func supports_target_power() -> bool:
	return not erg_unsupported and bool(capabilities.get("target_power", true))


func supports_simulation() -> bool:
	return bool(capabilities.get("simulation", true))


## Цель ERG (0x31) и запрос подтверждения 0x47. Без поддержки — ничего.
func write_target_power(watts: int) -> void:
	if not supports_target_power():
		return
	var bytes := FecCodec.encode_target_power(watts)
	if _in_flight(bytes):
		return
	_wind_sent = false
	_write(bytes)
	_write(FecCodec.encode_request_page(FecCodec.PAGE_COMMAND_STATUS))
	_status_deadline = _now + STATUS_TIMEOUT_SEC


## Фиксированное сопротивление (0x30), уровень в процентах.
func write_resistance(percent: int) -> void:
	_wind_sent = false
	var bytes := FecCodec.encode_basic_resistance(percent)
	if not _in_flight(bytes):
		_write(bytes)


## SIM (0x33; при входе в SIM — сначала 0x32). Без поддержки или вне пределов кодека — ничего.
func write_simulation(grade_pct: float, wind_mps: float, crr: float, cw: float) -> void:
	if not supports_simulation():
		return
	var track := FecCodec.encode_track_resistance(grade_pct, crr)
	if track.is_empty():
		push_warning("FecControl: уклон %.2f %% вне пределов страницы 0x33, команда не отправлена" % grade_pct)
		return
	if not _wind_sent:
		_write(FecCodec.encode_wind_resistance(cw, wind_mps))
		_wind_sent = true
	if not _in_flight(track):
		_write(track)


## Выход из SIM (ERG): следующий вход снова начнётся с 0x32.
func reset_simulation_entry() -> void:
	_wind_sent = false


## Страница из FEC2: 0x36 и 0x47; прочие — не наши.
func on_page(page_number: int, page: PackedByteArray) -> void:
	match page_number:
		FecCodec.PAGE_CAPABILITIES:
			var c := FecCodec.decode_capabilities(page)
			if c["ok"] and not capabilities_known:
				capabilities = c
				_caps_deadline = -1.0
				_resolve_capabilities()
		FecCodec.PAGE_COMMAND_STATUS:
			if _status_deadline < 0.0:
				return
			_status_deadline = -1.0
			var st := FecCodec.decode_command_status(page)
			if not st["ok"] or int(st["last_command"]) != FecCodec.PAGE_TARGET_POWER:
				push_warning("FecControl: 0x47 не о цели 0x31 (последняя команда 0x%02X) — цель считается отправленной" % int(st["last_command"]))
				return
			match int(st["status"]):
				FecCodec.COMMAND_PASS:
					pass
				FecCodec.COMMAND_FAIL, FecCodec.COMMAND_REJECTED:
					command_error.emit(TrainerDevice.ErrorCode.CONTROL_POINT_REJECTED,
						"Станок отверг цель ERG (0x47: %s)" % ("fail" if int(st["status"]) == FecCodec.COMMAND_FAIL else "rejected"))
				FecCodec.COMMAND_NOT_SUPPORTED:
					erg_unsupported = true
					erg_unsupported_detected.emit()
					# Same as the FTMS `80 05 02` path: the refusal is also reported as a command error.
					command_error.emit(TrainerDevice.ErrorCode.CONTROL_POINT_REJECTED,
						"Станок не поддерживает ERG (0x47: not supported)")
				_:
					push_warning("FecControl: статус 0x47 = 0x%02X — цель считается отправленной" % int(st["status"]))


## `write_done` по FEC3: true — событие наше.
func on_write_done(ok: bool) -> void:
	if _inflight.is_empty():
		return
	var w: Dictionary = _inflight.pop_front()
	if ok:
		return
	_handle_failure(w, "write_done(ok = false)")


## `error(WRITE_FAILED)` моста: относится к первой записи в полёте. false — записей нет.
func on_write_error(message: String) -> bool:
	if _inflight.is_empty():
		return false
	_handle_failure(_inflight.pop_front(), message)
	return true


func has_writes_in_flight() -> bool:
	return not _inflight.is_empty()


func _handle_failure(w: Dictionary, reason: String) -> void:
	if not w["retried"]:
		_send(w["bytes"], true)
		return
	command_error.emit(TrainerDevice.ErrorCode.WRITE_FAILED,
		"Запись FE-C %s не удалась дважды (%s)" % [FecCodec.describe(w["bytes"]), reason])


## Та же страница уже записана и ждёт `write_done` — повтор команды режима не дублируется
## (как очередь Control Point у FTMS: шаг FreeRide даёт «ERG выкл» и уровень подряд).
func _in_flight(bytes: PackedByteArray) -> bool:
	if bytes != _last_mode:
		_last_mode = bytes
		return false
	for w in _inflight:
		if w["bytes"] == bytes:
			return true
	return false


func _resolve_capabilities() -> void:
	capabilities_known = true
	capabilities_resolved.emit()


func _write(bytes: PackedByteArray) -> void:
	_send(bytes, false)


func _send(bytes: PackedByteArray, retried: bool) -> void:
	if bridge == null or device_id.is_empty() or bytes.is_empty():
		return
	_inflight.append({"bytes": bytes, "retried": retried})
	bridge.write(device_id, BleUuids.FEC_SERVICE, BleUuids.FEC_WRITE, bytes, true)
