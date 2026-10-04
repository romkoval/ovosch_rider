class_name FreeRideHudModel
extends RefCounted
## Модель HUD свободной езды (REQ-FRD-06 крит. 1, 2, 7; REQ-FRD-05 крит. 6 — отображение):
## подписывается на `FreeRideSession` и собирает словарь для `HudMetricPanel.set_state` в
## режиме `FREE_RIDE` — только числа, токены и готовые строки, без узлов сцены.
##
## Правила те же, что у `HudModel` тренировки (HUD-05, HUD-09):
## - сглаженная мощность — `PowerSmoother` 3 с по слотам потока 1 Гц; зона — по сглаженной
##   мощности и зонам профиля (мощность 0 → Z1, «нет данных» → «—»);
## - пульс и каденс — из последнего слота потока; зона пульса — по профилю (без `max_hr` и
##   своих зон — «—» без цвета);
## - время `мм:сс` до часа, далее `ч:мм:сс`; пауза не входит;
## - скорость — модели с уклоном (`FreeRideSession.speed_kmh()`, FRD-04 крит. 9), один знак;
## - уклон трассы g(s) (не переданный станку), режим и крутизна/уровень, дистанция, набор,
##   доля круга — `HudMetricPanel.free_ride_fields(session)`;
## - цели, отклонения и отсчёта нет (FRD-06 крит. 1).
##
## Дополнительно для экрана: состояние сессии и связи (фишки статусов) и `sim_unavailable` —
## станок не поддерживает SIM (FRD-04 крит. 6; сообщение на HUD показывает экран).
##
## Подписки — связанными методами; `dispose()` их снимает (цикл ссылок модель ↔ сессия).

const SMOOTHING_WINDOW_SEC: int = HudModel.SMOOTHING_WINDOW_SEC

## Состояние пересчитано (каждая секунда, смена режима, крутизны, уровня, связи, паузы).
signal changed(state: Dictionary)

var session: FreeRideSession
var profile: Profile = null

var _smoother := PowerSmoother.new(SMOOTHING_WINDOW_SEC)
var _sim_unavailable: bool = false
var _state: Dictionary = {}


func _init(ride_session: FreeRideSession, rider_profile: Profile = null) -> void:
	session = ride_session
	profile = rider_profile
	session.second_elapsed.connect(_on_second_elapsed)
	session.state_changed.connect(_refresh_int)
	session.mode_changed.connect(_refresh_int)
	session.steepness_changed.connect(_refresh_int)
	session.resistance_level_changed.connect(_refresh_int)
	session.simulation_unavailable.connect(_on_simulation_unavailable)
	session.trainer.connection_state_changed.connect(_refresh_int)
	refresh()


## Снять подписки на сессию и станок.
func dispose() -> void:
	if session == null:
		return
	for pair: Array in _subscriptions():
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])
	session = null


## Последнее вычисленное состояние (копия).
func state() -> Dictionary:
	return _state.duplicate()


## Станок не поддерживает SIM (событие пришло хотя бы раз за сессию).
func is_sim_unavailable() -> bool:
	return _sim_unavailable


## Пересчитать состояние и испустить `changed`.
func refresh() -> Dictionary:
	if session == null:
		return _state
	_state = _compute()
	changed.emit(_state.duplicate())
	return _state


func _compute() -> Dictionary:
	var smoothed: int = _smoother.value()
	var has_power: bool = smoothed != PowerSmoother.NO_VALUE
	var row: Dictionary = session.samples.last_row()
	var hr: int = int(row["heart_rate_bpm"]) if row.get("has_heart_rate", false) else HudModel.NO_DATA
	var cadence: int = int(row["cadence_rpm"]) if row.get("has_cadence", false) else HudModel.NO_DATA
	var speed: float = session.speed_kmh()
	var power_zone: int = _power_zone(smoothed) if has_power else 0
	var hr_zone: int = profile.hr_zone_of(hr) if profile != null and hr >= 0 else 0
	var connection: int = session.trainer.get_connection_state()
	var state := {
		"session_state": session.get_state(),
		"connection_state": connection,
		"connection_key": HudModel.connection_key(connection),
		"smoothed_power_w": smoothed if has_power else HudModel.NO_DATA,
		"power_text": ("%d" % smoothed) if has_power else HudModel.NO_DATA_TEXT,
		"power_zone": power_zone,
		"power_zone_text": ("Z%d" % power_zone) if power_zone > 0 else HudModel.NO_DATA_TEXT,
		"power_zone_token": ZonePalette.power_token(power_zone),
		"hr_bpm": hr,
		"hr_text": ("%d" % hr) if hr >= 0 else HudModel.NO_DATA_TEXT,
		"hr_zone": hr_zone,
		"hr_zone_text": ("Z%d" % hr_zone) if hr_zone > 0 else HudModel.NO_DATA_TEXT,
		"hr_zone_token": ZonePalette.hr_token(hr_zone),
		"cadence_rpm": cadence,
		"cadence_text": ("%d" % cadence) if cadence >= 0 else HudModel.NO_DATA_TEXT,
		"speed_kmh": speed,
		"speed_text": HudModel.format_speed(speed),
		"elapsed_sec": session.elapsed_sec(),
		"elapsed_text": HudModel.format_elapsed(session.elapsed_sec()),
		"sim_unavailable": _sim_unavailable,
		"lap_number": session.position.lap_number(),
	}
	state.merge(HudMetricPanel.free_ride_fields(session), true)
	return state


func _power_zone(power_w: int) -> int:
	if profile != null:
		return profile.power_zone_of(power_w)
	return Zones.power_zone(power_w, session.ftp_w)


func _on_second_elapsed(_elapsed_sec: int) -> void:
	# Сессия уже закрыла слот — читаем его.
	var row: Dictionary = session.samples.last_row()
	if row.get("has_power", false):
		_smoother.push(int(row["power_w"]))
	else:
		_smoother.push_missing()
	refresh()


func _on_simulation_unavailable() -> void:
	_sim_unavailable = true
	refresh()


func _refresh_int(_value: int) -> void:
	refresh()


func _subscriptions() -> Array[Array]:
	return [
		[session.second_elapsed, _on_second_elapsed],
		[session.state_changed, _refresh_int],
		[session.mode_changed, _refresh_int],
		[session.steepness_changed, _refresh_int],
		[session.resistance_level_changed, _refresh_int],
		[session.simulation_unavailable, _on_simulation_unavailable],
		[session.trainer.connection_state_changed, _refresh_int],
	]
