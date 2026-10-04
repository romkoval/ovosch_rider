class_name Workout
extends RefCounted
## Структурированная тренировка: плоский список шагов (REQ-INT-03, REQ-WRK-01).
##
## Повторы (`3x ...`) разворачиваются на этапе парсинга через `expand_repeat`;
## в модели хранится уже плоская последовательность (REQ-INT-03 крит. 5). След блока
## повторов — в `repeat_blocks` (только для показа, на исполнение не влияет; REQ-HUD-13 п.8).

## Допустимые значения `source`.
const SOURCES: Array[String] = ["intervals_icu", "zwo", "erg", "mrc", "manual"]

var name: String = ""
var description: String = ""
## Происхождение плана: "intervals_icu" | "zwo" | "erg" | "mrc" | "manual".
var source: String = "manual"
var steps: Array[WorkoutStep] = []
## Метаданные источника, не влияющие на исполнение: `author`, `sport_type`,
## `source_file`, `ftp_header`, `event_id` и т. п. (REQ-IMP-01 крит. 5, REQ-IMP-02 крит. 4).
## Только JSON-совместимые значения.
var metadata: Dictionary = {}
## Блоки повторов в плоском `steps`: `{first, last, period, count}` — индексы первого и
## последнего шага блока (`last` включительно), шагов в одном повторе и число повторов;
## `last = first + period * count - 1`. Тот же вид, что у блоков `IntervalsT`, которые
## `IntervalListModel.detect_repeat_blocks` находит в плане ZWO. Заполняют парсеры, которые
## знают границы повтора (Intervals.icu); вложенные повторы — только внешний блок.
## Метаданные показа: читать через `valid_repeat_blocks()` — она отбрасывает блоки,
## не совпадающие с текущими шагами.
var repeat_blocks: Array[Dictionary] = []

## Версия схемы `to_dict()`.
const SCHEMA_VERSION: int = 1


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


## Метаданные блока повторов (см. `repeat_blocks`) для блока из `period` шагов, повторённого
## `count` раз, начиная с шага `first`.
static func repeat_block(first: int, period: int, count: int) -> Dictionary:
	return {"first": first, "last": first + period * count - 1, "period": period, "count": count}


## Блоки `repeat_blocks`, согласованные со `steps`: индексы в пределах плана,
## `last = first + period * count - 1`, `period ≥ 1`, `count ≥ 1`, каждый повтор совпадает
## с первым (`WorkoutStep.same_as`), блоки не пересекаются. Порядок — по `first`.
## Остальные (устаревшие после правки шагов, битые из файла) молча пропускаются.
func valid_repeat_blocks() -> Array[Dictionary]:
	var sorted: Array[Dictionary] = repeat_blocks.duplicate(true)
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["first"]) < int(b["first"]))
	var out: Array[Dictionary] = []
	var next_free: int = 0
	for b in sorted:
		if _block_matches_steps(b) and int(b["first"]) >= next_free:
			out.append(b)
			next_free = int(b["last"]) + 1
	return out


func _block_matches_steps(b: Dictionary) -> bool:
	var first: int = int(b["first"])
	var last: int = int(b["last"])
	var period: int = int(b["period"])
	var count: int = int(b["count"])
	if first < 0 or period < 1 or count < 1 or last >= steps.size() or last != first + period * count - 1:
		return false
	for k in range(first + period, last + 1):
		if not steps[k].same_as(steps[k - period]):
			return false
	return true


## Блок повторов из словаря (`to_dict`/JSON): четыре целых поля; иначе пустой словарь.
static func _repeat_block_from(data: Variant) -> Dictionary:
	if not (data is Dictionary):
		return {}
	var d: Dictionary = data
	var out: Dictionary = {}
	for key in ["first", "last", "period", "count"]:
		var v: Variant = d.get(key)
		if not (v is int or v is float):
			return {}
		out[key] = roundi(clampf(float(v), -1.0e9, 1.0e9))
	return out


## Сериализация в словарь (JSON-совместимый): `{schema, name, description, source,
## metadata, steps: [WorkoutStep.to_dict()]}` и `repeat_blocks: [{first, last, period, count}]`,
## если блоки повторов есть (без них словарь прежнего вида). Числа метаданных отдаются как float
## (как они выглядят после JSON), поэтому `from_dict(to_dict()).to_dict()` и
## `from_dict(JSON(to_dict())).to_dict()` совпадают с `to_dict()` без потерь.
func to_dict() -> Dictionary:
	var items: Array = []
	for s in steps:
		items.append(s.to_dict())
	var out := {
		"schema": SCHEMA_VERSION,
		"name": name,
		"description": description,
		"source": source,
		"metadata": _json_numbers(metadata.duplicate(true)),
		"steps": items,
	}
	if not repeat_blocks.is_empty():
		out["repeat_blocks"] = repeat_blocks.duplicate(true)
	return out


## Восстановление из словаря; null, если нет массива `steps`. Битые шаги
## пропускаются (их отловит `validate()` по итогу), битые блоки повторов — тоже;
## словарь без `repeat_blocks` (старый) — план без блоков. Не падает на любом входе.
static func from_dict(data: Dictionary) -> Workout:
	if not (data.get("steps") is Array):
		return null
	var w := Workout.new()
	w.name = str(data.get("name", ""))
	w.description = str(data.get("description", ""))
	w.source = str(data.get("source", "manual"))
	var meta: Variant = data.get("metadata", {})
	if meta is Dictionary:
		w.metadata = (meta as Dictionary).duplicate(true)
	for item in data["steps"]:
		if item is Dictionary:
			var s := WorkoutStep.from_dict(item)
			if s != null:
				w.steps.append(s)
	var blocks: Variant = data.get("repeat_blocks", [])
	if blocks is Array:
		for item in blocks:
			var b := _repeat_block_from(item)
			if not b.is_empty():
				w.repeat_blocks.append(b)
	return w


## int → float рекурсивно (вид чисел после JSON), bool не трогается.
static func _json_numbers(value: Variant) -> Variant:
	if value is int:
		return float(value)
	if value is Dictionary:
		var d: Dictionary = value
		for k in d.keys():
			d[k] = _json_numbers(d[k])
		return d
	if value is Array:
		var a: Array = value
		for i in a.size():
			a[i] = _json_numbers(a[i])
		return a
	return value


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


## Сегменты полосы прогресса и графика предпросмотра (REQ-HUD-07 крит. 1, 2;
## REQ-INT-05 крит. 3): словари `{index, start_sec, duration_sec, start_watts, end_watts, zone}`.
## `zone` — зона мощности `start_watts` по `zones` (границы профиля, REQ-HUD-03 крит. 1);
## при `zones == null` — 7 зон Coggan от `ftp_w` (`Zones.power_zone`). Домен не знает
## о профиле: вызывающий передаёт `Profile.effective_power_zones()`. Пересчитывается
## при другом множителе. Сумма `duration_sec` равна `total_duration_sec()`.
func segments(ftp_w: int, intensity: float = 1.0, zones: PowerZones = null) -> Array[Dictionary]:
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
			"zone": zones.zone_of(start_w) if zones != null else Zones.power_zone(start_w, ftp_w),
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
