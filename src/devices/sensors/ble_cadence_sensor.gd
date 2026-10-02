class_name BleCadenceSensor
extends BleSensorBase
## Датчик каденса по CSC 1816 / 2A5B (REQ-DEV-04 крит. 1–3).
## Каденс считает `CscCadenceCalculator` по двум измерениям. `cadence` испускается
## на каждое измерение с валидным значением — даже если оно не изменилось
## (потребителю важно, что датчик жив: `SensorHub` считает источник свежим по
## последнему событию). Пакеты идут, а обороты стоят ≥ 3 с → `cadence(0)` с каждым
## пакетом (REQ-DEV-04 крит. 3). При тишине (пакетов нет) ничего не испускается —
## свежесть источника отмеряет `SensorHub` (решение Н-4).

signal cadence(rpm: int)

var calculator := CscCadenceCalculator.new()
var last_rpm: int = -1


func kind() -> String:
	return KIND_CADENCE


func _service_uuid() -> String:
	return BleUuids.CSC_SERVICE


func _measurement_uuid() -> String:
	return BleUuids.CSC_MEASUREMENT


func _on_measurement(bytes: PackedByteArray) -> void:
	var m := CscCodec.decode_csc_measurement(bytes)
	if not m["ok"] or not m["has_crank"]:
		return
	var rpm: int = calculator.push(m, _time_sec)
	if rpm >= 0:
		last_rpm = rpm
		cadence.emit(rpm)


## Текущее значение с учётом молчания датчика: -1 — нет данных.
func current_cadence(now_sec: float) -> int:
	return calculator.value(now_sec)
