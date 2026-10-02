extends GutTest
## Независимые приёмочные тесты эмулятора станка (тестировщик, T-001).
## Покрытие: REQ-DEV-09 (все критерии), а также части REQ-DEV-08, REQ-WRK-02,
## REQ-WRK-03, REQ-WRK-04, REQ-WRK-08, REQ-NFR-02, относящиеся к контракту
## устройства/эмулятора. Исполнитель тренировки и UI ещё не написаны — их
## критерии здесь не проверяются.
##
## Семантика границ, заявленная разработчиком (проверяется явно):
## - обрыв длительностью N с, начатый в t, глотает сэмплы t < s ≤ t+N;
## - часы эмулятора при обрыве не сбрасываются;
## - команды во время RECONNECTING логируются и применяются;
## - ERG включён по умолчанию;
## - команда попадает в журнал `commands` как `{type, value, at_sec}`.

const SEED: int = 2026
const DEVICE_ID: String = "fake-acceptance"

var _t: FakeTrainer
var _samples: Array[TrainerSample] = []
var _states: Array[int] = []
var _errors: Array[Dictionary] = []
var _hr: Array[int] = []


func before_each() -> void:
	_samples = []
	_states = []
	_errors = []
	_hr = []
	_t = _new_trainer(SEED)


func _new_trainer(seed: int) -> FakeTrainer:
	var t := FakeTrainer.new(seed)
	t.telemetry.connect(func(s: TrainerSample) -> void: _samples.append(s))
	t.connection_state_changed.connect(func(st: int) -> void: _states.append(st))
	t.error.connect(func(code: int, msg: String) -> void: _errors.append({"code": code, "message": msg}))
	t.heart_rate.connect(func(bpm: int) -> void: _hr.append(bpm))
	return t


## Подключение без задержки; очищает собранные сэмплы и состояния.
func _connect(t: FakeTrainer) -> void:
	t.connect_delay_sec = 0.0
	t.connect_device(DEVICE_ID)
	assert_eq(t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "предусловие: подключён")
	_samples = []
	_states = []


func _ticks(t: FakeTrainer, n: int, delta: float = 1.0) -> void:
	for i in n:
		t.tick(delta)


func _timestamps() -> Array[float]:
	var out: Array[float] = []
	for s in _samples:
		out.append(s.timestamp_sec)
	return out


func _last_power() -> int:
	return _samples[-1].power_w


# ===========================================================================
# REQ-DEV-09 крит. 1 — FakeTrainer реализует TrainerDevice целиком;
# переключение реализации только в src/devices/
# ===========================================================================

func test_req_dev_09_c1_fake_overrides_every_nonstatic_interface_method() -> void:
	var base: Script = TrainerDevice as Script
	var fake: Script = FakeTrainer as Script
	var own: Array[String] = []
	for m in fake.get_script_method_list():
		own.append(m["name"])
	var checked: int = 0
	for m in base.get_script_method_list():
		if m["flags"] & METHOD_FLAG_STATIC:
			continue
		if String(m["name"]).begins_with("_"):
			continue
		checked += 1
		assert_has(own, m["name"], "FakeTrainer не переопределяет %s" % m["name"])
	assert_gte(checked, 7, "в интерфейсе ожидается не меньше 7 публичных методов")


func test_req_dev_09_c1_fake_exposes_interface_signals_and_is_trainer_device() -> void:
	var dev: TrainerDevice = TrainerFactory.create(TrainerFactory.KIND_FAKE)
	assert_not_null(dev)
	assert_true(dev is TrainerDevice)
	for sig in ["connection_state_changed", "telemetry", "heart_rate", "error"]:
		assert_true(dev.has_signal(sig), "нет сигнала %s" % sig)
	assert_eq(dev.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_eq(TrainerDevice.state_name(dev.get_connection_state()), "disconnected")


func test_req_dev_09_c1_factory_rejects_unknown_kind_and_ble_not_ready() -> void:
	assert_null(TrainerFactory.create(TrainerFactory.KIND_BLE), "BLE на этапе 1 недоступен")
	assert_null(TrainerFactory.create("rowing-machine"), "неизвестная реализация → null")
	assert_push_error("неизвестная реализация", "фабрика сообщает об ошибке через push_error")


func test_req_dev_09_c1_implementation_choice_lives_only_in_src_devices() -> void:
	var offenders: Array[String] = []
	_scan_for_impl_refs("res://src", offenders)
	assert_eq(offenders, [], "упоминания FakeTrainer/BleTrainer вне src/devices/: %s" % str(offenders))


func _scan_for_impl_refs(dir_path: String, offenders: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var full: String = dir_path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				_scan_for_impl_refs(full, offenders)
		elif name.ends_with(".gd") and not full.begins_with("res://src/devices/"):
			var text: String = FileAccess.get_file_as_string(full)
			if text.contains("FakeTrainer") or text.contains("BleTrainer"):
				offenders.append(full)
		name = dir.get_next()
	dir.list_dir_end()


# ===========================================================================
# REQ-DEV-09 крит. 2 — ERG: через 3 с после команды |P − цель| ≤ 5 % цели
# ===========================================================================

func test_req_dev_09_c2_power_converges_within_3s_for_step_150_to_250() -> void:
	_connect(_t)
	_t.set_rider_power(150)
	_ticks(_t, 3)
	_t.set_target_power(250)
	_samples = []
	_ticks(_t, 3)
	var p: int = _last_power()
	assert_true(absi(p - 250) <= 12, "через 3 с |P−250| ≤ 12.5, факт P=%d" % p)


func test_req_dev_09_c2_command_at_fractional_time_converges_by_t_plus_3() -> void:
	_connect(_t)
	_ticks(_t, 2)
	_t.tick(0.3) # t = 2.3
	_t.set_target_power(200)
	_samples = []
	_t.tick(3.0) # t = 5.3 → сэмплы 3, 4, 5
	assert_eq(_samples.size(), 3)
	var p: int = _last_power()
	assert_true(absi(p - 200) <= 10, "через 3 с (сэмпл 5) |P−200| ≤ 10, факт P=%d" % p)


func test_req_dev_09_c2_holds_target_after_convergence_for_60s() -> void:
	_connect(_t)
	_t.set_target_power(300)
	_ticks(_t, 3)
	_samples = []
	_ticks(_t, 60)
	for s in _samples:
		assert_true(absi(s.power_w - 300) <= 15, "удержание 300 Вт: t=%.0f P=%d" % [s.timestamp_sec, s.power_w])


func test_req_dev_09_c2_converges_for_realistic_plan_transitions_default_model() -> void:
	# Переходы, встречающиеся в реальных планах (FTP 200): разминка, VO2, спринт, восстановление.
	var sequence: Array[int] = [150, 250, 130, 300, 60, 240, 50, 400, 100, 2000, 100]
	_connect(_t)
	_t.set_rider_power(150)
	_ticks(_t, 5)
	var violations: Array[String] = []
	var previous: int = 150
	for target in sequence:
		_t.set_target_power(target)
		_samples = []
		_ticks(_t, 3)
		var p: int = _last_power()
		var allowed: float = 0.05 * float(target)
		if absf(float(p - target)) > allowed:
			violations.append("%d→%d Вт: через 3 с P=%d, |Δ|=%d > %.1f" % [previous, target, p, absi(p - target), allowed])
		_ticks(_t, 10) # дать модели устояться перед следующим переходом
		previous = target
	assert_eq(violations, [], "нарушения критерия 2: %s" % "; ".join(violations))


func test_req_dev_09_c2_converges_without_noise_from_400_to_50() -> void:
	# Без шума — проверяется только постоянная времени модели по умолчанию.
	_connect(_t)
	_t.power_noise_w = 0.0
	_t.set_target_power(400)
	_ticks(_t, 15)
	assert_eq(_last_power(), 400, "предусловие: устоялся на 400 Вт")
	_t.set_target_power(50)
	_samples = []
	_ticks(_t, 3)
	var p: int = _last_power()
	assert_true(absi(p - 50) <= 2, "400→50 Вт без шума: через 3 с |P−50| ≤ 2.5, факт P=%d" % p)


func test_req_dev_09_c2_target_0_in_erg_means_free_ride_power_follows_rider() -> void:
	_connect(_t)
	_t.set_rider_power(120)
	_t.set_target_power(0)
	_ticks(_t, 10)
	assert_true(absi(_last_power() - 120) <= 6, "цель 0 = FreeRide, P→мощность всадника, факт %d" % _last_power())


# ===========================================================================
# REQ-DEV-09 крит. 3 — сценарии
# ===========================================================================

func test_req_dev_09_c3_constant_power_scenario_is_exact_without_noise() -> void:
	_connect(_t)
	_t.power_noise_w = 0.0
	_t.set_target_power(200)
	_ticks(_t, 10)
	_samples = []
	_ticks(_t, 30)
	for s in _samples:
		assert_eq(s.power_w, 200, "постоянная мощность t=%.0f" % s.timestamp_sec)


func test_req_dev_09_c3_surge_scenario_outside_erg_follows_rider_power_up_and_down() -> void:
	_connect(_t)
	_t.set_erg_enabled(false)
	_t.set_rider_power(150)
	_ticks(_t, 10)
	_t.set_rider_power(450) # рывок
	_samples = []
	_ticks(_t, 4)
	assert_gt(_last_power(), 400, "после рывка мощность растёт: %d" % _last_power())
	_t.set_rider_power(150)
	_samples = []
	_ticks(_t, 4)
	assert_lt(_last_power(), 180, "после рывка мощность возвращается: %d" % _last_power())


func test_req_dev_09_c3_surge_scenario_in_erg_via_target_jump_is_tracked() -> void:
	_connect(_t)
	_t.set_target_power(150)
	_ticks(_t, 5)
	_t.set_target_power(500)
	_samples = []
	_ticks(_t, 3)
	assert_true(absi(_last_power() - 500) <= 25, "рывок цели до 500 Вт: %d" % _last_power())


func test_req_dev_09_c3_zero_cadence_is_data_not_absence_and_power_decays() -> void:
	_connect(_t)
	_t.set_target_power(200)
	_ticks(_t, 5)
	_t.set_zero_cadence()
	_samples = []
	_ticks(_t, 10)
	assert_eq(_samples.size(), 10)
	for s in _samples:
		assert_true(s.has_cadence, "каденс 0 — это данные")
		assert_eq(s.cadence_rpm, 0)
		assert_true(s.has_power)
	assert_eq(_last_power(), 0, "без педалирования мощность → 0")
	assert_eq(_samples[-1].speed_kmh, 0.0)
	_t.set_rider_cadence(90)
	_samples = []
	_ticks(_t, 5)
	assert_gt(_samples[-1].cadence_rpm, 80, "педалирование возобновилось")
	assert_gt(_last_power(), 150, "мощность возвращается к цели: %d" % _last_power())


func test_req_dev_09_c3_packet_loss_n_seconds_without_data_keeps_connected() -> void:
	_connect(_t)
	_ticks(_t, 3)
	_t.inject_silence(4.0) # t=3 → без данных сэмплы 4..7
	_samples = []
	_states = []
	_ticks(_t, 4)
	assert_eq(_samples.size(), 0, "4 с без данных")
	assert_eq(_states, [], "состояние не менялось — это пропуск пакетов, не обрыв")
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	_ticks(_t, 1)
	assert_eq(_timestamps(), [8.0], "первый сэмпл после тишины — t=8")


func test_req_dev_09_c3_silence_at_fractional_time_swallows_t_lt_s_le_t_plus_n() -> void:
	_connect(_t)
	_ticks(_t, 2)
	_t.tick(0.5) # t = 2.5
	_t.inject_silence(1.0) # до 3.5 → глотает только сэмпл 3
	_samples = []
	_t.tick(2.5) # t = 5.0
	assert_eq(_timestamps(), [4.0, 5.0])


func test_req_dev_09_c3_dropout_and_restore_scenario() -> void:
	_connect(_t)
	_ticks(_t, 2)
	_t.inject_dropout(3.0) # t=2 → глотает 3,4,5
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING)
	_samples = []
	_ticks(_t, 3)
	assert_eq(_samples.size(), 0)
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "на t=5 уже восстановлен")
	_ticks(_t, 2)
	assert_eq(_timestamps(), [6.0, 7.0])
	assert_eq(_states, [TrainerDevice.ConnectionState.RECONNECTING, TrainerDevice.ConnectionState.CONNECTED])


func test_req_dev_09_c3_control_point_error_for_each_command_type() -> void:
	_connect(_t)
	_t.set_target_power(100)
	_t.set_resistance_level(10)
	# target_power
	_t.fail_next_command()
	_t.set_target_power(200)
	assert_eq(_errors.size(), 1)
	assert_eq(_errors[0]["code"], TrainerDevice.ErrorCode.CONTROL_POINT_REJECTED)
	assert_eq(_t.target_power_w, 100, "отвергнутая цель не применена")
	# erg
	_t.fail_next_command()
	_t.set_erg_enabled(false)
	assert_eq(_errors.size(), 2)
	assert_true(_t.erg_enabled, "отвергнутое выключение ERG не применено")
	# resistance
	_t.fail_next_command()
	_t.set_resistance_level(50)
	assert_eq(_errors.size(), 3)
	assert_eq(_t.resistance_percent, 10, "отвергнутое сопротивление не применено")
	assert_eq(_t.commands.size(), 5, "все пять команд в журнале, включая отвергнутые")
	# следующая без сбоя проходит
	_t.set_target_power(220)
	assert_eq(_errors.size(), 3)
	assert_eq(_t.target_power_w, 220)


func test_req_dev_09_c3_connection_failure_scenario_with_delay() -> void:
	_t.fail_next_connect()
	_t.connect_delay_sec = 0.5
	_t.connect_device("ghost")
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTING)
	_t.tick(0.4)
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTING)
	assert_eq(_errors.size(), 0)
	_t.tick(0.1)
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_eq(_errors.size(), 1)
	assert_eq(_errors[0]["code"], TrainerDevice.ErrorCode.CONNECTION_FAILED)
	assert_eq(_states, [TrainerDevice.ConnectionState.CONNECTING, TrainerDevice.ConnectionState.DISCONNECTED])
	# повторная попытка проходит
	_t.connect_device("ghost")
	_t.tick(0.5)
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)


func test_req_dev_09_c3_connection_failure_with_zero_delay_is_immediate() -> void:
	_t.fail_next_connect()
	_t.connect_delay_sec = 0.0
	_t.connect_device("ghost")
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_eq(_errors.size(), 1)
	_ticks(_t, 5)
	assert_eq(_samples.size(), 0)


# ===========================================================================
# REQ-DEV-09 крит. 4 — время управляется извне (инъекция часов)
# ===========================================================================

func test_req_dev_09_c4_clock_is_sum_of_ticks_and_nothing_happens_without_tick() -> void:
	_connect(_t)
	assert_eq(_t.get_time_sec(), 0.0)
	_t.tick(0.25)
	_t.tick(0.5)
	_t.tick(2.0)
	assert_almost_eq(_t.get_time_sec(), 2.75, 1e-9)
	assert_eq(_timestamps(), [1.0, 2.0])
	# без тиков часы и телеметрия не двигаются
	assert_almost_eq(_t.get_time_sec(), 2.75, 1e-9)
	assert_eq(_samples.size(), 2)


func test_req_dev_09_c4_zero_and_negative_tick_are_ignored() -> void:
	_connect(_t)
	_t.tick(0.0)
	_t.tick(-1.0)
	assert_eq(_t.get_time_sec(), 0.0)
	assert_eq(_samples.size(), 0)
	_t.tick(1.0)
	assert_eq(_timestamps(), [1.0])


func test_req_dev_09_c4_one_hour_simulated_in_single_tick() -> void:
	_connect(_t)
	_t.tick(3600.0)
	assert_eq(_samples.size(), 3600)
	assert_eq(_samples[0].timestamp_sec, 1.0)
	assert_eq(_samples[-1].timestamp_sec, 3600.0)
	assert_eq(_t.samples_emitted, 3600)


# ===========================================================================
# REQ-DEV-09 крит. 5 — симуляторы пульса и каденса, 1 Гц
# ===========================================================================

func test_req_dev_09_c5_heart_rate_sequence_at_1hz_with_fractional_ticks() -> void:
	_connect(_t)
	_t.set_heart_rate_sequence([110, 120, 130, 140])
	_ticks(_t, 60, 0.1) # 6 с
	assert_eq(_hr, [110, 120, 130, 140, 140, 140], "ровно одно значение в секунду, последнее удерживается")


func test_req_dev_09_c5_heart_rate_constant_and_off() -> void:
	_connect(_t)
	_t.set_heart_rate(145)
	_ticks(_t, 3)
	assert_eq(_hr, [145, 145, 145])
	_t.set_heart_rate(0)
	_ticks(_t, 3)
	assert_eq(_hr.size(), 3, "0 выключает пульс")
	_t.set_heart_rate(-20)
	_ticks(_t, 3)
	assert_eq(_hr.size(), 3, "отрицательное значение не включает пульс")


func test_req_dev_09_c5_no_heart_rate_before_connect_and_sequence_starts_at_first_sample() -> void:
	_t.set_heart_rate_sequence([100, 101, 102])
	_ticks(_t, 3)
	assert_eq(_hr, [], "до подключения датчик не играет")
	_connect(_t)
	_ticks(_t, 2)
	assert_eq(_hr, [100, 101])


func test_req_dev_09_c5_cadence_sequence_at_1hz_and_holds_last() -> void:
	_connect(_t)
	_t.set_cadence_sequence([80, 85, 90, 0, 95])
	_ticks(_t, 70, 0.1) # 7 с
	var cad: Array[int] = []
	for s in _samples:
		cad.append(s.cadence_rpm)
	assert_eq(cad, [80, 85, 90, 0, 95, 95, 95])
	assert_true(_samples[3].has_cadence)


func test_req_dev_09_c5_cadence_sequence_reset_by_set_rider_cadence_and_by_empty() -> void:
	_connect(_t)
	_t.set_cadence_sequence([50])
	_ticks(_t, 2)
	assert_eq(_samples[-1].cadence_rpm, 50)
	_t.set_rider_cadence(95)
	_ticks(_t, 2)
	assert_between(_samples[-1].cadence_rpm, 92, 98, "возврат к модели всадника")
	_t.set_cadence_sequence([60])
	_ticks(_t, 1)
	assert_eq(_samples[-1].cadence_rpm, 60)
	_t.set_cadence_sequence([])
	_ticks(_t, 1)
	assert_between(_samples[-1].cadence_rpm, 92, 98, "пустая последовательность — снова модель")


func test_req_dev_09_c5_heart_rate_tied_to_packet_stream_during_silence() -> void:
	# Пульс идёт в одном потоке с телеметрией: при тишине он тоже не приходит.
	_connect(_t)
	_t.set_heart_rate(130)
	_ticks(_t, 2)
	_t.inject_silence(2.0)
	_ticks(_t, 2)
	assert_eq(_hr.size(), 2, "во время тишины пульс не приходит")
	_ticks(_t, 1)
	assert_eq(_hr.size(), 3)


# ===========================================================================
# REQ-DEV-09 крит. 6 — доступен в приложении (запуск сессии) — n/a без исполнителя,
# проверяется только, что фабрика отдаёт готовый к работе эмулятор.
# ===========================================================================

func test_req_dev_09_c6_factory_fake_trainer_plays_600s_of_telemetry() -> void:
	var dev: TrainerDevice = TrainerFactory.create(TrainerFactory.KIND_FAKE)
	var count: Array[int] = [0] # массив — лямбда захватывает локальные значения копией
	dev.telemetry.connect(func(_s: TrainerSample) -> void: count[0] += 1)
	dev.connect_device("dev-mode")
	dev.tick(1.0) # задержка по умолчанию 0.5 с → подключён
	assert_eq(dev.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	dev.set_target_power(180)
	for i in 599:
		dev.tick(1.0)
	assert_eq(count[0], 600)


# ===========================================================================
# REQ-WRK-08 крит. 1 / REQ-NFR-02 крит. 1, 2 — поток 1 Гц, независимость от кадров
# ===========================================================================

func test_req_wrk_08_c1_600s_in_0_1s_ticks_gives_exactly_600_monotonic_samples() -> void:
	_connect(_t)
	_ticks(_t, 6000, 0.1)
	assert_eq(_samples.size(), 600)
	for i in _samples.size():
		assert_eq(_samples[i].timestamp_sec, float(i + 1), "метка сэмпла %d" % i)
	assert_almost_eq(_t.get_time_sec(), 600.0, 1e-6)


func test_req_wrk_08_c1_600s_in_frame_sized_ticks_1_60s_gives_600_samples() -> void:
	_connect(_t)
	_ticks(_t, 36000, 1.0 / 60.0)
	assert_eq(_samples.size(), 600)
	assert_eq(_samples[-1].timestamp_sec, 600.0)


func test_req_wrk_08_c1_irregular_ticks_never_duplicate_or_skip_seconds() -> void:
	_connect(_t)
	var deltas: Array[float] = [0.3, 0.7, 1.0, 0.05, 0.95, 2.5, 0.5, 0.001, 0.999, 3.0]
	var total: float = 0.0
	for d in deltas:
		_t.tick(d)
		total += d
	assert_almost_eq(total, 10.0, 1e-9)
	assert_eq(_timestamps(), [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0])


func test_req_wrk_08_c2_sample_has_time_power_cadence_speed_with_flags() -> void:
	_connect(_t)
	_t.set_target_power(200)
	_ticks(_t, 5)
	var s: TrainerSample = _samples[-1]
	assert_eq(s.timestamp_sec, 5.0)
	assert_true(s.has_power and s.has_cadence and s.has_speed)
	assert_gt(s.power_w, 0)
	assert_gt(s.cadence_rpm, 0)
	assert_gt(s.speed_kmh, 0.0)
	# «нет данных» — отдельный конструктор, флаги false
	var e := TrainerSample.empty(6.0)
	assert_eq(e.timestamp_sec, 6.0)
	assert_false(e.has_power or e.has_cadence or e.has_speed)
	assert_true(e._to_string().contains("-"))


func test_req_wrk_08_c5_speed_comes_from_trainer_and_grows_with_power() -> void:
	_connect(_t)
	_t.power_noise_w = 0.0
	_t.set_target_power(100)
	_ticks(_t, 15)
	var v100: float = _samples[-1].speed_kmh
	_t.set_target_power(300)
	_ticks(_t, 15)
	var v300: float = _samples[-1].speed_kmh
	assert_eq(_samples[-1].power_w, 300)
	assert_gt(v300, v100)
	assert_almost_eq(v100, 26.0, 3.0, "опорная точка 100 Вт ≈ 26 ± 3 км/ч")
	assert_almost_eq(v300, 40.0, 3.0, "опорная точка 300 Вт ≈ 40 ± 3 км/ч")


func test_req_nfr_02_c1_60_ticks_give_60_samples_without_process() -> void:
	_connect(_t)
	_ticks(_t, 60)
	assert_eq(_samples.size(), 60)
	assert_eq(_samples[-1].timestamp_sec, 60.0)


func test_req_nfr_02_c2_frame_freeze_of_2s_emits_missed_samples_postfactum_in_order() -> void:
	_connect(_t)
	_ticks(_t, 3)
	_t.tick(2.0) # заморозка кадра 2 с
	assert_eq(_timestamps(), [1.0, 2.0, 3.0, 4.0, 5.0])
	_t.tick(2.6) # t = 7.6
	assert_eq(_timestamps(), [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0])
	_t.tick(0.4) # t = 8.0
	assert_eq(_samples[-1].timestamp_sec, 8.0)


# ===========================================================================
# REQ-WRK-02 крит. 1, 2 (сторона устройства) — Set Target Power с меткой времени
# ===========================================================================

func test_req_wrk_02_c1_target_power_accepted_as_is_and_logged() -> void:
	_connect(_t)
	_t.set_target_power(130)
	assert_eq(_t.target_power_w, 130)
	assert_eq(_t.commands.size(), 1)
	var c: Dictionary = _t.commands[0]
	assert_eq(c.keys().size(), 3)
	assert_true(c.has("type") and c.has("value") and c.has("at_sec"))
	assert_eq(c["type"], FakeTrainer.CMD_TARGET_POWER)
	assert_eq(c["value"], 130)
	assert_eq(c["at_sec"], 0.0)


func test_req_wrk_02_c2_command_timestamp_equals_emulator_clock_at_call() -> void:
	_connect(_t)
	_t.tick(1.0)
	_t.tick(0.75)
	_t.set_target_power(200)
	_t.tick(3.0)
	_t.set_target_power(210)
	assert_eq(_t.commands.size(), 2)
	assert_almost_eq(float(_t.commands[0]["at_sec"]), 1.75, 1e-9)
	assert_almost_eq(float(_t.commands[1]["at_sec"]), 4.75, 1e-9)
	assert_true(float(_t.commands[1]["at_sec"]) > float(_t.commands[0]["at_sec"]), "журнал в порядке вызова")


func test_req_wrk_02_c1_negative_target_power_is_clamped_to_min_and_logged_clamped() -> void:
	_connect(_t)
	_t.set_target_power(150)
	_t.set_target_power(-50)
	assert_eq(_t.target_power_w, TrainerDevice.MIN_TARGET_POWER_W)
	assert_eq(_t.commands[-1]["value"], TrainerDevice.MIN_TARGET_POWER_W)
	assert_eq(_errors.size(), 0, "обрезка — не ошибка Control Point")
	assert_push_warning("вне диапазона", "обрезка сопровождается предупреждением в лог")


func test_req_wrk_02_c1_target_power_above_max_is_clamped_and_boundaries_accepted() -> void:
	_connect(_t)
	_t.set_target_power(TrainerDevice.MAX_TARGET_POWER_W + 1)
	assert_eq(_t.target_power_w, TrainerDevice.MAX_TARGET_POWER_W)
	_t.set_target_power(TrainerDevice.MAX_TARGET_POWER_W)
	assert_eq(_t.target_power_w, TrainerDevice.MAX_TARGET_POWER_W)
	_t.set_target_power(TrainerDevice.MIN_TARGET_POWER_W)
	assert_eq(_t.target_power_w, TrainerDevice.MIN_TARGET_POWER_W)
	_t.set_target_power(1)
	assert_eq(_t.target_power_w, 1)
	assert_eq(_errors.size(), 0)


# ===========================================================================
# REQ-WRK-03 (сторона устройства) — переключение ERG
# ===========================================================================

func test_req_wrk_03_c5_erg_enabled_by_default_before_and_after_connect() -> void:
	assert_true(_t.erg_enabled, "до подключения")
	_connect(_t)
	assert_true(_t.erg_enabled, "после подключения")
	assert_eq(_t.commands.size(), 0, "включение по умолчанию не является командой")


func test_req_wrk_03_c2_erg_off_mid_interval_switches_to_rider_power_and_logs() -> void:
	_connect(_t)
	_t.set_rider_power(110)
	_t.set_target_power(250)
	_ticks(_t, 5)
	_t.tick(0.5) # «посреди интервала», t = 5.5
	_t.set_erg_enabled(false)
	_t.set_resistance_level(30)
	assert_eq(_t.commands[-2]["type"], FakeTrainer.CMD_ERG)
	assert_eq(_t.commands[-2]["value"], false)
	assert_eq(_t.commands[-1]["type"], FakeTrainer.CMD_RESISTANCE)
	assert_almost_eq(float(_t.commands[-1]["at_sec"]), 5.5, 1e-9)
	_samples = []
	_ticks(_t, 5)
	assert_true(absi(_last_power() - 110) <= 6, "вне ERG P→всадник (110), факт %d" % _last_power())
	assert_eq(_t.target_power_w, 250, "цель сохранена для повторного включения")


func test_req_wrk_03_c3_erg_on_mid_interval_applies_stored_target() -> void:
	_connect(_t)
	_t.set_erg_enabled(false)
	_t.set_rider_power(100)
	_t.set_target_power(220)
	_ticks(_t, 5)
	assert_true(absi(_last_power() - 100) <= 6)
	_t.set_erg_enabled(true)
	_samples = []
	_ticks(_t, 3)
	assert_true(absi(_last_power() - 220) <= 11, "через 3 с после включения ERG |P−220| ≤ 11, факт %d" % _last_power())


func test_req_wrk_03_c4_toggling_erg_does_not_interrupt_telemetry_stream() -> void:
	_connect(_t)
	_t.set_target_power(200)
	_ticks(_t, 3)
	_t.set_erg_enabled(false)
	_ticks(_t, 3)
	_t.set_erg_enabled(true)
	_ticks(_t, 3)
	_t.set_erg_enabled(false)
	_t.set_erg_enabled(true)
	_ticks(_t, 1)
	assert_eq(_timestamps(), [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0])
	assert_eq(_states, [], "переключение ERG не меняет состояние подключения")


func test_req_wrk_03_repeated_same_value_is_still_logged_as_command() -> void:
	_connect(_t)
	_t.set_erg_enabled(true)
	_t.set_erg_enabled(true)
	assert_eq(_t.commands.size(), 2, "журнал отражает каждый вызов, дедупликация — забота исполнителя")


# ===========================================================================
# REQ-WRK-04 (сторона устройства) — уровень сопротивления
# ===========================================================================

func test_req_wrk_04_c1_resistance_boundaries_0_and_100_accepted() -> void:
	_connect(_t)
	_t.set_resistance_level(0)
	assert_eq(_t.resistance_percent, 0)
	_t.set_resistance_level(100)
	assert_eq(_t.resistance_percent, 100)
	_t.set_resistance_level(55)
	assert_eq(_t.resistance_percent, 55)
	assert_eq(_errors.size(), 0)


func test_req_wrk_04_c1_resistance_out_of_range_is_clamped() -> void:
	_connect(_t)
	_t.set_resistance_level(50)
	_t.set_resistance_level(101)
	assert_eq(_t.resistance_percent, 100)
	assert_eq(_t.commands[-1]["value"], 100)
	_t.set_resistance_level(-1)
	assert_eq(_t.resistance_percent, 0)
	assert_eq(_t.commands[-1]["value"], 0)
	_t.set_resistance_level(1000)
	assert_eq(_t.resistance_percent, 100)
	assert_eq(_errors.size(), 0, "обрезка — не ошибка Control Point")


func test_req_wrk_04_c3_resistance_set_while_erg_on_is_stored_and_does_not_affect_erg_power() -> void:
	_connect(_t)
	_t.set_target_power(200)
	_ticks(_t, 5)
	_t.set_resistance_level(80)
	assert_eq(_t.resistance_percent, 80, "значение сохранено")
	assert_true(_t.erg_enabled)
	_samples = []
	_ticks(_t, 5)
	assert_true(absi(_last_power() - 200) <= 10, "ERG продолжает держать цель: %d" % _last_power())
	_t.set_erg_enabled(false)
	assert_eq(_t.resistance_percent, 80, "после выключения ERG уровень доступен")


# ===========================================================================
# REQ-DEV-08 (сторона устройства) — обрыв и восстановление
# ===========================================================================

func test_req_dev_08_c1_dropout_moves_to_reconnecting_and_signal_emitted_once() -> void:
	_connect(_t)
	_ticks(_t, 2)
	_t.inject_dropout(5.0)
	assert_eq(_states, [TrainerDevice.ConnectionState.RECONNECTING])
	assert_eq(TrainerDevice.state_name(_t.get_connection_state()), "reconnecting")
	_ticks(_t, 5)
	assert_eq(_states, [TrainerDevice.ConnectionState.RECONNECTING, TrainerDevice.ConnectionState.CONNECTED])


func test_req_dev_08_c1_connect_device_during_reconnecting_is_harmless_noop() -> void:
	# Исполнитель может дёргать connect каждые 5 с; эмулятор не должен ломаться.
	_connect(_t)
	_ticks(_t, 1)
	_t.inject_dropout(12.0)
	_states = []
	for i in 2:
		_ticks(_t, 5)
		_t.connect_device("other-id")
		assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING)
	assert_eq(_t.device_id, DEVICE_ID, "id устройства не подменяется во время переподключения")
	assert_eq(_states, [], "лишних переходов нет")
	_ticks(_t, 3)
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_states, [TrainerDevice.ConnectionState.CONNECTED])


func test_req_dev_08_c2_clock_not_reset_by_dropout_and_timestamps_continue() -> void:
	_connect(_t)
	_ticks(_t, 10)
	_t.inject_dropout(3.0)
	_ticks(_t, 3)
	assert_almost_eq(_t.get_time_sec(), 13.0, 1e-9)
	_samples = []
	_ticks(_t, 2)
	assert_eq(_timestamps(), [14.0, 15.0], "после восстановления метки продолжают ряд, а не начинаются с 1")


func test_req_dev_08_c2_boundary_dropout_started_on_integer_second_swallows_t_lt_s_le_t_plus_n() -> void:
	_connect(_t)
	_ticks(_t, 3) # t = 3.0, сэмпл 3 уже выдан
	_t.inject_dropout(1.0) # глотает только сэмпл 4
	_samples = []
	_ticks(_t, 2)
	assert_eq(_timestamps(), [5.0])


func test_req_dev_08_c2_boundary_dropout_started_at_fractional_second() -> void:
	_connect(_t)
	_ticks(_t, 3)
	_t.tick(0.5) # t = 3.5
	_t.inject_dropout(2.0) # до 5.5 → глотает 4, 5
	_samples = []
	_t.tick(0.5) # 4.0
	_t.tick(1.0) # 5.0
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING)
	_t.tick(0.5) # 5.5 → восстановление ровно в 5.5
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	_t.tick(0.5) # 6.0
	assert_eq(_timestamps(), [6.0])


func test_req_dev_08_c2_dropout_shorter_than_a_second_swallows_nothing_if_no_boundary_inside() -> void:
	_connect(_t)
	_ticks(_t, 2) # t = 2.0
	_t.inject_dropout(0.5) # до 2.5: ни одного целого s в (2, 2.5]
	_samples = []
	_ticks(_t, 2)
	assert_eq(_timestamps(), [3.0, 4.0])


func test_req_dev_08_c2_zero_length_dropout_restores_immediately() -> void:
	_connect(_t)
	_ticks(_t, 1)
	_t.inject_dropout(0.0)
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_states, [TrainerDevice.ConnectionState.RECONNECTING, TrainerDevice.ConnectionState.CONNECTED])
	_ticks(_t, 1)
	assert_eq(_timestamps(), [1.0, 2.0])


func test_req_dev_08_c2_dropout_crossing_a_large_tick_emits_only_post_restore_samples() -> void:
	_connect(_t)
	_ticks(_t, 2)
	_t.inject_dropout(3.0) # глотает 3,4,5
	_samples = []
	_t.tick(6.0) # t = 8
	assert_eq(_timestamps(), [6.0, 7.0, 8.0])


func test_req_dev_08_c2_two_sequential_dropouts_each_swallow_their_window() -> void:
	_connect(_t)
	_ticks(_t, 2)
	_t.inject_dropout(2.0) # 3,4
	_ticks(_t, 2)
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	_ticks(_t, 1) # сэмпл 5
	_t.inject_dropout(1.0) # 6
	_ticks(_t, 2) # 7
	assert_eq(_timestamps(), [1.0, 2.0, 5.0, 7.0])
	assert_eq(_states, [
		TrainerDevice.ConnectionState.RECONNECTING, TrainerDevice.ConnectionState.CONNECTED,
		TrainerDevice.ConnectionState.RECONNECTING, TrainerDevice.ConnectionState.CONNECTED,
	])


func test_req_dev_08_c2_dropout_during_dropout_is_ignored_and_does_not_shorten_or_extend() -> void:
	_connect(_t)
	_ticks(_t, 1)
	_t.inject_dropout(4.0) # до 5
	_ticks(_t, 1)
	_t.inject_dropout(1.0) # игнорируется (не CONNECTED)
	_ticks(_t, 2) # t = 4
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING, "второй обрыв не укоротил первый")
	_ticks(_t, 1) # t = 5
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "и не удлинил")
	_ticks(_t, 1)
	assert_eq(_timestamps(), [1.0, 6.0])


func test_req_dev_08_c2_dropout_when_not_connected_is_ignored() -> void:
	_t.inject_dropout(3.0)
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_eq(_states, [])
	_t.connect_delay_sec = 1.0
	_t.connect_device(DEVICE_ID)
	_t.inject_dropout(3.0) # в CONNECTING тоже игнорируется
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTING)
	_t.tick(1.0)
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)


func test_req_dev_08_c3_command_during_reconnecting_is_logged_with_timestamp_and_applied() -> void:
	_connect(_t)
	_t.set_target_power(150)
	_ticks(_t, 2)
	_t.inject_dropout(3.0)
	_t.tick(1.0) # t = 3
	_t.set_target_power(280)
	_t.set_erg_enabled(false)
	_t.set_erg_enabled(true)
	_t.set_resistance_level(20)
	assert_eq(_t.commands.size(), 5)
	for c in _t.commands.slice(1):
		assert_almost_eq(float(c["at_sec"]), 3.0, 1e-9)
	assert_eq(_t.target_power_w, 280)
	assert_eq(_t.resistance_percent, 20)
	assert_eq(_errors.size(), 0, "во время RECONNECTING команды не отвергаются")
	_ticks(_t, 2) # восстановление на t=5
	_samples = []
	_ticks(_t, 3)
	assert_true(absi(_last_power() - 280) <= 14, "цель применена после восстановления: %d" % _last_power())


func test_req_dev_08_c3_resend_inside_connected_handler_gets_restore_timestamp() -> void:
	# Исполнитель повторно шлёт цель прямо из обработчика connected — метка = момент восстановления.
	_connect(_t)
	_t.set_target_power(200)
	_ticks(_t, 2)
	_t.connection_state_changed.connect(func(st: int) -> void:
		if st == TrainerDevice.ConnectionState.CONNECTED:
			_t.set_target_power(_t.target_power_w))
	_t.inject_dropout(2.5) # до 4.5
	_t.tick(2.0) # 4.0
	assert_eq(_t.commands.size(), 1)
	_t.tick(0.5) # 4.5 — восстановление
	assert_eq(_t.commands.size(), 2)
	assert_almost_eq(float(_t.commands[1]["at_sec"]), 4.5, 1e-9)
	assert_true(float(_t.commands[1]["at_sec"]) - 4.5 <= 1.0, "повтор не позже 1 с после connected")


func test_req_dev_08_disconnect_during_reconnecting_cancels_restore() -> void:
	_connect(_t)
	_ticks(_t, 1)
	_samples = []
	_t.inject_dropout(2.0)
	_t.disconnect_device()
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	_ticks(_t, 10)
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED, "таймер обрыва не воскрешает соединение")
	assert_eq(_samples.size(), 0)
	# явное переподключение работает
	_t.connect_device(DEVICE_ID)
	_ticks(_t, 1)
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_timestamps(), [12.0])


func test_req_dev_08_disconnect_during_connecting_cancels_connect() -> void:
	_t.connect_delay_sec = 1.0
	_t.connect_device(DEVICE_ID)
	_t.disconnect_device()
	_ticks(_t, 3)
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_eq(_samples.size(), 0)


func test_req_dev_08_repeated_connect_while_connected_is_noop() -> void:
	_connect(_t)
	_ticks(_t, 1)
	_t.connect_device("another")
	assert_eq(_t.device_id, DEVICE_ID)
	assert_eq(_states, [])
	_ticks(_t, 1)
	assert_eq(_timestamps(), [1.0, 2.0])


func test_req_dev_08_disconnect_when_already_disconnected_emits_nothing() -> void:
	_t.disconnect_device()
	assert_eq(_states, [])
	assert_eq(_errors.size(), 0)


# ===========================================================================
# Пропуск пакетов — граничные доли
# ===========================================================================

func test_req_dev_09_c3_packet_loss_ratio_0_loses_nothing() -> void:
	_connect(_t)
	_t.inject_packet_loss(0.0)
	_ticks(_t, 100)
	assert_eq(_samples.size(), 100)
	assert_eq(_t.samples_emitted, 100)


func test_req_dev_09_c3_packet_loss_ratio_1_loses_everything_but_stays_connected() -> void:
	_connect(_t)
	_t.set_heart_rate(140)
	_t.inject_packet_loss(1.0)
	_ticks(_t, 100)
	assert_eq(_samples.size(), 0)
	assert_eq(_hr.size(), 0, "пульс теряется вместе с пакетом")
	assert_eq(_t.samples_emitted, 0)
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_states, [])
	_t.inject_packet_loss(0.0)
	_ticks(_t, 2)
	assert_eq(_timestamps(), [101.0, 102.0], "после снятия потерь поток возвращается с актуальными метками")


func test_req_dev_09_c3_packet_loss_ratio_is_clamped_and_half_loses_about_half() -> void:
	_connect(_t)
	_t.inject_packet_loss(7.0) # → 1.0
	_ticks(_t, 20)
	assert_eq(_samples.size(), 0)
	_t.inject_packet_loss(-3.0) # → 0.0
	_ticks(_t, 20)
	assert_eq(_samples.size(), 20)
	_samples = []
	_t.inject_packet_loss(0.5)
	_ticks(_t, 400)
	assert_between(_samples.size(), 150, 250, "≈50 %% потерь, получено %d" % _samples.size())
	var prev: float = 0.0
	for s in _samples:
		assert_gt(s.timestamp_sec, prev)
		prev = s.timestamp_sec


# ===========================================================================
# Детерминизм
# ===========================================================================

func _scenario(seed: int) -> Dictionary:
	var samples: Array[TrainerSample] = []
	var hr: Array[int] = []
	var t := FakeTrainer.new(seed)
	t.telemetry.connect(func(s: TrainerSample) -> void: samples.append(s))
	t.heart_rate.connect(func(b: int) -> void: hr.append(b))
	t.connect_delay_sec = 0.3
	t.connect_device("d")
	t.set_heart_rate_sequence([120, 130, 140, 150])
	for i in 10:
		t.tick(0.1)
	t.set_target_power(230)
	t.inject_packet_loss(0.2)
	for i in 300:
		t.tick(0.25)
	t.inject_dropout(4.0)
	for i in 100:
		t.tick(0.1)
	t.set_target_power(90)
	t.set_erg_enabled(false)
	t.set_rider_power(170)
	for i in 50:
		t.tick(1.0)
	return {"samples": samples, "hr": hr, "commands": t.commands.duplicate(true)}


func test_req_dev_09_determinism_same_seed_identical_samples_hr_and_commands() -> void:
	var a: Dictionary = _scenario(99)
	var b: Dictionary = _scenario(99)
	var sa: Array = a["samples"]
	var sb: Array = b["samples"]
	assert_eq(sa.size(), sb.size())
	assert_gt(sa.size(), 50)
	for i in sa.size():
		assert_eq(sa[i].timestamp_sec, sb[i].timestamp_sec)
		assert_eq(sa[i].power_w, sb[i].power_w)
		assert_eq(sa[i].cadence_rpm, sb[i].cadence_rpm)
		assert_eq(sa[i].speed_kmh, sb[i].speed_kmh)
	assert_eq(a["hr"], b["hr"])
	assert_eq(a["commands"], b["commands"])


func test_req_dev_09_determinism_different_seed_differs_but_timeline_of_commands_same() -> void:
	var a: Dictionary = _scenario(1)
	var b: Dictionary = _scenario(2)
	var sa: Array = a["samples"]
	var sb: Array = b["samples"]
	var differs: bool = sa.size() != sb.size()
	if not differs:
		for i in sa.size():
			if sa[i].power_w != sb[i].power_w or sa[i].cadence_rpm != sb[i].cadence_rpm:
				differs = true
				break
	assert_true(differs, "разный seed — разный шум/потери")
	assert_eq(a["commands"], b["commands"], "журнал команд от seed не зависит")
	assert_eq(FakeTrainer.new(5).get_seed(), 5)


# ===========================================================================
# Команды в состоянии DISCONNECTED — контракт `ErrorCode.NOT_CONNECTED`
# (trainer_device.gd: «Команда вызвана, когда станок не в состоянии CONNECTED»)
# ===========================================================================

func test_contract_command_when_disconnected_reports_not_connected() -> void:
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	_t.set_target_power(200)
	var codes: Array[int] = []
	for e in _errors:
		codes.append(e["code"])
	assert_has(codes, TrainerDevice.ErrorCode.NOT_CONNECTED,
		"по контракту TrainerDevice команда без подключения → error(NOT_CONNECTED); факт: ошибок %d, target_power_w=%d, журнал=%s"
		% [_errors.size(), _t.target_power_w, str(_t.commands)])


func test_contract_command_when_disconnected_does_not_crash_and_is_observable() -> void:
	# Фиксация фактического поведения без суждения: вызов безопасен, журнал ведётся.
	_t.set_target_power(200)
	_t.set_erg_enabled(false)
	_t.set_resistance_level(40)
	assert_eq(_t.commands.size(), 3)
	assert_eq(_t.commands[0]["at_sec"], 0.0)
	_connect(_t)
	_ticks(_t, 3)
	assert_eq(_samples.size(), 3)
