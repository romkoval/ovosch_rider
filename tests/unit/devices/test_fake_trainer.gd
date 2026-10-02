extends GutTest
## Тесты эмулятора станка FakeTrainer (REQ-DEV-09) и контракта TrainerDevice.

const SEED: int = 12345

var _trainer: FakeTrainer
var _samples: Array[TrainerSample] = []
var _states: Array[int] = []
var _errors: Array[Dictionary] = []
var _heart_rates: Array[int] = []


func before_each() -> void:
	_samples = []
	_states = []
	_errors = []
	_heart_rates = []
	_trainer = _make_trainer(SEED)


func _make_trainer(seed: int) -> FakeTrainer:
	var t := FakeTrainer.new(seed)
	t.telemetry.connect(_on_telemetry)
	t.connection_state_changed.connect(_on_state)
	t.error.connect(_on_error)
	t.heart_rate.connect(_on_heart_rate)
	return t


func _on_telemetry(sample: TrainerSample) -> void:
	_samples.append(sample)


func _on_state(state: int) -> void:
	_states.append(state)


func _on_error(code: int, message: String) -> void:
	_errors.append({"code": code, "message": message})


func _on_heart_rate(bpm: int) -> void:
	_heart_rates.append(bpm)


## Подключает с нулевой задержкой и сбрасывает собранные сэмплы/состояния.
func _connect_now(t: FakeTrainer) -> void:
	t.connect_delay_sec = 0.0
	t.connect_device("fake-1")
	_samples = []
	_states = []


func _tick_n(t: FakeTrainer, n: int, delta: float = 1.0) -> void:
	for i in n:
		t.tick(delta)


# ---------------------------------------------------------------------------
# Подключение
# ---------------------------------------------------------------------------

func test_initial_state_is_disconnected() -> void:
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_eq(_trainer.commands.size(), 0)


func test_connect_passes_connecting_then_connected_after_delay() -> void:
	_trainer.connect_delay_sec = 0.5
	_trainer.connect_device("tacx-neo")
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.CONNECTING)
	assert_eq(_trainer.device_id, "tacx-neo")
	_trainer.tick(0.25)
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.CONNECTING, "ещё не прошло 0.5 с")
	_trainer.tick(0.25)
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_states, [TrainerDevice.ConnectionState.CONNECTING, TrainerDevice.ConnectionState.CONNECTED])


func test_connect_with_zero_delay_is_immediate() -> void:
	_trainer.connect_delay_sec = 0.0
	_trainer.connect_device("x")
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)


func test_disconnect_stops_telemetry() -> void:
	_connect_now(_trainer)
	_tick_n(_trainer, 3)
	assert_eq(_samples.size(), 3)
	_trainer.disconnect_device()
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	_tick_n(_trainer, 5)
	assert_eq(_samples.size(), 3, "после отключения сэмплы не идут")


func test_no_telemetry_before_connection() -> void:
	_tick_n(_trainer, 10)
	assert_eq(_samples.size(), 0)


func test_fail_next_connect_emits_error_and_returns_to_disconnected() -> void:
	_trainer.fail_next_connect()
	_trainer.connect_delay_sec = 0.2
	_trainer.connect_device("ghost")
	_trainer.tick(0.2)
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_eq(_errors.size(), 1)
	assert_eq(_errors[0]["code"], TrainerDevice.ErrorCode.CONNECTION_FAILED)


# ---------------------------------------------------------------------------
# Поток 1 Гц (REQ-WRK-08 крит. 1, REQ-NFR-02 крит. 1)
# ---------------------------------------------------------------------------

func test_600_ticks_of_one_second_give_600_samples_with_monotonic_timestamps() -> void:
	_trainer.connect_delay_sec = 0.5
	_trainer.connect_device("x")
	_trainer.tick(0.5)
	_samples = []
	_tick_n(_trainer, 600)
	assert_eq(_samples.size(), 600)
	for i in _samples.size():
		assert_almost_eq(_samples[i].timestamp_sec, float(i + 1), 1e-6)
	assert_true(_samples[0].has_power and _samples[0].has_cadence and _samples[0].has_speed)


func test_fractional_ticks_give_exact_sample_count() -> void:
	_connect_now(_trainer)
	_tick_n(_trainer, 6000, 0.1)
	assert_eq(_samples.size(), 600, "накопление float не должно терять сэмпл")


func test_large_tick_emits_all_missed_samples_postfactum() -> void:
	# Имитация заморозки кадра на 2 с (REQ-NFR-02 крит. 2).
	_connect_now(_trainer)
	_trainer.tick(1.0)
	_trainer.tick(2.0)
	assert_eq(_samples.size(), 3)
	assert_almost_eq(_samples[1].timestamp_sec, 2.0, 1e-6)
	assert_almost_eq(_samples[2].timestamp_sec, 3.0, 1e-6)


# ---------------------------------------------------------------------------
# ERG и команды (REQ-DEV-09 крит. 2, REQ-WRK-02/03/04)
# ---------------------------------------------------------------------------

func test_erg_power_converges_to_target_within_3_seconds() -> void:
	_connect_now(_trainer)
	_trainer.set_rider_power(150)
	_tick_n(_trainer, 2)
	_trainer.set_target_power(250)
	_samples = []
	_tick_n(_trainer, 3)
	var p: int = _samples[2].power_w
	assert_true(absi(p - 250) <= 13, "через 3 с |P − 250| ≤ 5 %%, получено %d Вт" % p)
	_tick_n(_trainer, 7)
	for s in _samples.slice(3):
		assert_true(absi(s.power_w - 250) <= 13, "удерживает цель: %d Вт" % s.power_w)


func test_set_target_power_is_logged_with_timestamp() -> void:
	_connect_now(_trainer)
	_trainer.tick(1.0)
	_trainer.tick(0.3)
	_trainer.set_target_power(130)
	assert_eq(_trainer.commands.size(), 1)
	var cmd: Dictionary = _trainer.commands[0]
	assert_eq(cmd["type"], FakeTrainer.CMD_TARGET_POWER)
	assert_eq(cmd["value"], 130)
	assert_almost_eq(float(cmd["at_sec"]), 1.3, 1e-6)
	assert_eq(_trainer.target_power_w, 130)


func test_erg_off_and_resistance_level_are_logged_and_power_follows_rider() -> void:
	_connect_now(_trainer)
	_trainer.set_target_power(300)
	_tick_n(_trainer, 5)
	assert_true(absi(_samples[-1].power_w - 300) <= 15, "в ERG держит 300 Вт")
	_trainer.set_erg_enabled(false)
	_trainer.set_resistance_level(40)
	assert_false(_trainer.erg_enabled)
	assert_eq(_trainer.resistance_percent, 40)
	assert_eq(_trainer.commands.size(), 3)
	assert_eq(_trainer.commands[1]["type"], FakeTrainer.CMD_ERG)
	assert_eq(_trainer.commands[1]["value"], false)
	assert_eq(_trainer.commands[2]["type"], FakeTrainer.CMD_RESISTANCE)
	assert_eq(_trainer.commands[2]["value"], 40)
	_trainer.set_rider_power(120)
	_samples = []
	_tick_n(_trainer, 5)
	assert_true(absi(_samples[-1].power_w - 120) <= 6, "вне ERG мощность = мощность всадника: %d" % _samples[-1].power_w)


func test_target_power_outside_erg_is_stored_and_applied_when_erg_enabled() -> void:
	_connect_now(_trainer)
	_trainer.set_erg_enabled(false)
	_trainer.set_rider_power(100)
	_trainer.set_target_power(200)
	_tick_n(_trainer, 5)
	assert_true(absi(_samples[-1].power_w - 100) <= 5, "вне ERG цель не действует")
	_trainer.set_erg_enabled(true)
	_samples = []
	_tick_n(_trainer, 5)
	assert_true(absi(_samples[-1].power_w - 200) <= 10, "после включения ERG цель применилась")


func test_out_of_range_arguments_are_clamped() -> void:
	_connect_now(_trainer)
	_trainer.set_target_power(5000)
	_trainer.set_resistance_level(-10)
	assert_eq(_trainer.target_power_w, TrainerDevice.MAX_TARGET_POWER_W)
	assert_eq(_trainer.resistance_percent, 0)
	assert_eq(_trainer.commands[0]["value"], TrainerDevice.MAX_TARGET_POWER_W)


func test_fail_next_command_emits_control_point_error_and_keeps_log() -> void:
	_connect_now(_trainer)
	_trainer.fail_next_command()
	_trainer.set_target_power(200)
	assert_eq(_errors.size(), 1)
	assert_eq(_errors[0]["code"], TrainerDevice.ErrorCode.CONTROL_POINT_REJECTED)
	assert_eq(_trainer.target_power_w, 0, "отвергнутая команда не применяется")
	assert_eq(_trainer.commands.size(), 1, "но в журнал попадает")
	_trainer.set_target_power(210)
	assert_eq(_errors.size(), 1, "следующая команда проходит")
	assert_eq(_trainer.target_power_w, 210)


# ---------------------------------------------------------------------------
# Обрыв и восстановление связи (REQ-DEV-08)
# ---------------------------------------------------------------------------

func test_dropout_goes_reconnecting_without_samples_then_restores() -> void:
	_connect_now(_trainer)
	_trainer.set_target_power(200)
	_tick_n(_trainer, 3)
	assert_eq(_samples.size(), 3)
	_trainer.inject_dropout(4.0)
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING)
	_samples = []
	_tick_n(_trainer, 3)
	assert_eq(_samples.size(), 0, "во время обрыва телеметрии нет")
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING)
	_trainer.tick(1.0)
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_samples.size(), 0, "обрыв на 4 с глотает ровно 4 сэмпла (4..7)")
	_tick_n(_trainer, 5)
	assert_eq(_samples.size(), 5)
	assert_almost_eq(_samples[-1].timestamp_sec, 12.0, 1e-6, "часы не сбрасывались")
	assert_eq(_states, [TrainerDevice.ConnectionState.RECONNECTING, TrainerDevice.ConnectionState.CONNECTED])
	assert_eq(_trainer.commands.size(), 1, "журнал команд не потерян")
	assert_eq(_trainer.commands[0]["value"], 200)


func test_command_during_dropout_is_logged_and_applied_after_restore() -> void:
	# Исполнитель может повторно отправить цель после `connected` (REQ-DEV-08 крит. 3).
	_connect_now(_trainer)
	_trainer.set_target_power(150)
	_tick_n(_trainer, 2)
	_trainer.inject_dropout(2.0)
	_trainer.set_target_power(260)
	_tick_n(_trainer, 2)
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_trainer.commands.size(), 2)
	assert_almost_eq(float(_trainer.commands[1]["at_sec"]), 2.0, 1e-6)
	_samples = []
	_tick_n(_trainer, 4)
	assert_true(absi(_samples[-1].power_w - 260) <= 13, "цель применена после восстановления: %d" % _samples[-1].power_w)


# ---------------------------------------------------------------------------
# Сценарии данных
# ---------------------------------------------------------------------------

func test_zero_cadence_yields_zero_cadence_and_power_decays_to_zero() -> void:
	_connect_now(_trainer)
	_trainer.set_target_power(200)
	_tick_n(_trainer, 3)
	assert_gt(_samples[-1].cadence_rpm, 70)
	_trainer.set_zero_cadence()
	_samples = []
	_tick_n(_trainer, 10)
	for s in _samples:
		assert_eq(s.cadence_rpm, 0)
		assert_true(s.has_cadence, "ноль — это данные, а не их отсутствие")
	assert_eq(_samples[-1].power_w, 0)
	assert_almost_eq(_samples[-1].speed_kmh, 0.0, 1e-6)


func test_cadence_is_about_85_rpm() -> void:
	_connect_now(_trainer)
	_tick_n(_trainer, 30)
	var total: int = 0
	for s in _samples:
		assert_between(s.cadence_rpm, 82, 88)
		total += s.cadence_rpm
	assert_between(float(total) / _samples.size(), 83.5, 86.5)


func test_speed_reference_point_34_kmh_at_200_w() -> void:
	_connect_now(_trainer)
	_trainer.power_noise_w = 0.0
	_trainer.set_target_power(200)
	_tick_n(_trainer, 15)
	assert_eq(_samples[-1].power_w, 200)
	assert_almost_eq(_samples[-1].speed_kmh, 34.0, 0.5)


func test_packet_loss_drops_part_of_samples_but_keeps_timestamps() -> void:
	_connect_now(_trainer)
	_trainer.inject_packet_loss(0.3)
	_tick_n(_trainer, 200)
	assert_between(_samples.size(), 110, 170, "теряется ~30 %% пакетов, получено %d" % _samples.size())
	assert_eq(_trainer.samples_emitted, _samples.size())
	var prev: float = 0.0
	for s in _samples:
		assert_gt(s.timestamp_sec, prev)
		prev = s.timestamp_sec


func test_inject_silence_pauses_telemetry_while_connected() -> void:
	_connect_now(_trainer)
	_tick_n(_trainer, 2)
	_trainer.inject_silence(5.0)
	_samples = []
	_tick_n(_trainer, 5)
	assert_eq(_samples.size(), 0, "5 с без данных")
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	_tick_n(_trainer, 3)
	assert_eq(_samples.size(), 3)
	assert_almost_eq(_samples[0].timestamp_sec, 8.0, 1e-6)


func test_heart_rate_sequence_is_played_at_1_hz_and_holds_last() -> void:
	_connect_now(_trainer)
	_trainer.set_heart_rate_sequence([120, 125, 130])
	_tick_n(_trainer, 5)
	assert_eq(_heart_rates, [120, 125, 130, 130, 130])
	_trainer.set_heart_rate(0)
	_tick_n(_trainer, 2)
	assert_eq(_heart_rates.size(), 5, "без датчика пульса сигнал не идёт")


func test_cadence_sequence_overrides_model() -> void:
	_connect_now(_trainer)
	_trainer.set_cadence_sequence([90, 95, 0])
	_tick_n(_trainer, 4)
	assert_eq(_samples[0].cadence_rpm, 90)
	assert_eq(_samples[1].cadence_rpm, 95)
	assert_eq(_samples[2].cadence_rpm, 0)
	assert_eq(_samples[3].cadence_rpm, 0)


# ---------------------------------------------------------------------------
# Детерминизм
# ---------------------------------------------------------------------------

func _run_scenario(seed: int) -> Array[TrainerSample]:
	var collected: Array[TrainerSample] = []
	var t := FakeTrainer.new(seed)
	t.telemetry.connect(func(s: TrainerSample) -> void: collected.append(s))
	t.connect_delay_sec = 0.0
	t.connect_device("d")
	t.set_target_power(220)
	t.inject_packet_loss(0.1)
	_tick_n(t, 60)
	t.set_target_power(120)
	_tick_n(t, 60)
	return collected


func test_same_seed_gives_identical_samples() -> void:
	var a := _run_scenario(777)
	var b := _run_scenario(777)
	assert_eq(a.size(), b.size())
	assert_gt(a.size(), 90)
	for i in a.size():
		assert_eq(a[i].timestamp_sec, b[i].timestamp_sec)
		assert_eq(a[i].power_w, b[i].power_w)
		assert_eq(a[i].cadence_rpm, b[i].cadence_rpm)
		assert_eq(a[i].speed_kmh, b[i].speed_kmh)


func test_different_seed_gives_different_noise() -> void:
	var a := _run_scenario(1)
	var b := _run_scenario(2)
	var differs: bool = a.size() != b.size()
	if not differs:
		for i in a.size():
			if a[i].power_w != b[i].power_w or a[i].cadence_rpm != b[i].cadence_rpm:
				differs = true
				break
	assert_true(differs)


# ---------------------------------------------------------------------------
# Фабрика и контракт интерфейса
# ---------------------------------------------------------------------------

func test_factory_creates_fake_and_returns_null_for_ble_for_now() -> void:
	var dev: TrainerDevice = TrainerFactory.create(TrainerFactory.KIND_FAKE)
	assert_not_null(dev)
	assert_true(dev is FakeTrainer)
	assert_true(dev is TrainerDevice)
	assert_eq(dev.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_null(TrainerFactory.create(TrainerFactory.KIND_BLE))


func test_fake_trainer_overrides_every_interface_method() -> void:
	var base_methods: Array[String] = [
		"connect_device", "disconnect_device", "set_target_power",
		"set_erg_enabled", "set_resistance_level", "get_connection_state", "tick",
	]
	var script: Script = FakeTrainer as Script
	var own: Array[String] = []
	for m in script.get_script_method_list():
		own.append(m["name"])
	for name in base_methods:
		assert_has(own, name, "FakeTrainer должен переопределять %s" % name)


func test_trainer_sample_empty_marks_no_data() -> void:
	var s := TrainerSample.empty(5.0)
	assert_eq(s.timestamp_sec, 5.0)
	assert_false(s.has_power)
	assert_false(s.has_cadence)
	assert_false(s.has_speed)
