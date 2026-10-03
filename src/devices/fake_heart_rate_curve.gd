class_name FakeHeartRateCurve
extends RefCounted
## Синтетический пульс эмулятора (REQ-DEV-09 п.5, расширение для dev-режима и снимков HUD).
##
## Тренд: линейный рост от `START_BPM` (95) до `PEAK_BPM` (165) за `RISE_SEC` (20 мин),
## дальше — плато. Поверх тренда — детерминированный «шум» в пределах ±`NOISE_BPM` (2):
## значения в узлах через `NOISE_KNOT_SEC` берутся из целочисленного хеша (номер узла, seed)
## и линейно интерполируются между узлами, поэтому линия на графике плавная, а не «пила».
## Одинаковый seed — одинаковая последовательность на любой машине (без RandomNumberGenerator
## и без `hash()` движка).
##
## `FakeTrainer` получает кривую через `set_heart_rate_sequence(sequence(...))`, это делает
## `TrainerFactory.create("fake")`. Тесты, которым пульс не нужен, создают `FakeTrainer.new()`.

## Пульс в начале, уд/мин.
const START_BPM: int = 95
## Пульс в конце подъёма и на плато, уд/мин.
const PEAK_BPM: int = 165
## Длительность подъёма, с (20 мин).
const RISE_SEC: int = 1200
## Амплитуда шума, уд/мин (±).
const NOISE_BPM: int = 2
## Шаг узлов шума, с.
const NOISE_KNOT_SEC: int = 8
## Длина последовательности по умолчанию, с (3 ч; дальше `FakeTrainer` держит последнее значение).
const DEFAULT_DURATION_SEC: int = 3 * 3600
## Seed по умолчанию.
const DEFAULT_SEED: int = 7

const _MASK_32: int = 0xFFFFFFFF

var _seed: int = DEFAULT_SEED


func _init(seed: int = DEFAULT_SEED) -> void:
	_seed = seed


## Тренд без шума, уд/мин: монотонно не убывает, 95 при t ≤ 0, 165 при t ≥ 20 мин.
static func trend_bpm(t_sec: float) -> float:
	var x: float = clampf(t_sec / float(RISE_SEC), 0.0, 1.0)
	return lerpf(float(START_BPM), float(PEAK_BPM), x)


## Шум в момент `t_sec`, уд/мин, в пределах [−NOISE_BPM; NOISE_BPM].
func noise_bpm(t_sec: float) -> float:
	var t: float = maxf(t_sec, 0.0)
	var knot: int = int(floor(t / float(NOISE_KNOT_SEC)))
	var frac: float = (t - float(knot * NOISE_KNOT_SEC)) / float(NOISE_KNOT_SEC)
	return lerpf(_knot_noise(knot), _knot_noise(knot + 1), frac)


## Пульс в момент `t_sec`, уд/мин (тренд + шум, округление до целого).
func bpm_at(t_sec: float) -> int:
	return int(round(trend_bpm(t_sec) + noise_bpm(t_sec)))


## Последовательность по одному значению на секунду: элемент `i` — пульс на `i + 1`-й секунде
## (первый сэмпл `FakeTrainer` приходит через 1 с после подключения).
func sequence(duration_sec: int = DEFAULT_DURATION_SEC) -> Array[int]:
	var out: Array[int] = []
	var n: int = maxi(duration_sec, 0)
	out.resize(n)
	for i in n:
		out[i] = bpm_at(float(i + 1))
	return out


## Значение шума в узле: целочисленный хеш (номер узла, seed) → [−NOISE_BPM; NOISE_BPM].
func _knot_noise(knot: int) -> float:
	# Множители < 2^31 и операнды < 2^32: произведение помещается в int64 без переполнения.
	var h: int = ((knot & _MASK_32) * 0x2545F491 + (_seed & 0xFFFF) * 0x5BD1E995) & _MASK_32
	h ^= h >> 16
	h = (h * 0x7FEB352D) & _MASK_32
	h ^= h >> 15
	h = (h * 0x46CA68B5) & _MASK_32
	h ^= h >> 16
	var unit: float = float(h) / float(_MASK_32)
	return lerpf(-float(NOISE_BPM), float(NOISE_BPM), unit)
