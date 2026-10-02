class_name PowerZones
extends RefCounted
## Зоны мощности относительно FTP с настраиваемыми границами (REQ-PRF-02, REQ-HUD-03).
##
## `boundaries_pct` — верхние границы зон 1..N-1 в % FTP по возрастанию.
## Правило границы: мощность, равная границе, относится к НИЖНЕЙ зоне
## (Z1 ≤ 55 %, Z2 — от 55 % исключительно до 75 % включительно и т.д.).
## При FTP 200: 110 Вт → Z1, 111 → Z2, 150 → Z2, 151 → Z3 (REQ-PRF-02 крит. 5).

## Границы Coggan по умолчанию: 7 зон.
const COGGAN_BOUNDARIES_PCT: Array[float] = [55.0, 75.0, 90.0, 105.0, 120.0, 150.0]

var ftp_w: int = 0
var boundaries_pct: Array[float] = COGGAN_BOUNDARIES_PCT.duplicate()


static func coggan(ftp: int) -> PowerZones:
	var z := PowerZones.new()
	z.ftp_w = ftp
	return z


static func custom(ftp: int, boundaries: Array[float]) -> PowerZones:
	var z := PowerZones.new()
	z.ftp_w = ftp
	z.boundaries_pct = boundaries.duplicate()
	return z


## Число зон (границ + 1).
func zone_count() -> int:
	return boundaries_pct.size() + 1


## Номер зоны 1..zone_count() для мощности `power_w`. При `ftp_w <= 0` → 0.
## Сравнение в целых «процентах × FTP», без накопления ошибки округления.
func zone_of(power_w: int) -> int:
	if ftp_w <= 0:
		return 0
	var zone: int = 1
	for b in boundaries_pct:
		if float(power_w) * 100.0 > b * float(ftp_w):
			zone += 1
		else:
			break
	return zone


## Первый ватт зоны `zone`: наименьшая мощность, строго превышающая границу
## предыдущей зоны. Для Z1 и некорректного номера → 0.
func zone_lower_watts(zone: int) -> int:
	if zone <= 1 or zone > zone_count():
		return 0
	return floori(boundaries_pct[zone - 2] / 100.0 * float(ftp_w)) + 1


## Ошибки конфигурации: границы должны быть положительны и строго возрастать.
func validate() -> Array[String]:
	var errors: Array[String] = []
	if ftp_w <= 0:
		errors.append("FTP должен быть > 0 (сейчас %d)" % ftp_w)
	if boundaries_pct.is_empty():
		errors.append("нет границ зон")
	for i in boundaries_pct.size():
		if boundaries_pct[i] <= 0.0:
			errors.append("граница %d не положительна: %s" % [i + 1, str(boundaries_pct[i])])
		if i > 0 and boundaries_pct[i] <= boundaries_pct[i - 1]:
			errors.append("границы не возрастают: %s после %s" % [str(boundaries_pct[i]), str(boundaries_pct[i - 1])])
	return errors
