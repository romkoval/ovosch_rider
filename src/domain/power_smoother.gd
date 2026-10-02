class_name PowerSmoother
extends RefCounted
## Скользящее среднее мощности за N секунд по сэмплам 1 Гц (REQ-HUD-09).
##
## Окно — последние `window_size` слотов времени (по умолчанию 3). Каждый
## вызов `push`/`push_missing` занимает один слот. Пропуски данных
## (`TrainerSample.has_power == false`) подаются через `push_missing()`:
## они занимают слот в окне (время идёт), но исключаются из среднего.
## Если во всех слотах окна пропуски — значения нет (`has_value()` false,
## `value()` и `push_missing()` возвращают `NO_VALUE`).
##
## Пример: 100, 200, 300 → 200; затем 300 → 267 (среднее 266.67, округление).
## Пока сэмплов меньше N — среднее доступных: 100 → 100; 100, 200 → 150.
## Сглаживание — только для HUD; в поток заезда и FIT пишется сырая мощность.

## Признак отсутствия значения.
const NO_VALUE: int = -1

var window_size: int = 3
## Слоты окна: мощность в Вт или NO_VALUE для пропуска. Старые — в начале.
var _slots: Array[int] = []


func _init(size: int = 3) -> void:
	window_size = maxi(size, 1)


## Добавляет сэмпл мощности и возвращает сглаженное значение (целые Вт).
func push(power_w: int) -> int:
	_append(power_w)
	return value()


## Добавляет слот «нет данных» и возвращает сглаженное значение по оставшимся
## сэмплам окна либо NO_VALUE, если их нет.
func push_missing() -> int:
	_append(NO_VALUE)
	return value()


## Текущее сглаженное значение или NO_VALUE.
func value() -> int:
	var sum: int = 0
	var n: int = 0
	for p in _slots:
		if p != NO_VALUE:
			sum += p
			n += 1
	if n == 0:
		return NO_VALUE
	return roundi(float(sum) / float(n))


func has_value() -> bool:
	return value() != NO_VALUE


## Сколько слотов окна занято (включая пропуски).
func sample_count() -> int:
	return _slots.size()


func reset() -> void:
	_slots.clear()


func _append(p: int) -> void:
	_slots.append(p)
	while _slots.size() > window_size:
		_slots.pop_front()
