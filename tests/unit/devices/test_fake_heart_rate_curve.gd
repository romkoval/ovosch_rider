extends GutTest
## Синтетический пульс эмулятора `FakeHeartRateCurve` и его подключение фабрикой
## `TrainerFactory.create("fake")` (T-059, REQ-DEV-09 п.5 — расширение).

const RISE_SEC: int = FakeHeartRateCurve.RISE_SEC

var _hr: Array[int] = []


func before_each() -> void:
	_hr = []


func _on_heart_rate(bpm: int) -> void:
	_hr.append(bpm)


func test_trend_is_monotone_on_rise_and_flat_after() -> void:
	var prev: float = FakeHeartRateCurve.trend_bpm(0.0)
	for t in range(1, RISE_SEC + 1):
		var v: float = FakeHeartRateCurve.trend_bpm(float(t))
		assert_true(v >= prev, "тренд не убывает на 0–20 мин (t=%d: %.2f < %.2f)" % [t, v, prev])
		if v < prev:
			return
		prev = v
	assert_eq(FakeHeartRateCurve.trend_bpm(0.0), 95.0)
	assert_eq(FakeHeartRateCurve.trend_bpm(float(RISE_SEC)), 165.0)
	assert_eq(FakeHeartRateCurve.trend_bpm(float(RISE_SEC) * 2.0), 165.0, "после 20 мин — плато")


func test_ends_of_rise_are_95_and_165_within_2() -> void:
	var curve := FakeHeartRateCurve.new()
	assert_almost_eq(curve.bpm_at(0.0), 95, 2)
	assert_almost_eq(curve.bpm_at(1.0), 95, 2)
	assert_almost_eq(curve.bpm_at(float(RISE_SEC)), 165, 2)
	for t in [RISE_SEC + 1, RISE_SEC + 600, 3 * 3600]:
		assert_almost_eq(curve.bpm_at(float(t)), 165, 2, "плато при t=%d" % t)


func test_noise_is_bounded_by_2_bpm() -> void:
	var curve := FakeHeartRateCurve.new()
	var max_dev: float = 0.0
	var distinct := {}
	for t in range(0, 2 * RISE_SEC):
		var dev: float = absf(float(curve.bpm_at(float(t))) - FakeHeartRateCurve.trend_bpm(float(t)))
		max_dev = maxf(max_dev, dev)
		distinct[curve.bpm_at(float(t)) - roundi(FakeHeartRateCurve.trend_bpm(float(t)))] = true
	assert_lte(max_dev, 2.5, "|пульс − тренд| ≤ 2 (+0.5 на округление)")
	assert_gt(distinct.size(), 2, "шум есть: на плато встречается больше двух отклонений")


func test_sequence_is_monotone_on_minute_averages_over_rise() -> void:
	# Шум ±2 делает посекундный ряд немонотонным; монотонность проверяется по средним за минуту.
	for seed in [FakeHeartRateCurve.DEFAULT_SEED, 1, 12345]:
		var seq: Array[int] = FakeHeartRateCurve.new(seed).sequence(RISE_SEC)
		assert_eq(seq.size(), RISE_SEC)
		var prev: float = -1.0
		for minute in RISE_SEC / 60:
			var sum: int = 0
			for i in 60:
				sum += seq[minute * 60 + i]
			var avg: float = float(sum) / 60.0
			assert_true(avg > prev, "seed %d: средний пульс минуты %d растёт (%.2f ≤ %.2f)" % [seed, minute, avg, prev])
			if avg <= prev:
				return
			prev = avg


func test_same_seed_gives_same_sequence_and_other_seed_differs() -> void:
	var a: Array[int] = FakeHeartRateCurve.new(5).sequence(600)
	var b: Array[int] = FakeHeartRateCurve.new(5).sequence(600)
	var c: Array[int] = FakeHeartRateCurve.new(6).sequence(600)
	assert_eq(a, b, "детерминированно при одинаковом seed")
	assert_ne(a, c, "другой seed — другой шум")


func test_sequence_element_i_is_value_at_second_i_plus_1() -> void:
	var curve := FakeHeartRateCurve.new()
	var seq: Array[int] = curve.sequence(10)
	for i in 10:
		assert_eq(seq[i], curve.bpm_at(float(i + 1)))
	assert_eq(curve.sequence(0), [] as Array[int])
	assert_eq(curve.sequence(-5), [] as Array[int])


func test_factory_fake_emits_heart_rate_within_first_2_seconds() -> void:
	var dev: TrainerDevice = TrainerFactory.create(TrainerFactory.KIND_FAKE)
	dev.heart_rate.connect(_on_heart_rate)
	dev.connect_device("emulator")
	dev.tick(2.0) # подключение 0.5 с по умолчанию, затем сэмплы на 1-й и 2-й секунде
	assert_gt(_hr.size(), 0, "пульс в первые 2 с")
	for bpm in _hr:
		assert_almost_eq(bpm, 95, 2, "начало кривой ~95 уд/мин")


func test_factory_fake_follows_curve_to_plateau() -> void:
	var dev: TrainerDevice = TrainerFactory.create(TrainerFactory.KIND_FAKE)
	dev.set("connect_delay_sec", 0.0)
	dev.heart_rate.connect(_on_heart_rate)
	dev.connect_device("emulator")
	dev.tick(float(RISE_SEC + 300))
	assert_eq(_hr.size(), RISE_SEC + 300, "одно значение пульса в секунду")
	assert_almost_eq(_hr[0], 95, 2)
	assert_almost_eq(_hr[RISE_SEC - 1], 165, 2, "к 20 мин — 165")
	assert_almost_eq(_hr[_hr.size() - 1], 165, 2, "плато")


func test_factory_fakes_are_independent() -> void:
	var a: TrainerDevice = TrainerFactory.create(TrainerFactory.KIND_FAKE)
	var b: TrainerDevice = TrainerFactory.create(TrainerFactory.KIND_FAKE)
	(a as Object).call("set_heart_rate", 0)
	b.heart_rate.connect(_on_heart_rate)
	b.set("connect_delay_sec", 0.0)
	b.connect_device("emulator")
	b.tick(3.0)
	assert_eq(_hr.size(), 3, "выключение пульса одного эмулятора не трогает другой")
