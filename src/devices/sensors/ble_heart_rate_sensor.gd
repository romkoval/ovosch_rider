class_name BleHeartRateSensor
extends BleSensorBase
## Датчик пульса по Heart Rate Service 180D / 2A37 (REQ-DEV-03 крит. 1, 2).
## Измерение с флагом «контакт поддерживается, но не обнаружен» считается
## недостоверным: `heart_rate` не испускается (для потребителя — «нет данных»),
## `contact_ok` становится false.

signal heart_rate(bpm: int)

## Последнее состояние контакта (true, если контакт есть или не поддерживается).
var contact_ok: bool = true
var last_bpm: int = -1


func kind() -> String:
	return KIND_HEART_RATE


func _service_uuid() -> String:
	return BleUuids.HRS_SERVICE


func _measurement_uuid() -> String:
	return BleUuids.HEART_RATE_MEASUREMENT


func _on_measurement(bytes: PackedByteArray) -> void:
	var m := HrsCodec.decode_heart_rate_measurement(bytes)
	if not m["ok"]:
		return
	contact_ok = m["contact_ok"]
	if not contact_ok:
		return
	last_bpm = m["bpm"]
	heart_rate.emit(last_bpm)
