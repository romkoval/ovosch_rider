class_name FrameStats
extends RefCounted
## Статистика кадров за заезд или замер (T-116a; инструмент для REQ-D3D-05 п.1, методика —
## `docs/perf_budget.md`, «Ручной замер»): по длительностям кадров считает средний FPS,
## «1 % low», перцентили времени кадра и долю долгих кадров.
##
## Определения (все времена — мс):
## - `avg_fps` = кадров / суммарное время кадров (а не среднее мгновенных FPS);
## - `low_1pct_fps` = 1000 / среднее время 1 % самых долгих кадров (не меньше одного кадра) —
##   «1 % low» в принятом у игровых замеров смысле;
## - `p50_ms`, `p95_ms`, `p99_ms` — перцентили времени кадра по ближайшему рангу;
## - `share_over_16_7_ms`, `share_over_33_ms` — доля кадров длиннее 16.7 и 33 мс (0..1);
##   критерий D3D-05 п.1 — доля > 33 мс не больше 1 %.
## Сводка — `summary()`, словарь для журнала (`DiagLog`) и экрана замера.
##
## Длительности хранятся точно (`PackedFloat32Array` с удвоением ёмкости — без выделения
## памяти в каждом кадре), предел — `MAX_FRAMES` (больше суток при 60 FPS не нужно); кадры
## сверх предела учитываются в сумме и счётчиках, но не в перцентилях.

const SLOW_FRAME_MS: float = 16.7
const VERY_SLOW_FRAME_MS: float = 33.0
## 4 часа при 120 Гц.
const MAX_FRAMES: int = 4 * 3600 * 120
const INITIAL_CAPACITY: int = 4096

var _frames: PackedFloat32Array = PackedFloat32Array()
var _stored: int = 0
var _count: int = 0
var _total_ms: float = 0.0
var _max_ms: float = 0.0
var _over_slow: int = 0
var _over_very_slow: int = 0


func _init() -> void:
	_frames.resize(INITIAL_CAPACITY)


## Статистика по готовой серии длительностей кадров, мс (для тестов и разбора журналов).
static func from_frame_times_ms(times_ms: PackedFloat32Array) -> FrameStats:
	var stats := FrameStats.new()
	for ms in times_ms:
		stats.add_frame_ms(ms)
	return stats


func reset() -> void:
	_stored = 0
	_count = 0
	_total_ms = 0.0
	_max_ms = 0.0
	_over_slow = 0
	_over_very_slow = 0


## Учесть кадр длительностью `ms` (неположительные — пропускаются).
func add_frame_ms(ms: float) -> void:
	if ms <= 0.0:
		return
	_count += 1
	_total_ms += ms
	if ms > _max_ms:
		_max_ms = ms
	if ms > SLOW_FRAME_MS:
		_over_slow += 1
	if ms > VERY_SLOW_FRAME_MS:
		_over_very_slow += 1
	if _stored >= MAX_FRAMES:
		return
	if _stored >= _frames.size():
		_frames.resize(mini(_frames.size() * 2, MAX_FRAMES))
	_frames[_stored] = ms
	_stored += 1


func add_frame_usec(usec: int) -> void:
	add_frame_ms(float(usec) / 1000.0)


func frame_count() -> int:
	return _count


func total_ms() -> float:
	return _total_ms


## Сводка: `frames`, `duration_s`, `avg_fps`, `avg_frame_ms`, `low_1pct_fps`, `p50_ms`,
## `p95_ms`, `p99_ms`, `max_ms`, `frames_over_16_7_ms`, `frames_over_33_ms`,
## `share_over_16_7_ms`, `share_over_33_ms`. Без кадров — нули.
func summary() -> Dictionary:
	var out := {
		"frames": _count,
		"duration_s": _round(_total_ms / 1000.0, 2),
		"avg_fps": 0.0,
		"avg_frame_ms": 0.0,
		"low_1pct_fps": 0.0,
		"p50_ms": 0.0,
		"p95_ms": 0.0,
		"p99_ms": 0.0,
		"max_ms": _round(_max_ms, 2),
		"frames_over_16_7_ms": _over_slow,
		"frames_over_33_ms": _over_very_slow,
		"share_over_16_7_ms": 0.0,
		"share_over_33_ms": 0.0,
	}
	if _count == 0 or _total_ms <= 0.0:
		return out
	var sorted := _frames.slice(0, _stored)
	sorted.sort()
	out["avg_fps"] = _round(float(_count) * 1000.0 / _total_ms, 2)
	out["avg_frame_ms"] = _round(_total_ms / float(_count), 3)
	out["p50_ms"] = _round(_percentile(sorted, 50.0), 3)
	out["p95_ms"] = _round(_percentile(sorted, 95.0), 3)
	out["p99_ms"] = _round(_percentile(sorted, 99.0), 3)
	var worst := maxi(ceili(float(sorted.size()) * 0.01), 1)
	var worst_sum := 0.0
	for i in range(sorted.size() - worst, sorted.size()):
		worst_sum += sorted[i]
	out["low_1pct_fps"] = _round(1000.0 * float(worst) / worst_sum, 2) if worst_sum > 0.0 else 0.0
	out["share_over_16_7_ms"] = _round(float(_over_slow) / float(_count), 4)
	out["share_over_33_ms"] = _round(float(_over_very_slow) / float(_count), 4)
	return out


## Перцентиль по ближайшему рангу в отсортированной серии.
static func _percentile(sorted: PackedFloat32Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	var rank := clampi(ceili(p / 100.0 * float(sorted.size())), 1, sorted.size())
	return sorted[rank - 1]


static func _round(value: float, digits: int) -> float:
	var k := pow(10.0, digits)
	return roundf(value * k) / k
