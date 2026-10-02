class_name BlePowerMeter
extends BleSensorBase
## Измеритель мощности по CPS 1818 / 2A63 (REQ-DEV-05 крит. 1, 3).
## `power(watts)` на каждое измерение; при наличии crank data — `cadence(rpm)`
## через `CscCadenceCalculator` (как у CSC) на каждое измерение с валидным
## значением (и неизменным тоже — признак живого источника); пакеты без новых
## оборотов ≥ 3 с → `cadence(0)`; при тишине ничего не испускается (решение Н-4).

signal power(watts: int)
signal cadence(rpm: int)

var calculator := CscCadenceCalculator.new()
var last_power_w: int = -1
var last_rpm: int = -1


func kind() -> String:
	return KIND_POWER


func _service_uuid() -> String:
	return BleUuids.CPS_SERVICE


func _measurement_uuid() -> String:
	return BleUuids.CYCLING_POWER_MEASUREMENT


func _on_measurement(bytes: PackedByteArray) -> void:
	var m := CpsCodec.decode_cycling_power_measurement(bytes)
	if not m["ok"]:
		return
	last_power_w = m["power_w"]
	power.emit(last_power_w)
	if m["has_crank"]:
		var rpm: int = calculator.push(m, _time_sec)
		if rpm >= 0:
			last_rpm = rpm
			cadence.emit(rpm)


## Текущий каденс с учётом молчания: -1 — нет данных.
func current_cadence(now_sec: float) -> int:
	return calculator.value(now_sec)
