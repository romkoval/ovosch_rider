extends GutTest
## Тесты SensorHub (REQ-DEV-03 крит. 3, REQ-DEV-04 крит. 4, REQ-DEV-05 крит. 2, 3,
## REQ-WRK-08 крит. 4, REQ-DEV-08 крит. 2; решения 12, 13).

var _trainer: FakeTrainer
var _bridge: StubBleBridge
var _hub: SensorHub
var _samples: Array[TrainerSample] = []
var _hr: Array[int] = []
var _disposables: Array = []


func before_each() -> void:
	_samples = []
	_hr = []
	_trainer = FakeTrainer.new(3)
	_trainer.connect_delay_sec = 0.0
	_trainer.power_noise_w = 0.0
	_trainer.cadence_noise_rpm = 0.0
	_trainer.connect_device("fake")
	_bridge = StubBleBridge.new()
	_hub = SensorHub.new(_trainer)
	_hub.telemetry.connect(func(s: TrainerSample) -> void: _samples.append(s))
	_hub.heart_rate.connect(func(b: int) -> void: _hr.append(b))
	_disposables = []


func after_each() -> void:
	for d in _disposables:
		(d as Object).call("dispose")
	_disposables = []
	if _hub != null:
		_hub.dispose()


func _hrs() -> BleHeartRateSensor:
	var s := BleHeartRateSensor.new(_bridge)
	_disposables.append(s)
	s.connect_device("hrs")
	_bridge.pump()
	_hub.set_heart_rate_sensor(s)
	return s


func _csc() -> BleCadenceSensor:
	var s := BleCadenceSensor.new(_bridge)
	_disposables.append(s)
	s.connect_device("csc")
	_bridge.pump()
	_hub.set_cadence_sensor(s)
	return s


func _pm() -> BlePowerMeter:
	var s := BlePowerMeter.new(_bridge)
	_disposables.append(s)
	s.connect_device("pm")
	_bridge.pump()
	_hub.set_power_meter(s)
	return s


func _tick_n(n: int, delta: float = 1.0) -> void:
	for i in n:
		_hub.tick(delta)


# ---------------------------------------------------------------------------
# Делегирование
# ---------------------------------------------------------------------------

func test_hub_is_trainer_device_and_delegates_commands_and_state() -> void:
	assert_true(_hub is TrainerDevice)
	assert_eq(_hub.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	_hub.set_target_power(200)
	_hub.set_erg_enabled(false)
	_hub.set_resistance_level(40)
	assert_eq(_trainer.commands.size(), 3)
	assert_eq(_trainer.commands[0]["value"], 200)
	assert_eq(_trainer.commands[1]["value"], false)
	assert_eq(_trainer.commands[2]["value"], 40)
	var states: Array[int] = []
	_hub.connection_state_changed.connect(func(s: int) -> void: states.append(s))
	_hub.disconnect_device()
	assert_eq(states, [TrainerDevice.ConnectionState.DISCONNECTED] as Array[int], "состояние станка пробрасывается")
	_hub.connect_device("fake")
	assert_eq(_hub.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)


func test_hub_forwards_trainer_errors() -> void:
	var errs: Array[int] = []
	_hub.error.connect(func(c: int, _m: String) -> void: errs.append(c))
	_trainer.fail_next_command()
	_hub.set_target_power(100)
	assert_eq(errs, [TrainerDevice.ErrorCode.CONTROL_POINT_REJECTED] as Array[int])


# ---------------------------------------------------------------------------
# Один сэмпл в секунду, станок как единственный источник
# ---------------------------------------------------------------------------

func test_one_merged_sample_per_second_from_trainer_only() -> void:
	_hub.set_target_power(200)
	_tick_n(10)
	assert_eq(_samples.size(), 10)
	assert_almost_eq(_samples[0].timestamp_sec, 1.0, 1e-9)
	assert_almost_eq(_samples[9].timestamp_sec, 10.0, 1e-9)
	var s := _samples[9]
	assert_true(s.has_power)
	assert_true(s.has_cadence)
	assert_true(s.has_speed)
	assert_true(absi(s.power_w - 200) <= 10)
	assert_eq(_hub.power_source_in_use(), SensorHub.SOURCE_TRAINER)
	assert_eq(_hub.cadence_source_in_use(), SensorHub.SOURCE_TRAINER)
	assert_eq(_hub.heart_rate_source_in_use(), SensorHub.SOURCE_NONE)
	assert_eq(_hr.size(), 0)


func test_fractional_ticks_give_exact_sample_count() -> void:
	_tick_n(50, 0.2)
	assert_eq(_samples.size(), 10)
	_hub.tick(2.5)
	assert_eq(_samples.size(), 12, "большая дельта догоняет две секунды")


func test_trainer_heart_rate_used_when_no_hrs() -> void:
	_trainer.set_heart_rate(140)
	_tick_n(3)
	assert_eq(_hr, [140, 140, 140] as Array[int])
	assert_eq(_hub.heart_rate_source_in_use(), SensorHub.SOURCE_TRAINER)


func test_trainer_dropout_gives_no_data_but_samples_continue() -> void:
	_tick_n(3)
	_trainer.inject_dropout(20.0)
	_tick_n(4)
	assert_eq(_samples.size(), 7, "REQ-DEV-08 крит. 2: слоты идут")
	assert_true(_samples[6].has_power, "4 с тишины < 5 с — последнее значение ещё считается актуальным")
	_tick_n(2)
	assert_false(_samples[8].has_power, "REQ-WRK-08 крит. 4: 5 с без данных → нет данных")
	assert_false(_samples[8].has_cadence)
	assert_false(_samples[8].has_speed)
	assert_eq(_hub.power_source_in_use(), SensorHub.SOURCE_NONE)


# ---------------------------------------------------------------------------
# Приоритеты (решение 13)
# ---------------------------------------------------------------------------

func test_hrs_has_priority_over_trainer_heart_rate() -> void:
	_trainer.set_heart_rate(140)
	_hrs()
	_bridge.emit_notification("hrs", "2A37", BleBytes.from_hex("06 A0"))  # 160, контакт есть
	_tick_n(1)
	assert_eq(_hr, [160] as Array[int], "REQ-DEV-03 крит. 3: HRS > станок")
	assert_eq(_hub.heart_rate_source_in_use(), SensorHub.SOURCE_HEART_RATE_SENSOR)


func test_hrs_silent_5s_yields_to_trainer_heart_rate() -> void:
	_trainer.set_heart_rate(140)
	_hrs()
	_bridge.emit_notification("hrs", "2A37", BleBytes.from_hex("06 A0"))
	_tick_n(4)
	assert_eq(_hr.back(), 160, "4 с — ещё HRS")
	_tick_n(1)
	assert_eq(_hr.back(), 140, "5 с молчания → уступает станку")
	assert_eq(_hub.heart_rate_source_in_use(), SensorHub.SOURCE_TRAINER)


func test_hrs_without_contact_counts_as_silence() -> void:
	_trainer.set_heart_rate(140)
	_hrs()
	for i in 6:
		_bridge.emit_notification("hrs", "2A37", BleBytes.from_hex("04 A0"))  # нет контакта
		_tick_n(1)
	assert_eq(_hr.back(), 140, "недостоверный пульс HRS не перебивает станок")


func test_csc_has_priority_over_power_meter_and_trainer_cadence() -> void:
	_csc()
	_pm()
	_bridge.emit_notification("csc", "2A5B", CscCodec.encode_crank_measurement(10, 1024))
	_bridge.emit_notification("pm", "2A63", CpsCodec.encode_cycling_power_measurement(300, 20, 1024))
	_tick_n(2)
	_bridge.emit_notification("csc", "2A5B", CscCodec.encode_crank_measurement(13, 3072))     # 90 rpm
	_bridge.emit_notification("pm", "2A63", CpsCodec.encode_cycling_power_measurement(300, 22, 3072))  # 60 rpm
	_tick_n(1)
	var s: TrainerSample = _samples.back()
	assert_eq(s.cadence_rpm, 90, "REQ-DEV-04 крит. 4: CSC > CPS > станок")
	assert_eq(_hub.cadence_source_in_use(), SensorHub.SOURCE_CADENCE_SENSOR)
	assert_true(s.has_power)
	assert_eq(_hub.power_source_in_use(), SensorHub.SOURCE_POWER_METER, "мощность — измеритель > станок (DEV-05 п.2, У-32)")


func test_csc_silent_yields_to_power_meter_cadence_then_trainer() -> void:
	_csc()
	_pm()
	_bridge.emit_notification("csc", "2A5B", CscCodec.encode_crank_measurement(10, 1024))
	_bridge.emit_notification("pm", "2A63", CpsCodec.encode_cycling_power_measurement(300, 20, 1024))
	_tick_n(2)
	_bridge.emit_notification("csc", "2A5B", CscCodec.encode_crank_measurement(13, 3072))
	_bridge.emit_notification("pm", "2A63", CpsCodec.encode_cycling_power_measurement(300, 22, 3072))
	_tick_n(1)
	assert_eq(_samples.back().cadence_rpm, 90)
	# CSC замолкает (пакетов нет); измеритель шлёт crank data каждую секунду (60 rpm).
	var revs: int = 22
	var t: int = 3072
	for i in 1:
		revs += 1
		t += 1024
		_bridge.emit_notification("pm", "2A63", CpsCodec.encode_cycling_power_measurement(300, revs, t))
		_tick_n(1)
	assert_eq(_hub.cadence_source_in_use(), SensorHub.SOURCE_CADENCE_SENSOR, "2 с тишины — CSC ещё свеж")
	assert_eq(_samples.back().cadence_rpm, 90)
	revs += 1
	t += 1024
	_bridge.emit_notification("pm", "2A63", CpsCodec.encode_cycling_power_measurement(300, revs, t))
	_tick_n(1)
	assert_eq(_samples.back().cadence_rpm, 60, "Н-4: CSC молчит 3 с → сразу каденс измерителя, без ложного нуля")
	assert_eq(_hub.cadence_source_in_use(), SensorHub.SOURCE_POWER_METER)
	# Измеритель тоже замолкает → через 3 с каденс станка.
	_tick_n(3)
	assert_eq(_hub.cadence_source_in_use(), SensorHub.SOURCE_TRAINER, "измеритель молчит 3 с → станок")
	assert_true(_samples.back().has_cadence)
	assert_gt(_samples.back().cadence_rpm, 0)
	assert_true(_samples.back().has_power, "мощность станка при этом свежа (порог 5 с)")


func test_csc_stopped_pedals_with_packets_gives_zero_not_fallback() -> void:
	_csc()
	_bridge.emit_notification("csc", "2A5B", CscCodec.encode_crank_measurement(10, 1024))
	_tick_n(2)
	var same := CscCodec.encode_crank_measurement(13, 3072)
	_bridge.emit_notification("csc", "2A5B", same)
	_tick_n(1)
	assert_eq(_samples.back().cadence_rpm, 90)
	for i in 3:
		_bridge.emit_notification("csc", "2A5B", same)
		_tick_n(1)
	assert_eq(_samples.back().cadence_rpm, 0, "REQ-DEV-04 крит. 3: пакеты идут, обороты стоят → 0 от датчика")
	assert_eq(_hub.cadence_source_in_use(), SensorHub.SOURCE_CADENCE_SENSOR, "0 — это данные CSC, не станок")


## REQ-DEV-05 п.2 (а), У-32: измеритель мощности главнее станка без выбора в настройках.
func test_power_meter_has_priority_over_trainer() -> void:
	_tick_n(1)
	assert_eq(_hub.power_source_in_use(), SensorHub.SOURCE_TRAINER, "без измерителя — станок")
	_pm()
	_tick_n(1)
	assert_eq(_hub.power_source_in_use(), SensorHub.SOURCE_TRAINER, "измеритель без пакетов — ещё станок")
	_bridge.emit_notification("pm", "2A63", BleBytes.from_hex("00 00 2C 01"))  # 300 Вт
	_tick_n(1)
	assert_eq(_samples.back().power_w, 300, "первый пакет измерителя — его мощность")
	assert_eq(_hub.power_source_in_use(), SensorHub.SOURCE_POWER_METER)
	assert_false("power_source" in _hub, "выбора источника мощности у хаба нет")


func test_power_meter_silent_falls_back_to_trainer_and_vice_versa() -> void:
	_pm()
	_bridge.emit_notification("pm", "2A63", BleBytes.from_hex("00 00 2C 01"))
	_tick_n(5)
	assert_eq(_hub.power_source_in_use(), SensorHub.SOURCE_TRAINER, "измеритель молчит 5 с → станок")
	_trainer.inject_dropout(30.0)
	_bridge.emit_notification("pm", "2A63", BleBytes.from_hex("00 00 2C 01"))
	_tick_n(4)
	assert_eq(_hub.power_source_in_use(), SensorHub.SOURCE_POWER_METER, "измеритель свеж → он")
	assert_eq(_samples.back().power_w, 300)
	_tick_n(1)
	assert_false(_samples.back().has_power, "оба молчат 5 с → нет данных")
	assert_eq(_hub.power_source_in_use(), SensorHub.SOURCE_NONE)


func test_replacing_sensor_disconnects_old_handlers() -> void:
	var old := _hrs()
	var fresh := BleHeartRateSensor.new(_bridge)
	_disposables.append(fresh)
	fresh.connect_device("hrs2")
	_bridge.pump()
	_hub.set_heart_rate_sensor(fresh)
	_bridge.emit_notification("hrs", "2A37", BleBytes.from_hex("06 A0"))
	_tick_n(1)
	assert_eq(_hr.size(), 0, "старый датчик больше не слушается")
	_bridge.emit_notification("hrs2", "2A37", BleBytes.from_hex("06 64"))
	_tick_n(1)
	assert_eq(_hr, [100] as Array[int])
	assert_eq(old.last_bpm, 160, "сам старый датчик продолжает работать")
	_hub.set_heart_rate_sensor(null)
	_tick_n(1)
	assert_eq(_hr.size(), 1)


func test_cadence_timeout_is_3s_while_power_timeout_is_5s() -> void:
	_csc()
	_bridge.emit_notification("csc", "2A5B", CscCodec.encode_crank_measurement(10, 1024))
	_tick_n(2)
	_bridge.emit_notification("csc", "2A5B", CscCodec.encode_crank_measurement(13, 3072))
	_tick_n(1)
	assert_eq(_samples.back().cadence_rpm, 90)
	_tick_n(2)
	assert_eq(_hub.cadence_source_in_use(), SensorHub.SOURCE_TRAINER, "3 с тишины CSC → каденс станка")
	_trainer.inject_dropout(30.0)
	_tick_n(3)
	assert_false(_samples.back().has_cadence, "каденс станка тоже стареет за 3 с")
	assert_true(_samples.back().has_power, "мощность станка — порог 5 с")
	_tick_n(2)
	assert_false(_samples.back().has_power)


func test_hub_works_inside_workout_session() -> void:
	_trainer.set_heart_rate(130)
	_hrs()
	var steps: Array[WorkoutStep] = [WorkoutStep.percent(10, 50.0), WorkoutStep.percent(10, 100.0)]
	var session := WorkoutSession.new(Workout.make("hub", steps), _hub, 200)
	session.start()
	for i in 20:
		_bridge.emit_notification("hrs", "2A37", BleBytes.from_hex("06 A0"))
		session.tick(1.0)
	assert_eq(session.get_state(), WorkoutSession.State.FINISHED)
	assert_eq(session.samples.size(), 20)
	assert_eq(session.samples.count_with_power(), 20)
	assert_eq(session.samples.heart_rate_bpm[10], 160, "пульс в поток — с HRS через хаб")
	assert_eq(_trainer.commands[1]["value"], 200, "команды дошли до станка через хаб")
	assert_almost_eq(float(_trainer.commands[1]["at_sec"]), 10.0, 1e-6)


func test_dispose_detaches_hub_from_trainer_and_sensors() -> void:
	_hrs()
	_tick_n(1)
	assert_eq(_samples.size(), 1)
	_hub.dispose()
	assert_null(_hub.trainer)
	assert_null(_hub.heart_rate_sensor)
	_trainer.tick(1.0)
	_hub.tick(1.0)
	assert_eq(_samples.size(), 2, "хаб тикает свои часы, но телеметрии станка уже не получает")
	assert_false(_samples[1].has_power)
	_hub.set_target_power(100)
	assert_eq(_hub.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
