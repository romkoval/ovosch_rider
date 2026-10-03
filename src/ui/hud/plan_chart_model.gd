class_name PlanChartModel
extends RefCounted
## Модель нижнего графика плана (REQ-HUD-10 крит. 1–5; `docs/game/hud.md` п. 7, 12.3).
## Только числа и токены, без узлов и отрисовки: рисует `HudChart` (T-071).
##
## Шаги — из `Workout.segments(ftp, intensity, zones)` (модель сегментов HUD-07.1) с текущим
## множителем WRK-07. Для каждого шага: начало, длительность, цели в начале и в конце (Вт),
## зона и признак «свободно» (FreeRide/MaxEffort — `WorkoutStep.is_free_ride()`; у такого
## шага нет зоны, `color_token = FREE_TOKEN`, высота — `FREE_HEIGHT_FRACTION` поля).
##
## Куски (`pieces()`) — то, что рисуется: рампа режется по точкам, где цель пересекает
## границу зоны, — число кусков равно числу зон, через которые проходит цель
## (40 → 70 % FTP при Coggan → Z1 и Z2); ровный шаг — один кусок. Текущий шаг дополнительно
## режется курсором: слева — `done`, справа — `upcoming`, у обоих `current = true`.
##
## Оси: X — весь план целиком, `x(0) = 0`, `x(total) = width`, линейно (скользящего окна нет).
## Y мощности — 0…`y_max = max(Y_MAX_FACTOR × максимальная цель плана с учётом множителя,
## FTP_FLOOR_FACTOR × FTP)` (HUD-10.2, решение У-2), у плана без целей — `Y_MAX_FACTOR × FTP`;
## пунктир FTP (`ftp_fraction()` высоты поля) поэтому всегда внутри поля. При смене множителя
## пересчитываются `y_max`, цели и зоны (вызов `set_intensity`/`sync` раз в сэмпл).
##
## Курсор — позиция в плане: начало текущего шага + смещение в нём. Без пропусков это ровно
## прошедшее активное время (HUD-10.5); после пропуска (WRK-06) курсор стоит в текущем
## шаге, а остаток пропущенного шага остаётся слева от курсора в состоянии `skipped`.
## На паузе исполнитель не продвигает время — курсор стоит.
##
## Сдвиг серий факта (HUD-10.5, HUD-11.1, решение У-1): точка сэмпла активного времени `e`
## стоит в плане на `e + shift_at(e)`. Сдвиг берётся из журнала пропусков сессии, а не из
## текущего состояния: пропуск шага k на активном времени a даёт сдвиг
## `конец шага k − ⌊a⌋` всем сэмплам с `e > ⌊a⌋` (до следующего пропуска). Поэтому результат
## не зависит от того, как часто вызывается `sync`.
##
## Статусы шага: `skipped` (по журналу сессии) → `current` (индекс исполнителя) →
## `done` (конец шага не правее курсора) → `upcoming`.

const STATUS_DONE: String = "done"
const STATUS_CURRENT: String = "current"
const STATUS_UPCOMING: String = "upcoming"
const STATUS_SKIPPED: String = "skipped"

## Потолок шкалы мощности: доля от максимальной цели плана (HUD-10.2).
const Y_MAX_FACTOR: float = 1.25
## Нижняя граница потолка шкалы: доля FTP — пунктир FTP всегда в поле (HUD-10.2, У-2).
const FTP_FLOOR_FACTOR: float = 1.1
## Высота сегмента «свободно» в долях высоты поля (HUD-10.6).
const FREE_HEIGHT_FRACTION: float = 0.30
## Токен цвета сегмента «свободно» (`hud.md` п. 11).
const FREE_TOKEN: String = "hud.free"

var workout: Workout
var ftp_w: int = 0
var intensity: float = 1.0
## Зоны мощности профиля; null — 7 зон Coggan от `ftp_w`.
var zones: PowerZones = null

## Шаги без статуса — пересчитываются только при смене множителя, FTP или зон.
var _base: Array[Dictionary] = []
var _total_sec: int = 0
var _y_max: float = 1.0
var _cursor_sec: float = 0.0
var _current_index: int = -1
var _skipped: Array[int] = []
var _time_shift_sec: int = 0
## Журнал сдвигов по пропускам: с активного времени `_shift_from[i]` (включительно) действует
## сдвиг `_shift_value[i]`; по возрастанию `_shift_from`.
var _shift_from := PackedInt32Array()
var _shift_value := PackedInt32Array()
var _revision: int = 0


func _init(plan: Workout, ftp: int, intensity_factor: float = 1.0, power_zones: PowerZones = null) -> void:
	workout = plan
	ftp_w = ftp
	intensity = intensity_factor
	zones = power_zones
	_rebuild()


## Модель для сессии: план, FTP и множитель исполнителя; затем `sync(session)` раз в сэмпл.
static func for_session(session: WorkoutSession, power_zones: PowerZones = null) -> PlanChartModel:
	var ex := session.executor
	var model := PlanChartModel.new(ex.workout, ex.ftp_w, ex.intensity, power_zones)
	model.sync(session)
	return model


# ---------------------------------------------------------------------------
# Обновление
# ---------------------------------------------------------------------------

## Подтянуть множитель, курсор, текущий шаг и пропуски из сессии. Вызывать на каждом
## сэмпле и при смене множителя/пропуске. Возвращает true, если что-то изменилось.
func sync(session: WorkoutSession) -> bool:
	var ex := session.executor
	var changed: bool = set_intensity(ex.intensity)
	var index: int = ex.current_step_index()
	var cursor: float = _cursor_sec
	if index >= 0:
		cursor = float(workout.step_start_sec(index) + ex.step_offset_sec())
	elif ex.is_finished():
		# Досрочное завершение — курсор там, где остановились; иначе план пройден целиком.
		cursor = _cursor_sec if ex.stopped_early else float(_total_sec)
	else:
		cursor = 0.0
	changed = set_progress(cursor, index, skipped_indices(session.events)) or changed
	set_skip_log(session.events)
	if index >= 0:
		_time_shift_sec = maxi(roundi(cursor) - ex.elapsed_sec(), 0)
	return changed


## Множитель интенсивности WRK-07: пересчитывает цели, зоны и `y_max`.
func set_intensity(value: float) -> bool:
	if is_equal_approx(value, intensity):
		return false
	intensity = value
	_rebuild()
	return true


## FTP профиля: меняет ватты целей в % FTP, границы зон и пунктир FTP.
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


## Положение в плане: курсор (с), индекс текущего шага (-1 — нет), пропущенные шаги.
## Курсор зажимается в 0…длительность плана. Возвращает true, если что-то изменилось.
func set_progress(cursor_sec: float, current_index: int, skipped: Array[int] = []) -> bool:
	var cursor: float = clampf(cursor_sec, 0.0, float(_total_sec))
	var sorted_skipped: Array[int] = skipped.duplicate()
	sorted_skipped.sort()
	var status_changed: bool = current_index != _current_index or sorted_skipped != _skipped
	var changed: bool = status_changed or not is_equal_approx(cursor, _cursor_sec)
	_cursor_sec = cursor
	_current_index = current_index
	_skipped = sorted_skipped
	if status_changed:
		_revision += 1
	return changed


## Индексы пропущенных шагов из журнала событий сессии (WRK-06 крит. 4).
static func skipped_indices(events: Array[Dictionary]) -> Array[int]:
	var out: Array[int] = []
	for e in events:
		if e.get("type") == WorkoutSession.EVENT_SKIP and int(e.get("value", -1)) >= 0:
			out.append(int(e["value"]))
	return out


## Журнал сдвигов из событий пропуска сессии (`WorkoutSession.EVENT_SKIP`: `at_sec` — активное
## время пропуска, `value` — индекс пропущенного шага). Вызывается из `sync`; отдельно — для
## восстановленной сессии или тестов.
func set_skip_log(events: Array[Dictionary]) -> void:
	_shift_from.clear()
	_shift_value.clear()
	if workout == null:
		return
	for e in events:
		if e.get("type") != WorkoutSession.EVENT_SKIP:
			continue
		var index: int = int(e.get("value", -1))
		if index < 0 or index >= workout.steps.size():
			continue
		var at: int = floori(float(e.get("at_sec", 0.0)))
		var shift: int = maxi(workout.step_start_sec(index + 1) - at, 0)
		var from: int = at + 1
		# Несколько пропусков в одну секунду — действует последний.
		if _shift_from.size() > 0 and _shift_from[_shift_from.size() - 1] >= from:
			_shift_value[_shift_value.size() - 1] = shift
			continue
		_shift_from.append(from)
		_shift_value.append(shift)


## Сдвиг позиции в плане относительно активного времени для сэмпла, закрытого на активном
## времени `elapsed_sec` (точка серии факта — `elapsed_sec + shift_at(elapsed_sec)`), с (≥ 0).
## Сэмплы до первого пропуска — 0; после пропуска — сдвиг, действовавший в их момент.
func shift_at(elapsed_sec: int) -> int:
	for i in range(_shift_from.size() - 1, -1, -1):
		if elapsed_sec >= _shift_from[i]:
			return _shift_value[i]
	return 0


# ---------------------------------------------------------------------------
# Оси
# ---------------------------------------------------------------------------

## Длительность плана, с.
func total_sec() -> int:
	return _total_sec


## Наибольшая цель плана с учётом множителя, Вт (0 — в плане только «свободно»).
func max_target_w() -> int:
	var best: int = 0
	for seg in _base:
		if not seg["free"]:
			best = maxi(best, maxi(int(seg["start_watts"]), int(seg["end_watts"])))
	return best


## Потолок шкалы мощности, Вт: max(1.25 × максимальная цель, 1.1 × FTP); без целей — 1.25 × FTP.
func y_max() -> float:
	return _y_max


## X момента `t_sec` от левого края поля шириной `width`: x(0) = 0, x(total) = width.
func x_of(t_sec: float, width: float) -> float:
	if _total_sec <= 0:
		return 0.0
	return clampf(t_sec, 0.0, float(_total_sec)) / float(_total_sec) * width


## Доля высоты поля для мощности `watts` (0 — низ, 1 — верх `y_max`), зажата в 0…1.
func power_fraction(watts: float) -> float:
	return clampf(watts / _y_max, 0.0, 1.0)


## Y мощности от верхнего края поля высотой `height` (Godot: ось Y вниз).
func y_of(watts: float, height: float) -> float:
	return height * (1.0 - power_fraction(watts))


## Доля высоты пунктира FTP: при FTP > 0 не больше 1 / 1.1 (потолок шкалы ≥ 1.1 × FTP).
func ftp_fraction() -> float:
	return float(ftp_w) / _y_max


## Пунктир FTP в поле графика: всегда при FTP > 0 (HUD-10.2, У-2).
func ftp_visible() -> bool:
	return ftp_w > 0


## Подписи шкалы времени (HUD-10.4), см. `TimeAxis.labels`.
func time_labels() -> Array[Dictionary]:
	return TimeAxis.labels(_total_sec)


# ---------------------------------------------------------------------------
# Курсор
# ---------------------------------------------------------------------------

## Курсор — позиция в плане, с (0…total).
func cursor_sec() -> float:
	return _cursor_sec


## Курсор в долях ширины поля (0…1).
func cursor_fraction() -> float:
	return _cursor_sec / float(_total_sec) if _total_sec > 0 else 0.0


## Насколько позиция в плане опережает активное время сейчас (на последнем `sync`), с (≥ 0).
## Для серий факта — не текущий сдвиг, а сдвиг на момент сэмпла: `shift_at(e)`
## (`EffortSeries.sync_from_plan(stream, model)`).
func time_shift_sec() -> int:
	return _time_shift_sec


## Номер версии раскладки сегментов: растёт при смене целей/зон и статусов шагов,
## но не при движении курсора — по нему view перерисовывает кэш сегментов.
func revision() -> int:
	return _revision


# ---------------------------------------------------------------------------
# Сегменты и куски
# ---------------------------------------------------------------------------

## Шаги плана: `{index, start_sec, end_sec, duration_sec, start_watts, end_watts, zone,
## zone_token, color_token, free, ramp, status}`; сумма `duration_sec` = `total_sec()`.
func segments() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for seg in _base:
		var s: Dictionary = seg.duplicate()
		s.erase("pieces")
		s["status"] = _status_of(seg)
		out.append(s)
	return out


## Куски для отрисовки в порядке времени: `{step_index, start_sec, end_sec, start_watts,
## end_watts, top_start, top_end, zone, zone_token, color_token, free, ramp, status, current}`.
## `top_*` — высота верха в долях поля (у «свободно» — `FREE_HEIGHT_FRACTION`).
## `status` куска — `done`/`upcoming`/`skipped`; текущий шаг разрезан курсором.
## Шаги нулевой длительности кусков не дают.
func pieces() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for seg in _base:
		var status: String = _status_of(seg)
		for p: Dictionary in seg["pieces"]:
			if status != STATUS_CURRENT:
				out.append(_piece_out(p, status, false))
				continue
			var a: float = float(p["start_sec"])
			var b: float = float(p["end_sec"])
			if b <= _cursor_sec:
				out.append(_piece_out(p, STATUS_DONE, true))
			elif a >= _cursor_sec:
				out.append(_piece_out(p, STATUS_UPCOMING, true))
			else:
				out.append(_piece_out(_cut(p, a, _cursor_sec), STATUS_DONE, true))
				out.append(_piece_out(_cut(p, _cursor_sec, b), STATUS_UPCOMING, true))
	return out


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _rebuild() -> void:
	_base.clear()
	_total_sec = workout.total_duration_sec() if workout != null else 0
	if workout == null:
		_y_max = 1.0
		return
	var z: PowerZones = zones if zones != null else PowerZones.coggan(ftp_w)
	for seg in workout.segments(ftp_w, intensity, z):
		var index: int = int(seg["index"])
		var free: bool = workout.steps[index].is_free_ride()
		var start: int = int(seg["start_sec"])
		var duration: int = int(seg["duration_sec"])
		var w0: int = int(seg["start_watts"])
		var w1: int = int(seg["end_watts"])
		var zone: int = 0 if free else int(seg["zone"])
		seg["end_sec"] = start + duration
		seg["zone"] = zone
		seg["zone_token"] = ZonePalette.power_token(zone)
		seg["color_token"] = FREE_TOKEN if free else ZonePalette.power_token(zone)
		seg["free"] = free
		seg["ramp"] = not free and w0 != w1
		seg["pieces"] = _split_by_zones(index, float(start), float(duration), w0, w1, free, z)
		_base.append(seg)
	var top: int = max_target_w()
	if top > 0:
		_y_max = maxf(Y_MAX_FACTOR * float(top), FTP_FLOOR_FACTOR * float(ftp_w))
	else:
		_y_max = Y_MAX_FACTOR * float(ftp_w) if ftp_w > 0 else 1.0
	# Высоты верха считаются от нового y_max.
	for seg in _base:
		for p: Dictionary in seg["pieces"]:
			_fill_tops(p)
	_revision += 1


## Режет шаг по точкам пересечения границ зон (HUD-10.3). Ровный шаг и «свободно» — один кусок.
func _split_by_zones(index: int, start: float, duration: float, w0: int, w1: int, free: bool,
		z: PowerZones) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if duration <= 0.0:
		return out
	var cuts: Array[float] = [0.0]
	if not free and w0 != w1 and z.ftp_w > 0:
		for pct in z.boundaries_pct:
			var b: float = pct / 100.0 * float(z.ftp_w)
			if (float(w0) < b and b < float(w1)) or (float(w1) < b and b < float(w0)):
				cuts.append((b - float(w0)) / float(w1 - w0) * duration)
		cuts.sort()
	cuts.append(duration)
	for k in cuts.size() - 1:
		var a: float = cuts[k]
		var b: float = cuts[k + 1]
		if b <= a:
			continue
		var wa: float = lerpf(float(w0), float(w1), a / duration)
		var wb: float = lerpf(float(w0), float(w1), b / duration)
		var zone: int = 0 if free else _zone_of(z, (wa + wb) * 0.5)
		out.append({
			"step_index": index,
			"start_sec": start + a,
			"end_sec": start + b,
			"start_watts": wa,
			"end_watts": wb,
			"zone": zone,
			"zone_token": ZonePalette.power_token(zone),
			"color_token": FREE_TOKEN if free else ZonePalette.power_token(zone),
			"free": free,
			"ramp": not free and w0 != w1,
		})
	return out


## Зона дробной мощности по тому же правилу, что `PowerZones.zone_of` (граница — нижней зоне).
static func _zone_of(z: PowerZones, watts: float) -> int:
	if z.ftp_w <= 0:
		return 0
	var zone: int = 1
	for b in z.boundaries_pct:
		if watts * 100.0 > b * float(z.ftp_w):
			zone += 1
		else:
			break
	return zone


func _fill_tops(p: Dictionary) -> void:
	if p["free"]:
		p["top_start"] = FREE_HEIGHT_FRACTION
		p["top_end"] = FREE_HEIGHT_FRACTION
	else:
		p["top_start"] = power_fraction(float(p["start_watts"]))
		p["top_end"] = power_fraction(float(p["end_watts"]))


## Часть куска `p` на [a; b] с линейно интерполированными целями.
func _cut(p: Dictionary, a: float, b: float) -> Dictionary:
	var out: Dictionary = p.duplicate()
	var p0: float = float(p["start_sec"])
	var span: float = float(p["end_sec"]) - p0
	var w0: float = float(p["start_watts"])
	var w1: float = float(p["end_watts"])
	out["start_sec"] = a
	out["end_sec"] = b
	out["start_watts"] = lerpf(w0, w1, (a - p0) / span)
	out["end_watts"] = lerpf(w0, w1, (b - p0) / span)
	_fill_tops(out)
	return out


func _piece_out(p: Dictionary, status: String, current: bool) -> Dictionary:
	var out: Dictionary = p.duplicate()
	out["status"] = status
	out["current"] = current
	return out


func _status_of(seg: Dictionary) -> String:
	var index: int = int(seg["index"])
	if _skipped.has(index):
		return STATUS_SKIPPED
	if index == _current_index:
		return STATUS_CURRENT
	# Шаг целиком левее курсора (у шага нулевой длительности — строго левее).
	if float(seg["end_sec"]) <= _cursor_sec and float(seg["start_sec"]) < _cursor_sec:
		return STATUS_DONE
	return STATUS_UPCOMING
