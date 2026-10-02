class_name HrZones
extends RefCounted
## Зоны пульса от максимального пульса с настраиваемыми границами (REQ-PRF-02, REQ-HUD-04).
##
## `boundaries_pct` — нижние границы зон 2..N в % от max HR по возрастанию.
## Правило границы: пульс, равный границе, относится к ВЕРХНЕЙ зоне
## (Z1 < 60 %, Z2 — от 60 % включительно до 70 % исключительно и т.д.).
## При max HR 180: 107 → Z1, 108 → Z2, 126 → Z3, 144 → Z4, 162 → Z5 (REQ-HUD-04 крит. 1).
## Обратите внимание: правило противоположно зонам мощности (`PowerZones`),
## это следует из чисел в требованиях.

## Границы по умолчанию: 5 зон.
const DEFAULT_BOUNDARIES_PCT: Array[float] = [60.0, 70.0, 80.0, 90.0]

var max_hr: int = 0
var boundaries_pct: Array[float] = DEFAULT_BOUNDARIES_PCT.duplicate()
## Абсолютные границы, уд/мин (REQ-INT-06 крит. 3: зоны Intervals.icu приходят
## в уд/мин). Если массив не пуст, `zone_of` использует их и не смотрит на
## `max_hr`/`boundaries_pct`. Правило границы то же: значение, равное границе,
## относится к верхней зоне.
var boundaries_bpm: Array[int] = []


static func five_zone(max_bpm: int) -> HrZones:
	var z := HrZones.new()
	z.max_hr = max_bpm
	return z


static func custom(max_bpm: int, boundaries: Array[float]) -> HrZones:
	var z := HrZones.new()
	z.max_hr = max_bpm
	z.boundaries_pct = boundaries.duplicate()
	return z


## Зоны с абсолютными границами в уд/мин; `max_hr` не требуется.
## Пример: [108, 126, 144, 162] эквивалентно `five_zone(180)`.
static func custom_bpm(boundaries: Array[int]) -> HrZones:
	var z := HrZones.new()
	z.boundaries_bpm = boundaries.duplicate()
	return z


func is_absolute() -> bool:
	return not boundaries_bpm.is_empty()


func zone_count() -> int:
	return (boundaries_bpm.size() if is_absolute() else boundaries_pct.size()) + 1


## Номер зоны 1..zone_count() для пульса `bpm`. При `bpm <= 0` → 0 («нет данных»,
## REQ-HUD-04 крит. 2); для относительных границ также при `max_hr <= 0` → 0.
func zone_of(bpm: int) -> int:
	if bpm <= 0:
		return 0
	if is_absolute():
		var z: int = 1
		for b in boundaries_bpm:
			if bpm >= b:
				z += 1
			else:
				break
		return z
	if max_hr <= 0:
		return 0
	var zone: int = 1
	for b in boundaries_pct:
		if float(bpm) * 100.0 >= b * float(max_hr):
			zone += 1
		else:
			break
	return zone


func validate() -> Array[String]:
	var errors: Array[String] = []
	if is_absolute():
		for i in boundaries_bpm.size():
			if boundaries_bpm[i] <= 0:
				errors.append("граница %d не положительна: %d" % [i + 1, boundaries_bpm[i]])
			if i > 0 and boundaries_bpm[i] <= boundaries_bpm[i - 1]:
				errors.append("границы не возрастают: %d после %d" % [boundaries_bpm[i], boundaries_bpm[i - 1]])
		return errors
	if max_hr <= 0:
		errors.append("максимальный пульс должен быть > 0 (сейчас %d)" % max_hr)
	if boundaries_pct.is_empty():
		errors.append("нет границ зон")
	for i in boundaries_pct.size():
		if boundaries_pct[i] <= 0.0:
			errors.append("граница %d не положительна: %s" % [i + 1, str(boundaries_pct[i])])
		if i > 0 and boundaries_pct[i] <= boundaries_pct[i - 1]:
			errors.append("границы не возрастают: %s после %s" % [str(boundaries_pct[i]), str(boundaries_pct[i - 1])])
	return errors
