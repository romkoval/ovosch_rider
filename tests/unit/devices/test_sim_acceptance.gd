extends GutTest
## Приёмка T-063 (tester): SIM в FTMS-кодеке и в `TrainerDevice`.
## REQ-FRD-04 крит. 1 (байты команды 0x11, отклонение значений вне типов), крит. 3 (чтение
## Supported Inclination Range 0x2AD5 после подключения, запасной диапазон −10…+20 %),
## крит. 6 (поддержка SIM по биту Target Setting Features в 0x2ACC и по коду ответа на 0x11).
## Ограничение уклона диапазоном, частота, переход на сопротивление и сообщение на HUD —
## T-068/T-084, здесь не проверяются.

const DEV: String = "neo-acc"
const OTHER: String = "kickr-acc"
const FTMS_SIM_CHARS: Array[String] = ["2AD2", "2AD9", "2ADA", "2AD6", "2ACC", "2AD5"]
## Fitness Machine Features (cadence, power…) — любые; Target Setting Features: бит 13 SIM,
## бит 2 сопротивление, бит 3 мощность.
const FEATURES_SIM: String = "02 40 00 00 0C 20 00 00"
const FEATURES_NO_SIM: String = "02 40 00 00 0C 00 00 00"

var _bridge: StubBleBridge
var _ble: BleTrainer
var _errors: Array[Dictionary] = []


func before_each() -> void:
	_errors = []
	_bridge = StubBleBridge.new()
	_ble = BleTrainer.new(_bridge)
	_ble.error.connect(_on_error)


func after_each() -> void:
	if _ble != null:
		_ble.dispose()
	if _bridge != null:
		_bridge.dispose()


func _on_error(code: int, message: String) -> void:
	_errors.append({"code": code, "message": message})


func _hex(bytes: PackedByteArray) -> String:
	return BleBytes.to_hex(bytes)


func _sim(wind: float, grade: float, crr: float, cw: float) -> String:
	return _hex(FtmsCodec.encode_indoor_bike_simulation(wind, grade, crr, cw))


func _declare(id: String, chars: Array[String], features_hex: String, incl_hex: String) -> void:
	_bridge.set_device_services(id, {"1826": chars, "180F": ["2A19"]})
	if features_hex != "":
		_bridge.set_read_value("2ACC", BleBytes.from_hex(features_hex))
	if incl_hex != "":
		_bridge.set_read_value("2AD5", BleBytes.from_hex(incl_hex))


func _connect(id: String = DEV) -> void:
	_ble.connect_device(id)
	_bridge.pump()


func _cp_writes() -> Array[String]:
	var out: Array[String] = []
	for w in _bridge.writes_to("2AD9"):
		out.append(_hex(w["bytes"]))
	return out


func _reads_of(char_uuid: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in _bridge.calls_of("read_characteristic"):
		if c["char"] == char_uuid:
			out.append(c)
	return out


func _error_codes() -> Array[int]:
	var out: Array[int] = []
	for e in _errors:
		out.append(int(e["code"]))
	return out


# ---------------------------------------------------------------------------
# FRD-04 крит. 1 — байты команды 0x11
# ---------------------------------------------------------------------------

func test_req_frd_04_c1_reference_commands_bytes() -> void:
	assert_eq(_sim(0.0, 5.0, 0.004, 0.20), "11 00 00 F4 01 28 14", "уклон 5.00 %")
	assert_eq(_sim(0.0, -3.0, 0.004, 0.20), "11 00 00 D4 FE 28 14", "уклон −3.00 %")
	assert_eq(_sim(0.0, 0.0, 0.004, 0.20), "11 00 00 00 00 28 14", "уклон 0 %")


func test_req_frd_04_c1_individual_fields() -> void:
	var b := FtmsCodec.encode_indoor_bike_simulation(0.0, 12.34, 0.004, 0.20)
	assert_eq(b.size(), 7, "команда — 7 байт")
	assert_eq(_hex(b.slice(3, 5)), "D2 04", "Grade 12.34 %")
	b = FtmsCodec.encode_indoor_bike_simulation(1.5, 0.0, 0.004, 0.20)
	assert_eq(_hex(b.slice(1, 3)), "DC 05", "Wind Speed 1.5 м/с")
	b = FtmsCodec.encode_indoor_bike_simulation(-1.5, 0.0, 0.004, 0.20)
	assert_eq(_hex(b.slice(1, 3)), "24 FA", "Wind Speed −1.5 м/с (sint16)")
	assert_eq(b[5], 0x28, "Crr 0.004 → 28")
	assert_eq(b[6], 0x14, "Cw 0.20 → 14")
	assert_eq(b[0], 0x11, "опкод 0x11")


func test_req_frd_04_c1_type_boundaries_accepted() -> void:
	assert_eq(_sim(0.0, 327.67, 0.004, 0.20), "11 00 00 FF 7F 28 14", "уклон +327.67 % — край sint16")
	assert_eq(_sim(0.0, -327.67, 0.004, 0.20), "11 00 00 01 80 28 14", "уклон −327.67 %")
	assert_eq(_sim(0.0, 0.0, 0.0255, 0.20), "11 00 00 00 00 FF 14", "Crr 0.0255 — край uint8")
	assert_eq(_sim(0.0, 0.0, 0.004, 2.55), "11 00 00 00 00 28 FF", "Cw 2.55 — край uint8")
	assert_eq(_sim(0.0, 0.0, 0.0, 0.0), "11 00 00 00 00 00 00", "Crr и Cw 0")


func test_req_frd_04_c1_out_of_range_values_rejected_without_bytes() -> void:
	var bad: Dictionary = {
		"уклон 327.68 %": [0.0, 327.68, 0.004, 0.20],
		"уклон −327.68 %": [0.0, -327.68, 0.004, 0.20],
		"уклон 1000 %": [0.0, 1000.0, 0.004, 0.20],
		"Crr 0.0256": [0.0, 5.0, 0.0256, 0.20],
		"Crr 0.1": [0.0, 5.0, 0.1, 0.20],
		"Crr < 0": [0.0, 5.0, -0.001, 0.20],
		"Cw 2.56": [0.0, 5.0, 0.004, 2.56],
		"Cw < 0": [0.0, 5.0, 0.004, -0.01],
		"уклон NaN": [0.0, NAN, 0.004, 0.20],
		"уклон INF": [0.0, INF, 0.004, 0.20],
		"ветер 40 м/с": [40.0, 5.0, 0.004, 0.20],
	}
	for label in bad:
		var a: Array = bad[label]
		var bytes := FtmsCodec.encode_indoor_bike_simulation(a[0], a[1], a[2], a[3])
		assert_eq(bytes.size(), 0, "%s: кодек отклоняет (байты %s)" % [label, _hex(bytes)])


func test_req_frd_04_c1_ble_trainer_writes_sim_to_control_point_with_defaults() -> void:
	_declare(DEV, FTMS_SIM_CHARS, FEATURES_SIM, "9C FF C8 00 05 00")
	_connect()
	_bridge.clear_calls()
	_ble.set_simulation(5.0)
	_bridge.pump()
	var writes := _bridge.writes_to("2AD9")
	assert_eq(writes.size(), 1, "одна запись в Control Point")
	if writes.size() == 1:
		assert_eq(_hex(writes[0]["bytes"]), "11 00 00 F4 01 28 14", "ветер 0, Crr 0.004, Cw 0.20 по умолчанию")
		assert_eq(writes[0]["service"], "1826", "FTMS")
		assert_eq(writes[0]["id"], DEV)
	assert_false(_ble.is_erg_enabled(), "SIM выключает ERG")
	_ble.set_simulation(-3.0)
	_bridge.pump()
	assert_eq(_cp_writes().back(), "11 00 00 D4 FE 28 14")
	assert_eq(_errors, [] as Array[Dictionary], "без ошибок: %s" % str(_errors))


func test_req_frd_04_c1_fake_trainer_logs_sim_command_with_parameters() -> void:
	var fake := FakeTrainer.new(7)
	fake.connect_delay_sec = 0.0
	fake.connect_device("fake")
	fake.set_erg_enabled(true)
	fake.set_target_power(220)
	fake.set_simulation(5.004)
	var last: Dictionary = fake.commands.back()
	assert_eq(last["type"], FakeTrainer.CMD_SIM, "в журнале CMD_SIM")
	assert_almost_eq(float(last["value"]), 5.0, 1e-9, "уклон округлён до 0.01 %")
	assert_almost_eq(float(last["crr"]), 0.004, 1e-9)
	assert_almost_eq(float(last["cw"]), 0.20, 1e-9)
	assert_almost_eq(float(last["wind_mps"]), 0.0, 1e-9)
	assert_false(fake.is_erg_enabled(), "в SIM ERG выключен")
	# Мощность в SIM задаёт гонщик (set_rider_power), а не цель ERG.
	fake.power_noise_w = 0.0
	fake.set_rider_power(140)
	var powers: Array[int] = []
	fake.telemetry.connect(func(s: TrainerSample) -> void: powers.append(s.power_w))
	for i in 30:
		fake.tick(1.0)
	assert_gt(powers.size(), 0)
	if powers.size() > 0:
		assert_almost_eq(powers.back(), 140, 3, "мощность в SIM — мощность гонщика, не цель 220 Вт")


# ---------------------------------------------------------------------------
# FRD-04 крит. 3 — Supported Inclination Range
# ---------------------------------------------------------------------------

func test_req_frd_04_c3_reads_2ad5_from_ftms_after_connect_and_uses_it() -> void:
	# −15.0 … +25.0 %, шаг 0.5 %.
	_declare(DEV, FTMS_SIM_CHARS, FEATURES_SIM, "6A FF FA 00 05 00")
	assert_eq(_ble.inclination_range(), Vector2(-10.0, 20.0), "до подключения — запасной диапазон")
	_connect()
	var reads := _reads_of("2AD5")
	assert_eq(reads.size(), 1, "2AD5 прочитан один раз после подключения")
	if reads.size() == 1:
		assert_eq(reads[0]["service"], "1826", "read_characteristic(id, 0x1826, 0x2AD5)")
		assert_eq(reads[0]["id"], DEV)
	var r: Vector2 = _ble.inclination_range()
	assert_almost_eq(r.x, -15.0, 1e-6, "min из 2AD5")
	assert_almost_eq(r.y, 25.0, 1e-6, "max из 2AD5")


func test_req_frd_04_c3_codec_decodes_inclination_range() -> void:
	var d := FtmsCodec.decode_supported_inclination_range(BleBytes.from_hex("9C FF C8 00 05 00"))
	assert_true(d["ok"])
	assert_almost_eq(float(d["min_pct"]), -10.0, 1e-6)
	assert_almost_eq(float(d["max_pct"]), 20.0, 1e-6)
	assert_almost_eq(float(d["increment_pct"]), 0.5, 1e-6)
	assert_false(FtmsCodec.decode_supported_inclination_range(BleBytes.from_hex("9C FF C8")).get("ok", true), "обрезанный пакет")
	assert_false(FtmsCodec.decode_supported_inclination_range(BleBytes.from_hex("C8 00 9C FF 05 00")).get("ok", true), "max < min")


func test_req_frd_04_c3_no_response_gives_fallback_minus10_plus20() -> void:
	# 2AD5 заявлен, но чтение не отвечает значением (ошибка характеристики).
	_declare(DEV, FTMS_SIM_CHARS, FEATURES_SIM, "")
	_connect()
	assert_eq(_reads_of("2AD5").size(), 1, "чтение было")
	assert_eq(_ble.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "ошибка чтения не рвёт связь")
	assert_eq(_ble.inclination_range(), Vector2(-10.0, 20.0), "без ответа — −10…+20 %")


func test_req_frd_04_c3_read_failure_and_garbage_give_fallback() -> void:
	_declare(DEV, FTMS_SIM_CHARS, FEATURES_SIM, "01 02")
	_connect()
	assert_eq(_ble.inclination_range(), Vector2(-10.0, 20.0), "обрезанный ответ — запасной диапазон")
	var b2 := StubBleBridge.new()
	var t2 := BleTrainer.new(b2)
	b2.set_device_services(DEV, {"1826": FTMS_SIM_CHARS})
	b2.set_read_value("2AD5", BleBytes.from_hex("9C FF C8 00 05 00"))
	b2.fail_next_read()
	t2.connect_device(DEV)
	b2.pump()
	assert_eq(t2.inclination_range(), Vector2(-10.0, 20.0), "ошибка чтения — запасной диапазон")
	t2.dispose()
	b2.dispose()


func test_req_frd_04_c3_trainer_without_2ad5_uses_fallback_and_switching_trainer_forgets_range() -> void:
	_declare(DEV, FTMS_SIM_CHARS, FEATURES_SIM, "6A FF FA 00 05 00")
	_connect()
	assert_eq(_ble.inclination_range(), Vector2(-15.0, 25.0))
	_ble.disconnect_device()
	_bridge.pump()
	_declare(OTHER, ["2AD2", "2AD9", "2ADA", "2AD6"] as Array[String], "", "")
	_connect(OTHER)
	assert_eq(_ble.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_ble.inclination_range(), Vector2(-10.0, 20.0), "другой станок без 2AD5 — запасной, не диапазон прежнего")


func test_req_frd_04_c3_fake_trainer_range_default_and_custom() -> void:
	var fake := FakeTrainer.new(3)
	assert_eq(fake.inclination_range(), Vector2(-10.0, 20.0), "по умолчанию запасной")
	fake.set_inclination_range(-5.0, 15.0)
	assert_eq(fake.inclination_range(), Vector2(-5.0, 15.0))
	fake.set_inclination_range(10.0, 10.0)
	assert_eq(fake.inclination_range(), Vector2(-5.0, 15.0), "min ≥ max не принимается")


# ---------------------------------------------------------------------------
# FRD-04 крит. 6 — определение поддержки
# ---------------------------------------------------------------------------

func test_req_frd_04_c6_reads_2acc_and_bit13_means_supported() -> void:
	_declare(DEV, FTMS_SIM_CHARS, FEATURES_SIM, "9C FF C8 00 05 00")
	assert_eq(_ble.simulation_support(), TrainerDevice.SimulationSupport.UNKNOWN, "до подключения неизвестно")
	_connect()
	var reads := _reads_of("2ACC")
	assert_eq(reads.size(), 1, "2ACC прочитан после подключения")
	if reads.size() == 1:
		assert_eq(reads[0]["service"], "1826")
	assert_eq(_ble.simulation_support(), TrainerDevice.SimulationSupport.SUPPORTED, "бит 13 TSF → SUPPORTED")


func test_req_frd_04_c6_bit_not_set_means_unsupported() -> void:
	_declare(DEV, FTMS_SIM_CHARS, FEATURES_NO_SIM, "9C FF C8 00 05 00")
	_connect()
	assert_eq(_ble.simulation_support(), TrainerDevice.SimulationSupport.UNSUPPORTED, "без бита 13 → UNSUPPORTED")
	# Соседние биты не путаются с битом SIM: только бит 12 и бит 14.
	var only_neighbours := FtmsCodec.decode_fitness_machine_feature(BleBytes.from_hex("00 00 00 00 00 50 00 00"))
	assert_true(only_neighbours["ok"])
	assert_false(only_neighbours["simulation_supported"], "биты 12 и 14 — не SIM")
	var only_sim := FtmsCodec.decode_fitness_machine_feature(BleBytes.from_hex("00 00 00 00 00 20 00 00"))
	assert_true(only_sim["simulation_supported"], "бит 13 Target Setting Features")
	# Бит 13 в Fitness Machine Features (первое поле) — не тот флаг.
	var wrong_field := FtmsCodec.decode_fitness_machine_feature(BleBytes.from_hex("00 20 00 00 00 00 00 00"))
	assert_false(wrong_field["simulation_supported"], "бит 13 первого поля — не SIM")


func test_req_frd_04_c6_rejection_of_0x11_any_result_code_gives_unsupported_and_error() -> void:
	for result in [FtmsCodec.RESULT_NOT_SUPPORTED, FtmsCodec.RESULT_INVALID_PARAMETER,
			FtmsCodec.RESULT_OPERATION_FAILED, FtmsCodec.RESULT_CONTROL_NOT_PERMITTED]:
		var bridge := StubBleBridge.new()
		var t := BleTrainer.new(bridge)
		var codes: Array[int] = []
		t.error.connect(func(code: int, _m: String) -> void: codes.append(code))
		bridge.set_device_services(DEV, {"1826": FTMS_SIM_CHARS})
		bridge.set_read_value("2ACC", BleBytes.from_hex(FEATURES_SIM))
		t.connect_device(DEV)
		bridge.pump()
		assert_eq(t.simulation_support(), TrainerDevice.SimulationSupport.SUPPORTED, "заявлен в 2ACC")
		bridge.fail_next_control_point(result)
		t.set_simulation(4.0)
		bridge.pump()
		assert_eq(t.simulation_support(), TrainerDevice.SimulationSupport.UNSUPPORTED,
			"ответ 0x%02X на 0x11 → UNSUPPORTED" % result)
		assert_true(codes.has(TrainerDevice.ErrorCode.SIMULATION_REJECTED), "0x%02X: error(SIMULATION_REJECTED): %s" % [result, str(codes)])
		assert_eq(t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "0x%02X: связь не рвётся" % result)
		t.dispose()
		bridge.dispose()


func test_req_frd_04_c6_rejection_with_unknown_support_and_fixed_resistance_still_works() -> void:
	# Станок не заявил 2ACC: поддержка неизвестна до ответа на 0x11.
	_declare(DEV, ["2AD2", "2AD9", "2ADA", "2AD6"] as Array[String], "", "")
	_connect()
	assert_eq(_ble.simulation_support(), TrainerDevice.SimulationSupport.UNKNOWN)
	_bridge.fail_next_control_point(FtmsCodec.RESULT_NOT_SUPPORTED)
	_ble.set_simulation(5.0)
	_bridge.pump()
	assert_eq(_cp_writes().back(), "11 00 00 F4 01 28 14", "команда SIM ушла")
	assert_eq(_ble.simulation_support(), TrainerDevice.SimulationSupport.UNSUPPORTED, "0x02 → UNSUPPORTED")
	assert_true(_error_codes().has(TrainerDevice.ErrorCode.SIMULATION_REJECTED))
	# Сессия не прерывается: фиксированное сопротивление уходит на станок.
	_bridge.clear_calls()
	_ble.set_resistance_level(40)
	_bridge.pump()
	var w := _cp_writes()
	assert_eq(w.size(), 1, "после отказа SIM уходит Set Target Resistance Level: %s" % str(w))
	if w.size() == 1:
		assert_true(w[0].begins_with("04"), "опкод 0x04")
	assert_eq(_ble.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)


func test_req_frd_04_c6_success_of_0x11_keeps_supported_and_no_error() -> void:
	_declare(DEV, ["2AD2", "2AD9", "2ADA", "2AD6"] as Array[String], "", "")
	_connect()
	_ble.set_simulation(2.0)
	_bridge.pump()
	assert_eq(_ble.simulation_support(), TrainerDevice.SimulationSupport.SUPPORTED, "станок принял 0x11 → SUPPORTED")
	assert_false(_error_codes().has(TrainerDevice.ErrorCode.SIMULATION_REJECTED))


func test_req_frd_04_c6_reconnect_to_other_trainer_resets_support() -> void:
	_declare(DEV, FTMS_SIM_CHARS, FEATURES_NO_SIM, "")
	_connect()
	assert_eq(_ble.simulation_support(), TrainerDevice.SimulationSupport.UNSUPPORTED)
	_ble.disconnect_device()
	_bridge.pump()
	_declare(OTHER, FTMS_SIM_CHARS, FEATURES_SIM, "")
	_connect(OTHER)
	assert_eq(_ble.simulation_support(), TrainerDevice.SimulationSupport.SUPPORTED, "новый станок — новая проверка")


func test_req_frd_04_c6_fake_trainer_without_sim_rejects_and_reports_unsupported() -> void:
	var fake := FakeTrainer.new(5)
	var codes: Array[int] = []
	fake.error.connect(func(code: int, _m: String) -> void: codes.append(code))
	fake.connect_delay_sec = 0.0
	fake.connect_device("fake")
	assert_eq(fake.simulation_support(), TrainerDevice.SimulationSupport.SUPPORTED, "эмулятор по умолчанию с SIM")
	fake.set_simulation_supported(false)
	assert_eq(fake.simulation_support(), TrainerDevice.SimulationSupport.UNSUPPORTED)
	fake.set_simulation(6.0)
	assert_eq(fake.commands.back()["type"], FakeTrainer.CMD_SIM, "команда журналируется")
	assert_true(codes.has(TrainerDevice.ErrorCode.SIMULATION_REJECTED), "отказ SIM: %s" % str(codes))
	assert_false(fake.simulation_active, "SIM не применён")
	assert_eq(fake.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "связь не рвётся")
	fake.set_resistance_level(30)
	assert_eq(fake.resistance_percent, 30, "фиксированное сопротивление работает после отказа")


func test_req_frd_04_c6_fake_trainer_rejected_sim_command_switches_support() -> void:
	var fake := FakeTrainer.new(5)
	fake.connect_delay_sec = 0.0
	fake.connect_device("fake")
	fake.fail_next_command()
	fake.set_simulation(3.0)
	assert_eq(fake.simulation_support(), TrainerDevice.SimulationSupport.UNSUPPORTED, "ответ ≠ 0x01 на SIM → UNSUPPORTED")
