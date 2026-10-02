extends GutTest
## Тесты кодека CSC и калькулятора каденса (REQ-DEV-04 крит. 1–3).
## Векторы собраны по раскладке CSC v1.0 §3.1 / GSS §CSC Measurement.


func _hex(s: String) -> PackedByteArray:
	return BleBytes.from_hex(s)


func test_decode_crank_data() -> void:
	# flags 0x02: crank; revs 0x000A = 10; time 0x0400 = 1024.
	var r := CscCodec.decode_csc_measurement(_hex("02 0A 00 00 04"))
	assert_true(r["ok"])
	assert_true(r["has_crank"])
	assert_false(r["has_wheel"])
	assert_eq(r["crank_revolutions"], 10)
	assert_eq(r["crank_event_time"], 1024)


func test_decode_wheel_and_crank_data() -> void:
	# flags 0x03: wheel (uint32 0x000003E8 = 1000, time 0x0800) + crank (10, 1024).
	var r := CscCodec.decode_csc_measurement(_hex("03 E8 03 00 00 00 08 0A 00 00 04"))
	assert_true(r["ok"])
	assert_true(r["has_wheel"])
	assert_eq(r["wheel_revolutions"], 1000)
	assert_eq(r["wheel_event_time"], 2048)
	assert_eq(r["crank_revolutions"], 10)


func test_decode_truncated_not_ok() -> void:
	assert_false(CscCodec.decode_csc_measurement(_hex("02 0A 00 00"))["ok"])
	assert_false(CscCodec.decode_csc_measurement(_hex("01 E8 03 00 00"))["ok"])
	assert_false(CscCodec.decode_csc_measurement(PackedByteArray())["ok"])
	var none := CscCodec.decode_csc_measurement(_hex("00"))
	assert_true(none["ok"], "без данных — валидный пустой пакет")
	assert_false(none["has_crank"])


func test_cadence_from_pair_3_revs_in_2048_ticks_is_90() -> void:
	var a := CscCodec.decode_csc_measurement(_hex("02 0A 00 00 04"))
	var b := CscCodec.decode_csc_measurement(_hex("02 0D 00 00 0C"))
	assert_almost_eq(CscCodec.cadence_from_pair(a, b), 90.0, 1e-9, "REQ-DEV-04 крит. 1")


func test_cadence_from_pair_handles_uint16_overflow() -> void:
	# time 0xFF00 → 0x0100: Δ = 0x0200 = 512 тиков = 0.5 с; revs 0xFFFF → 0x0002: Δ = 3.
	var a := CscCodec.decode_csc_measurement(_hex("02 FF FF 00 FF"))
	var b := CscCodec.decode_csc_measurement(_hex("02 02 00 00 01"))
	var rpm := CscCodec.cadence_from_pair(a, b)
	assert_almost_eq(rpm, 360.0, 1e-9, "REQ-DEV-04 крит. 2: без отрицательных значений")
	assert_gt(rpm, 0.0)


func test_cadence_from_pair_no_new_event_is_minus_one() -> void:
	var a := CscCodec.decode_csc_measurement(_hex("02 0A 00 00 04"))
	assert_almost_eq(CscCodec.cadence_from_pair(a, a), -1.0, 1e-9)


func test_wheel_speed_from_pair() -> void:
	# 10 оборотов за 1024 тика (1 с) при окружности 2096 мм → 20.96 м/с → 75.456 км/ч.
	var a := {"wheel_revolutions": 100, "wheel_event_time": 0}
	var b := {"wheel_revolutions": 110, "wheel_event_time": 1024}
	assert_almost_eq(CscCodec.wheel_speed_from_pair(a, b, 2096.0), 75.456, 1e-6)
	var wrap_a := {"wheel_revolutions": 0xFFFFFFFF, "wheel_event_time": 0xFFFF}
	var wrap_b := {"wheel_revolutions": 0x00000009, "wheel_event_time": 0x03FF}
	assert_almost_eq(CscCodec.wheel_speed_from_pair(wrap_a, wrap_b, 2096.0), 75.456, 1e-6, "переполнение uint32/uint16")
	assert_almost_eq(CscCodec.wheel_speed_from_pair(a, a, 2096.0), -1.0, 1e-9)


func test_encode_crank_measurement_roundtrip() -> void:
	var b := CscCodec.encode_crank_measurement(13, 3072)
	assert_eq(BleBytes.to_hex(b), "02 0D 00 00 0C")
	assert_eq(BleBytes.to_hex(CscCodec.encode_crank_measurement(0x1FFFF, 0x10400)), "02 FF FF 00 04", "обрезка до uint16")


func test_calculator_first_sample_then_90_rpm() -> void:
	var calc := CscCadenceCalculator.new()
	assert_eq(calc.push(CscCodec.decode_csc_measurement(_hex("02 0A 00 00 04")), 0.0), -1, "одного измерения мало")
	assert_eq(calc.push(CscCodec.decode_csc_measurement(_hex("02 0D 00 00 0C")), 2.0), 90)
	assert_eq(calc.current(2.5), 90)


func test_calculator_holds_then_zero_after_3s_without_revolutions() -> void:
	var calc := CscCadenceCalculator.new()
	calc.push(CscCodec.decode_csc_measurement(_hex("02 0A 00 00 04")), 0.0)
	calc.push(CscCodec.decode_csc_measurement(_hex("02 0D 00 00 0C")), 2.0)
	var same := CscCodec.decode_csc_measurement(_hex("02 0D 00 00 0C"))
	assert_eq(calc.push(same, 3.0), 90, "нет нового события — удерживаем")
	assert_eq(calc.push(same, 4.9), 90)
	assert_eq(calc.push(same, 5.0), 0, "REQ-DEV-04 крит. 3: 3 с без оборотов → 0")
	assert_eq(calc.current(10.0), 0, "current(): чистый расчёт по оборотам")
	assert_true(calc.is_silent(10.0))
	assert_eq(calc.value(10.0), -1, "Н-4: пакетов нет 5 с → «нет данных», не 0")
	assert_eq(calc.value(7.9), 0, "пакет был 2.9 с назад — ещё 0")
	# Новые обороты — снова считаем.
	assert_eq(calc.push(CscCodec.decode_csc_measurement(_hex("02 0F 00 00 14")), 10.0), 60, "2 оборота за 2048 тиков → 60")


func test_calculator_ignores_packets_without_crank_and_resets() -> void:
	var calc := CscCadenceCalculator.new()
	calc.push(CscCodec.decode_csc_measurement(_hex("02 0A 00 00 04")), 0.0)
	calc.push(CscCodec.decode_csc_measurement(_hex("02 0D 00 00 0C")), 2.0)
	assert_eq(calc.push(CscCodec.decode_csc_measurement(_hex("00")), 2.5), 90, "пакет без crank не ломает")
	calc.reset()
	assert_eq(calc.current(3.0), -1)
	assert_eq(calc.push(CscCodec.decode_csc_measurement(_hex("02 0D 00 00 0C")), 3.0), -1)


func test_calculator_custom_timeout() -> void:
	var calc := CscCadenceCalculator.new()
	calc.zero_timeout_sec = 1.0
	calc.push(CscCodec.decode_csc_measurement(_hex("02 0A 00 00 04")), 0.0)
	calc.push(CscCodec.decode_csc_measurement(_hex("02 0D 00 00 0C")), 1.0)
	assert_eq(calc.current(1.9), 90)
	assert_eq(calc.current(2.0), 0)
	assert_eq(calc.value(2.0), -1, "таймаут молчания тот же: 1 с без пакетов → нет данных")
	assert_eq(calc.push(CscCodec.decode_csc_measurement(_hex("02 0D 00 00 0C")), 2.0), 0, "пакет без оборотов → 0")
	assert_eq(calc.value(2.5), 0)


func test_calculator_value_distinguishes_silence_from_stopped_pedals() -> void:
	var calc := CscCadenceCalculator.new()
	assert_eq(calc.value(0.0), -1, "до первого пакета — нет данных")
	assert_true(calc.is_silent(0.0))
	var m := CscCodec.decode_csc_measurement(_hex("02 0A 00 00 04"))
	calc.push(m, 0.0)
	assert_false(calc.is_silent(0.0))
	calc.push(m, 1.0)
	calc.push(m, 2.0)
	assert_eq(calc.push(m, 3.0), 0, "пакеты идут, обороты стоят 3 с → 0")
	assert_eq(calc.value(3.0), 0)
	assert_eq(calc.value(5.9), 0, "последний пакет 2.9 с назад")
	assert_eq(calc.value(6.0), -1, "3 с без пакетов → нет данных")
	assert_eq(calc.current(6.0), 0, "current() при этом по-прежнему 0")
	calc.reset()
	assert_true(calc.is_silent(100.0))
