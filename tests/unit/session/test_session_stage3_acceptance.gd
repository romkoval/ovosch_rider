extends GutTest
## Независимые приёмочные тесты сессии этапа 3 (тестировщик; коммиты bdddd4d, bcbbe7c).
## Покрытие: REQ-WRK-02 (все, крит. 5 по В-10), REQ-WRK-03 (все), REQ-WRK-04 крит. 1, 3,
## REQ-WRK-05 (все), REQ-WRK-06 (все), REQ-WRK-07 (все), REQ-WRK-08 (все),
## REQ-NFR-01 крит. 1, 2, REQ-D3D-02 крит. 1–4 (только модель `SpeedModel`).
## Станок — `FakeTrainer` через интерфейс `TrainerDevice`; метки команд — часы эмулятора.

const FTP: int = 200
const SEED: int = 31

var _trainer: FakeTrainer
var _session: WorkoutSession
var _events: Array[Dictionary] = []


func before_each() -> void:
	_events = []
	_trainer = FakeTrainer.new(SEED)
	_trainer.connect_delay_sec = 0.0
	_trainer.power_noise_w = 0.0
	_trainer.connect_device("stage3")
	_session = null


func _make(steps: Array, intensity: float = 1.0, weight: float = 75.0) -> WorkoutSession:
	var typed: Array[WorkoutStep] = []
	for s in steps:
		typed.append(s)
	_session = WorkoutSession.new(Workout.make("acc", typed), _trainer, FTP, intensity, weight)
	_session.event_logged.connect(func(e: Dictionary) -> void: _events.append(e))
	return _session


func _tick(seconds: float, piece: float = 1.0) -> void:
	var left := seconds
	while left > 1e-9:
		var d := minf(piece, left)
		_session.tick(d)
		left -= d


## Команды типа `type` как массив [value, at_sec].
func _cmds(type: String, since_index: int = 0) -> Array:
	var out: Array = []
	for i in range(since_index, _trainer.commands.size()):
		var c: Dictionary = _trainer.commands[i]
		if c["type"] == type:
			out.append([c["value"], float(c["at_sec"])])
	return out


func _types(since_index: int = 0) -> Array[String]:
	var out: Array[String] = []
	for i in range(since_index, _trainer.commands.size()):
		out.append(str(_trainer.commands[i]["type"]))
	return out


func _journal_size() -> int:
	return _trainer.commands.size()


func _events_of(type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _session.events:
		if e["type"] == type:
			out.append(e)
	return out


# ===========================================================================
# REQ-WRK-02 — цель на смене интервала
# ===========================================================================

func test_req_wrk_02_c1_percent_watts_and_rounding_are_sent_at_boundaries() -> void:
	_make([WorkoutStep.percent(60, 50.0), WorkoutStep.percent(30, 65.0), WorkoutStep.watts(30, 250.0), WorkoutStep.percent(30, 33.3)])
	_session.start()
	_tick(150)
	assert_eq(_cmds("target_power"), [[100, 0.0], [130, 60.0], [250, 90.0], [67, 120.0]],
		"65 %% от 200 → 130; ватты как есть; 33.3 %% от 200 = 66.6 → 67")
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED)


func test_req_wrk_02_c2_nfr_01_c1_twenty_intervals_commands_land_exactly_on_boundaries_with_1s_and_200ms_frames() -> void:
	for piece in [1.0, 0.2]:
		before_each()
		var steps: Array = []
		for i in 20:
			steps.append(WorkoutStep.percent(10, 50.0 + 5.0 * i))
		_make(steps)
		_session.start()
		_tick(200, piece)
		var targets := _cmds("target_power")
		assert_eq(targets.size(), 20, "кадр %.1f с: 20 переходов → 20 команд" % piece)
		for i in targets.size():
			var boundary := float(i * 10)
			var delay: float = targets[i][1] - boundary
			assert_true(delay >= -1e-6 and delay <= 1.0, "кадр %.1f: переход %d — задержка %.3f с" % [piece, i, delay])
			assert_almost_eq(delay, 0.0, 1e-6, "фактически команда уходит ровно на границе (с учётом накопления float при кадрах 0.2 с)")
			assert_eq(targets[i][0], roundi((50.0 + 5.0 * i) / 100.0 * FTP))


func test_req_wrk_02_c3_ramp_target_recomputed_each_second_and_sent_only_on_1w_change() -> void:
	# 100 → 200 Вт за 100 с: +1 Вт/с → команда каждую секунду, ровно одна в секунду.
	_make([WorkoutStep.ramp_percent(100, 50.0, 100.0)])
	_session.start()
	_tick(100)
	var targets := _cmds("target_power")
	assert_eq(targets.size(), 100, "каждую секунду ровно одна команда")
	for i in targets.size():
		assert_eq(targets[i][0], 100 + i, "секунда %d" % i)
		assert_almost_eq(targets[i][1], float(i), 1e-6)
	# 100 → 110 Вт за 100 с: +0.1 Вт/с → команды только при изменении ≥ 1 Вт.
	before_each()
	_make([WorkoutStep.ramp_watts(100, 100.0, 110.0)])
	_session.start()
	_tick(100)
	targets = _cmds("target_power")
	assert_between(targets.size(), 10, 11, "≈10 команд за 100 с, а не 100")
	var last_t := -1.0
	for i in range(1, targets.size()):
		assert_gte(int(targets[i][0]) - int(targets[i - 1][0]), 1, "каждая следующая цель ≥ 1 Вт выше")
		assert_true(targets[i][1] - targets[i - 1][1] >= 1.0 - 1e-6, "не чаще раза в секунду")
		last_t = targets[i][1]
	assert_gt(last_t, 0.0)


func test_req_wrk_02_c4_intensity_is_applied_before_sending() -> void:
	_make([WorkoutStep.watts(30, 200.0), WorkoutStep.percent(30, 65.0)], 1.1)
	_session.start()
	_tick(60)
	assert_eq(_cmds("target_power"), [[220, 0.0], [143, 30.0]], "200 Вт × 1.1 = 220; 130 × 1.1 = 143")


func test_req_wrk_02_c5_free_ride_in_erg_switches_trainer_to_resistance_and_back_same_second() -> void:
	_make([WorkoutStep.percent(30, 50.0), WorkoutStep.free_ride(30), WorkoutStep.percent(30, 100.0)])
	_session.set_resistance_level(35)
	_session.start()
	_tick(30)
	var at_free := _journal_size()
	assert_eq(_types(), ["target_power", "erg", "resistance"], "на границе FreeRide: erg=false + уровень пользователя")
	assert_eq(_trainer.commands[1]["value"], false)
	assert_almost_eq(float(_trainer.commands[1]["at_sec"]), 30.0, 1e-6, "не позже 1 с от начала шага (ровно на границе)")
	assert_eq(_trainer.commands[2]["value"], 35)
	assert_almost_eq(float(_trainer.commands[2]["at_sec"]), 30.0, 1e-6)
	assert_true(_session.erg_enabled, "флаг пользователя не изменился")
	assert_false(_session.is_erg_active_on_trainer())
	assert_true(_session.is_freeride_suspended())
	_tick(29.5)
	assert_eq(_cmds("target_power", at_free), [], "за время FreeRide Set Target Power отсутствует")
	assert_eq(_journal_size(), at_free, "и вообще никаких команд внутри шага")
	_tick(0.5)
	assert_eq(_types(at_free), ["erg", "target_power"], "на следующем шаге: erg=true + цель в ту же секунду")
	assert_eq(_trainer.commands[at_free]["value"], true)
	assert_almost_eq(float(_trainer.commands[at_free]["at_sec"]), 60.0, 1e-6)
	assert_eq(_trainer.commands[at_free + 1]["value"], 200)
	assert_almost_eq(float(_trainer.commands[at_free + 1]["at_sec"]), 60.0, 1e-6)
	assert_true(_session.erg_enabled)
	assert_true(_session.is_erg_active_on_trainer())
	assert_eq(_trainer.erg_enabled, true, "состояние станка восстановлено")


func test_req_wrk_02_c5_free_ride_with_user_erg_off_changes_nothing() -> void:
	_make([WorkoutStep.percent(30, 50.0), WorkoutStep.free_ride(30), WorkoutStep.percent(30, 100.0)])
	_session.set_erg_enabled(false)
	_session.start()
	var after_start := _journal_size()
	assert_eq(_types(), ["erg", "resistance"], "старт вне ERG: erg=false + уровень")
	_tick(90)
	assert_eq(_journal_size(), after_start, "ни FreeRide, ни следующий шаг не шлют команд при выключенном пользователем ERG")
	assert_false(_session.erg_enabled)
	assert_false(_session.is_freeride_suspended())


func test_req_wrk_02_c5_free_ride_as_first_step_suspends_erg_at_start_without_target() -> void:
	_make([WorkoutStep.free_ride(20), WorkoutStep.percent(20, 50.0)])
	_session.start()
	assert_eq(_types(), ["erg", "resistance"], "первый шаг FreeRide: сразу режим сопротивления, без цели")
	assert_eq(_trainer.commands[0]["value"], false)
	assert_eq(_cmds("target_power"), [])
	_tick(20)
	assert_eq(_types(2), ["erg", "target_power"])
	assert_eq(_cmds("target_power"), [[100, 20.0]])


func test_req_wrk_02_c5_two_free_rides_in_a_row_do_not_repeat_commands() -> void:
	_make([WorkoutStep.percent(10, 50.0), WorkoutStep.free_ride(10), WorkoutStep.free_ride(10), WorkoutStep.percent(10, 50.0)])
	_session.start()
	_tick(10)
	var after_first := _journal_size()
	assert_eq(_types(1), ["erg", "resistance"])
	_tick(10) # граница между двумя FreeRide
	assert_eq(_journal_size(), after_first, "второй FreeRide подряд не дублирует erg/уровень")
	_tick(10)
	assert_eq(_types(after_first), ["erg", "target_power"], "возврат ERG — на первом шаге с целью")


func test_req_wrk_02_c5_free_ride_as_last_step_finishes_without_restoring_erg_command() -> void:
	_make([WorkoutStep.percent(10, 50.0), WorkoutStep.free_ride(10)])
	_session.start()
	_tick(20)
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED)
	assert_eq(_types(), ["target_power", "erg", "resistance"], "после финиша команд нет")
	assert_true(_session.erg_enabled, "флаг пользователя по-прежнему вкл")
	assert_eq(_session.metadata()["erg_enabled"], true)


func test_req_wrk_02_c5_user_turns_erg_off_during_free_ride_then_next_step_sends_no_target() -> void:
	_make([WorkoutStep.free_ride(10), WorkoutStep.percent(10, 50.0)])
	_session.start()
	_tick(5)
	var before := _journal_size()
	_session.toggle_erg()
	assert_false(_session.erg_enabled)
	assert_false(_session.is_freeride_suspended(), "режим шага больше не нужен — пользователь сам выключил")
	assert_eq(_types(before), ["erg", "resistance"], "выключение пользователем подтверждается станку")
	var mid := _journal_size()
	_tick(5)
	assert_eq(_journal_size(), mid, "переход на шаг с целью при пользовательском ERG выкл ничего не шлёт")
	assert_eq(_session.current_target_watts(), 100, "цель известна, но не отправлена")


func test_req_wrk_02_c5_toggle_erg_on_pause_is_deferred_and_applied_on_resume_with_one_erg_and_one_level() -> void:
	_make([WorkoutStep.percent(60, 50.0)])
	_session.start()
	_tick(10)
	_session.pause()
	var before := _journal_size()
	_session.toggle_erg()
	_tick(3)
	assert_eq(_journal_size(), before, "на паузе ничего не шлётся")
	_session.resume()
	assert_eq(_types(before), ["erg", "resistance"], "при возобновлении — отложенный ERG выкл и уровень")
	assert_eq(_trainer.commands[before]["value"], false)
	assert_almost_eq(float(_trainer.commands[before]["at_sec"]), float(_trainer.commands[before + 1]["at_sec"]), 1e-9, "в одну секунду")


# ===========================================================================
# REQ-WRK-03 — ERG одним действием
# ===========================================================================

func test_req_wrk_03_c1_toggle_is_one_action_and_signals_state() -> void:
	_make([WorkoutStep.percent(60, 50.0)])
	var changes: Array[bool] = []
	_session.erg_changed.connect(func(e: bool) -> void: changes.append(e))
	_session.start()
	_session.toggle_erg()
	assert_false(_session.erg_enabled)
	_session.toggle_erg()
	assert_true(_session.erg_enabled)
	assert_eq(changes, [false, true])
	assert_eq(_events_of(WorkoutSession.EVENT_ERG_OFF).size(), 1)
	assert_eq(_events_of(WorkoutSession.EVENT_ERG_ON).size(), 1)
	_session.set_erg_enabled(true)
	assert_eq(changes.size(), 2, "повтор того же значения — без сигнала и события")


func test_req_wrk_03_c2_erg_off_mid_interval_sends_resistance_level_same_second() -> void:
	_make([WorkoutStep.percent(60, 65.0)])
	_session.set_resistance_level(40)
	_session.start()
	_tick(15.5, 0.5)
	var before := _journal_size()
	_session.set_erg_enabled(false)
	assert_eq(_types(before), ["erg", "resistance"])
	assert_eq(_trainer.commands[before + 1]["value"], 40, "текущий уровень WRK-04")
	assert_almost_eq(float(_trainer.commands[before + 1]["at_sec"]), 15.5, 1e-6, "не позже 1 с — немедленно")
	assert_eq(_trainer.erg_enabled, false)
	assert_eq(_trainer.resistance_percent, 40)


func test_req_wrk_03_c3_erg_on_mid_interval_sends_target_with_intensity_same_second() -> void:
	_make([WorkoutStep.percent(60, 65.0)], 1.1)
	_session.set_erg_enabled(false)
	_session.start()
	_tick(20.25, 0.25)
	var before := _journal_size()
	_session.set_erg_enabled(true)
	assert_eq(_types(before), ["erg", "target_power"])
	assert_eq(_trainer.commands[before + 1]["value"], 143, "65 %% × 200 × 1.1 = 143")
	assert_almost_eq(float(_trainer.commands[before + 1]["at_sec"]), 20.25, 1e-6)


func test_req_wrk_03_c4_toggling_does_not_stop_timer_or_recording() -> void:
	_make([WorkoutStep.percent(60, 50.0)])
	_session.start()
	_tick(5)
	_session.toggle_erg()
	_tick(5)
	_session.toggle_erg()
	_tick(5)
	assert_eq(_session.executor.elapsed_sec(), 15)
	assert_eq(_session.samples.size(), 15)
	assert_true(_session.samples.is_monotonic())
	assert_eq(_session.samples.count_with_power(), 15, "телеметрия записывалась всё время")
	assert_eq(Array(_session.samples.erg_enabled).slice(4, 11), [true, false, false, false, false, false, true], "флаг ERG в сэмплах отражает переключения")


func test_req_wrk_03_c5_erg_is_on_by_default_and_start_sends_no_erg_command() -> void:
	_make([WorkoutStep.percent(10, 50.0)])
	assert_true(_session.erg_enabled)
	_session.start()
	assert_eq(_types(), ["target_power"], "при ERG по умолчанию уходит только цель")
	assert_eq(_session.metadata()["erg_enabled"], true)


# ===========================================================================
# REQ-WRK-04 крит. 1, 3 — уровень сопротивления
# ===========================================================================

func test_req_wrk_04_c1_level_snaps_to_5_within_0_100_and_signals_for_profile() -> void:
	_make([WorkoutStep.percent(60, 50.0)])
	var changes: Array[int] = []
	_session.resistance_level_changed.connect(func(p: int) -> void: changes.append(p))
	assert_eq(_session.resistance_level, 50, "по умолчанию 50")
	var cases := {101: 100, -5: 0, 52: 50, 53: 55, 57: 55, 58: 60, 0: 0, 100: 100, 1000: 100}
	for raw in cases.keys():
		_session.set_resistance_level(raw)
		assert_eq(_session.resistance_level, cases[raw], "уровень %d → %d" % [raw, cases[raw]])
	assert_eq(changes, [100, 0, 50, 55, 60, 0, 100], "сигнал на каждое изменение; повторы (50 после 52, 55 после 57, 100) без сигнала")
	assert_eq(WorkoutSession.snap_resistance(52), 50)
	assert_eq(WorkoutSession.snap_resistance(-5), 0)
	assert_eq(WorkoutSession.snap_resistance(101), 100)
	assert_eq(_events_of(WorkoutSession.EVENT_RESISTANCE).size(), changes.size())


func test_req_wrk_04_c3_level_change_in_erg_is_stored_not_sent_until_erg_off() -> void:
	_make([WorkoutStep.percent(60, 50.0)])
	_session.start()
	_tick(5)
	var before := _journal_size()
	_session.set_resistance_level(30)
	assert_eq(_journal_size(), before, "при ERG уровень только запоминается")
	assert_eq(_session.resistance_level, 30)
	_session.set_erg_enabled(false)
	assert_eq(_cmds("resistance", before), [[30, 5.0]], "ушёл при выключении ERG")
	_session.set_resistance_level(60)
	assert_eq(_cmds("resistance", before)[-1][0], 60, "вне ERG изменение уходит сразу")


# ===========================================================================
# REQ-WRK-05 — пауза, возобновление, досрочное завершение
# ===========================================================================

func test_req_wrk_05_c1_pause_stops_step_and_total_timers() -> void:
	_make([WorkoutStep.percent(60, 50.0), WorkoutStep.percent(60, 100.0)])
	_session.start()
	_tick(20)
	_session.pause()
	assert_eq(_session.get_state(), WorkoutSession.State.PAUSED)
	var elapsed := _session.executor.elapsed_sec()
	var remaining := _session.executor.step_remaining_sec()
	var total_remaining := _session.executor.total_remaining_sec()
	_tick(50)
	assert_eq(_session.executor.elapsed_sec(), elapsed, "общий таймер стоит")
	assert_eq(_session.executor.step_remaining_sec(), remaining, "таймер шага стоит")
	assert_eq(_session.executor.total_remaining_sec(), total_remaining)
	assert_eq(_session.executor.current_step_index(), 0, "план не продвинулся")
	assert_almost_eq(_trainer.get_time_sec(), 70.0, 1e-6, "часы станка идут (телеметрия продолжается)")


func test_req_wrk_05_c2_no_samples_during_pause_and_pause_event_has_begin_and_end() -> void:
	_make([WorkoutStep.percent(60, 50.0)])
	_session.start()
	_tick(10)
	_session.pause()
	_tick(5)
	assert_eq(_session.samples.size(), 10, "на паузе слоты не пишутся")
	_session.resume()
	_tick(2)
	assert_eq(_session.samples.size(), 12)
	assert_true(_session.samples.is_monotonic(), "после паузы ряд продолжается без разрыва (10, 11)")
	var pauses := _events_of(WorkoutSession.EVENT_PAUSE)
	assert_eq(pauses.size(), 1)
	assert_almost_eq(float(pauses[0]["at_sec"]), 10.0, 1e-6, "начало паузы в сессионном времени")
	assert_true(pauses[0].has("until_sec"), "у события паузы есть время конца")
	assert_true(float(pauses[0]["until_sec"]) - float(pauses[0]["at_sec"]) > 0.0,
		"конец паузы должен быть позже начала (пауза длилась 5 с реального времени); факт at=%s until=%s" % [str(pauses[0]["at_sec"]), str(pauses[0]["until_sec"])])
	assert_eq(_events_of(WorkoutSession.EVENT_RESUME).size(), 1)


func test_req_wrk_05_c3_resume_continues_same_remaining_and_resends_exactly_one_command() -> void:
	_make([WorkoutStep.percent(60, 50.0), WorkoutStep.percent(60, 100.0)])
	_session.start()
	_tick(20)
	_session.pause()
	_tick(7)
	var before := _journal_size()
	_session.resume()
	assert_eq(_types(before), ["target_power"], "ровно одна команда — текущая цель (ERG)")
	assert_eq(_trainer.commands[before]["value"], 100)
	assert_almost_eq(float(_trainer.commands[before]["at_sec"]), 27.0, 1e-6, "немедленно (по часам станка)")
	assert_eq(_session.executor.step_remaining_sec(), 40, "остаток шага тот же")
	_tick(40)
	assert_eq(_cmds("target_power", before)[-1], [200, 67.0], "граница второго шага сдвинута на длительность паузы по часам станка")
	# вне ERG — уровень
	before_each()
	_make([WorkoutStep.percent(60, 50.0)])
	_session.set_erg_enabled(false)
	_session.set_resistance_level(25)
	_session.start()
	_tick(5)
	_session.pause()
	before = _journal_size()
	_session.resume()
	assert_eq(_types(before), ["resistance"], "вне ERG — повторно уровень, одна команда")
	assert_eq(_trainer.commands[before]["value"], 25)


func test_req_wrk_05_c4_stop_marks_stopped_early_and_keeps_data() -> void:
	_make([WorkoutStep.percent(60, 50.0), WorkoutStep.percent(60, 100.0)])
	_session.start()
	_tick(75)
	_session.stop()
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED)
	var meta := _session.metadata()
	assert_true(meta["stopped_early"], "помечен «завершён досрочно»")
	assert_eq(meta["elapsed_sec"], 75, "фактическая длительность")
	assert_eq(meta["planned_sec"], 120)
	assert_eq(meta["sample_count"], 75)
	assert_eq(_session.samples.size(), 75, "данные целы")
	assert_eq(_session.samples.count_with_power(), 75)
	var types: Array[String] = []
	for e in _session.events:
		types.append(e["type"])
	assert_eq(types.slice(-2), [WorkoutSession.EVENT_STOP, WorkoutSession.EVENT_FINISH])
	_tick(10)
	assert_eq(_session.samples.size(), 75, "после стопа ничего не дописывается")
	# план, доигранный до конца, досрочным не считается
	before_each()
	_make([WorkoutStep.percent(10, 50.0)])
	_session.start()
	_tick(10)
	assert_false(_session.metadata()["stopped_early"])


func test_req_wrk_05_c5_nothing_is_sent_during_pause_including_boundaries_and_changes() -> void:
	_make([WorkoutStep.percent(30, 50.0), WorkoutStep.percent(30, 100.0)])
	_session.start()
	_tick(29.5, 0.5)
	_session.pause()
	var before := _journal_size()
	_tick(10) # граница 30 с не наступает — план стоит
	_session.set_intensity(1.2)
	_session.set_resistance_level(70)
	_trainer.error.emit(TrainerDevice.ErrorCode.WRITE_FAILED, "x")
	assert_eq(_journal_size(), before, "журнал станка за время паузы пуст")
	assert_eq(_trainer.target_power_w, 100, "целью станка остаётся последняя отправленная")
	assert_eq(_session.samples.size(), 29)
	_session.resume()
	assert_eq(_types(before), ["target_power"], "при возобновлении — одна команда")
	assert_eq(_trainer.commands[before]["value"], 120, "с новым множителем 1.2")
	_tick(0.5)
	assert_eq(_cmds("target_power", before)[-1][0], 240, "граница шага наступила после возобновления: 200 × 1.2")


# ===========================================================================
# REQ-WRK-06 — пропуск интервала
# ===========================================================================

func test_req_wrk_06_c1_c2_c4_skip_advances_now_reduces_remaining_and_sends_target_and_logs_event() -> void:
	_make([WorkoutStep.percent(60, 50.0), WorkoutStep.percent(30, 100.0), WorkoutStep.percent(30, 60.0)])
	_session.start()
	_tick(10)
	var total_before := _session.executor.total_remaining_sec()
	assert_eq(total_before, 110)
	var before := _journal_size()
	_session.skip_step()
	assert_eq(_session.executor.current_step_index(), 1, "переход немедленно")
	assert_eq(_session.executor.total_remaining_sec(), 60, "остаток уменьшился на остаток пропущенного шага (50)")
	assert_eq(_cmds("target_power", before), [[200, 10.0]], "новая цель в ту же секунду")
	var skips := _events_of(WorkoutSession.EVENT_SKIP)
	assert_eq(skips.size(), 1)
	assert_eq(skips[0]["value"], 0, "номер пропущенного шага")
	assert_almost_eq(float(skips[0]["at_sec"]), 10.0, 1e-6, "время пропуска")
	_tick(30)
	assert_eq(_session.executor.current_step_index(), 2, "следующая граница — через 30 с после пропуска")


func test_req_wrk_06_c3_skipping_last_step_finishes_not_marked_early() -> void:
	_make([WorkoutStep.percent(10, 50.0), WorkoutStep.percent(10, 100.0)])
	_session.start()
	_tick(10)
	_session.skip_step()
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED)
	assert_false(_session.metadata()["stopped_early"], "пропуск последнего — завершение по плану, не стоп")
	assert_eq(_events_of(WorkoutSession.EVENT_SKIP).size(), 1)
	assert_eq(_events_of(WorkoutSession.EVENT_FINISH).size(), 1)


func test_req_wrk_06_edge_skip_while_paused_defers_target_to_resume() -> void:
	_make([WorkoutStep.percent(60, 50.0), WorkoutStep.percent(60, 100.0)])
	_session.start()
	_tick(10)
	_session.pause()
	var before := _journal_size()
	_session.skip_step()
	assert_eq(_session.executor.current_step_index(), 1)
	assert_eq(_journal_size(), before, "на паузе цель нового шага не уходит")
	_session.resume()
	assert_eq(_cmds("target_power", before), [[200, 10.0]])


func test_req_wrk_06_edge_skip_when_idle_or_finished_is_ignored() -> void:
	_make([WorkoutStep.percent(10, 50.0)])
	_session.skip_step()
	assert_eq(_session.events, [], "до старта пропуск игнорируется")
	_session.start()
	_tick(10)
	var n := _session.events.size()
	_session.skip_step()
	assert_eq(_session.events.size(), n, "после финиша — тоже")


# ===========================================================================
# REQ-WRK-07 — множитель интенсивности
# ===========================================================================

func test_req_wrk_07_c1_range_50_150_step_5_default_100_and_no_event_without_change() -> void:
	_make([WorkoutStep.percent(60, 50.0)])
	assert_eq(_session.intensity(), 1.0, "по умолчанию 100 %")
	var changes: Array[float] = []
	_session.intensity_changed.connect(func(f: float) -> void: changes.append(f))
	var cases := {1.07: 1.05, 1.08: 1.10, 0.3: 0.5, 2.0: 1.5, 1.0: 1.0, 0.5: 0.5, 1.5: 1.5}
	for raw in cases.keys():
		_session.set_intensity(raw)
		assert_almost_eq(_session.intensity(), cases[raw], 1e-9, "%.2f → %.2f" % [raw, cases[raw]])
	assert_eq(changes, [1.05, 1.10, 0.5, 1.5, 1.0, 0.5, 1.5], "сигнал на каждое реальное изменение (7 из 7 — каждое значение отличалось от предыдущего)")
	var n := _events_of(WorkoutSession.EVENT_INTENSITY).size()
	_session.set_intensity(1.5)
	_session.set_intensity(1.52)
	_session.set_intensity(1.49)
	assert_eq(_events_of(WorkoutSession.EVENT_INTENSITY).size(), n, "без изменения (1.5, 1.52→1.5, 1.49→1.5) — без событий и сигналов")
	assert_eq(changes.size(), 7)
	assert_almost_eq(IntervalExecutor.snap_intensity(1.07), 1.05, 1e-9)


func test_req_wrk_07_c2_c3_multiplier_applies_to_watts_and_percent_and_sends_within_same_second() -> void:
	_make([WorkoutStep.watts(60, 200.0), WorkoutStep.percent(60, 65.0)])
	_session.start()
	_tick(12.5, 0.5)
	var before := _journal_size()
	_session.set_intensity(1.1)
	assert_eq(_cmds("target_power", before), [[220, 12.5]], "200 Вт при 110 % → 220, немедленно")
	_tick(47.5, 0.5)
	assert_eq(_cmds("target_power", before)[-1], [143, 60.0], "65 %% × 200 × 1.1 = 143 на следующем шаге")
	_session.set_intensity(0.9)
	assert_eq(_cmds("target_power", before)[-1][0], 117, "130 × 0.9 = 117")


func test_req_wrk_07_c5_intensity_is_stored_in_metadata_and_event_log() -> void:
	_make([WorkoutStep.percent(10, 50.0)], 0.95)
	assert_almost_eq(float(_session.metadata()["intensity"]), 0.95, 1e-9, "множитель конструктора")
	_session.start()
	_session.set_intensity(1.15)
	_tick(10)
	assert_almost_eq(float(_session.metadata()["intensity"]), 1.15, 1e-9)
	var ev := _events_of(WorkoutSession.EVENT_INTENSITY)
	assert_eq(ev.size(), 1)
	assert_almost_eq(float(ev[0]["value"]), 1.15, 1e-9)


# ===========================================================================
# REQ-WRK-08 — потоки 1 Гц
# ===========================================================================

func test_req_wrk_08_c1_600s_give_600_monotonic_samples() -> void:
	_make([WorkoutStep.percent(600, 50.0)])
	_session.start()
	_tick(600, 0.3)
	assert_eq(_session.samples.size(), 600)
	assert_true(_session.samples.is_monotonic())
	assert_eq(_session.samples.time_sec[0], 0)
	assert_eq(_session.samples.time_sec[599], 599)


func test_req_wrk_08_c2_sample_fields_and_no_data_flags() -> void:
	_make([WorkoutStep.percent(60, 50.0)])
	_trainer.set_heart_rate(140)
	_session.start()
	_tick(3)
	var row := _session.samples.row(2)
	for key in ["time_sec", "power_w", "heart_rate_bpm", "cadence_rpm", "speed_kmh", "target_w", "step_index", "erg_enabled"]:
		assert_true(row.has(key), "поле %s" % key)
	assert_eq(row["time_sec"], 2)
	assert_true(row["has_power"] and row["has_cadence"] and row["has_speed"] and row["has_heart_rate"])
	assert_eq(row["heart_rate_bpm"], 140)
	assert_eq(row["target_w"], 100)
	assert_eq(row["step_index"], 0)
	assert_eq(row["erg_enabled"], true)
	_trainer.inject_silence(3.0)
	_trainer.set_heart_rate(0)
	_tick(3)
	row = _session.samples.last_row()
	assert_false(row["has_power"], "нет телеметрии — «нет данных», не 0 и не повтор")
	assert_false(row["has_heart_rate"])
	assert_eq(row["target_w"], 100, "цель и шаг известны всегда")
	assert_eq(_session.samples.size(), 6, "слот есть даже без данных")


func test_req_wrk_08_c3_last_of_several_values_in_a_second_wins() -> void:
	_make([WorkoutStep.percent(10, 50.0)])
	_trainer.inject_silence(1000.0) # станок молчит — телеметрию подаём вручную
	_session.start()
	_trainer.telemetry.emit(TrainerSample.full(0.2, 111, 80, 30.0))
	_trainer.telemetry.emit(TrainerSample.full(0.5, 222, 81, 31.0))
	_trainer.telemetry.emit(TrainerSample.full(0.9, 333, 82, 32.0))
	_trainer.heart_rate.emit(120)
	_trainer.heart_rate.emit(125)
	_tick(1)
	var row := _session.samples.row(0)
	assert_eq(row["power_w"], 333, "последнее значение мощности")
	assert_eq(row["cadence_rpm"], 82)
	assert_eq(row["heart_rate_bpm"], 125, "последний пульс")


func test_req_wrk_08_c4_five_seconds_without_data_is_no_data_and_age_counts() -> void:
	_make([WorkoutStep.percent(60, 50.0)])
	_trainer.set_heart_rate(130)
	_session.start()
	_tick(3)
	assert_eq(_session.data_age_sec("power"), 0)
	_trainer.inject_silence(6.0)
	_trainer.set_heart_rate(0)
	_tick(5)
	assert_eq(_session.data_age_sec("power"), 5, "5 с без данных")
	assert_eq(_session.data_age_sec("heart_rate"), 5)
	assert_true(SampleStream.is_stale(5))
	assert_false(SampleStream.is_stale(4))
	assert_true(SampleStream.is_stale(-1))
	var row := _session.samples.last_row()
	assert_false(row["has_power"], "значение не повторяется")
	assert_eq(row["power_age_sec"], 5)
	_tick(2) # тишина кончилась на 9-й секунде, данные снова идут
	assert_eq(_session.data_age_sec("power"), 0, "возраст сбрасывается при новых данных")
	assert_true(_session.samples.last_row()["has_power"])


func test_req_wrk_08_c5_speed_source_trainer_when_speed_field_present() -> void:
	_make([WorkoutStep.percent(20, 100.0)])
	_session.start()
	_tick(20)
	assert_eq(_session.samples.speed_source, SampleStream.SPEED_SOURCE_TRAINER)
	assert_eq(_session.metadata()["speed_source"], "trainer")
	var row := _session.samples.last_row()
	assert_true(row["has_speed"])
	assert_almost_eq(float(row["speed_kmh"]), 34.0, 1.0, "скорость станка (эмулятор: 34 км/ч при 200 Вт)")
	assert_gt(float(_session.metadata()["distance_m"]), 0.0)


func test_req_wrk_08_c5_speed_source_model_when_trainer_has_no_speed_field() -> void:
	_trainer.emit_speed = false
	_make([WorkoutStep.percent(40, 100.0)], 1.0, 75.0)
	_session.start()
	_tick(40)
	assert_eq(_session.samples.speed_source, SampleStream.SPEED_SOURCE_MODEL)
	assert_eq(_session.metadata()["speed_source"], "model")
	var row := _session.samples.last_row()
	assert_true(row["has_speed"], "расчётная скорость присутствует в сэмпле")
	assert_almost_eq(float(row["speed_kmh"]), SpeedModel.steady_speed_kmh(200.0, 75.0), 0.5, "модель сошлась к установившейся при 200 Вт")
	assert_between(float(row["speed_kmh"]), 31.0, 37.0, "34 ± 3 км/ч при 200 Вт / 75 кг")
	assert_lt(float(_session.samples.row(0)["speed_kmh"]), 6.0, "старт с нуля, плавный разгон")
	_trainer.emit_speed = true
	_tick(0) # источник выбран один раз
	assert_eq(_session.samples.speed_source, SampleStream.SPEED_SOURCE_MODEL)


func test_req_wrk_08_c5_distance_is_integral_of_speed() -> void:
	_make([WorkoutStep.percent(10, 100.0)])
	_session.start()
	_tick(10)
	var expected := 0.0
	for i in 10:
		expected += float(_session.samples.speed_kmh[i]) / 3.6
	assert_almost_eq(_session.samples.total_distance_m(), expected, 1e-3)
	assert_almost_eq(float(_session.metadata()["distance_m"]), expected, 1e-3)


func test_req_wrk_08_sample_stream_dict_roundtrip_and_tolerant_from_dict() -> void:
	_trainer.set_heart_rate(150)
	_make([WorkoutStep.percent(5, 50.0), WorkoutStep.free_ride(5)])
	_session.start()
	_tick(10)
	var d := _session.samples.to_dict()
	var back := SampleStream.from_dict(d)
	assert_eq(back.to_dict(), d, "to_dict/from_dict без потерь")
	assert_eq(back.speed_source, "trainer")
	# JSON-прогон: числа становятся float
	var via_json: Dictionary = JSON.parse_string(JSON.stringify(d))
	var back2 := SampleStream.from_dict(via_json)
	assert_eq(back2.size(), 10)
	assert_eq(back2.power_w[3], _session.samples.power_w[3])
	assert_eq(back2.has_heart_rate[3], true)
	assert_eq(back2.step_index[7], 1)
	# неполные данные: колонки разной длины и отсутствующие
	var partial := SampleStream.from_dict({"time_sec": [0, 1, 2], "power_w": [100, 200], "has_power": [true, true]})
	assert_eq(partial.size(), 2, "обрезано до самой короткой колонки")
	assert_false(partial.has_cadence[1], "отсутствующие колонки — «нет данных»")
	assert_eq(partial.step_index[1], -1)
	assert_eq(SampleStream.from_dict({}).size(), 0)
	assert_eq(SampleStream.from_dict({"time_sec": "junk"}).size(), 0)


# ===========================================================================
# REQ-NFR-01 крит. 2 — повтор при ошибке записи
# ===========================================================================

func test_req_nfr_01_c2_write_failed_is_retried_once_in_same_second() -> void:
	_make([WorkoutStep.percent(10, 50.0), WorkoutStep.percent(10, 100.0)])
	_session.start()
	_tick(9)
	_trainer.fail_next_command(TrainerDevice.ErrorCode.WRITE_FAILED)
	var before := _journal_size()
	_tick(1)
	assert_eq(_cmds("target_power", before), [[200, 10.0], [200, 10.0]], "отвергнутая запись + один повтор в ту же секунду")
	assert_eq(_trainer.target_power_w, 200, "повтор принят станком")
	var retries := _events_of(WorkoutSession.EVENT_RETRY)
	assert_eq(retries.size(), 1)
	assert_eq(retries[0]["value"], 10)


func test_req_nfr_01_c2_two_write_failures_in_one_second_give_one_retry() -> void:
	_make([WorkoutStep.percent(10, 50.0), WorkoutStep.percent(10, 100.0)])
	_session.start()
	_tick(9)
	_trainer.fail_next_command(TrainerDevice.ErrorCode.WRITE_FAILED)
	var before := _journal_size()
	_tick(1)
	assert_eq(_cmds("target_power", before).size(), 2)
	_trainer.error.emit(TrainerDevice.ErrorCode.WRITE_FAILED, "второй отказ в ту же секунду")
	assert_eq(_cmds("target_power", before).size(), 2, "второго повтора в ту же секунду нет")
	assert_eq(_events_of(WorkoutSession.EVENT_RETRY).size(), 1)
	_tick(1)
	_trainer.error.emit(TrainerDevice.ErrorCode.WRITE_FAILED, "отказ в следующей секунде")
	assert_eq(_cmds("target_power", before).size(), 3, "в следующей секунде повтор снова возможен")


func test_req_nfr_01_c2_write_failed_on_pause_or_control_point_rejected_is_not_retried() -> void:
	_make([WorkoutStep.percent(60, 50.0)])
	_session.start()
	_tick(5)
	_session.pause()
	var before := _journal_size()
	_trainer.error.emit(TrainerDevice.ErrorCode.WRITE_FAILED, "на паузе")
	assert_eq(_journal_size(), before, "на паузе повтора нет")
	assert_eq(_events_of(WorkoutSession.EVENT_RETRY).size(), 0)
	_session.resume()
	before = _journal_size()
	_trainer.fail_next_command(TrainerDevice.ErrorCode.CONTROL_POINT_REJECTED)
	_session.set_intensity(1.1)
	assert_eq(_cmds("target_power", before).size(), 1, "CONTROL_POINT_REJECTED сессией не повторяется")
	assert_eq(_trainer.target_power_w, 100, "отвергнутая цель не применена")


func test_req_nfr_01_c2_write_failed_outside_erg_retries_resistance_level() -> void:
	_make([WorkoutStep.percent(60, 50.0)])
	_session.set_erg_enabled(false)
	_session.start()
	_tick(3)
	var before := _journal_size()
	_trainer.fail_next_command(TrainerDevice.ErrorCode.WRITE_FAILED)
	_session.set_resistance_level(80)
	assert_eq(_cmds("resistance", before), [[80, 3.0], [80, 3.0]], "уровень повторён в ту же секунду")
	assert_eq(_trainer.resistance_percent, 80)


# ===========================================================================
# Метаданные заезда
# ===========================================================================

func test_req_wrk_metadata_contains_required_fields() -> void:
	_make([WorkoutStep.percent(5, 50.0)], 1.05, 82.5)
	_session.start()
	_tick(5)
	var m := _session.metadata()
	for key in ["workout_name", "workout_source", "started_at_unix", "ftp_w", "weight_kg", "intensity", "erg_enabled",
			"resistance_level", "speed_source", "stopped_early", "elapsed_sec", "planned_sec", "distance_m", "sample_count", "event_count"]:
		assert_true(m.has(key), "metadata.%s" % key)
	assert_eq(m["ftp_w"], FTP)
	assert_almost_eq(float(m["weight_kg"]), 82.5, 1e-9)
	assert_gt(int(m["started_at_unix"]), 1_700_000_000)
	assert_eq(m["event_count"], _session.events.size())
	assert_eq(m["sample_count"], 5)


# ===========================================================================
# REQ-D3D-02 крит. 1–4 — только модель скорости
# ===========================================================================

func test_req_d3d_02_c1_steady_speed_monotonic_in_power_and_mass() -> void:
	var prev := 0.0
	for p in [50.0, 100.0, 150.0, 200.0, 300.0, 400.0, 800.0]:
		var v := SpeedModel.steady_speed_kmh(p, 75.0)
		assert_gt(v, prev, "растёт по мощности: %.0f Вт → %.1f" % [p, v])
		prev = v
	prev = 1e9
	for m in [50.0, 60.0, 75.0, 95.0, 120.0]:
		var v := SpeedModel.steady_speed_kmh(200.0, m)
		assert_lt(v, prev, "убывает по массе: %.0f кг → %.1f" % [m, v])
		prev = v
	assert_eq(SpeedModel.steady_speed_kmh(0.0, 75.0), 0.0)
	assert_eq(SpeedModel.steady_speed_kmh(-100.0, 75.0), 0.0)
	assert_eq(SpeedModel.from_power(200.0, 75.0), SpeedModel.steady_speed_kmh(200.0, 75.0))


func test_req_d3d_02_c2_reference_points_on_flat_road() -> void:
	assert_almost_eq(SpeedModel.steady_speed_kmh(200.0, 75.0), 34.0, 3.0)
	assert_almost_eq(SpeedModel.steady_speed_kmh(100.0, 75.0), 26.0, 3.0)
	assert_almost_eq(SpeedModel.steady_speed_kmh(300.0, 75.0), 40.0, 3.0)
	assert_lt(SpeedModel.steady_speed_kmh(200.0, 95.0), SpeedModel.steady_speed_kmh(200.0, 75.0))


func test_req_d3d_02_c3_zero_power_from_30_kmh_decays_monotonically_to_zero_within_30s() -> void:
	var m := SpeedModel.new()
	m.reset(30.0)
	var prev := 30.0
	var stopped_at := -1
	for i in 30:
		var v := m.step(0.0, 75.0, 1.0)
		assert_lte(v, prev, "монотонно убывает на шаге %d" % i)
		prev = v
		if v == 0.0 and stopped_at < 0:
			stopped_at = i + 1
	assert_true(stopped_at > 0 and stopped_at <= 30, "остановка не позже 30 с (факт: %d)" % stopped_at)


func test_req_d3d_02_c4_power_jump_0_to_400_changes_speed_at_most_5_kmh_per_sample() -> void:
	var m := SpeedModel.new()
	var prev := 0.0
	for i in 60:
		var v := m.step(400.0, 75.0, 1.0)
		assert_lte(v - prev, 5.0 + 1e-9, "шаг %d: прирост %.2f" % [i, v - prev])
		assert_gte(v, prev)
		prev = v
	assert_almost_eq(prev, SpeedModel.steady_speed_kmh(400.0, 75.0), 0.5, "сошлась к установившейся")


func test_req_d3d_02_edge_dt_zero_negative_weight_and_reset() -> void:
	var m := SpeedModel.new()
	m.reset(-5.0)
	assert_eq(m.speed_kmh, 0.0, "отрицательная начальная → 0")
	m.reset(20.0)
	assert_eq(m.step(200.0, 75.0, 0.0), 20.0, "dt 0 — без изменений")
	assert_eq(m.step(200.0, 75.0, -1.0), 20.0)
	var v := SpeedModel.steady_speed_kmh(200.0, -50.0)
	assert_true(v > 0.0 and v < SpeedModel.MAX_SPEED_KMH, "отрицательная масса трактуется как 0 кг всадника")
	assert_lt(SpeedModel.steady_speed_kmh(100000.0, 75.0), SpeedModel.MAX_SPEED_KMH + 1e-6, "ограничение сверху")
