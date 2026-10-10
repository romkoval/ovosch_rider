class_name IntervalListModel
extends RefCounted
## Модель списка интервалов HUD (REQ-HUD-13 крит. 2, 3, 8; `docs/game/hud.md` п. 6).
## Только числа, токены и короткие строки чисел, без узлов и отрисовки: рисует `IntervalList`.
##
## Строка — шаг плана: длительность (`м:сс`, от часа `ч:мм:сс`), цель в Вт с учётом множителя
## WRK-07 (рампа — «начало→конец»), признак «свободно» (`WorkoutStep.is_free_ride()`), зона
## (по цели в начале шага, как у `Workout.segments`) и состояние.
##
## Состояния (как у `PlanChartModel`): `skipped` (по журналу сессии, WRK-06) → `current`
## (индекс исполнителя, ровно одна строка) → `done` (шаг левее текущего) → `upcoming`.
##
## Повторы (HUD-13.8). Пока блок не начался, он свёрнут в одну строку `kind = repeat`
## («3 × 2:00 300 / 1:00 125 Вт»); с начала первого шага блока — строка на каждый шаг.
## Цвет свёрнутой строки — зона рабочего отрезка: шага повтора с наибольшей целью (блок может
## начинаться с отдыха: «3x (2m 50%, 1m 120%)»; T-113). Границы блоков — сохранённые парсером
## (`Workout.repeat_blocks`: Intervals.icu `Nx`, ZWO `IntervalsT`), блок любой длины периода.
## В планах без сохранённых блоков (сохранены до T-099/T-113) — прежняя эвристика: подряд идущие
## пары `INTERVAL_ON` + `INTERVAL_OFF` с одинаковыми длительностями и целями (так разворачивается
## `IntervalsT`); два соседних `IntervalsT` с одинаковыми параметрами при этом неотличимы
## от одного и сворачиваются вместе.
##
## Окно (HUD-13.3): до `DONE_ROWS` строк перед текущей, текущая и до `NEXT_ROWS` после —
## не больше `MAX_ROWS`. До старта окно стоит так, как будто текущая — первая строка.

const STATUS_DONE: String = "done"
const STATUS_CURRENT: String = "current"
const STATUS_UPCOMING: String = "upcoming"
const STATUS_SKIPPED: String = "skipped"

const KIND_STEP: String = "step"
const KIND_REPEAT: String = "repeat"

## Токен цвета строки «свободно» (`hud.md` п. 11), тот же, что у графика.
const FREE_TOKEN: String = PlanChartModel.FREE_TOKEN

## Окно списка (HUD-13.3): всего, пройденных над текущей, следующих под ней.
const MAX_ROWS: int = 8
const DONE_ROWS: int = 2
const NEXT_ROWS: int = 5

var workout: Workout
var ftp_w: int = 0
var intensity: float = 1.0
## Зоны мощности профиля; null — 7 зон Coggan от `ftp_w`.
var zones: PowerZones = null

## Шаги без состояния: `{index, duration_sec, start_watts, end_watts, zone, zone_token,
## color_token, free, ramp, duration_text, target_text}`.
var _base: Array[Dictionary] = []
## Блоки повторов: `{first, last, period, count}` (индексы шагов, `last` включительно).
var _blocks: Array[Dictionary] = []
var _total_sec: int = 0
var _current_index: int = -1
var _last_index: int = -1
var _finished: bool = false
var _stopped_early: bool = false
var _skipped: Array[int] = []
var _step_offset_sec: float = 0.0
var _rows: Array[Dictionary] = []
var _revision: int = 0
## Target rule (`WorkoutSession.target_rule_key`) and the clamp it implies; invalid — plan targets.
var _target_rule_key: String = ""
var _target_limit: Callable = Callable()


func _init(plan: Workout, ftp: int, intensity_factor: float = 1.0, power_zones: PowerZones = null) -> void:
	workout = plan
	ftp_w = ftp
	intensity = intensity_factor
	zones = power_zones
	_blocks = detect_repeat_blocks(plan)
	_rebuild()


## Модель для сессии: план, FTP и множитель исполнителя; затем `sync(session)` раз в сэмпл.
static func for_session(session: WorkoutSession, power_zones: PowerZones = null) -> IntervalListModel:
	var ex := session.executor
	var model := IntervalListModel.new(ex.workout, ex.ftp_w, ex.intensity, power_zones)
	model.sync(session)
	return model


# ---------------------------------------------------------------------------
# Обновление
# ---------------------------------------------------------------------------

## Подтянуть множитель, текущий шаг, смещение в нём, пропуски и завершение из сессии.
## Вызывать на каждом сэмпле и сразу после пропуска/смены множителя. true — что-то изменилось.
func sync(session: WorkoutSession) -> bool:
	var ex := session.executor
	var changed: bool = set_intensity(ex.intensity)
	changed = _sync_target_rule(session) or changed
	var index: int = ex.current_step_index()
	var offset: float = float(ex.step_offset_sec()) if index >= 0 else 0.0
	changed = set_progress(index, PlanChartModel.skipped_indices(session.events), offset,
			ex.is_finished(), ex.stopped_early) or changed
	return changed


## Row targets follow the trainer while ERG acts on it (DEV-10 p.6, U-37, HUD-13 p.2): ramps
## clamp both ends. Returns true when the rule changed (rows rebuilt).
func _sync_target_rule(session: WorkoutSession) -> bool:
	var key: String = session.target_rule_key()
	if key == _target_rule_key:
		return false
	_target_rule_key = key
	_target_limit = Callable() if key.is_empty() else session.applied_target
	_rebuild()
	return true


## Множитель интенсивности WRK-07: пересчитывает ватты и зоны строк.
func set_intensity(value: float) -> bool:
	if is_equal_approx(value, intensity):
		return false
	intensity = value
	_rebuild()
	return true


## FTP профиля: меняет ватты целей в % FTP и границы зон.
func set_ftp(value: int) -> bool:
	if value == ftp_w:
		return false
	ftp_w = value
	_rebuild()
	return true


## Зоны мощности профиля (null — Coggan от FTP).
func set_zones(power_zones: PowerZones) -> void:
	zones = power_zones
	_rebuild()


## Положение в плане: индекс текущего шага (-1 — нет), пропущенные шаги, смещение в текущем
## шаге (с), завершение. Возвращает true, если изменилось что-то видимое (в том числе смещение).
func set_progress(current_index: int, skipped: Array[int] = [], step_offset_sec: float = 0.0,
		finished: bool = false, stopped_early: bool = false) -> bool:
	var sorted_skipped: Array[int] = skipped.duplicate()
	sorted_skipped.sort()
	var status_changed: bool = current_index != _current_index or sorted_skipped != _skipped \
			or finished != _finished or stopped_early != _stopped_early
	var changed: bool = status_changed or not is_equal_approx(step_offset_sec, _step_offset_sec)
	_current_index = current_index
	if current_index >= 0:
		_last_index = current_index
	_skipped = sorted_skipped
	_finished = finished
	_stopped_early = stopped_early
	_step_offset_sec = maxf(step_offset_sec, 0.0)
	if status_changed:
		_build_rows()
	return changed


# ---------------------------------------------------------------------------
# Строки
# ---------------------------------------------------------------------------

## Строки списка целиком (не только окно), сверху вниз:
## `{key, kind, first_step, last_step, status, duration_sec, duration_text, target_text,
## start_watts, end_watts, zone, zone_token, color_token, free, ramp, repeat_count, parts}`.
## `key` стабилен между перестроениями (`s<i>` — шаг, `r<i>` — свёрнутый блок с первого шага i).
## У `repeat`: `repeat_count` — число повторов, `parts` — шаги одного повтора
## (`{duration_text, target_text, free}`), длительность — всего блока, зона и цвет — рабочего
## отрезка. Возвращается копия.
func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in _rows:
		out.append(r.duplicate(true))
	return out


func row_count() -> int:
	return _rows.size()


## Индекс строки «текущий» (-1 — тренировка не идёт).
func current_row() -> int:
	for i in _rows.size():
		if _rows[i]["status"] == STATUS_CURRENT:
			return i
	return -1


## Окно видимых строк (HUD-13.3): `Vector2i(первая строка, число строк)`, не больше `MAX_ROWS`.
## Текущая строка — `DONE_ROWS + 1`-я сверху, если над ней хватает строк. До старта окно
## начинается с первой строки; после завершения — `DONE_ROWS` последних пройденных строк и
## следующие за ними.
func visible_window() -> Vector2i:
	var n: int = _rows.size()
	if n == 0:
		return Vector2i.ZERO
	var anchor: int = current_row()
	if anchor < 0 and _finished:
		# После завершения — как будто текущая строка следует за последней пройденной.
		anchor = _row_of_step(_last_index) + 1 if _stopped_early and _last_index >= 0 else n
	anchor = maxi(anchor, 0)
	var first: int = maxi(anchor - DONE_ROWS, 0)
	var last: int = mini(anchor + NEXT_ROWS, n - 1)
	return Vector2i(first, mini(last - first + 1, MAX_ROWS))


## Доля пройденного в текущем шаге 0…1 (затемнение текущей строки; 0 — нет текущего).
func current_progress() -> float:
	if _current_index < 0 or _current_index >= _base.size():
		return 0.0
	var duration: int = int(_base[_current_index]["duration_sec"])
	return clampf(_step_offset_sec / float(duration), 0.0, 1.0) if duration > 0 else 0.0


## Номер текущего шага (с 1) и число шагов плана — для подвала «Шаг N из M».
## До старта N = 0; после завершения N = M.
func step_counter() -> Vector2i:
	var m: int = _base.size()
	if _current_index >= 0:
		return Vector2i(_current_index + 1, m)
	return Vector2i(m if _finished else 0, m)


## Длительность плана, с.
func total_sec() -> int:
	return _total_sec


## Позиция в плане, с: начало текущего шага + смещение; после пропуска остаток пропущенного
## шага считается пройденным (как курсор `PlanChartModel`).
func position_sec() -> float:
	if _current_index >= 0:
		return minf(float(workout.step_start_sec(_current_index)) + _step_offset_sec, float(_total_sec))
	if _finished:
		return float(_total_sec) if not _stopped_early else float(workout.step_start_sec(maxi(_last_index, 0)))
	return 0.0


## Остаток тренировки, с (шапка «Осталось»). После досрочного завершения — 0.
func remaining_sec() -> int:
	if _finished:
		return 0
	return maxi(_total_sec - roundi(position_sec()), 0)


## Общий прогресс тренировки 0…1 (полоса в шапке).
func progress() -> float:
	if _finished:
		return 1.0
	return clampf(position_sec() / float(_total_sec), 0.0, 1.0) if _total_sec > 0 else 0.0


## Название тренировки (шапка).
func title() -> String:
	return workout.name if workout != null else ""


## Блоки повторов плана: `{first, last, period, count}`.
func repeat_blocks() -> Array[Dictionary]:
	return _blocks.duplicate(true)


## Номер версии строк: растёт при смене состава строк, их целей и состояний, но не при
## движении смещения внутри шага. По нему view перестраивает раскладку и запускает анимацию.
func revision() -> int:
	return _revision


# ---------------------------------------------------------------------------
# Форматы
# ---------------------------------------------------------------------------

## Длительность шага (HUD-13.2, `hud.md` п. 5.3): `м:сс` (`5:00`, `0:15`), от часа `ч:мм:сс`.
static func format_duration(sec: int) -> String:
	var s: int = maxi(sec, 0)
	if s < 3600:
		return "%d:%02d" % [s / 60, s % 60]
	return "%d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]


## Цель числами без единицы: `180`, рампа — `125→225`.
static func format_target(start_w: int, end_w: int) -> String:
	if start_w == end_w:
		return str(start_w)
	return "%d→%d" % [start_w, end_w]


## Цель строки с единицей: `180 Вт`, `125→225 Вт`, у свободного шага — `free_text`.
## У свёрнутого блока — `2:00 300 / 1:00 125 Вт` (без префикса «N ×»).
static func target_label(row: Dictionary, unit: String, free_text: String) -> String:
	if row.get("kind") == KIND_REPEAT:
		var parts: Array[String] = []
		var all_free: bool = true
		for p: Dictionary in row["parts"]:
			var t: String = free_text if p["free"] else str(p["target_text"])
			parts.append(("%s %s" % [p["duration_text"], t]).strip_edges())
			all_free = all_free and bool(p["free"])
		var body: String = " / ".join(parts)
		return body if all_free or unit.is_empty() else "%s %s" % [body, unit]
	if row.get("free", false):
		return free_text
	return ("%s %s" % [row["target_text"], unit]).strip_edges()


## Префикс свёрнутого блока: `3 ×`; у шага — пусто.
static func repeat_prefix(row: Dictionary) -> String:
	return "%d ×" % int(row["repeat_count"]) if row.get("kind") == KIND_REPEAT else ""


## Текст строки целиком (HUD-13.2, 13.8): `5:00  180 Вт`, `5:00  125→225 Вт`,
## `3:00  свободно`, `3 × 2:00 300 / 1:00 125 Вт`.
static func row_text(row: Dictionary, unit: String, free_text: String) -> String:
	if row.get("kind") == KIND_REPEAT:
		return "%s %s" % [repeat_prefix(row), target_label(row, unit, free_text)]
	return ("%s  %s" % [row["duration_text"], target_label(row, unit, free_text)]).strip_edges()


# ---------------------------------------------------------------------------
# Повторы
# ---------------------------------------------------------------------------

## Блоки повторов плана `{first, last, period, count}` по `first`: сохранённые парсером
## (`Workout.valid_repeat_blocks()`), а в остальных шагах — блоки `IntervalsT`: максимальные
## серии пар `INTERVAL_ON` + `INTERVAL_OFF` с одинаковыми длительностями и целями (`period = 2`).
static func detect_repeat_blocks(plan: Workout) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if plan == null:
		return out
	var explicit: Array[Dictionary] = plan.valid_repeat_blocks()
	var steps: Array[WorkoutStep] = plan.steps
	var n: int = steps.size()
	var taken := PackedByteArray()
	taken.resize(n)
	for b in explicit:
		for k in range(int(b["first"]), int(b["last"]) + 1):
			taken[k] = 1
	var i: int = 0
	while i < n:
		if not _is_free_pair_at(steps, taken, i):
			i += 1
			continue
		var count: int = 1
		var j: int = i + 2
		while _is_free_pair_at(steps, taken, j) and _same_step(steps[j], steps[i]) and _same_step(steps[j + 1], steps[i + 1]):
			count += 1
			j += 2
		out.append({"first": i, "last": j - 1, "period": 2, "count": count})
		i = j
	out.append_array(explicit)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["first"]) < int(b["first"]))
	return out


static func _is_free_pair_at(steps: Array[WorkoutStep], taken: PackedByteArray, i: int) -> bool:
	return _is_pair_at(steps, i) and taken[i] == 0 and taken[i + 1] == 0


static func _is_pair_at(steps: Array[WorkoutStep], i: int) -> bool:
	return i + 1 < steps.size() \
			and steps[i].kind == WorkoutStep.StepKind.INTERVAL_ON \
			and steps[i + 1].kind == WorkoutStep.StepKind.INTERVAL_OFF


static func _same_step(a: WorkoutStep, b: WorkoutStep) -> bool:
	return a.kind == b.kind and a.duration_sec == b.duration_sec and a.target_kind == b.target_kind \
			and is_equal_approx(a.target_start, b.target_start) and is_equal_approx(a.target_end, b.target_end)


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _rebuild() -> void:
	_base.clear()
	_total_sec = workout.total_duration_sec() if workout != null else 0
	if workout != null:
		var z: PowerZones = zones if zones != null else PowerZones.coggan(ftp_w)
		for seg in workout.segments(ftp_w, intensity, z):
			var index: int = int(seg["index"])
			var free: bool = workout.steps[index].is_free_ride()
			var w0: int = 0 if free else int(seg["start_watts"])
			var w1: int = 0 if free else int(seg["end_watts"])
			var zone: int = 0 if free else int(seg["zone"])
			if not free and _target_limit.is_valid():
				var l0: int = _target_limit.call(w0)
				var l1: int = _target_limit.call(w1)
				if l0 != w0 or l1 != w1:
					w0 = l0
					w1 = l1
					zone = PlanChartModel._zone_of(z, (w0 + w1) * 0.5)
			_base.append({
				"index": index,
				"duration_sec": int(seg["duration_sec"]),
				"start_watts": w0,
				"end_watts": w1,
				"zone": zone,
				"zone_token": ZonePalette.power_token(zone),
				"color_token": FREE_TOKEN if free else ZonePalette.power_token(zone),
				"free": free,
				"ramp": not free and w0 != w1,
				"duration_text": format_duration(int(seg["duration_sec"])),
				"target_text": "" if free else format_target(w0, w1),
			})
	_build_rows()


func _build_rows() -> void:
	_rows.clear()
	var block_at: Dictionary = {}
	for b in _blocks:
		block_at[int(b["first"])] = b
	var i: int = 0
	while i < _base.size():
		if block_at.has(i) and _block_collapsed(block_at[i]):
			_rows.append(_repeat_row(block_at[i]))
			i = int(block_at[i]["last"]) + 1
			continue
		_rows.append(_step_row(i))
		i += 1
	_revision += 1


## Блок свёрнут, пока ни один его шаг не начинался (текущий шаг левее блока или нет старта).
func _block_collapsed(block: Dictionary) -> bool:
	var reached: int = _current_index if _current_index >= 0 else (_last_index if _finished else -1)
	if _finished and not _stopped_early:
		return false
	for s in _skipped:
		if s >= int(block["first"]) and s <= int(block["last"]):
			return false
	return reached < int(block["first"])


func _step_row(i: int) -> Dictionary:
	var base: Dictionary = _base[i]
	return {
		"key": "s%d" % i,
		"kind": KIND_STEP,
		"first_step": i,
		"last_step": i,
		"status": _status_of(i),
		"duration_sec": base["duration_sec"],
		"duration_text": base["duration_text"],
		"target_text": base["target_text"],
		"start_watts": base["start_watts"],
		"end_watts": base["end_watts"],
		"zone": base["zone"],
		"zone_token": base["zone_token"],
		"color_token": base["color_token"],
		"free": base["free"],
		"ramp": base["ramp"],
		"repeat_count": 1,
		"parts": [],
	}


func _repeat_row(block: Dictionary) -> Dictionary:
	var first: int = int(block["first"])
	var last: int = int(block["last"])
	var period: int = int(block["period"])
	var work: Dictionary = _base[_work_step(first, period)]
	var parts: Array = []
	for k in period:
		var p: Dictionary = _base[first + k]
		parts.append({"duration_text": p["duration_text"], "target_text": p["target_text"], "free": p["free"]})
	var duration: int = 0
	for k in range(first, last + 1):
		duration += int(_base[k]["duration_sec"])
	return {
		"key": "r%d" % first,
		"kind": KIND_REPEAT,
		"first_step": first,
		"last_step": last,
		"status": STATUS_UPCOMING,
		"duration_sec": duration,
		"duration_text": format_duration(duration),
		"target_text": work["target_text"],
		"start_watts": work["start_watts"],
		"end_watts": work["end_watts"],
		"zone": work["zone"],
		"zone_token": work["zone_token"],
		"color_token": work["color_token"],
		"free": work["free"],
		"ramp": work["ramp"],
		"repeat_count": int(block["count"]),
		"parts": parts,
	}


## Рабочий отрезок повтора `[first, first + period)`: шаг с наибольшей целью (у рампы —
## по большему концу), свободные шаги — без цели, ниже любых; при равенстве — первый.
func _work_step(first: int, period: int) -> int:
	var best: int = first
	var best_w: int = -1
	for k in range(first, first + period):
		var p: Dictionary = _base[k]
		var w: int = -1 if p["free"] else maxi(int(p["start_watts"]), int(p["end_watts"]))
		if w > best_w:
			best = k
			best_w = w
	return best


func _status_of(i: int) -> String:
	if _skipped.has(i):
		return STATUS_SKIPPED
	if i == _current_index:
		return STATUS_CURRENT
	if _finished:
		if not _stopped_early or i <= _last_index:
			return STATUS_DONE
		return STATUS_UPCOMING
	if _current_index >= 0 and i < _current_index:
		return STATUS_DONE
	return STATUS_UPCOMING


## Индекс строки, в которую входит шаг `step` (-1 — нет такой строки).
func _row_of_step(step: int) -> int:
	for i in _rows.size():
		if int(_rows[i]["first_step"]) <= step and step <= int(_rows[i]["last_step"]):
			return i
	return -1
