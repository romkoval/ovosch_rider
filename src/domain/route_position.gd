class_name RoutePosition
extends RefCounted
## Позиция гонщика на замкнутой трассе (REQ-FRD-04 крит. 2 — s как интеграл скорости
## по модулю L; REQ-FRD-07 крит. 1 — оборачивание s и монотонная дистанция,
## крит. 4 — набор высоты по сэмплам).
##
## `advance(speed_kmh, dt_sec)` продвигает накопленную дистанцию на v · dt; позиция
## на круге s = (s₀ + дистанция) mod L, где s₀ — точка старта. Высота h(s) и уклон
## g(s) берутся из `RouteProfile` (уклон — полный, без крутизны SIM: FRD-04 крит. 8).
## Круги считаются по дистанции: полный круг — каждые L метров от старта (так же
## режет круги FIT, FRD-07 крит. 5).
##
## Набор высоты — сумма положительных приращений h между соседними вызовами
## `advance` (в сессии — один вызов на сэмпл 1 Гц, FRD-07 крит. 4). Вызов с нулевым
## продвижением набор не меняет.
##
## Время извне: объект не знает о часах и сцене; пауза — просто не вызывать `advance`.

var _profile: RouteProfile = null
var _length: float = 0.0
var _start_s: float = 0.0
var _distance: float = 0.0
var _s: float = 0.0
var _height: float = 0.0
var _ascent: float = 0.0


## `profile` — профиль трассы (`RouteCatalog.get_route(id).profile`); `start_s_m` — точка
## старта на круге, м. Без валидного профиля позиция стоит в 0, высота и уклон 0,
## дистанция всё равно накапливается.
func _init(profile: RouteProfile = null, start_s_m: float = 0.0) -> void:
	_profile = profile
	_length = profile.length_m() if profile != null and profile.is_valid() else 0.0
	reset(start_s_m)


## Вернуться на старт: дистанция и набор — 0, s = `start_s_m` по модулю L.
func reset(start_s_m: float = 0.0) -> void:
	_start_s = fposmod(start_s_m, _length) if _length > 0.0 else 0.0
	_distance = 0.0
	_ascent = 0.0
	_update_s()
	_height = _height_at(_s)


## Продвинуться со скоростью `speed_kmh` за `dt_sec` секунд. Отрицательные скорость
## и время не двигают назад (дистанция монотонна). Возвращает пройденные метры.
func advance(speed_kmh: float, dt_sec: float) -> float:
	if dt_sec <= 0.0 or speed_kmh <= 0.0 or not is_finite(speed_kmh) or not is_finite(dt_sec):
		return 0.0
	var delta_m: float = speed_kmh / 3.6 * dt_sec
	_distance += delta_m
	_update_s()
	var h: float = _height_at(_s)
	if h > _height:
		_ascent += h - _height
	_height = h
	return delta_m


## Длина круга L, м (0 без валидного профиля).
func length_m() -> float:
	return _length


## Точка старта на круге, м.
func start_s_m() -> float:
	return _start_s


## Позиция на круге s ∈ [0; L), м.
func s_m() -> float:
	return _s


## Накопленная дистанция от старта, м (монотонно не убывает).
func distance_m() -> float:
	return _distance


## Число полностью пройденных кругов: floor(дистанция / L); 0 без профиля.
func laps_completed() -> int:
	if _length <= 0.0:
		return 0
	return floori(_distance / _length)


## Номер текущего круга с 1 (для показа): `laps_completed() + 1`.
func lap_number() -> int:
	return laps_completed() + 1


## Пройдено на текущем круге, м: дистанция − L · `laps_completed()`.
func lap_distance_m() -> float:
	return _distance - _length * float(laps_completed())


## Высота h(s) в текущей позиции, м.
func height_m() -> float:
	return _height


## Полный уклон трассы g(s) в текущей позиции, % (крутизна SIM не применяется).
func grade_pct() -> float:
	if _length <= 0.0:
		return 0.0
	return _profile.grade_at(_s)


## Набор высоты с начала (с последнего `reset`), м.
func ascent_m() -> float:
	return _ascent


func _update_s() -> void:
	_s = fposmod(_start_s + _distance, _length) if _length > 0.0 else 0.0


func _height_at(s: float) -> float:
	if _length <= 0.0:
		return 0.0
	return _profile.height_at(s)
