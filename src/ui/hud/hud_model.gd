class_name HudModel
extends RefCounted
## Модель HUD тренировки (REQ-HUD-01..09, REQ-WRK-07 крит. 4, REQ-INT-05 крит. 3):
## подписывается на `WorkoutSession` и выдаёт словарь состояния для отрисовки —
## только числа, токены и готовые строки; никаких узлов сцены.
##
## Правила:
## - сглаженная мощность — `PowerSmoother` 3 с по слотам потока 1 Гц (HUD-09;
##   в поток и FIT идёт сырая мощность — сглаживание живёт только здесь);
## - отклонение: «в цели», если |факт − цель| ≤ max(5 % цели, 10 Вт), иначе
##   «выше»/«ниже»; при цели «—» или без данных — скрыто (HUD-02, решение 6);
## - зона мощности — по сглаженной мощности и зонам профиля; мощность 0 → Z1,
##   «нет данных» → «—» (HUD-03 крит. 3); зона пульса — по профилю, без `max_hr`
##   и переопределения — «—» без цвета (HUD-04 крит. 2);
## - цвета зон — токены `ZonePalette` (`z1..z7`, `hr1..hr5`);
## - время: `мм:сс` до часа, далее `ч:мм:сс`; обратный отсчёт шага `мм:сс`,
##   «скоро смена» за 5 с (HUD-05/06); время паузы не входит (WRK-05);
## - подсказки показываются 10 с или до смены шага, длиннее 120 символов — обрезка с «…» (HUD-08, решение 21);
## - «нет данных» в числовых полях — -1, в текстовых — `NO_DATA_TEXT` («—»).
##
## `progress_segments()` — полоса HUD-07 на `Workout.segments(ftp, intensity)`:
## статус `done|current|skipped|upcoming` по исполнителю и журналу событий сессии,
## зона и ватты пересчитываются при смене множителя (WRK-07 крит. 4).

const NO_DATA: int = -1
const NO_DATA_TEXT: String = "—"

const DEVIATION_HIDDEN: String = "hidden"
const DEVIATION_BELOW: String = "below"
const DEVIATION_ON: String = "on"
const DEVIATION_ABOVE: String = "above"
## Порог «в цели»: max(5 % цели, 10 Вт).
const DEVIATION_PCT: float = 0.05
const DEVIATION_MIN_W: int = 10

const SEGMENT_DONE: String = "done"
const SEGMENT_CURRENT: String = "current"
const SEGMENT_SKIPPED: String = "skipped"
const SEGMENT_UPCOMING: String = "upcoming"

const CUE_SHOW_SEC: int = 10
const CUE_MAX_LENGTH: int = 120
const CUE_ELLIPSIS: String = "…"
const ABOUT_TO_CHANGE_SEC: int = 5
const SMOOTHING_WINDOW_SEC: int = 3

## Состояние пересчитано (после каждой секунды, смены шага, подсказки, режима).
signal changed(state: Dictionary)

var session: WorkoutSession
var profile: Profile = null

var _smoother := PowerSmoother.new(SMOOTHING_WINDOW_SEC)
var _cue_text: String = ""
var _cue_until_sec: int = -1
var _state: Dictionary = {}


func _init(workout_session: WorkoutSession, rider_profile: Profile = null) -> void:
	session = workout_session
	profile = rider_profile
	var ex := session.executor
	ex.second_elapsed.connect(_on_second_elapsed)
	ex.step_changed.connect(_on_step_changed)
	# Только связанные методы, не лямбды: лямбда захватывает self сильной ссылкой и
	# образует цикл модель → сессия → сигнал → лямбда → модель (утечка RefCounted).
	ex.target_changed.connect(_refresh_int)
	ex.cue.connect(_on_cue)
	ex.finished.connect(refresh)
	session.state_changed.connect(_refresh_int)
	session.erg_changed.connect(_refresh_bool)
	session.intensity_changed.connect(_refresh_float)
	session.trainer.connection_state_changed.connect(_refresh_int)
	refresh()


# ---------------------------------------------------------------------------
# Состояние
# ---------------------------------------------------------------------------

## Последнее вычисленное состояние (копия).
func state() -> Dictionary:
	return _state.duplicate()


## Пересчитать состояние и испустить `changed`.
func refresh() -> Dictionary:
	_state = _compute()
	changed.emit(_state.duplicate())
	return _state


func _compute() -> Dictionary:
	var ex := session.executor
	var target: int = session.current_target_watts()
	var has_target: bool = target > 0 and ex.current_step_index() >= 0
	var smoothed: int = _smoother.value()
	var has_power: bool = smoothed != PowerSmoother.NO_VALUE
	var row: Dictionary = session.samples.last_row()
	var hr: int = int(row["heart_rate_bpm"]) if row.get("has_heart_rate", false) else NO_DATA
	var cadence: int = int(row["cadence_rpm"]) if row.get("has_cadence", false) else NO_DATA
	var speed: float = float(row["speed_kmh"]) if row.get("has_speed", false) else float(NO_DATA)
	var power_zone: int = _power_zone(smoothed) if has_power else 0
	var hr_zone: int = _hr_zone(hr) if hr >= 0 else 0
	var remaining: int = ex.step_remaining_sec()
	var total_steps: int = ex.workout.steps.size()
	var step_index: int = ex.current_step_index()
	return {
		"session_state": session.get_state(),
		"connection_state": session.trainer.get_connection_state(),
		"connection_key": connection_key(session.trainer.get_connection_state()),
		"target_w": target if has_target else NO_DATA,
		"target_text": ("%d" % target) if has_target else NO_DATA_TEXT,
		"smoothed_power_w": smoothed if has_power else NO_DATA,
		"power_text": ("%d" % smoothed) if has_power else NO_DATA_TEXT,
		"power_deviation": deviation_state(smoothed if has_power else NO_DATA, target if has_target else NO_DATA),
		"power_zone": power_zone,
		"power_zone_text": ("Z%d" % power_zone) if power_zone > 0 else NO_DATA_TEXT,
		"power_zone_token": ZonePalette.power_token(power_zone),
		"hr_bpm": hr,
		"hr_text": ("%d" % hr) if hr >= 0 else NO_DATA_TEXT,
		"hr_zone": hr_zone,
		"hr_zone_text": ("Z%d" % hr_zone) if hr_zone > 0 else NO_DATA_TEXT,
		"hr_zone_token": ZonePalette.hr_token(hr_zone),
		"cadence_rpm": cadence,
		"cadence_text": ("%d" % cadence) if cadence >= 0 else NO_DATA_TEXT,
		"speed_kmh": speed,
		"speed_text": format_speed(speed),
		"elapsed_sec": ex.elapsed_sec(),
		"elapsed_text": format_elapsed(ex.elapsed_sec()),
		"step_remaining_sec": remaining,
		"countdown_text": format_countdown(remaining),
		"about_to_change": step_index >= 0 and remaining <= ABOUT_TO_CHANGE_SEC,
		"step_index": step_index,
		"step_total": total_steps,
		"step_text": ("%d/%d" % [step_index + 1, total_steps]) if step_index >= 0 else ("%d/%d" % [total_steps, total_steps] if ex.is_finished() else NO_DATA_TEXT),
		"erg_enabled": session.erg_enabled,
		"erg_active_on_trainer": session.is_erg_active_on_trainer(),
		"intensity": ex.intensity,
		"intensity_pct": roundi(ex.intensity * 100.0),
		"cue_text": _cue_text,
		"distance_m": session.samples.total_distance_m(),
		"progress": cursor(),
	}


# ---------------------------------------------------------------------------
# Полоса прогресса (HUD-07, WRK-07 крит. 4, INT-05 крит. 3)
# ---------------------------------------------------------------------------

## Сегменты плана: `{index, start_sec, duration_sec, start_watts, end_watts, zone, zone_token, status}`.
## Ватты и зона — с текущим множителем; статус — по исполнителю и событиям skip.
func progress_segments() -> Array[Dictionary]:
	var ex := session.executor
	var segments := ex.workout.segments(ex.ftp_w, ex.intensity)
	var skipped := skipped_step_indices()
	var current: int = ex.current_step_index()
	var finished: bool = ex.is_finished()
	for seg in segments:
		var i: int = int(seg["index"])
		var zone: int = _power_zone(int(seg["start_watts"])) if int(seg["start_watts"]) > 0 else 0
		seg["zone"] = zone
		seg["zone_token"] = ZonePalette.power_token(zone)
		if skipped.has(i):
			seg["status"] = SEGMENT_SKIPPED
		elif finished or (current >= 0 and i < current):
			seg["status"] = SEGMENT_DONE
		elif i == current:
			seg["status"] = SEGMENT_CURRENT
		else:
			seg["status"] = SEGMENT_UPCOMING
	return segments


## Индексы пропущенных шагов из журнала событий сессии (REQ-WRK-06 крит. 4).
func skipped_step_indices() -> Array[int]:
	var out: Array[int] = []
	for e in session.events:
		if e["type"] == WorkoutSession.EVENT_SKIP and int(e["value"]) >= 0:
			out.append(int(e["value"]))
	return out


## Позиция курсора 0..1 = прошедшее время / длительность плана.
func cursor() -> float:
	var total: int = session.executor.workout.total_duration_sec()
	if total <= 0:
		return 0.0
	return clampf(float(session.executor.elapsed_sec()) / float(total), 0.0, 1.0)


# ---------------------------------------------------------------------------
# Чистые функции форматирования и правил
# ---------------------------------------------------------------------------

## Ключ перевода состояния подключения станка (REQ-DEV-07 крит. 1, REQ-DEV-08 крит. 5):
## `ui.hud.connection.<state>`. Модель не переводит — это делает view через `tr()` при
## каждой отрисовке, иначе смена языка не обновит кэш (REQ-NFR-08 крит. 1).
static func connection_key(state: int) -> String:
	return "ui.hud.connection." + TrainerDevice.state_name(state)


## Состояние индикации отклонения (HUD-02 крит. 2): «в цели» при |факт − цель| ≤ max(5 % цели, 10 Вт).
static func deviation_state(actual_w: int, target_w: int) -> String:
	if target_w <= 0 or actual_w < 0:
		return DEVIATION_HIDDEN
	var tolerance: float = maxf(DEVIATION_PCT * float(target_w), float(DEVIATION_MIN_W))
	var diff: int = actual_w - target_w
	if absf(float(diff)) <= tolerance:
		return DEVIATION_ON
	return DEVIATION_ABOVE if diff > 0 else DEVIATION_BELOW


## `мм:сс` до часа, далее `ч:мм:сс` (HUD-05 крит. 1).
static func format_elapsed(total_sec: int) -> String:
	var s: int = maxi(total_sec, 0)
	if s < 3600:
		return "%02d:%02d" % [s / 60, s % 60]
	return "%d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]


## Обратный отсчёт `мм:сс` (HUD-06 крит. 1).
static func format_countdown(remaining_sec: int) -> String:
	var s: int = maxi(remaining_sec, 0)
	return "%02d:%02d" % [s / 60, s % 60]


## Скорость с одним знаком; отрицательная — «—».
static func format_speed(speed_kmh: float) -> String:
	return ("%.1f" % speed_kmh) if speed_kmh >= 0.0 else NO_DATA_TEXT


## Обрезка подсказки длиннее 120 символов с «…» (HUD-08 крит. 3).
static func truncate_cue(text: String) -> String:
	if text.length() <= CUE_MAX_LENGTH:
		return text
	return text.substr(0, CUE_MAX_LENGTH - CUE_ELLIPSIS.length()) + CUE_ELLIPSIS


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _refresh_int(_value: int) -> void:
	refresh()


func _refresh_bool(_value: bool) -> void:
	refresh()


func _refresh_float(_value: float) -> void:
	refresh()


func _power_zone(power_w: int) -> int:
	if profile != null:
		return profile.power_zone_of(power_w)
	return Zones.power_zone(power_w, session.executor.ftp_w)


func _hr_zone(bpm: int) -> int:
	if profile == null:
		return 0
	return profile.hr_zone_of(bpm)


func _on_second_elapsed(elapsed_sec: int, _offset: int, _remaining: int) -> void:
	# Сессия (подписана раньше) уже закрыла слот — читаем его.
	var row: Dictionary = session.samples.last_row()
	if row.get("has_power", false):
		_smoother.push(int(row["power_w"]))
	else:
		_smoother.push_missing()
	if _cue_until_sec >= 0 and elapsed_sec >= _cue_until_sec:
		_clear_cue()
	refresh()


func _on_step_changed(_index: int, _step: WorkoutStep) -> void:
	# Подсказка исчезает при смене шага (HUD-08 крит. 2); подсказка нового шага
	# с offset 0 придёт следом в ту же секунду.
	_clear_cue()
	refresh()


func _on_cue(text: String) -> void:
	_cue_text = truncate_cue(text)
	_cue_until_sec = session.executor.elapsed_sec() + CUE_SHOW_SEC
	refresh()


func _clear_cue() -> void:
	_cue_text = ""
	_cue_until_sec = -1
