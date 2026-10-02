class_name SampleStream
extends RefCounted
## Поток сэмплов 1 Гц сессии (REQ-WRK-08, REQ-DEV-08 крит. 2).
##
## Колонки одинаковой длины; строка i — секунда `time_sec[i]` активного
## времени (с от старта, монотонно, шаг 1). Ровно один слот на секунду:
## если за секунду телеметрия не пришла, слот всё равно добавляется с
## `has_* == false` («нет данных», а не 0). Если пришло несколько сэмплов —
## записывается последний (REQ-WRK-08 крит. 3; выбор делает `WorkoutSession`).

var time_sec := PackedInt32Array()
var power_w := PackedInt32Array()
var has_power: Array[bool] = []
var cadence_rpm := PackedInt32Array()
var has_cadence: Array[bool] = []
var speed_kmh := PackedFloat32Array()
var has_speed: Array[bool] = []
var heart_rate_bpm := PackedInt32Array()
var has_heart_rate: Array[bool] = []
## Целевая мощность исполнителя в этот момент, Вт (0 — нет цели).
var target_w := PackedInt32Array()
## Номер шага плана (-1 — вне плана).
var step_index := PackedInt32Array()
var erg_enabled: Array[bool] = []


func size() -> int:
	return time_sec.size()


## Добавить слот секунды `t`. `sample` может быть null (нет телеметрии за секунду);
## `hr_bpm < 0` — нет пульса.
func append(t: int, sample: TrainerSample, hr_bpm: int, target: int, step: int, erg: bool) -> void:
	time_sec.append(t)
	var p_ok: bool = sample != null and sample.has_power
	var c_ok: bool = sample != null and sample.has_cadence
	var s_ok: bool = sample != null and sample.has_speed
	power_w.append(sample.power_w if p_ok else 0)
	has_power.append(p_ok)
	cadence_rpm.append(sample.cadence_rpm if c_ok else 0)
	has_cadence.append(c_ok)
	speed_kmh.append(sample.speed_kmh if s_ok else 0.0)
	has_speed.append(s_ok)
	heart_rate_bpm.append(hr_bpm if hr_bpm >= 0 else 0)
	has_heart_rate.append(hr_bpm >= 0)
	target_w.append(target)
	step_index.append(step)
	erg_enabled.append(erg)


## Строка i словарём — для тестов и отладки.
func row(i: int) -> Dictionary:
	return {
		"time_sec": time_sec[i],
		"power_w": power_w[i], "has_power": has_power[i],
		"cadence_rpm": cadence_rpm[i], "has_cadence": has_cadence[i],
		"speed_kmh": speed_kmh[i], "has_speed": has_speed[i],
		"heart_rate_bpm": heart_rate_bpm[i], "has_heart_rate": has_heart_rate[i],
		"target_w": target_w[i], "step_index": step_index[i], "erg_enabled": erg_enabled[i],
	}


## Метки времени идут подряд с шагом 1 с.
func is_monotonic() -> bool:
	for i in range(1, time_sec.size()):
		if time_sec[i] != time_sec[i - 1] + 1:
			return false
	return true


func count_with_power() -> int:
	var n: int = 0
	for ok in has_power:
		if ok:
			n += 1
	return n
