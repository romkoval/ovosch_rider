class_name Workout
extends RefCounted
## Структурированная тренировка: плоский список шагов (REQ-INT-03, REQ-WRK-01).
##
## Повторы (`3x ...`) разворачиваются на этапе парсинга через `expand_repeat`;
## в модели хранится уже плоская последовательность (REQ-INT-03 крит. 5).

## Допустимые значения `source`.
const SOURCES: Array[String] = ["intervals_icu", "zwo", "erg", "mrc", "manual"]

var name: String = ""
var description: String = ""
## Происхождение плана: "intervals_icu" | "zwo" | "erg" | "mrc" | "manual".
var source: String = "manual"
var steps: Array[WorkoutStep] = []


static func make(workout_name: String, workout_steps: Array[WorkoutStep],
		workout_source: String = "manual") -> Workout:
	var w := Workout.new()
	w.name = workout_name
	w.steps = workout_steps
	w.source = workout_source
	return w


## Разворачивает блок шагов в `count` повторов. Каждый повтор — глубокие
## копии шагов, чтобы правка одного экземпляра не затронула остальные.
## При `count <= 0` возвращает пустой массив.
static func expand_repeat(block: Array[WorkoutStep], count: int) -> Array[WorkoutStep]:
	var out: Array[WorkoutStep] = []
	for i in maxi(count, 0):
		for step in block:
			out.append(step.duplicate_step())
	return out


## Суммарная длительность, с.
func total_duration_sec() -> int:
	var total: int = 0
	for step in steps:
		total += step.duration_sec
	return total


## Индекс шага, идущего в момент `elapsed_sec` от старта тренировки.
## Шаг i занимает полуинтервал [start_i; start_i + duration_i): на границе
## двух шагов возвращается следующий. При `elapsed_sec < 0` или
## `elapsed_sec >= total_duration_sec()` (тренировка завершена) → -1.
func step_index_at(elapsed_sec: float) -> int:
	if elapsed_sec < 0.0:
		return -1
	var start: int = 0
	for i in steps.size():
		var end: int = start + steps[i].duration_sec
		if elapsed_sec < float(end):
			return i
		start = end
	return -1


## Смещение внутри текущего шага, с. Если шага нет (см. `step_index_at`) → -1.0.
func step_offset_at(elapsed_sec: float) -> float:
	var idx := step_index_at(elapsed_sec)
	if idx < 0:
		return -1.0
	return elapsed_sec - float(step_start_sec(idx))


## Время начала шага `index` от старта тренировки, с. Для `index == steps.size()`
## вернёт общую длительность; вне диапазона → -1.
func step_start_sec(index: int) -> int:
	if index < 0 or index > steps.size():
		return -1
	var start: int = 0
	for i in index:
		start += steps[i].duration_sec
	return start


## Целевая мощность в момент `elapsed_sec` (0, если шага нет или он свободный).
func target_watts_at(elapsed_sec: float, ftp_w: int, intensity: float = 1.0) -> int:
	var idx := step_index_at(elapsed_sec)
	if idx < 0:
		return 0
	return steps[idx].target_watts_at(elapsed_sec - float(step_start_sec(idx)), ftp_w, intensity)


## Профиль целевой мощности по времени для графика (REQ-INT-05, REQ-HUD-07).
## Элемент k — мощность в момент t = k * resolution_sec (начало слота).
## Длина = ceil(total / resolution_sec); при resolution_sec = 1 равна
## `total_duration_sec()`. Множитель интенсивности применяется ко всем целям.
func power_profile(ftp_w: int, resolution_sec: int = 1, intensity: float = 1.0) -> PackedInt32Array:
	var profile := PackedInt32Array()
	var res: int = maxi(resolution_sec, 1)
	var total: int = total_duration_sec()
	if total <= 0:
		return profile
	profile.resize(ceili(float(total) / float(res)))
	var k: int = 0
	var start: int = 0
	for step in steps:
		var end: int = start + step.duration_sec
		while k * res < end and k < profile.size():
			profile[k] = step.target_watts_at(float(k * res - start), ftp_w, intensity)
			k += 1
		start = end
	return profile


## Ломаная целевой мощности для графика (REQ-INT-05 крит. 1, 2): для каждого
## шага две точки `(start_sec, start_watts)` и `(end_sec, end_watts)`; у рампы
## конечная точка равна цели конца, у постоянного шага обе одинаковы,
## у свободной езды — 0. На стыке шагов две точки с одинаковым t дают
## вертикальный скачок. Пустой план → пустой массив.
func power_points(ftp_w: int, intensity: float = 1.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	var start: int = 0
	for step in steps:
		var end: int = start + step.duration_sec
		points.append(Vector2(float(start), float(step.start_watts(ftp_w, intensity))))
		points.append(Vector2(float(end), float(step.end_watts(ftp_w, intensity))))
		start = end
	return points


## Сегменты полосы прогресса (REQ-HUD-07 крит. 1, 2): словари
## `{index, start_sec, duration_sec, start_watts, end_watts, zone}`.
## `zone` — зона мощности `start_watts` по Coggan (`Zones.power_zone`);
## пересчитывается при другом множителе. Сумма `duration_sec` равна
## `total_duration_sec()`.
func segments(ftp_w: int, intensity: float = 1.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var start: int = 0
	for i in steps.size():
		var step: WorkoutStep = steps[i]
		var start_w: int = step.start_watts(ftp_w, intensity)
		out.append({
			"index": i,
			"start_sec": start,
			"duration_sec": step.duration_sec,
			"start_watts": start_w,
			"end_watts": step.end_watts(ftp_w, intensity),
			"zone": Zones.power_zone(start_w, ftp_w),
		})
		start += step.duration_sec
	return out


## Список ошибок плана (пустой — план валиден). Проверяются: пустой список
## шагов, допустимость `source`, а также каждый шаг (нулевая длительность,
## отрицательная цель — см. `WorkoutStep.validate`).
func validate() -> Array[String]:
	var errors: Array[String] = []
	if steps.is_empty():
		errors.append("тренировка не содержит шагов")
	if not SOURCES.has(source):
		errors.append("неизвестный источник: '%s'" % source)
	for i in steps.size():
		for e in steps[i].validate():
			errors.append("шаг %d: %s" % [i + 1, e])
	return errors


func is_valid() -> bool:
	return validate().is_empty()


func _to_string() -> String:
	return "Workout('%s', %d шагов, %d с, %s)" % [name, steps.size(), total_duration_sec(), source]
