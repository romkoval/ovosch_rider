extends GutTest
## Тесты WorkoutSession: исполнитель + FakeTrainer (REQ-WRK-01 крит. 5, REQ-DEV-09 крит. 6,
## REQ-WRK-02, REQ-WRK-05, REQ-WRK-06, REQ-WRK-08, REQ-DEV-08 крит. 3, REQ-NFR-01).

const FTP: int = 200
const SEED: int = 7

var _trainer: FakeTrainer
var _session: WorkoutSession
var _finished_count: int = 0
var _states: Array[int] = []


func before_each() -> void:
	_finished_count = 0
	_states = []
	_trainer = FakeTrainer.new(SEED)
	_trainer.connect_delay_sec = 0.0
	_trainer.connect_device("fake-session")


func _plan_60_30_90() -> Workout:
	var steps: Array[WorkoutStep] = [
		WorkoutStep.percent(60, 65.0),
		WorkoutStep.percent(30, 100.0),
		WorkoutStep.percent(90, 50.0),
	]
	return Workout.make("60/30/90", steps)


func _plan_600() -> Workout:
	var steps: Array[WorkoutStep] = [WorkoutStep.percent(300, 50.0), WorkoutStep.percent(300, 75.0)]
	return Workout.make("600", steps)


func _make(w: Workout, intensity: float = 1.0) -> WorkoutSession:
	var s := WorkoutSession.new(w, _trainer, FTP, intensity)
	s.session_finished.connect(func() -> void: _finished_count += 1)
	s.state_changed.connect(func(st: int) -> void: _states.append(st))
	return s


func _tick_n(s: WorkoutSession, n: int, delta: float = 1.0) -> void:
	for i in n:
		s.tick(delta)


func _commands(type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in _trainer.commands:
		if c["type"] == type:
			out.append(c)
	return out


# ---------------------------------------------------------------------------
# Полный прогон
# ---------------------------------------------------------------------------

func test_full_run_finishes_and_commands_hit_step_boundaries() -> void:
	_session = _make(_plan_60_30_90())
	_session.start()
	assert_eq(_session.get_state(), WorkoutSession.State.RUNNING)
	_tick_n(_session, 180)
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED, "REQ-WRK-01 крит. 5: план доигран на FakeTrainer")
	assert_eq(_finished_count, 1)
	var cmds := _commands(FakeTrainer.CMD_TARGET_POWER)
	assert_eq(cmds.size(), 3, "Set Target Power на каждом переходе")
	assert_eq(cmds[0]["value"], 130)
	assert_almost_eq(float(cmds[0]["at_sec"]), 0.0, 1e-6)
	assert_eq(cmds[1]["value"], 200)
	assert_almost_eq(float(cmds[1]["at_sec"]), 60.0, 1e-6, "REQ-WRK-02 крит. 2 / NFR-01: та же секунда, что граница")
	assert_eq(cmds[2]["value"], 100)
	assert_almost_eq(float(cmds[2]["at_sec"]), 90.0, 1e-6)
	assert_eq(_trainer.commands.size(), 3, "в ERG по умолчанию никаких лишних команд")


func test_600s_plan_records_exactly_600_samples() -> void:
	_session = _make(_plan_600())
	_session.start()
	_tick_n(_session, 600)
	assert_eq(_session.samples.size(), 600, "REQ-WRK-08 крит. 1")
	assert_true(_session.samples.is_monotonic())
	assert_eq(_session.samples.time_sec[0], 0)
	assert_eq(_session.samples.time_sec[599], 599)
	assert_eq(_finished_count, 1)
	_tick_n(_session, 10)
	assert_eq(_session.samples.size(), 600, "после финиша сэмплы не пишутся")


func test_trainer_actually_rode_power_converges_to_target() -> void:
	_session = _make(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 60)
	var s := _session.samples
	assert_eq(s.count_with_power(), 60)
	var p59: int = s.power_w[59]
	assert_true(absi(p59 - 130) <= 130 * 0.05 + _trainer.power_noise_w,
		"мощность сошлась к 130 Вт (REQ-DEV-09 крит. 2), получено %d" % p59)
	assert_true(s.has_cadence[59])
	assert_true(s.has_speed[59])
	assert_gt(s.speed_kmh[59], 0.0)


func test_sample_columns_target_step_erg() -> void:
	_session = _make(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 61)
	var s := _session.samples
	assert_eq(s.step_index[59], 0)
	assert_eq(s.target_w[59], 130, "слот 59 — ещё первый шаг")
	assert_eq(s.step_index[60], 1)
	assert_eq(s.target_w[60], 200, "слот 60 — уже второй")
	assert_true(s.erg_enabled[60])
	var r := s.row(60)
	assert_eq(r["time_sec"], 60)
	assert_eq(r["step_index"], 1)


func test_sub_second_ticks_keep_commands_within_boundary_second() -> void:
	_session = _make(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 900, 0.2)
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED)
	var cmds := _commands(FakeTrainer.CMD_TARGET_POWER)
	assert_eq(cmds.size(), 3)
	assert_almost_eq(float(cmds[1]["at_sec"]), 60.0, 1e-3, "REQ-NFR-01: ≤ 1 с при кадре 200 мс")
	assert_almost_eq(float(cmds[2]["at_sec"]), 90.0, 1e-3)
	assert_eq(_session.samples.size(), 180)
	assert_true(_session.samples.is_monotonic())


func test_frame_freeze_2s_still_yields_all_samples() -> void:
	_session = _make(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 10)
	_session.tick(2.0)
	_tick_n(_session, 48)
	assert_eq(_session.samples.size(), 60, "REQ-NFR-02 крит. 2: сэмплы за «замороженные» секунды есть")
	assert_true(_session.samples.is_monotonic())
	assert_eq(_session.samples.count_with_power(), 60, "каждый слот получил свою телеметрию, не «последний победил»")
	_session.tick(2.0)
	var cmd: Dictionary = _trainer.commands.back()
	assert_eq(cmd["value"], 200)
	assert_almost_eq(float(cmd["at_sec"]), 60.0, 1e-6, "команда перехода — ровно на границе и после заморозки")


# ---------------------------------------------------------------------------
# Пауза, пропуск, стоп
# ---------------------------------------------------------------------------

func test_pause_sends_nothing_and_records_nothing_resume_resends_target() -> void:
	_session = _make(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 10)
	_session.pause()
	assert_eq(_session.get_state(), WorkoutSession.State.PAUSED)
	var cmds_before: int = _trainer.commands.size()
	var samples_before: int = _session.samples.size()
	_tick_n(_session, 20)
	assert_eq(_trainer.commands.size(), cmds_before, "REQ-WRK-05 крит. 5: журнал команд за паузу пуст")
	assert_eq(_session.samples.size(), samples_before, "крит. 2: на паузе сэмплы не пишутся")
	assert_almost_eq(_trainer.get_time_sec(), 30.0, 1e-6, "часы станка идут и на паузе")
	_session.resume()
	var last: Dictionary = _trainer.commands.back()
	assert_eq(last["type"], FakeTrainer.CMD_TARGET_POWER)
	assert_eq(last["value"], 130, "крит. 3: цель повторно уходит при возобновлении")
	assert_almost_eq(float(last["at_sec"]), 30.0, 1e-6)
	_tick_n(_session, 50)
	assert_eq(_session.executor.current_step_index(), 1)
	assert_eq(_session.samples.size(), 60)
	assert_true(_session.samples.is_monotonic(), "время паузы не входит в сессионное время")


func test_skip_step_sends_new_target_immediately() -> void:
	_session = _make(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 10)
	_session.skip_step()
	var last: Dictionary = _trainer.commands.back()
	assert_eq(last["value"], 200, "REQ-WRK-06 крит. 2")
	assert_almost_eq(float(last["at_sec"]), 10.0, 1e-6)
	assert_eq(_session.current_target_watts(), 200)


func test_skip_while_paused_defers_target_until_resume() -> void:
	_session = _make(_plan_60_30_90())
	_session.start()
	_session.pause()
	var before: int = _trainer.commands.size()
	_session.skip_step()
	assert_eq(_trainer.commands.size(), before, "на паузе ничего не шлём")
	_session.resume()
	assert_eq(_trainer.commands.back()["value"], 200)


func test_stop_finishes_early_and_stops_recording() -> void:
	_session = _make(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 5)
	_session.stop()
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED)
	assert_eq(_finished_count, 1)
	assert_true(_session.executor.stopped_early)
	_tick_n(_session, 10)
	assert_eq(_session.samples.size(), 5)
	_session.stop()
	assert_eq(_finished_count, 1)


func test_start_twice_and_lifecycle_states() -> void:
	_session = _make(_plan_60_30_90())
	_session.start()
	_session.start()
	assert_eq(_commands(FakeTrainer.CMD_TARGET_POWER).size(), 1)
	_session.pause()
	_session.resume()
	_session.stop()
	assert_eq(_states, [WorkoutSession.State.RUNNING, WorkoutSession.State.PAUSED,
		WorkoutSession.State.RUNNING, WorkoutSession.State.FINISHED] as Array[int])


# ---------------------------------------------------------------------------
# Интенсивность, ERG, сопротивление
# ---------------------------------------------------------------------------

func test_set_intensity_sends_new_target() -> void:
	_session = _make(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 3)
	_session.set_intensity(1.1)
	var last: Dictionary = _trainer.commands.back()
	assert_eq(last["value"], 143, "130 × 1.1 = 143 (REQ-WRK-07 крит. 2, 3)")
	assert_almost_eq(float(last["at_sec"]), 3.0, 1e-6)
	assert_eq(_trainer.target_power_w, 143)


func test_erg_off_sends_resistance_and_suppresses_targets_erg_on_resends() -> void:
	_session = _make(_plan_60_30_90())
	_session.resistance_level = 40
	_session.start()
	_tick_n(_session, 5)
	_session.set_erg_enabled(false)
	var n: int = _trainer.commands.size()
	assert_eq(_trainer.commands[n - 2]["type"], FakeTrainer.CMD_ERG)
	assert_eq(_trainer.commands[n - 2]["value"], false)
	assert_eq(_trainer.commands[n - 1]["type"], FakeTrainer.CMD_RESISTANCE)
	assert_eq(_trainer.commands[n - 1]["value"], 40)
	assert_false(_trainer.erg_enabled)
	_tick_n(_session, 55)
	assert_eq(_session.executor.current_step_index(), 1)
	assert_eq(_commands(FakeTrainer.CMD_TARGET_POWER).size(), 1, "вне ERG цель на границе не шлётся")
	assert_false(_session.samples.erg_enabled[30])
	_session.set_erg_enabled(true)
	n = _trainer.commands.size()
	assert_eq(_trainer.commands[n - 2]["type"], FakeTrainer.CMD_ERG)
	assert_eq(_trainer.commands[n - 2]["value"], true)
	assert_eq(_trainer.commands[n - 1]["type"], FakeTrainer.CMD_TARGET_POWER)
	assert_eq(_trainer.commands[n - 1]["value"], 200, "при включении ERG уходит текущая цель")
	_session.set_erg_enabled(true)
	assert_eq(_trainer.commands.size(), n, "повтор того же значения — без команд")


func test_set_resistance_level_sent_only_outside_erg() -> void:
	_session = _make(_plan_60_30_90())
	_session.start()
	_session.set_resistance_level(70)
	assert_eq(_commands(FakeTrainer.CMD_RESISTANCE).size(), 0, "в ERG уровень только запоминается")
	_session.set_erg_enabled(false)
	assert_eq(_commands(FakeTrainer.CMD_RESISTANCE).back()["value"], 70)
	_session.set_resistance_level(130)
	assert_eq(_session.resistance_level, 100, "кламп 0..100")
	assert_eq(_commands(FakeTrainer.CMD_RESISTANCE).back()["value"], 100)


func test_erg_toggle_while_paused_is_deferred_to_resume() -> void:
	_session = _make(_plan_60_30_90())
	_session.start()
	_session.pause()
	var before: int = _trainer.commands.size()
	_session.set_erg_enabled(false)
	assert_eq(_trainer.commands.size(), before)
	_session.resume()
	var cmds := _trainer.commands.slice(before)
	assert_eq(cmds.size(), 2)
	assert_eq(cmds[0]["type"], FakeTrainer.CMD_ERG)
	assert_eq(cmds[0]["value"], false)
	assert_eq(cmds[1]["type"], FakeTrainer.CMD_RESISTANCE)


func test_start_with_erg_disabled_sends_resistance_not_target() -> void:
	_session = _make(_plan_60_30_90())
	_session.set_erg_enabled(false)
	_session.start()
	assert_eq(_commands(FakeTrainer.CMD_TARGET_POWER).size(), 0)
	assert_eq(_commands(FakeTrainer.CMD_ERG).size(), 1)
	assert_eq(_commands(FakeTrainer.CMD_RESISTANCE).size(), 1)


func test_free_ride_step_sends_no_target_power() -> void:
	var steps: Array[WorkoutStep] = [WorkoutStep.free_ride(10), WorkoutStep.percent(10, 80.0)]
	_session = _make(Workout.make("free", steps))
	_session.start()
	assert_eq(_trainer.commands.size(), 0, "REQ-WRK-02 крит. 5")
	assert_eq(_session.current_target_watts(), 0)
	_tick_n(_session, 10)
	assert_eq(_commands(FakeTrainer.CMD_TARGET_POWER).size(), 1)
	assert_eq(_trainer.commands.back()["value"], 160)
	assert_eq(_session.samples.target_w[5], 0)


# ---------------------------------------------------------------------------
# Телеметрия, пульс, обрывы
# ---------------------------------------------------------------------------

func test_heart_rate_recorded_when_present() -> void:
	_trainer.set_heart_rate(150)
	_session = _make(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 5)
	assert_true(_session.samples.has_heart_rate[4])
	assert_eq(_session.samples.heart_rate_bpm[4], 150)
	_trainer.set_heart_rate(0)
	_tick_n(_session, 5)
	assert_false(_session.samples.has_heart_rate[9], "без датчика — «нет данных»")


func test_silence_yields_no_data_slots_but_one_slot_per_second() -> void:
	_session = _make(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 10)
	_trainer.inject_silence(3.0)
	_tick_n(_session, 10)
	var s := _session.samples
	assert_eq(s.size(), 20, "ровно один слот на секунду")
	assert_eq(s.count_with_power(), 17)
	assert_false(s.has_power[10])
	assert_false(s.has_power[12])
	assert_true(s.has_power[13])
	assert_eq(s.power_w[11], 0, "значение без данных не повторяет последнее")


func test_reconnect_resends_erg_and_target_same_second() -> void:
	_session = _make(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 10)
	_trainer.inject_dropout(5.0)
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING)
	var before: int = _trainer.commands.size()
	_tick_n(_session, 4)
	assert_eq(_trainer.commands.size(), before, "во время обрыва ничего не шлём")
	assert_eq(_session.samples.size(), 14, "REQ-DEV-08 крит. 2: таймер и запись идут")
	assert_false(_session.samples.has_power[12])
	_session.tick(1.0)
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	var cmds := _trainer.commands.slice(before)
	assert_eq(cmds.size(), 2)
	assert_eq(cmds[0]["type"], FakeTrainer.CMD_ERG)
	assert_eq(cmds[0]["value"], true)
	assert_eq(cmds[1]["type"], FakeTrainer.CMD_TARGET_POWER)
	assert_eq(cmds[1]["value"], 130, "REQ-DEV-08 крит. 3: цель текущего интервала")
	assert_almost_eq(float(cmds[1]["at_sec"]), 15.0, 1e-6, "не позже 1 с после connected")


func test_sample_stream_append_null_sample() -> void:
	var s := SampleStream.new()
	s.append(0, null, -1, 100, 0, true)
	s.append(1, TrainerSample.full(1.0, 150, 90, 30.0), 120, 100, 0, true)
	assert_eq(s.size(), 2)
	assert_false(s.has_power[0])
	assert_false(s.has_heart_rate[0])
	assert_true(s.has_power[1])
	assert_eq(s.power_w[1], 150)
	assert_eq(s.heart_rate_bpm[1], 120)
	assert_true(s.is_monotonic())
	s.append(5, null, -1, 0, -1, false)
	assert_false(s.is_monotonic())
