class_name WorkoutSerializer
extends RefCounted
## Тонкая обёртка над `Workout.to_dict()/from_dict()` для библиотеки тренировок
## и кэша плана (REQ-IMP-04, REQ-INT-07): добавляет JSON-строку. Сериализация
## живёт в домене (решение Н-6).

const SCHEMA_VERSION: int = Workout.SCHEMA_VERSION
const TARGET_KIND_NAMES: Dictionary = WorkoutStep.TARGET_KIND_NAMES
const STEP_KIND_NAMES: Dictionary = WorkoutStep.STEP_KIND_NAMES


static func to_dict(w: Workout) -> Dictionary:
	return w.to_dict()


static func step_to_dict(s: WorkoutStep) -> Dictionary:
	return s.to_dict()


## null, если структура не похожа на план (нет массива `steps`).
static func from_dict(data: Dictionary) -> Workout:
	return Workout.from_dict(data)


static func step_from_dict(data: Dictionary) -> WorkoutStep:
	return WorkoutStep.from_dict(data)


static func to_json(w: Workout) -> String:
	return JSON.stringify(w.to_dict(), "\t")


## Разбор JSON-строки; null при синтаксической ошибке или чужой структуре.
static func from_json(text: String) -> Workout:
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return null
	return Workout.from_dict(json.data)
