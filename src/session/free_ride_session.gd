class_name FreeRideSession
extends RefCounted
## Сессия свободной езды: езда по зацикленной трассе без плана тренировки
## (REQ-FRD-01 крит. 1–3, REQ-FRD-04 крит. 5, 9, REQ-FRD-05 крит. 5, 6, REQ-FRD-07 крит. 1–4).
##
## Связующий слой: знает только интерфейс `TrainerDevice`, не реализацию. Исполнителя
## интервалов нет: событий смены шага и целевой мощности нет, лимита по времени и
## дистанции нет — сессия кончается только явным `stop()` (подтверждение — на стороне UI).
## Подключением станка не управляет: ей передают подключаемое или подключённое устройство.
## Параметры профиля (вес, FTP, крутизна, уровень) передаются значениями: слой сессии
## профиль не импортирует (REQ-NFR-06 крит. 3).
##
## Время — извне: `tick(delta_sec)` (из `SessionTicker` — через его сигнал `ticked`, или
## напрямую). Дельта нарезается по границам целых секунд активного времени; в каждом
## куске сначала `trainer.tick`, затем (на границе секунды) закрытие слота, затем
## `SimController.tick` с уклоном новой позиции — команда с новым уклоном уходит в ту же
## секунду, когда позиция пересекла границу участка (FRD-04 крит. 5).
##
## Секунда активного времени (слот t − 1 закрывается на секунде t, как у `WorkoutSession`):
## мощность — последняя телеметрия за секунду (нет — 0 Вт для модели и «нет данных» в
## сэмпле); скорость v = `SpeedModel.step(P, вес, 1, g(s))` с полным уклоном трассы
## (FRD-04 крит. 8, 9 — источник скорости «модель», не скорость станка); позиция
## `RoutePosition.advance(v, 1)`; сэмпл с `{distance_m, altitude_m, grade_pct}` —
## накопленная дистанция от старта, h(s) и g(s) после продвижения (FRD-07 крит. 4).
##
## Станок — через `SimController` (FRD-04, FRD-05): старт — SIM `0x11` с уклоном точки
## старта или уровень `0x04`, если заранее выбран фиксированный режим (FRD-01 крит. 2);
## `set_target_power` не вызывается никогда. Принудительная отправка текущего режима —
## при старте, возобновлении и восстановлении связи (делает контроллер).
##
## Пауза (REQ-WRK-05 по смыслу, В-4; FRD-07 крит. 2): на станок ничего не уходит,
## время, дистанция, позиция и модель скорости стоят, слоты не пишутся; станок и
## контроллер продолжают тикать (контроллер считает реальное время между командами).
## Настройки режима и крутизны на паузе принимаются и уходят при `resume()`.
## Переключение режима и крутизны не трогает таймер, поток сэмплов и позицию
## (FRD-05 крит. 5): модель скорости в любом режиме считает полный уклон трассы.
##
## Журнал событий `events`: `{type, at_sec, value}` — тот же формат, что у
## `WorkoutSession` (`at_sec` — активное время, у паузы после возобновления —
## `duration_sec`, `until_sec`). Типы: `WorkoutSession.EVENT_START|PAUSE|RESUME|STOP|
## FINISH|DISCONNECT|RECONNECT`, события контроллера `SimController.EVENT_MODE|
## EVENT_STEEPNESS|EVENT_RESISTANCE` (FRD-05 крит. 6) и `EVENT_SIM_UNAVAILABLE`
## (один раз за сессию — станок не поддерживает SIM, FRD-04 крит. 6).
##
## Контракт записи для `RideRecorder` и `Ride.from_session` (T-064): сигналы
## `state_changed(int)` (значения `WorkoutSession.State`), `event_logged(Dictionary)`,
## `second_elapsed(int)`; методы `get_state()`, `elapsed_sec()`, `metadata()`; свойства
## `samples`, `events`, `started_at_unix`. Метаданные свободной езды — те же ключи, что
## у `Ride.free_ride_metadata` (класс хранилища слою сессии недоступен, ключи
## продублированы константами `META_*`; совпадение проверяет тест).
##
## Подписки на сигналы станка и контроллера — связанными методами; `dispose()`
## отключает их и освобождает контроллер.

## Активное время: доля секунды, ближе которой к целой секунде граница считается достигнутой.
const TIME_EPSILON: float = 1e-6
const DEFAULT_WEIGHT_KG: float = 75.0

## Станок не поддерживает SIM — сессия перешла на фиксированное сопротивление (FRD-04 крит. 6).
const EVENT_SIM_UNAVAILABLE: String = "sim_unavailable"

## Ключи метаданных свободной езды (как `Ride.KEY_*` и `Ride.free_ride_metadata`, REQ-FRD-07 крит. 3).
const META_RIDE_TYPE: String = "ride_type"
const RIDE_TYPE_FREE_RIDE: String = "free_ride"
const META_ROUTE_ID: String = "route_id"
const META_SIM_STEEPNESS_START_PCT: String = "sim_steepness_start_pct"
const META_TOTAL_DISTANCE_M: String = "total_distance_m"
const META_TOTAL_ASCENT_M: String = "total_ascent_m"

## Состояние сессии — значения `WorkoutSession.State` (контракт `RideRecorder`).
signal state_changed(state: int)
## Сессия завершена `stop()`.
signal session_finished()
## Добавлено событие в журнал.
signal event_logged(event: Dictionary)
## Закрыта секунда активного времени `elapsed_sec` (слот `elapsed_sec − 1` записан).
signal second_elapsed(elapsed_sec: int)
## Режим нагрузки сменился (`SimController.Mode`) — для HUD.
signal mode_changed(mode: int)
## Крутизна SIM сменилась, % — владелец сохраняет её в профиль (FRD-05 крит. 1).
signal steepness_changed(percent: int)
## Уровень фиксированного сопротивления сменился, % — владелец сохраняет его в профиль.
signal resistance_level_changed(percent: int)
## Станок не поддерживает SIM: режим — фиксированное сопротивление (сообщение на HUD — FRD-06 крит. 7).
signal simulation_unavailable()

var trainer: TrainerDevice
## Управление нагрузкой станка (SIM / фиксированное сопротивление).
var sim: SimController
## Трасса заезда.
var route: RouteCatalog.RouteDef
## Позиция на трассе (накопленная дистанция, s по модулю L, h(s), g(s), набор).
var position: RoutePosition
var samples := SampleStream.new()
## Журнал событий заезда.
var events: Array[Dictionary] = []
## Время старта, unix-секунды (0 — не стартовала).
var started_at_unix: int = 0
## Вес всадника для модели скорости, кг.
var weight_kg: float = DEFAULT_WEIGHT_KG
## FTP всадника на момент заезда, Вт (для метаданных: зоны сводки и графика; 0 — не задан).
var ftp_w: int = 0

var _state: WorkoutSession.State = WorkoutSession.State.IDLE
var _speed_model := SpeedModel.new()
var _steepness_start_pct: int = SimController.DEFAULT_STEEPNESS_PCT
var _mode_start: SimController.Mode = SimController.Mode.SIM
## Целые секунды активного времени и дробная часть текущей секунды.
var _elapsed_sec: int = 0
var _pending_sec: float = 0.0
var _latest_sample: TrainerSample = null
var _latest_hr_bpm: int = -1
var _power_age: int = -1
var _cadence_age: int = -1
var _hr_age: int = -1
var _sim_unavailable_logged: bool = false
var _pause_event_index: int = -1
## Всё протиканное время, включая паузы, с (для длительности пауз).
var _wall_sec: float = 0.0
var _pause_started_wall_sec: float = 0.0
var _paused_total_sec: float = 0.0


## `route_id` — трасса каталога (неизвестная — `RouteCatalog.DEFAULT_ID` с предупреждением);
## `steepness_pct` — крутизна SIM на старте (шаг 5 %); `initial_mode` — режим, выбранный
## пользователем до старта; `resistance_pct` — уровень фиксированного сопротивления.
func _init(device: TrainerDevice, route_id: String = RouteCatalog.DEFAULT_ID,
		steepness_pct: int = SimController.DEFAULT_STEEPNESS_PCT,
		rider_weight_kg: float = DEFAULT_WEIGHT_KG, rider_ftp_w: int = 0,
		initial_mode: SimController.Mode = SimController.Mode.SIM,
		resistance_pct: int = SimController.DEFAULT_RESISTANCE_PCT) -> void:
	trainer = device
	weight_kg = rider_weight_kg
	ftp_w = maxi(rider_ftp_w, 0)
	var resolved: String = RouteCatalog.resolve_id(route_id)
	if resolved != route_id:
		push_warning("FreeRideSession: трассы «%s» нет в каталоге, взята «%s»" % [route_id, resolved])
	route = RouteCatalog.get_route(resolved)
	position = RoutePosition.new(route.profile)
	samples.speed_source = SampleStream.SPEED_SOURCE_MODEL
	sim = SimController.new(device, steepness_pct, initial_mode, resistance_pct)
	_steepness_start_pct = sim.steepness_pct()
	_mode_start = initial_mode
	sim.ride_event.connect(_on_sim_event)
	sim.mode_changed.connect(_on_sim_mode_changed)
	sim.steepness_changed.connect(_on_sim_steepness_changed)
	sim.resistance_level_changed.connect(_on_sim_resistance_changed)
	sim.simulation_unavailable.connect(_on_sim_unavailable)
	trainer.telemetry.connect(_on_telemetry)
	trainer.heart_rate.connect(_on_heart_rate)
	trainer.connection_state_changed.connect(_on_connection_state_changed)


## Отключить подписки на станок и контроллер, освободить контроллер (разрыв ссылок).
## После `dispose()` сессия команд не шлёт и телеметрию не принимает.
func dispose() -> void:
	if trainer != null:
		if trainer.telemetry.is_connected(_on_telemetry):
			trainer.telemetry.disconnect(_on_telemetry)
		if trainer.heart_rate.is_connected(_on_heart_rate):
			trainer.heart_rate.disconnect(_on_heart_rate)
		if trainer.connection_state_changed.is_connected(_on_connection_state_changed):
			trainer.connection_state_changed.disconnect(_on_connection_state_changed)
	if sim != null:
		if sim.ride_event.is_connected(_on_sim_event):
			sim.ride_event.disconnect(_on_sim_event)
		if sim.mode_changed.is_connected(_on_sim_mode_changed):
			sim.mode_changed.disconnect(_on_sim_mode_changed)
		if sim.steepness_changed.is_connected(_on_sim_steepness_changed):
			sim.steepness_changed.disconnect(_on_sim_steepness_changed)
		if sim.resistance_level_changed.is_connected(_on_sim_resistance_changed):
			sim.resistance_level_changed.disconnect(_on_sim_resistance_changed)
		if sim.simulation_unavailable.is_connected(_on_sim_unavailable):
			sim.simulation_unavailable.disconnect(_on_sim_unavailable)
		sim.dispose()


# ---------------------------------------------------------------------------
# Управление
# ---------------------------------------------------------------------------

## Старт: событие `start`, затем контроллер отправляет текущий режим (SIM — уклон точки
## старта с крутизной, FIXED — уровень). Без связи команда уйдёт после CONNECTED.
## Сеть не нужна (FRD-01 крит. 3).
func start() -> void:
	if _state != WorkoutSession.State.IDLE:
		push_warning("FreeRideSession.start: сессия уже запущена")
		return
	started_at_unix = int(Time.get_unix_time_from_system())
	_set_state(WorkoutSession.State.RUNNING)
	_log(WorkoutSession.EVENT_START, 0)
	sim.start(position.grade_pct())


## Продвигает время. Большая дельта нарезается по границам целых секунд активного
## времени, чтобы станок, позиция и контроллер шли вперемежку (как у `WorkoutSession`).
func tick(delta_sec: float) -> void:
	if delta_sec <= 0.0 or not is_finite(delta_sec):
		return
	_wall_sec += delta_sec
	var remaining: float = delta_sec
	while remaining > 0.0:
		var piece: float = remaining
		var running: bool = _state == WorkoutSession.State.RUNNING
		if running:
			piece = minf(remaining, 1.0 - _pending_sec)
		trainer.tick(piece)
		# Обработчики сигналов станка могли остановить сессию (stop из UI по сигналу).
		if running and _state == WorkoutSession.State.RUNNING:
			_pending_sec += piece
			if _pending_sec >= 1.0 - TIME_EPSILON:
				_pending_sec = 0.0
				_close_second()
		if sim != null:
			sim.tick(piece, position.grade_pct())
		remaining -= piece


## Пауза: на станок ничего не уходит; время, дистанция и позиция стоят.
func pause() -> void:
	if _state != WorkoutSession.State.RUNNING:
		return
	sim.pause()
	_set_state(WorkoutSession.State.PAUSED)
	_pause_event_index = events.size()
	_pause_started_wall_sec = _wall_sec
	_log(WorkoutSession.EVENT_PAUSE, _elapsed_sec)


## Возобновление: текущий режим уходит на станок принудительно (FRD-04 крит. 5).
func resume() -> void:
	if _state != WorkoutSession.State.PAUSED:
		return
	_set_state(WorkoutSession.State.RUNNING)
	_close_pause()
	# Телеметрия, пришедшая на паузе, к активным секундам не относится.
	_latest_sample = null
	_latest_hr_bpm = -1
	_log(WorkoutSession.EVENT_RESUME, _elapsed_sec)
	sim.resume()


## Завершение — только явным вызовом (подтверждение — на стороне UI, FRD-07 крит. 2).
## Незакрытая доля секунды отбрасывается; на паузе пауза закрывается. После `stop()`
## команд на станок нет; запись завершает `RideRecorder` по `state_changed(FINISHED)`.
func stop() -> void:
	if _state != WorkoutSession.State.RUNNING and _state != WorkoutSession.State.PAUSED:
		return
	_close_pause()
	_log(WorkoutSession.EVENT_STOP, _elapsed_sec)
	sim.stop()
	_log(WorkoutSession.EVENT_FINISH, _elapsed_sec)
	_set_state(WorkoutSession.State.FINISHED)
	session_finished.emit()


## Крутизна SIM, % (0..100, шаг 5; FRD-05 крит. 1, 3).
func set_steepness(percent: int) -> void:
	sim.set_steepness(percent)


## Уровень фиксированного сопротивления, % (0..100, шаг 5; FRD-05 крит. 4).
func set_resistance_level(percent: int) -> void:
	sim.set_resistance_level(percent)


## Режим SIM ↔ фиксированное сопротивление (FRD-05 крит. 4). Возвращает, действует ли
## запрошенный режим (без поддержки SIM возврат в SIM отклоняется).
func set_mode(new_mode: SimController.Mode) -> bool:
	return sim.set_mode(new_mode)


## Одно действие пользователя «SIM ↔ сопротивление».
func toggle_mode() -> bool:
	return sim.toggle_mode()


# ---------------------------------------------------------------------------
# Состояние
# ---------------------------------------------------------------------------

## Значение `WorkoutSession.State`.
func get_state() -> int:
	return _state


## Целые секунды активного времени (пауза не входит).
func elapsed_sec() -> int:
	return _elapsed_sec


## Активное время с дробной частью, с.
func session_time_sec() -> float:
	return float(_elapsed_sec) + _pending_sec


## Скорость модели, км/ч (на паузе стоит).
func speed_kmh() -> float:
	return _speed_model.speed_kmh


## Накопленная дистанция от старта, м (не по модулю круга).
func distance_m() -> float:
	return position.distance_m()


## Набор высоты с начала заезда, м.
func ascent_m() -> float:
	return position.ascent_m()


## Полный уклон трассы g(s) в текущей позиции, % (на HUD; крутизна не применяется, FRD-06 крит. 2).
func route_grade_pct() -> float:
	return position.grade_pct()


func mode() -> SimController.Mode:
	return sim.mode()


func steepness_pct() -> int:
	return sim.steepness_pct()


func resistance_level() -> int:
	return sim.resistance_level()


## Возраст данных источника (`"power"|"cadence"|"heart_rate"`) на момент последнего слота, с; -1 — не было.
func data_age_sec(source: String) -> int:
	match source:
		"power":
			return _power_age
		"cadence":
			return _cadence_age
		"heart_rate":
			return _hr_age
	return -1


## Метаданные заезда (LOC-01 крит. 1 и FRD-07 крит. 3): тип «свободная езда», трасса,
## крутизна на старте, источник скорости — модель, итоговые дистанция и набор; плана нет;
## источник станка (эмулятор / реальное устройство, T-160).
func metadata() -> Dictionary:
	return {
		META_RIDE_TYPE: RIDE_TYPE_FREE_RIDE,
		WorkoutSession.META_TRAINER_SOURCE: trainer.trainer_source() if trainer != null else TrainerDevice.SOURCE_BLE,
		META_ROUTE_ID: route.id,
		META_SIM_STEEPNESS_START_PCT: float(_steepness_start_pct),
		"speed_source": SampleStream.SPEED_SOURCE_MODEL,
		"started_at_unix": started_at_unix,
		"ftp_w": ftp_w,
		"weight_kg": weight_kg,
		"sim_mode_start": SimController.mode_to_name(_mode_start),
		"sim_mode": sim.mode_name() if sim != null else SimController.mode_to_name(_mode_start),
		"sim_steepness_pct": sim.steepness_pct() if sim != null else _steepness_start_pct,
		"resistance_level": sim.resistance_level() if sim != null else SimController.DEFAULT_RESISTANCE_PCT,
		"stopped_early": false,
		"elapsed_sec": _elapsed_sec,
		"paused_total_sec": _paused_total_sec,
		"distance_m": position.distance_m(),
		META_TOTAL_DISTANCE_M: position.distance_m(),
		META_TOTAL_ASCENT_M: position.ascent_m(),
		"laps_completed": position.laps_completed(),
		"sample_count": samples.size(),
		"event_count": events.size(),
	}


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _set_state(state: WorkoutSession.State) -> void:
	if state == _state:
		return
	_state = state
	state_changed.emit(state)


func _log(type: String, value: Variant) -> void:
	var event := {"type": type, "at_sec": session_time_sec(), "value": value}
	events.append(event)
	event_logged.emit(event)


func _is_started() -> bool:
	return _state == WorkoutSession.State.RUNNING or _state == WorkoutSession.State.PAUSED


## Закрыть открытую паузу: учесть длительность по протиканному времени и дописать
## `duration_sec`/`until_sec` в событие паузы. Без открытой паузы — ничего.
func _close_pause() -> void:
	if _pause_event_index < 0:
		return
	if _pause_event_index < events.size():
		var paused_for: float = maxf(_wall_sec - _pause_started_wall_sec, 0.0)
		_paused_total_sec += paused_for
		events[_pause_event_index]["duration_sec"] = paused_for
		events[_pause_event_index]["until_sec"] = float(events[_pause_event_index]["at_sec"]) + paused_for
	_pause_event_index = -1


## Закрыть секунду активного времени: модель скорости, позиция, слот, сигнал.
func _close_second() -> void:
	_elapsed_sec += 1
	var sample := _latest_sample
	_power_age = 0 if sample != null and sample.has_power else (_power_age + 1 if _power_age >= 0 else -1)
	_cadence_age = 0 if sample != null and sample.has_cadence else (_cadence_age + 1 if _cadence_age >= 0 else -1)
	_hr_age = 0 if _latest_hr_bpm >= 0 else (_hr_age + 1 if _hr_age >= 0 else -1)
	var power: float = float(sample.power_w) if sample != null and sample.has_power else 0.0
	var v: float = _speed_model.step(power, weight_kg, 1.0, position.grade_pct())
	position.advance(v, 1.0)
	samples.append(_elapsed_sec - 1, sample, _latest_hr_bpm, 0, -1, false, v,
		{"power": _power_age, "cadence": _cadence_age, "heart_rate": _hr_age},
		{"distance_m": position.distance_m(), "altitude_m": position.height_m(), "grade_pct": position.grade_pct()})
	_latest_sample = null
	_latest_hr_bpm = -1
	second_elapsed.emit(_elapsed_sec)


func _on_telemetry(sample: TrainerSample) -> void:
	if _state == WorkoutSession.State.RUNNING:
		_latest_sample = sample


## Пульс 0 от датчика — «нет данных» (как у `WorkoutSession`).
func _on_heart_rate(bpm: int) -> void:
	if _state == WorkoutSession.State.RUNNING:
		_latest_hr_bpm = bpm if bpm > 0 else -1


## Обрыв и восстановление — события журнала; повторную отправку режима после
## CONNECTED делает контроллер (на паузе — при `resume()`).
func _on_connection_state_changed(state: int) -> void:
	if not _is_started():
		return
	match state:
		TrainerDevice.ConnectionState.RECONNECTING, TrainerDevice.ConnectionState.DISCONNECTED:
			_log(WorkoutSession.EVENT_DISCONNECT, TrainerDevice.state_name(state))
		TrainerDevice.ConnectionState.CONNECTED:
			_log(WorkoutSession.EVENT_RECONNECT, TrainerDevice.state_name(state))


func _on_sim_event(type: String, value: Variant) -> void:
	if _is_started():
		_log(type, value)


func _on_sim_mode_changed(new_mode: int) -> void:
	mode_changed.emit(new_mode)


func _on_sim_steepness_changed(percent: int) -> void:
	steepness_changed.emit(percent)


func _on_sim_resistance_changed(percent: int) -> void:
	resistance_level_changed.emit(percent)


func _on_sim_unavailable() -> void:
	if _is_started() and not _sim_unavailable_logged:
		_sim_unavailable_logged = true
		_log(EVENT_SIM_UNAVAILABLE, sim.mode_name())
	simulation_unavailable.emit()
