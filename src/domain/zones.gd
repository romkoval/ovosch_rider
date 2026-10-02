class_name Zones
extends RefCounted
## Статические помощники для зон по умолчанию (REQ-PRF-02, REQ-HUD-03, REQ-HUD-04).
## Для пользовательских границ используйте `PowerZones` / `HrZones`.
##
## Правила границ (зафиксированы тестами):
## - мощность: значение РОВНО на границе принадлежит нижней зоне
##   (110 Вт при FTP 200 → Z1, 111 → Z2);
## - пульс: значение РОВНО на границе принадлежит верхней зоне
##   (108 уд/мин при max 180 → Z2, 107 → Z1).


## Зона мощности 1..7 (Coggan: 55/75/90/105/120/150 % FTP). При `ftp_w <= 0` → 0.
## Мощность 0 → Z1 (REQ-HUD-03 крит. 3).
static func power_zone(power_w: int, ftp_w: int) -> int:
	return PowerZones.coggan(ftp_w).zone_of(power_w)


## Зона пульса 1..5 (60/70/80/90 % от max HR). При `max_hr <= 0` или `bpm <= 0` → 0.
static func hr_zone(bpm: int, max_hr: int) -> int:
	return HrZones.five_zone(max_hr).zone_of(bpm)
