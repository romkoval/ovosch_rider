class_name EffortSeries
extends RefCounted
## Серии факта на нижнем графике HUD: сглаженная мощность и пульс
## (REQ-HUD-11 крит. 1–5, REQ-HUD-12 крит. 1, 2, 5–7, REQ-FRD-06 крит. 4 — модель окна и шкалы;
## `docs/game/hud.md` п. 7, 8). Только числа и токены, без узлов: рисует `HudChart` (T-071, T-079).
##
## Точки:
## - одна точка на сэмпл (1 Гц), время `t` — активное время сэмпла плюс сдвиг плана после
##   пропусков, действовавший в момент этого сэмпла (`PlanChartModel.shift_at`, `sync_from_plan`);
## - мощность — сглаженная 3 с (`PowerSmoother`, HUD-09); 100, 200, 300, 300 → 100, 150, 200, 267;
## - сэмпл «нет данных» мощности — разрыв линии, а не точка 0 (в сглаживатель он идёт пропуском);
## - пульс — одна точка на сэмпл с пульсом > 0; пульс 0 и «нет данных» — разрыв;
## - пауза сэмплов не даёт, активное время на паузе стоит — линия продолжается с того же x;
##   скачок времени больше 1 с (пропуск шага) — разрыв.
##
## Выдача (`runs`): отрезки линии между разрывами — `{points: PackedVector2Array (t, значение),
## clipped: PackedByteArray}`. Значение вне шкалы рисуется на её границе и помечено `clipped = 1`.
## Если точек в диапазоне больше 2 × ширины, они прореживаются: диапазон делится на `width_px`
## корзин, из каждой берутся минимум и максимум в порядке времени (как LOC-03.2) — не больше
## 2 × ширины точек, пики сохраняются.
##
## Режимы:
## - `MODE_PLAN` — тренировка по плану: ось X и `y_max` задаёт `PlanChartModel`, мощность — линия;
## - `MODE_WINDOW` — свободная езда: окно `window_sec` (по умолчанию 30 мин; первые 30 мин
##   шкала 0…30 мин, дальше — последние 30 мин), `power_y_max()` =
##   max(`ftp_factor` × FTP, ⌈максимум сглаженной мощности в окне / 50⌉ × 50), растёт сразу,
##   уменьшается не чаще раза в `Y_MAX_SHRINK_INTERVAL_SEC`; мощность — площадь с линией.
##
## Шкала пульса своя: `HR_MIN_BPM`…`max_hr` профиля (или `HR_DEFAULT_MAX_BPM`), подписи
## `HR_LABELS_BPM` справа (`SIDE_RIGHT`), подписи мощности/FTP — слева. Без данных пульса
## серия пустая и `hr_scale_visible()` — false (шкала и половина легенды скрыты).

const MODE_PLAN: String = "plan"
const MODE_WINDOW: String = "window"

const SERIES_POWER: String = "power"
const SERIES_HR: String = "hr"

## Стиль серии: только полилиния / площадь под линией плюс линия.
const STYLE_LINE: String = "line"
const STYLE_AREA_LINE: String = "area_line"

const SIDE_LEFT: String = "left"
const SIDE_RIGHT: String = "right"

## Токены цвета (`hud.md` п. 11); сами цвета — в теме UI (T-060/T-071).
const TOKEN_POWER_LINE: String = "hud.power_line"
const TOKEN_HR_LINE: String = "hud.hr_line"
const TOKEN_HR_LABEL: String = "hud.hr_label"
const TOKEN_OUTLINE: String = "hud.ink"
## Толщины в lp (умножаются на масштаб s): линия 2·s, обводка 2·s + 3·s; альфа обводки 0.9.
const LINE_WIDTH_LP: float = 2.0
const OUTLINE_WIDTH_LP: float = 5.0
const OUTLINE_ALPHA: float = 0.9

const SMOOTHING_WINDOW_SEC: int = 3

const HR_MIN_BPM: int = 50
const HR_DEFAULT_MAX_BPM: int = 200
const HR_LABELS_BPM: Array[int] = [100, 150]

const DEFAULT_WINDOW_SEC: int = 1800
const DEFAULT_FTP_FACTOR: float = 1.5
const Y_MAX_ROUND_W: int = 50
const Y_MAX_SHRINK_INTERVAL_SEC: int = 60

## Признак «нет значения» в хранилище точек.
const NO_VALUE: int = -1

var mode: String = MODE_PLAN
## Окно графика свободной езды, с (FRD-06 крит. 4).
var window_sec: int = DEFAULT_WINDOW_SEC
## Нижняя граница потолка шкалы мощности в окне: доля FTP.
var ftp_factor: float = DEFAULT_FTP_FACTOR

var _ftp_w: int = 0
var _max_hr: int = 0
var _smoother := PowerSmoother.new(SMOOTHING_WINDOW_SEC)
var _t := PackedInt32Array()
var _power := PackedInt32Array()
var _hr := PackedInt32Array()
## 1 — перед точкой скачок времени > 1 с (разрыв обеих серий).
var _jump := PackedByteArray()
var _consumed_rows: int = 0
var _y_max: float = 0.0
var _last_shrink_t: int = -1
var _hr_points: int = 0


func _init(series_mode: String = MODE_PLAN, ftp: int = 0, max_hr: int = 0) -> void:
	mode = series_mode
	_ftp_w = ftp
	_max_hr = max_hr
	_update_y_max(true)


## Режим «история усилия» свободной езды с окном и коэффициентом шкалы.
static func sliding_window(ftp: int, max_hr: int = 0, window: int = DEFAULT_WINDOW_SEC,
		factor: float = DEFAULT_FTP_FACTOR) -> EffortSeries:
	var s := EffortSeries.new(MODE_WINDOW, ftp, max_hr)
	s.window_sec = maxi(window, 1)
	s.ftp_factor = factor
	s._update_y_max(true)
	return s


# ---------------------------------------------------------------------------
# Наполнение
# ---------------------------------------------------------------------------

## Добавить сэмпл секунды `t_sec`. Время должно расти; повтор или откат игнорируется (false).
func push(t_sec: int, power_w: int, has_power: bool, hr_bpm: int, has_hr: bool) -> bool:
	if _t.size() > 0 and t_sec <= _t[_t.size() - 1]:
		return false
	var jump: bool = _t.size() > 0 and t_sec - _t[_t.size() - 1] > 1
	var smoothed: int = NO_VALUE
	if has_power:
		smoothed = _smoother.push(power_w)
	else:
		_smoother.push_missing()
	_t.append(t_sec)
	_power.append(smoothed)
	var hr_ok: bool = has_hr and hr_bpm > 0
	_hr.append(hr_bpm if hr_ok else NO_VALUE)
	if hr_ok:
		_hr_points += 1
	_jump.append(1 if jump else 0)
	if mode == MODE_WINDOW:
		_update_y_max(false)
	return true


## Забрать новые строки потока сессии. Строка потока помечена началом своей секунды
## (`time_sec = elapsed − 1`), точка графика — её концом (`elapsed`), чтобы последняя точка
## стояла ровно на курсоре. `time_shift_sec` прибавляется ко всем новым строкам одинаково —
## годится без пропусков (свободная езда); для плана — `sync_from_plan`. Новый (более
## короткий) поток — сброс. Возвращает число добавленных точек.
func sync_from_stream(stream: SampleStream, time_shift_sec: int = 0) -> int:
	return _consume(stream, null, time_shift_sec)


## То же для тренировки по плану: каждая строка получает сдвиг позиции в плане, действовавший
## в её момент (`plan.shift_at(elapsed)`, журнал пропусков сессии — HUD-10.5, HUD-11.1).
## Результат не зависит от частоты вызова: одна синхронизация в конце даёт те же точки, что
## синхронизация на каждом сэмпле. `plan.sync(session)` — раньше этого вызова.
func sync_from_plan(stream: SampleStream, plan: PlanChartModel) -> int:
	return _consume(stream, plan, 0)


func _consume(stream: SampleStream, plan: PlanChartModel, time_shift_sec: int) -> int:
	if stream.size() < _consumed_rows:
		reset()
	var added: int = 0
	for i in range(_consumed_rows, stream.size()):
		var elapsed: int = stream.time_sec[i] + 1
		var shift: int = plan.shift_at(elapsed) if plan != null else time_shift_sec
		if push(elapsed + shift, stream.power_w[i], stream.has_power[i],
				stream.heart_rate_bpm[i], stream.has_heart_rate[i]):
			added += 1
	_consumed_rows = stream.size()
	return added


func reset() -> void:
	_smoother.reset()
	_t.clear()
	_power.clear()
	_hr.clear()
	_jump.clear()
	_consumed_rows = 0
	_last_shrink_t = -1
	_hr_points = 0
	_update_y_max(true)


## FTP профиля (потолок шкалы окна). Пересчитывает `power_y_max()` сразу.
func set_ftp(ftp: int) -> void:
	_ftp_w = ftp
	_update_y_max(true)


## `max_hr` профиля (0 — не задан, шкала до 200).
func set_max_hr(max_hr: int) -> void:
	_max_hr = max_hr


# ---------------------------------------------------------------------------
# Данные
# ---------------------------------------------------------------------------

## Число сэмплов (включая разрывы).
func size() -> int:
	return _t.size()


## Время последнего сэмпла, с (0 — сэмплов нет).
func last_time_sec() -> int:
	return _t[_t.size() - 1] if _t.size() > 0 else 0


## Все точки серии без прореживания и зажима: `(t, значение)` только для сэмплов с данными.
func raw_points(series: String) -> PackedVector2Array:
	var values: PackedInt32Array = _values(series)
	var out := PackedVector2Array()
	for i in _t.size():
		if values[i] != NO_VALUE:
			out.append(Vector2(float(_t[i]), float(values[i])))
	return out


## Есть хотя бы одна точка пульса.
func has_hr_data() -> bool:
	return _hr_points > 0


## Отрезки серии `series` в диапазоне времени [t_from; t_to], прореженные под ширину
## `width_px`, значения зажаты в [v_min; v_max] с флагом обрезки.
func runs(series: String, t_from: float, t_to: float, width_px: int, v_min: float, v_max: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var values: PackedInt32Array = _values(series)
	var first: int = _first_index_at_or_after(t_from)
	var last: int = _last_index_at_or_before(t_to)
	if first > last:
		return out
	var picked: PackedInt32Array = _pick(values, first, last, t_from, t_to, maxi(width_px, 1))
	# Разрыв между соседними выбранными точками — если между ними есть сэмпл без данных
	# или скачок времени (префиксная сумма маркеров).
	var marks := PackedInt32Array()
	marks.resize(last - first + 2)
	marks[0] = 0
	for i in range(first, last + 1):
		var m: int = 1 if values[i] == NO_VALUE or _jump[i] == 1 else 0
		marks[i - first + 1] = marks[i - first] + m
	var run_points := PackedVector2Array()
	var run_clipped := PackedByteArray()
	var prev: int = -1
	for idx in picked:
		if prev >= 0 and marks[idx - first + 1] - marks[prev - first + 1] > 0:
			out.append({"points": run_points, "clipped": run_clipped})
			run_points = PackedVector2Array()
			run_clipped = PackedByteArray()
		var v: float = float(values[idx])
		var clamped: float = clampf(v, v_min, v_max)
		run_points.append(Vector2(float(_t[idx]), clamped))
		run_clipped.append(1 if clamped != v else 0)
		prev = idx
	if run_points.size() > 0:
		out.append({"points": run_points, "clipped": run_clipped})
	return out


## Отрезки мощности: шкала 0…`y_max` (в плане — `PlanChartModel.y_max()`).
func power_runs(t_from: float, t_to: float, width_px: int, y_max: float) -> Array[Dictionary]:
	return runs(SERIES_POWER, t_from, t_to, width_px, 0.0, y_max)


## Отрезки пульса: своя шкала `hr_scale_min()`…`hr_scale_max()`.
func hr_runs(t_from: float, t_to: float, width_px: int) -> Array[Dictionary]:
	return runs(SERIES_HR, t_from, t_to, width_px, float(hr_scale_min()), float(hr_scale_max()))


## Число точек во всех отрезках.
static func point_count(series_runs: Array[Dictionary]) -> int:
	var n: int = 0
	for r in series_runs:
		n += (r["points"] as PackedVector2Array).size()
	return n


# ---------------------------------------------------------------------------
# Шкалы и стиль
# ---------------------------------------------------------------------------

func hr_scale_min() -> int:
	return HR_MIN_BPM


## Верх шкалы пульса: `max_hr` профиля, если задан (> 50), иначе 200.
func hr_scale_max() -> int:
	return _max_hr if _max_hr > HR_MIN_BPM else HR_DEFAULT_MAX_BPM


## Доля высоты поля для пульса `bpm` по своей шкале, зажата в 0…1.
func hr_fraction(bpm: float) -> float:
	var lo: float = float(hr_scale_min())
	return clampf((bpm - lo) / (float(hr_scale_max()) - lo), 0.0, 1.0)


## Подписи шкалы пульса (100 и 150, если попадают в шкалу); пусто без данных пульса.
func hr_scale_labels() -> Array[int]:
	var out: Array[int] = []
	if not hr_scale_visible():
		return out
	for bpm in HR_LABELS_BPM:
		if bpm >= hr_scale_min() and bpm <= hr_scale_max():
			out.append(bpm)
	return out


## Шкала пульса и половина легенды «пульс» видны только при данных пульса (HUD-12.6).
func hr_scale_visible() -> bool:
	return has_hr_data()


## Стиль серии: `{style, fill, color_token, outline_token, outline_alpha, width_lp,
## outline_width_lp, scale_side, label_token}`. У пульса всегда `STYLE_LINE`, `fill = false`.
func style(series: String) -> Dictionary:
	if series == SERIES_HR:
		return {
			"style": STYLE_LINE, "fill": false,
			"color_token": TOKEN_HR_LINE, "outline_token": TOKEN_OUTLINE, "outline_alpha": OUTLINE_ALPHA,
			"width_lp": LINE_WIDTH_LP, "outline_width_lp": OUTLINE_WIDTH_LP,
			"scale_side": SIDE_RIGHT, "label_token": TOKEN_HR_LABEL,
		}
	var area: bool = mode == MODE_WINDOW
	return {
		"style": STYLE_AREA_LINE if area else STYLE_LINE, "fill": area,
		"color_token": TOKEN_POWER_LINE, "outline_token": TOKEN_OUTLINE, "outline_alpha": OUTLINE_ALPHA,
		"width_lp": LINE_WIDTH_LP, "outline_width_lp": OUTLINE_WIDTH_LP,
		"scale_side": SIDE_LEFT, "label_token": "",
	}


# ---------------------------------------------------------------------------
# Скользящее окно (свободная езда)
# ---------------------------------------------------------------------------

## Видимый диапазон времени окна `(t_from, t_to)`: до конца первого окна — (0, окно),
## дальше — последние `window_sec` секунд, «сейчас» у правого края.
func visible_range() -> Vector2:
	var now: int = last_time_sec()
	if now <= window_sec:
		return Vector2(0.0, float(window_sec))
	return Vector2(float(now - window_sec), float(now))


## X момента `t_sec` в окне от левого края поля шириной `width`.
func window_x_of(t_sec: float, width: float) -> float:
	var r: Vector2 = visible_range()
	return clampf((t_sec - r.x) / (r.y - r.x), 0.0, 1.0) * width


## Подписи шкалы времени окна, см. `TimeAxis.window_labels`.
func window_time_labels() -> Array[Dictionary]:
	return TimeAxis.window_labels(last_time_sec(), window_sec)


## Потолок шкалы мощности окна, Вт (с гистерезисом на уменьшение). В режиме плана не
## обновляется — там потолок задаёт `PlanChartModel.y_max()`.
func power_y_max() -> float:
	return _y_max


## Потолок без гистерезиса: max(ftp_factor × FTP, ⌈максимум в окне / 50⌉ × 50), не меньше 50.
func target_power_y_max() -> float:
	var r: Vector2 = visible_range()
	var peak: int = 0
	for i in range(_first_index_at_or_after(r.x), _t.size()):
		peak = maxi(peak, _power[i])
	var rounded: int = ceili(float(peak) / float(Y_MAX_ROUND_W)) * Y_MAX_ROUND_W
	return maxf(maxf(ftp_factor * float(_ftp_w), float(rounded)), float(Y_MAX_ROUND_W))


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _values(series: String) -> PackedInt32Array:
	return _hr if series == SERIES_HR else _power


## Растёт сразу; уменьшается не чаще раза в `Y_MAX_SHRINK_INTERVAL_SEC` активного времени.
func _update_y_max(force: bool) -> void:
	var target: float = target_power_y_max()
	if force or target > _y_max:
		_y_max = target
		return
	if target < _y_max:
		var now: int = last_time_sec()
		if _last_shrink_t < 0 or now - _last_shrink_t >= Y_MAX_SHRINK_INTERVAL_SEC:
			_y_max = target
			_last_shrink_t = now


## Индексы точек с данными для отрисовки: все, если их ≤ 2 × ширины, иначе min/max по корзинам.
func _pick(values: PackedInt32Array, first: int, last: int, t_from: float, t_to: float, width_px: int) -> PackedInt32Array:
	var all := PackedInt32Array()
	for i in range(first, last + 1):
		if values[i] != NO_VALUE:
			all.append(i)
	if all.size() <= 2 * width_px:
		return all
	var out := PackedInt32Array()
	var span: float = maxf(t_to - t_from, 1.0)
	var bucket: int = -1
	var lo: int = -1
	var hi: int = -1
	for i in all:
		var b: int = clampi(floori((float(_t[i]) - t_from) / span * float(width_px)), 0, width_px - 1)
		if b != bucket:
			_emit_bucket(out, lo, hi)
			bucket = b
			lo = i
			hi = i
			continue
		if values[i] < values[lo]:
			lo = i
		if values[i] > values[hi]:
			hi = i
	_emit_bucket(out, lo, hi)
	return out


static func _emit_bucket(out: PackedInt32Array, lo: int, hi: int) -> void:
	if lo < 0:
		return
	if lo == hi:
		out.append(lo)
	else:
		out.append(mini(lo, hi))
		out.append(maxi(lo, hi))


func _first_index_at_or_after(t: float) -> int:
	return _t.bsearch(ceili(t), true)


func _last_index_at_or_before(t: float) -> int:
	return _t.bsearch(floori(t), false) - 1
