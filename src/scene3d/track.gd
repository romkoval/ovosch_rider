class_name Track
extends RefCounted
## Интерфейс трассы (REQ-D3D-06 крит. 1, 2; REQ-D3D-03): «дай точку на дистанции s».
## Игровой цикл (`RideScene`) и привязка к телеметрии знают только этот интерфейс;
## конкретная трасса (`LoopTrack`, в будущем маршрут GPX) подменяется без правки цикла.
##
## Контракт: `length_m() > 0`; для зацикленной трассы `sample(0) == sample(length_m())`;
## `forward` и `up` — единичные; при шаге по дистанции Δs смещение позиции ≤ Δs (с допуском).
## `sample_into` не аллоцирует — заполняет переданный `TrackSample`.


## Длина трассы, м.
func length_m() -> float:
	push_error("Track.length_m: not implemented")
	return 0.0


## Замкнута ли трасса (дистанция оборачивается по модулю длины).
func is_loop() -> bool:
	return true


## Дистанция, приведённая к [0; length) (имя не `wrap`: так зовётся встроенная функция GDScript): для петли — по модулю, иначе — кламп.
func wrap_distance(distance_m: float) -> float:
	var length := length_m()
	if length <= 0.0:
		return 0.0
	if is_loop():
		return fposmod(distance_m, length)
	return clampf(distance_m, 0.0, length)


## Заполнить `out` точкой трассы на дистанции `distance_m` (без аллокаций).
func sample_into(_distance_m: float, _out: TrackSample) -> void:
	push_error("Track.sample_into: not implemented")


## Удобная форма с аллокацией — для тестов и инициализации.
func sample(distance_m: float) -> TrackSample:
	var out := TrackSample.new()
	sample_into(distance_m, out)
	return out
