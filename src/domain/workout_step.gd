class_name WorkoutStep
extends RefCounted
## Один шаг структурированной тренировки (REQ-INT-03, REQ-WRK-01).
##
## Цель задаётся парой `target_start`/`target_end`: для постоянного шага они
## равны, для рампы различаются и интерполируются линейно по времени.
## Единица цели определяется `target_kind`: проценты FTP или ватты.
## Для `TargetKind.NONE` (свободная езда) целевая мощность всегда 0.

## Единица измерения цели.
enum TargetKind { NONE, PERCENT_FTP, WATTS }

## Семантический тип шага. На расчёт мощности не влияет — нужен UI/исполнителю.
enum StepKind { WARMUP, STEADY, INTERVAL_ON, INTERVAL_OFF, RAMP, FREE_RIDE, COOLDOWN }

## Строковые имена перечислений для `to_dict()/from_dict()` — файл читаем и
## устойчив к перенумерации.
const TARGET_KIND_NAMES: Dictionary = {
	TargetKind.NONE: "none",
	TargetKind.PERCENT_FTP: "percent_ftp",
	TargetKind.WATTS: "watts",
}
const STEP_KIND_NAMES: Dictionary = {
	StepKind.WARMUP: "warmup",
	StepKind.STEADY: "steady",
	StepKind.INTERVAL_ON: "interval_on",
	StepKind.INTERVAL_OFF: "interval_off",
	StepKind.RAMP: "ramp",
	StepKind.FREE_RIDE: "free_ride",
	StepKind.COOLDOWN: "cooldown",
}

## Длительность шага, с (> 0 для валидного шага).
var duration_sec: int = 0
var target_kind: TargetKind = TargetKind.NONE
## Цель в начале шага (% FTP или Вт в зависимости от `target_kind`).
var target_start: float = 0.0
## Цель в конце шага. Равна `target_start` для постоянного шага.
var target_end: float = 0.0
## Целевой каденс, об/мин. 0 — не задан.
var cadence_rpm: int = 0
var text_cues: Array[TextCue] = []
var kind: StepKind = StepKind.STEADY


## Постоянный шаг с целью в % FTP.
static func percent(duration: int, pct: float, step_kind: StepKind = StepKind.STEADY) -> WorkoutStep:
	return _make(duration, TargetKind.PERCENT_FTP, pct, pct, step_kind)


## Постоянный шаг с целью в ваттах.
static func watts(duration: int, w: float, step_kind: StepKind = StepKind.STEADY) -> WorkoutStep:
	return _make(duration, TargetKind.WATTS, w, w, step_kind)


## Рампа в % FTP от `pct_start` до `pct_end`.
static func ramp_percent(duration: int, pct_start: float, pct_end: float,
		step_kind: StepKind = StepKind.RAMP) -> WorkoutStep:
	return _make(duration, TargetKind.PERCENT_FTP, pct_start, pct_end, step_kind)


## Рампа в ваттах от `w_start` до `w_end`.
static func ramp_watts(duration: int, w_start: float, w_end: float,
		step_kind: StepKind = StepKind.RAMP) -> WorkoutStep:
	return _make(duration, TargetKind.WATTS, w_start, w_end, step_kind)


## Свободная езда без цели (ERG выключен).
static func free_ride(duration: int) -> WorkoutStep:
	return _make(duration, TargetKind.NONE, 0.0, 0.0, StepKind.FREE_RIDE)


static func _make(duration: int, tk: TargetKind, start: float, end: float, sk: StepKind) -> WorkoutStep:
	var s := WorkoutStep.new()
	s.duration_sec = duration
	s.target_kind = tk
	s.target_start = start
	s.target_end = end
	s.kind = sk
	return s


## Шаг без целевой мощности (свободная езда или `TargetKind.NONE`).
func is_free_ride() -> bool:
	return target_kind == TargetKind.NONE or kind == StepKind.FREE_RIDE


## Рампа: начальная и конечная цели различаются.
func is_ramp() -> bool:
	return target_kind != TargetKind.NONE and not is_equal_approx(target_start, target_end)


## Цель (в единицах `target_kind`) на смещении `offset_sec` от начала шага.
## Линейная интерполяция, смещение зажимается в [0; duration_sec].
## Для шага нулевой длительности возвращается `target_start`.
func target_value_at(offset_sec: float) -> float:
	if duration_sec <= 0:
		return target_start
	var t: float = clampf(offset_sec / float(duration_sec), 0.0, 1.0)
	return lerpf(target_start, target_end, t)


## Целевая мощность в ваттах на смещении `offset_sec` с учётом FTP и
## множителя интенсивности (REQ-WRK-07). Округление до целого Вт
## (`roundi`: 0.5 → вверх). Для `TargetKind.NONE` → 0.
## Пример: 65 % при FTP 200 → 130 Вт; с множителем 1.1 → 143 Вт.
func target_watts_at(offset_sec: float, ftp_w: int, intensity: float = 1.0) -> int:
	if target_kind == TargetKind.NONE:
		return 0
	var value: float = target_value_at(offset_sec)
	var w: float = 0.0
	match target_kind:
		TargetKind.PERCENT_FTP:
			w = value / 100.0 * float(ftp_w)
		TargetKind.WATTS:
			w = value
	return maxi(0, roundi(w * intensity))


## Целевая мощность в начале шага.
func start_watts(ftp_w: int, intensity: float = 1.0) -> int:
	return target_watts_at(0.0, ftp_w, intensity)


## Целевая мощность в конце шага.
func end_watts(ftp_w: int, intensity: float = 1.0) -> int:
	return target_watts_at(float(duration_sec), ftp_w, intensity)


## Глубокая копия шага (подсказки копируются).
func duplicate_step() -> WorkoutStep:
	var s := WorkoutStep.new()
	s.duration_sec = duration_sec
	s.target_kind = target_kind
	s.target_start = target_start
	s.target_end = target_end
	s.cadence_rpm = cadence_rpm
	s.kind = kind
	for cue in text_cues:
		s.text_cues.append(cue.duplicate_cue())
	return s


## Тот же шаг по содержанию: тип, длительность, цель, каденс и подсказки. Так совпадают
## копии одного шага в развёрнутом повторе (`Workout.expand_repeat`).
func same_as(other: WorkoutStep) -> bool:
	if other == null or kind != other.kind or duration_sec != other.duration_sec \
			or target_kind != other.target_kind or cadence_rpm != other.cadence_rpm \
			or not is_equal_approx(target_start, other.target_start) \
			or not is_equal_approx(target_end, other.target_end) \
			or text_cues.size() != other.text_cues.size():
		return false
	for i in text_cues.size():
		if text_cues[i].at_sec != other.text_cues[i].at_sec or text_cues[i].text != other.text_cues[i].text:
			return false
	return true


## Сериализация в словарь (JSON-совместимый): `{duration_sec, target_kind, target_start,
## target_end, cadence_rpm, kind, text_cues: [{at_sec, text}]}`; перечисления — строками.
func to_dict() -> Dictionary:
	var cues: Array = []
	for c in text_cues:
		cues.append(c.to_dict())
	return {
		"duration_sec": duration_sec,
		"target_kind": TARGET_KIND_NAMES.get(target_kind, "none"),
		"target_start": target_start,
		"target_end": target_end,
		"cadence_rpm": cadence_rpm,
		"kind": STEP_KIND_NAMES.get(kind, "steady"),
		"text_cues": cues,
	}


## Восстановление из словаря; null, если нет `duration_sec`. Неизвестные имена
## перечислений → NONE/STEADY, битые подсказки пропускаются. Не падает на любом входе.
static func from_dict(data: Dictionary) -> WorkoutStep:
	if not data.has("duration_sec"):
		return null
	var s := WorkoutStep.new()
	s.duration_sec = int(data.get("duration_sec", 0))
	s.target_kind = _enum_from_name(TARGET_KIND_NAMES, str(data.get("target_kind", "none")), TargetKind.NONE) as TargetKind
	s.target_start = float(data.get("target_start", 0.0))
	s.target_end = float(data.get("target_end", s.target_start))
	s.cadence_rpm = int(data.get("cadence_rpm", 0))
	s.kind = _enum_from_name(STEP_KIND_NAMES, str(data.get("kind", "steady")), StepKind.STEADY) as StepKind
	var cues: Variant = data.get("text_cues", [])
	if cues is Array:
		for c in cues:
			if c is Dictionary:
				var cue := TextCue.from_dict(c)
				if cue != null:
					s.text_cues.append(cue)
	return s


static func _enum_from_name(names: Dictionary, wanted: String, fallback: int) -> int:
	for k in names.keys():
		if names[k] == wanted:
			return int(k)
	return fallback


## Ошибки шага (пусто — шаг валиден). Используется `Workout.validate()`.
func validate() -> Array[String]:
	var errors: Array[String] = []
	if duration_sec <= 0:
		errors.append("длительность шага должна быть > 0 с (сейчас %d)" % duration_sec)
	if target_kind != TargetKind.NONE:
		if is_ramp():
			if target_start < 0.0:
				errors.append("отрицательная начальная цель: %s" % str(target_start))
			if target_end < 0.0:
				errors.append("отрицательная конечная цель: %s" % str(target_end))
		elif target_start < 0.0:
			errors.append("отрицательная цель: %s" % str(target_start))
	if cadence_rpm < 0:
		errors.append("отрицательный каденс: %d" % cadence_rpm)
	for cue in text_cues:
		if cue.at_sec < 0 or cue.at_sec >= maxi(duration_sec, 1):
			errors.append("подсказка на %d с вне шага длительностью %d с" % [cue.at_sec, duration_sec])
	return errors


func _to_string() -> String:
	var unit := "%" if target_kind == TargetKind.PERCENT_FTP else "W"
	if target_kind == TargetKind.NONE:
		return "WorkoutStep(%d s, free)" % duration_sec
	if is_ramp():
		return "WorkoutStep(%d s, %s→%s%s)" % [duration_sec, str(target_start), str(target_end), unit]
	return "WorkoutStep(%d s, %s%s)" % [duration_sec, str(target_start), unit]
