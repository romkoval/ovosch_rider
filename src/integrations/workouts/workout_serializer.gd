class_name WorkoutSerializer
extends RefCounted
## Сериализация `Workout` в словарь/JSON и обратно для библиотеки тренировок
## (REQ-IMP-04). Домен не меняется: это внешняя по отношению к `Workout`
## функция; при появлении `Workout.to_dict()/from_dict()` сводится к их вызову.

const SCHEMA_VERSION: int = 1

## Строковые имена перечислений — чтобы файл был читаем и устойчив к перенумерации.
const TARGET_KIND_NAMES: Dictionary = {
	WorkoutStep.TargetKind.NONE: "none",
	WorkoutStep.TargetKind.PERCENT_FTP: "percent_ftp",
	WorkoutStep.TargetKind.WATTS: "watts",
}
const STEP_KIND_NAMES: Dictionary = {
	WorkoutStep.StepKind.WARMUP: "warmup",
	WorkoutStep.StepKind.STEADY: "steady",
	WorkoutStep.StepKind.INTERVAL_ON: "interval_on",
	WorkoutStep.StepKind.INTERVAL_OFF: "interval_off",
	WorkoutStep.StepKind.RAMP: "ramp",
	WorkoutStep.StepKind.FREE_RIDE: "free_ride",
	WorkoutStep.StepKind.COOLDOWN: "cooldown",
}


static func to_dict(w: Workout) -> Dictionary:
	var steps: Array = []
	for s in w.steps:
		steps.append(step_to_dict(s))
	return {
		"schema": SCHEMA_VERSION,
		"name": w.name,
		"description": w.description,
		"source": w.source,
		"steps": steps,
	}


static func step_to_dict(s: WorkoutStep) -> Dictionary:
	var cues: Array = []
	for c in s.text_cues:
		cues.append({"at_sec": c.at_sec, "text": c.text})
	return {
		"duration_sec": s.duration_sec,
		"target_kind": TARGET_KIND_NAMES.get(s.target_kind, "none"),
		"target_start": s.target_start,
		"target_end": s.target_end,
		"cadence_rpm": s.cadence_rpm,
		"kind": STEP_KIND_NAMES.get(s.kind, "steady"),
		"text_cues": cues,
	}


## Восстановить план из словаря. Возвращает null, если структура не похожа на план
## (нет массива `steps`); отдельные битые шаги пропускаются.
static func from_dict(data: Dictionary) -> Workout:
	if not (data.get("steps") is Array):
		return null
	var w := Workout.new()
	w.name = str(data.get("name", ""))
	w.description = str(data.get("description", ""))
	w.source = str(data.get("source", "manual"))
	for item in data["steps"]:
		if item is Dictionary:
			var s := step_from_dict(item)
			if s != null:
				w.steps.append(s)
	return w


static func step_from_dict(data: Dictionary) -> WorkoutStep:
	if not data.has("duration_sec"):
		return null
	var s := WorkoutStep.new()
	s.duration_sec = int(data.get("duration_sec", 0))
	s.target_kind = _enum_from_name(TARGET_KIND_NAMES, str(data.get("target_kind", "none")),
			WorkoutStep.TargetKind.NONE) as WorkoutStep.TargetKind
	s.target_start = float(data.get("target_start", 0.0))
	s.target_end = float(data.get("target_end", s.target_start))
	s.cadence_rpm = int(data.get("cadence_rpm", 0))
	s.kind = _enum_from_name(STEP_KIND_NAMES, str(data.get("kind", "steady")),
			WorkoutStep.StepKind.STEADY) as WorkoutStep.StepKind
	var cues: Variant = data.get("text_cues", [])
	if cues is Array:
		for c in cues:
			if c is Dictionary:
				s.text_cues.append(TextCue.make(int(c.get("at_sec", 0)), str(c.get("text", ""))))
	return s


static func to_json(w: Workout) -> String:
	return JSON.stringify(to_dict(w), "\t")


## Разбор JSON-строки; null при синтаксической ошибке или чужой структуре.
static func from_json(text: String) -> Workout:
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return null
	return from_dict(json.data)


static func _enum_from_name(names: Dictionary, wanted: String, fallback: int) -> int:
	for k in names.keys():
		if names[k] == wanted:
			return int(k)
	return fallback
