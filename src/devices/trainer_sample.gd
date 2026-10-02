class_name TrainerSample
extends RefCounted
## Один сэмпл телеметрии станка (мощность, каденс, скорость) на момент времени.
##
## Отсутствие данных не равно нулю (REQ-DEV-08 крит. 2, REQ-WRK-08 крит. 2):
## если источник не прислал значение, соответствующий флаг `has_*` равен false,
## а числовое поле не имеет смысла (по умолчанию 0). Потребитель обязан
## проверять флаги, а не сравнивать значение с 0.

## Время сэмпла в секундах по часам устройства (монотонно, шаг 1 с для потока 1 Гц).
var timestamp_sec: float = 0.0

## Мгновенная мощность, Вт (целые). Диапазон FTMS: sint16, на практике 0..2000.
var power_w: int = 0
## Каденс, об/мин (целые). FTMS передаёт в 0.5 rpm — округляется до целого.
var cadence_rpm: int = 0
## Скорость, км/ч. FTMS передаёт в 0.01 км/ч.
var speed_kmh: float = 0.0

## Флаги наличия данных в этом сэмпле.
var has_power: bool = false
var has_cadence: bool = false
var has_speed: bool = false


## Удобный конструктор полного сэмпла (все три потока присутствуют).
static func full(ts_sec: float, power: int, cadence: int, speed: float) -> TrainerSample:
	var s := TrainerSample.new()
	s.timestamp_sec = ts_sec
	s.power_w = power
	s.has_power = true
	s.cadence_rpm = cadence
	s.has_cadence = true
	s.speed_kmh = speed
	s.has_speed = true
	return s


## Сэмпл «нет данных» с меткой времени — для записи в поток при обрыве связи.
static func empty(ts_sec: float) -> TrainerSample:
	var s := TrainerSample.new()
	s.timestamp_sec = ts_sec
	return s


func _to_string() -> String:
	return "TrainerSample(t=%.1f, P=%s, C=%s, V=%s)" % [
		timestamp_sec,
		str(power_w) if has_power else "-",
		str(cadence_rpm) if has_cadence else "-",
		("%.1f" % speed_kmh) if has_speed else "-",
	]
