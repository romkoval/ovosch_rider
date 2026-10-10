extends GutTest
## Независимая приёмка T-006/T-007 (коммит 637a04b): `IntervalExecutor`, `WorkoutSession`,
## `SampleStream` на `FakeTrainer`. Критерии: REQ-WRK-01 (все), REQ-WRK-02 крит. 1–5,
## REQ-WRK-05 крит. 1, 3, 5, REQ-WRK-06 крит. 1–3, REQ-WRK-07 крит. 1–4, REQ-WRK-08 крит. 1, 2, 3, 6,
## REQ-DEV-08 крит. 2, 3, REQ-DEV-09 крит. 6, REQ-NFR-01 крит. 1, REQ-NFR-02 крит. 1, 2.
## Имена: test_req_<area>_<nn>_c<k>_<описание>. К реальному станку не подключаемся.

const FTP: int = 200
const SEED: int = 11

var _trainer: FakeTrainer
var _session: WorkoutSession
var _finished: int = 0
var _step_events: Array[Dictionary] = []
var _targets: Array[int] = []
var _seconds: Array[int] = []


func before_each() -> void:
	_finished = 0
	_step_events = []
	_targets = []
	_seconds = []
	_trainer = FakeTrainer.new(SEED)
	_trainer.connect_delay_sec = 0.0
	_trainer.connect_device("fake-acceptance")
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)


func _steps(arr: Array) -> Array[WorkoutStep]:
	var out: Array[WorkoutStep] = []
	for s in arr:
		out.append(s)
	return out


func _plan_60_30_90() -> Workout:
	return Workout.make("60/30/90", _steps([
		WorkoutStep.percent(60, 65.0), WorkoutStep.percent(30, 100.0), WorkoutStep.percent(90, 50.0)]))


func _plan_150_250() -> Workout:
	return Workout.make("150→250", _steps([WorkoutStep.watts(10, 150.0), WorkoutStep.watts(10, 250.0)]))


func _plan_20_intervals() -> Workout:
	var arr: Array = []
	for i in 20:
		arr.append(WorkoutStep.watts(10, 100.0 + 10.0 * i))
	return Workout.make("20x", _steps(arr))


func _executor(w: Workout, intensity: float = 1.0) -> IntervalExecutor:
	var ex := IntervalExecutor.new(w, FTP, intensity)
	ex.finished.connect(func() -> void: _finished += 1)
	ex.step_changed.connect(func(i: int, s: WorkoutStep) -> void:
		_step_events.append({"index": i, "step": s, "elapsed": ex.elapsed_sec()}))
	ex.target_changed.connect(func(w_: int) -> void: _targets.append(w_))
	ex.second_elapsed.connect(func(t: int, _o: int, _r: int) -> void: _seconds.append(t))
	return ex


func _session_for(w: Workout, intensity: float = 1.0) -> WorkoutSession:
	var s := WorkoutSession.new(w, _trainer, FTP, intensity)
	s.session_finished.connect(func() -> void: _finished += 1)
	return s


func _tick_n(obj: Object, n: int, delta: float = 1.0) -> void:
	for i in n:
		obj.tick(delta)


func _cmds(type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in _trainer.commands:
		if c["type"] == type:
			out.append(c)
	return out


func _targets_cmds() -> Array[Dictionary]:
	return _cmds(FakeTrainer.CMD_TARGET_POWER)


# ---------------------------------------------------------------------------
# REQ-WRK-01 — запуск и автоматическое следование интервалам
# ---------------------------------------------------------------------------

func test_req_wrk_01_c1_transition_exactly_on_tick_when_offset_reaches_duration() -> void:
	var ex := _executor(_plan_60_30_90())
	ex.start()
	assert_eq(ex.current_step_index(), 0)
	_tick_n(ex, 59)
	assert_eq(ex.current_step_index(), 0, "на 59-м тике ещё первый шаг")
	assert_eq(ex.step_offset_sec(), 59)
	assert_eq(ex.step_remaining_sec(), 1)
	ex.tick(1.0)
	assert_eq(ex.current_step_index(), 1, "на тике 60 (offset ≥ duration) — переход")
	assert_eq(ex.step_offset_sec(), 0)
	assert_eq(ex.step_remaining_sec(), 30)
	_tick_n(ex, 29)
	assert_eq(ex.current_step_index(), 1)
	ex.tick(1.0)
	assert_eq(ex.current_step_index(), 2, "переход на тике 90")
	assert_eq(_step_events.size(), 3)
	assert_eq(_step_events[1]["elapsed"], 60, "событие перехода на 60-й секунде")
	assert_eq(_step_events[2]["elapsed"], 90)


func test_req_wrk_01_c2_plan_60_30_90_finishes_at_tick_180_once() -> void:
	var ex := _executor(_plan_60_30_90())
	ex.start()
	_tick_n(ex, 179)
	assert_false(ex.is_finished(), "на 179 с ещё не завершено")
	assert_eq(_finished, 0)
	ex.tick(1.0)
	assert_true(ex.is_finished(), "завершено ровно на тике 180")
	assert_eq(ex.elapsed_sec(), 180)
	assert_eq(_finished, 1, "событие завершения — один раз")
	_tick_n(ex, 20)
	ex.stop()
	ex.skip_step()
	assert_eq(_finished, 1, "повторных событий завершения нет")
	assert_eq(ex.elapsed_sec(), 180, "после финиша время не идёт")
	assert_eq(ex.current_step_index(), -1)


func test_req_wrk_01_c3_executor_and_session_are_not_scene_nodes() -> void:
	var ex: Variant = _executor(_plan_60_30_90())
	assert_false(ex is Node, "исполнитель — не Node")
	assert_true(ex is RefCounted)
	assert_false(ClassDB.is_parent_class((ex as Object).get_class(), "Node"))
	var s: Variant = _session_for(_plan_60_30_90())
	assert_false(s is Node, "сессия — не Node")
	assert_true(s is RefCounted)
	var stream: Variant = (s as WorkoutSession).samples
	assert_false(stream is Node)
	# Весь прогон — без SceneTree/_process: только явные tick().
	s.start()
	_tick_n(s, 180)
	assert_eq(s.get_state(), WorkoutSession.State.FINISHED)


func test_req_wrk_01_c4_step_event_carries_index_target_and_duration() -> void:
	var w := Workout.make("ev", _steps([
		WorkoutStep.percent(60, 65.0), WorkoutStep.watts(30, 250.0), WorkoutStep.ramp_watts(90, 100.0, 200.0)]))
	var ex := _executor(w)
	ex.start()
	_tick_n(ex, 90)
	assert_eq(_step_events.size(), 3, "событие на каждый вход в шаг (включая первый)")
	assert_eq(_step_events[0]["index"], 0)
	var s0: WorkoutStep = _step_events[0]["step"]
	assert_eq(s0.duration_sec, 60, "длительность в событии")
	assert_eq(s0.target_start, 65.0, "цель в событии")
	assert_eq(s0.target_kind, WorkoutStep.TargetKind.PERCENT_FTP)
	assert_eq(_step_events[1]["index"], 1)
	var s1: WorkoutStep = _step_events[1]["step"]
	assert_eq(s1.duration_sec, 30)
	assert_eq(s1.target_start, 250.0)
	assert_eq(_step_events[2]["index"], 2)
	var s2: WorkoutStep = _step_events[2]["step"]
	assert_eq(s2.target_start, 100.0)
	assert_eq(s2.target_end, 200.0)
	# Цель в ваттах на каждом переходе (первые три target_changed).
	assert_eq(_targets[0], 130)
	assert_eq(_targets[1], 250)
	assert_eq(_targets[2], 100)


func test_req_wrk_01_c5_full_plan_plays_on_fake_trainer() -> void:
	_session = _session_for(_plan_60_30_90())
	_session.start()
	assert_eq(_session.get_state(), WorkoutSession.State.RUNNING)
	_tick_n(_session, 180)
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED, "план доигран на FakeTrainer")
	assert_eq(_finished, 1)
	assert_eq(_session.samples.size(), 180)
	assert_eq(_session.samples.count_with_power(), 180, "станок выдавал телеметрию всю тренировку")
	# Станок реально держал цели: к концу каждого шага мощность у цели.
	var s := _session.samples
	assert_true(absi(s.power_w[59] - 130) <= 7, "конец шага 1: ~130 Вт, факт %d" % s.power_w[59])
	assert_true(absi(s.power_w[89] - 200) <= 10, "конец шага 2: ~200 Вт, факт %d" % s.power_w[89])
	assert_true(absi(s.power_w[179] - 100) <= 5, "конец шага 3: ~100 Вт, факт %d" % s.power_w[179])


func test_req_wrk_01_edge_empty_plan_finishes_immediately_no_commands_no_samples() -> void:
	_session = _session_for(Workout.new())
	_session.start()
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED, "пустой план завершается сразу")
	assert_eq(_finished, 1, "finished один раз")
	assert_eq(_trainer.commands.size(), 0, "на станок ничего не ушло")
	_tick_n(_session, 5)
	assert_eq(_session.samples.size(), 0, "сэмплы не пишутся")
	assert_eq(_finished, 1)
	assert_eq(_session.executor.current_step_index(), -1)
	assert_eq(_session.executor.elapsed_sec(), 0)


func test_req_wrk_01_edge_zero_duration_step_is_skipped_without_events_loop() -> void:
	var w := Workout.make("z", _steps([
		WorkoutStep.watts(5, 100.0), WorkoutStep.watts(0, 999.0), WorkoutStep.watts(5, 200.0)]))
	var ex := _executor(w)
	ex.start()
	_tick_n(ex, 5)
	assert_eq(ex.current_step_index(), 2, "шаг нулевой длительности пропущен")
	assert_eq(_step_events.size(), 2)
	assert_eq(_step_events[1]["index"], 2)
	assert_false(_targets.has(999), "цель пропущенного шага не испускалась")
	_tick_n(ex, 5)
	assert_true(ex.is_finished())
	assert_eq(_finished, 1)


# ---------------------------------------------------------------------------
# REQ-WRK-02 — ERG: передача целевой мощности на смене интервала
# ---------------------------------------------------------------------------

func test_req_wrk_02_c1_65pct_of_200_sends_130_watts_as_is_and_rounded() -> void:
	var w := Workout.make("c1", _steps([
		WorkoutStep.percent(10, 65.0), WorkoutStep.watts(10, 250.0), WorkoutStep.percent(10, 62.75)]))
	_session = _session_for(w)
	_session.start()
	_tick_n(_session, 20)
	var cmds := _targets_cmds()
	assert_eq(cmds.size(), 3)
	assert_eq(cmds[0]["value"], 130, "65 % FTP 200 → Set Target Power 130")
	assert_eq(cmds[1]["value"], 250, "ватты — как есть")
	# 62.75 % × 200 = 125.5: требование задаёт только «целые Вт» (правило половины не задано).
	# Наблюдение: из-за порядка операций value / 100.0 * ftp получается 125.4999… → 125,
	# хотя в комментарии WorkoutStep заявлено «0.5 → вверх».
	var v: int = cmds[2]["value"]
	assert_true(v == 125 or v == 126, "62.75 %% × 200 = 125.5 → целое 125 или 126 (факт %d)" % v)
	assert_eq(_trainer.target_power_w, v, "станок принял цель")
	assert_eq(_session.executor.workout.steps[2].target_watts_at(0.0, 201), 126,
		"62.75 % × 201 = 126.13 → 126 — однозначное округление до целого")
	assert_true(_trainer.erg_enabled)


func test_req_wrk_02_c2_command_at_boundary_with_1s_ticks() -> void:
	_session = _session_for(_plan_150_250())
	_session.start()
	_tick_n(_session, 20)
	var cmds := _targets_cmds()
	assert_eq(cmds.size(), 2)
	assert_eq(cmds[1]["value"], 250)
	assert_almost_eq(float(cmds[1]["at_sec"]), 10.0, 1e-6, "150→250: метка команды = граница 10 с")


func test_req_wrk_02_c2_command_at_boundary_with_0_2s_ticks() -> void:
	_session = _session_for(_plan_150_250())
	_session.start()
	_tick_n(_session, 100, 0.2)
	var cmds := _targets_cmds()
	assert_eq(cmds.size(), 2)
	assert_eq(cmds[1]["value"], 250)
	assert_almost_eq(float(cmds[1]["at_sec"]), 10.0, 1e-3, "150→250 при кадре 200 мс: метка = граница (факт %s)" % str(cmds[1]["at_sec"]))
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED)


func test_req_wrk_02_c2_command_at_boundary_with_60hz_ticks() -> void:
	_session = _session_for(_plan_150_250())
	_session.start()
	_tick_n(_session, 1200, 1.0 / 60.0)
	var cmds := _targets_cmds()
	assert_eq(cmds.size(), 2)
	assert_eq(cmds[1]["value"], 250)
	assert_almost_eq(float(cmds[1]["at_sec"]), 10.0, 1e-3, "150→250 при 60 Гц: метка = граница (факт %s)" % str(cmds[1]["at_sec"]))
	assert_eq(_session.samples.size(), 20, "20 слотов за 20 с при 60 Гц")
	assert_true(_session.samples.is_monotonic())


func test_req_wrk_02_c2_command_at_boundary_within_single_tick_2_5s() -> void:
	_session = _session_for(_plan_150_250())
	_session.start()
	_tick_n(_session, 8)
	_session.tick(2.5)
	var cmds := _targets_cmds()
	assert_eq(cmds.size(), 2, "переход произошёл внутри одного большого тика")
	assert_eq(cmds[1]["value"], 250)
	assert_almost_eq(float(cmds[1]["at_sec"]), 10.0, 1e-6, "метка команды — ровно граница 10 с, а не конец тика 10.5")
	assert_almost_eq(_trainer.get_time_sec(), 10.5, 1e-6)
	assert_eq(_session.samples.size(), 10, "слоты 0..9 закрыты")
	assert_eq(_session.samples.count_with_power(), 10)


func test_req_wrk_02_c3_ramp_target_each_second_on_1w_change_max_once_per_second() -> void:
	# 100 → 200 Вт за 50 с: 2 Вт/с → команда каждую секунду.
	var w := Workout.make("ramp", _steps([WorkoutStep.ramp_watts(50, 100.0, 200.0)]))
	_session = _session_for(w)
	_session.start()
	_tick_n(_session, 49)
	var cmds := _targets_cmds()
	assert_eq(cmds.size(), 50, "старт + 49 секунд рампы")
	assert_eq(cmds[0]["value"], 100)
	assert_eq(cmds[1]["value"], 102)
	assert_eq(cmds[49]["value"], 198)
	var seen := {}
	for c in cmds:
		var key := str(snappedf(float(c["at_sec"]), 0.001))
		assert_false(seen.has(key), "не чаще 1 команды в секунду (t=%s)" % key)
		seen[key] = true
	for i in range(1, cmds.size()):
		assert_true(int(cmds[i]["value"]) - int(cmds[i - 1]["value"]) >= 1, "каждая команда — изменение ≥ 1 Вт")


func test_req_wrk_02_c3_slow_ramp_sends_only_when_rounded_target_changes() -> void:
	# 100 → 110 Вт за 100 с: 0.1 Вт/с → команда только при смене целого значения.
	var w := Workout.make("slow", _steps([WorkoutStep.ramp_watts(100, 100.0, 110.0)]))
	_session = _session_for(w)
	_session.start()
	_tick_n(_session, 99)
	var cmds := _targets_cmds()
	assert_eq(cmds.size(), 11, "100,101,...,110 — 11 различных целей (факт %d)" % cmds.size())
	for i in range(1, cmds.size()):
		assert_eq(int(cmds[i]["value"]) - int(cmds[i - 1]["value"]), 1, "каждая команда — ровно +1 Вт")
	assert_eq(cmds.back()["value"], 110)


func test_req_wrk_02_c4_intensity_applied_before_sending() -> void:
	var w := Workout.make("c4", _steps([WorkoutStep.percent(10, 65.0), WorkoutStep.watts(10, 200.0)]))
	_session = _session_for(w, 1.1)
	_session.start()
	_tick_n(_session, 10)
	var cmds := _targets_cmds()
	assert_eq(cmds.size(), 2)
	assert_eq(cmds[0]["value"], 143, "130 × 1.1 = 143")
	assert_eq(cmds[1]["value"], 220, "200 × 1.1 = 220")
	assert_eq(_trainer.target_power_w, 220)


func test_req_wrk_02_c5_free_ride_sends_no_target_power() -> void:
	var w := Workout.make("fr", _steps([
		WorkoutStep.watts(10, 150.0), WorkoutStep.free_ride(10), WorkoutStep.watts(10, 250.0)]))
	_session = _session_for(w)
	_session.start()
	_tick_n(_session, 10)
	var before := _trainer.commands.size()
	_tick_n(_session, 9)
	assert_eq(_trainer.commands.size(), before, "на шаге FreeRide — никаких команд (ни цели, ни сопротивления)")
	assert_eq(_session.current_target_watts(), 0)
	assert_eq(_session.samples.target_w[15], 0, "в потоке цель 0 на свободной езде")
	_session.tick(1.0)
	var cmds := _targets_cmds()
	assert_eq(cmds.size(), 2, "после FreeRide цель следующего шага ушла")
	assert_eq(cmds[1]["value"], 250)
	assert_almost_eq(float(cmds[1]["at_sec"]), 20.0, 1e-6)
	# Наблюдение для владельца (не критерий): в ERG станок на FreeRide продолжает держать
	# последнюю отправленную цель (150 Вт), т.к. ERG не выключается и команда не шлётся.
	assert_eq(_trainer.target_power_w, 250)


func test_req_wrk_02_c5_free_ride_outside_erg_keeps_resistance_level() -> void:
	var w := Workout.make("fr", _steps([WorkoutStep.watts(10, 150.0), WorkoutStep.free_ride(10)]))
	_session = _session_for(w)
	_session.erg_enabled = false
	_session.resistance_level = 35
	_session.start()
	_tick_n(_session, 20)
	assert_eq(_targets_cmds().size(), 0, "вне ERG цель не шлётся")
	var res := _cmds(FakeTrainer.CMD_RESISTANCE)
	assert_eq(res.size(), 1, "уровень сопротивления ушёл один раз на старте")
	assert_eq(res[0]["value"], 35)
	assert_eq(_trainer.resistance_percent, 35, "сопротивление остаётся как в WRK-04")
	assert_false(_trainer.erg_enabled)


# ---------------------------------------------------------------------------
# REQ-WRK-05 — пауза и возобновление
# ---------------------------------------------------------------------------

func test_req_wrk_05_c1_pause_stops_step_and_total_timers() -> void:
	_session = _session_for(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 50)
	_session.pause()
	assert_eq(_session.get_state(), WorkoutSession.State.PAUSED)
	var ex := _session.executor
	assert_eq(ex.elapsed_sec(), 50)
	assert_eq(ex.step_remaining_sec(), 10)
	_tick_n(_session, 30)
	assert_eq(ex.elapsed_sec(), 50, "общий таймер стоит")
	assert_eq(ex.step_offset_sec(), 50, "таймер шага стоит")
	assert_eq(ex.step_remaining_sec(), 10)
	assert_eq(ex.current_step_index(), 0, "перехода на 60-й секунде не произошло — план не продвигается")
	assert_eq(ex.total_remaining_sec(), 130)
	assert_gt(_trainer.get_time_sec(), 50.0, "часы станка идут и на паузе")


func test_req_wrk_05_c3_resume_continues_same_remaining_and_resends_target_same_second() -> void:
	_session = _session_for(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 50)
	_session.pause()
	_tick_n(_session, 30)
	var cmds_before := _trainer.commands.size()
	_session.resume()
	assert_eq(_session.get_state(), WorkoutSession.State.RUNNING)
	assert_eq(_session.executor.step_remaining_sec(), 10, "остаток шага тот же")
	var cmds := _trainer.commands.slice(cmds_before)
	assert_eq(cmds.size(), 1, "при возобновлении — ровно одна команда")
	assert_eq(cmds[0]["type"], FakeTrainer.CMD_TARGET_POWER)
	assert_eq(cmds[0]["value"], 130, "повторно текущая цель")
	assert_almost_eq(float(cmds[0]["at_sec"]), 80.0, 1e-6, "в момент resume (≤ 1 с)")
	_tick_n(_session, 10)
	assert_eq(_session.executor.current_step_index(), 1, "через 10 с после resume — переход")
	assert_eq(_session.executor.elapsed_sec(), 60, "активное время без паузы")


func test_req_wrk_05_c3_resume_outside_erg_resends_resistance_level() -> void:
	_session = _session_for(_plan_60_30_90())
	_session.erg_enabled = false
	_session.resistance_level = 40
	_session.start()
	_tick_n(_session, 5)
	_session.pause()
	_tick_n(_session, 5)
	var before := _trainer.commands.size()
	_session.resume()
	var cmds := _trainer.commands.slice(before)
	assert_eq(cmds.size(), 1)
	assert_eq(cmds[0]["type"], FakeTrainer.CMD_RESISTANCE, "вне ERG — повторно уровень")
	assert_eq(cmds[0]["value"], 40)


func test_req_wrk_05_c5_nothing_sent_and_nothing_recorded_during_pause() -> void:
	_session = _session_for(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 20)
	_session.pause()
	var cmds_before := _trainer.commands.size()
	var samples_before := _session.samples.size()
	var target_before := _trainer.target_power_w
	_tick_n(_session, 50, 1.0)
	_tick_n(_session, 25, 0.2)
	assert_eq(_trainer.commands.size(), cmds_before, "журнал команд за паузу пуст")
	assert_eq(_trainer.target_power_w, target_before, "цель станка — последняя отправленная")
	assert_eq(_session.samples.size(), samples_before, "телеметрия на паузе не пишется")
	assert_eq(_session.executor.elapsed_sec(), 20, "время паузы не входит в прошедшее")
	_session.resume()
	_tick_n(_session, 1)
	assert_eq(_session.samples.size(), samples_before + 1, "после resume запись продолжается без дыр")
	assert_true(_session.samples.is_monotonic(), "метки времени без скачка за паузу")
	assert_eq(_session.samples.time_sec[samples_before], samples_before)


func test_req_wrk_05_c5_set_intensity_during_pause_is_deferred_to_resume() -> void:
	_session = _session_for(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 10)
	_session.pause()
	var before := _trainer.commands.size()
	_session.set_intensity(1.1)
	assert_eq(_trainer.commands.size(), before, "на паузе смена множителя ничего не шлёт")
	assert_eq(_session.current_target_watts(), 143, "цель сессии уже пересчитана")
	assert_eq(_trainer.target_power_w, 130, "станок ещё держит 130")
	_tick_n(_session, 3)
	_session.resume()
	var cmds := _trainer.commands.slice(before)
	assert_eq(cmds.size(), 1)
	assert_eq(cmds[0]["value"], 143, "при resume уходит новая цель 143")
	assert_eq(_trainer.target_power_w, 143)


func test_req_wrk_05_edge_pause_keeps_fraction_and_boundary_timing() -> void:
	_session = _session_for(_plan_150_250())
	_session.start()
	_tick_n(_session, 9)
	_session.tick(0.4)
	_session.pause()
	_tick_n(_session, 5)
	_session.resume()
	var before := _targets_cmds().size()
	_session.tick(0.5)
	assert_eq(_targets_cmds().size(), before, "0.4 + 0.5 < 1 — границы ещё нет")
	_session.tick(0.1)
	var cmds := _targets_cmds()
	assert_eq(cmds.size(), before + 1, "дробь сохранена на паузе: граница на 0.4 + 0.5 + 0.1")
	assert_eq(cmds.back()["value"], 250)


func test_req_wrk_05_edge_pause_resume_from_wrong_states_is_noop() -> void:
	_session = _session_for(_plan_60_30_90())
	_session.pause()
	assert_eq(_session.get_state(), WorkoutSession.State.IDLE, "пауза до старта игнорируется")
	_session.resume()
	assert_eq(_session.get_state(), WorkoutSession.State.IDLE)
	assert_eq(_trainer.commands.size(), 0)
	_session.start()
	_session.resume()
	assert_eq(_session.get_state(), WorkoutSession.State.RUNNING, "resume без паузы — ничего")
	assert_eq(_trainer.commands.size(), 1, "никаких лишних повторов цели")
	_tick_n(_session, 180)
	_session.pause()
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED, "пауза после финиша игнорируется")


# ---------------------------------------------------------------------------
# REQ-WRK-06 — пропуск интервала
# ---------------------------------------------------------------------------

func test_req_wrk_06_c1_skip_moves_to_next_step_and_shrinks_remaining() -> void:
	var ex := _executor(_plan_60_30_90())
	ex.start()
	_tick_n(ex, 20)
	assert_eq(ex.total_remaining_sec(), 160)
	ex.skip_step()
	assert_eq(ex.current_step_index(), 1, "сразу следующий шаг")
	assert_eq(ex.step_offset_sec(), 0)
	assert_eq(ex.step_remaining_sec(), 30)
	assert_eq(ex.total_remaining_sec(), 120, "остаток уменьшился на 40 с пропущенного шага")
	assert_eq(ex.elapsed_sec(), 20, "прошедшее время не прыгает")
	_tick_n(ex, 30)
	assert_eq(ex.current_step_index(), 2, "следующий переход через полную длительность шага 2")


func test_req_wrk_06_c2_skip_sends_new_target_immediately() -> void:
	_session = _session_for(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 20)
	_session.tick(0.3)
	var before := _trainer.commands.size()
	_session.skip_step()
	var cmds := _trainer.commands.slice(before)
	assert_eq(cmds.size(), 1)
	assert_eq(cmds[0]["type"], FakeTrainer.CMD_TARGET_POWER)
	assert_eq(cmds[0]["value"], 200, "цель нового шага (100 % × 200)")
	assert_almost_eq(float(cmds[0]["at_sec"]), 20.3, 1e-6, "в момент пропуска, без ожидания тика")
	assert_eq(_trainer.target_power_w, 200)


func test_req_wrk_06_c3_skip_last_step_finishes_once() -> void:
	_session = _session_for(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 100)
	assert_eq(_session.executor.current_step_index(), 2)
	_session.skip_step()
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED, "пропуск последнего шага завершает тренировку")
	assert_true(_session.executor.is_finished())
	assert_eq(_finished, 1, "session_finished один раз")
	var cmds_after := _trainer.commands.size()
	_session.skip_step()
	_session.skip_step()
	_tick_n(_session, 5)
	assert_eq(_finished, 1, "повторные пропуски/тики не дублируют завершение")
	assert_eq(_trainer.commands.size(), cmds_after, "и не шлют команд")
	assert_eq(_session.samples.size(), 100, "после финиша слоты не пишутся")


func test_req_wrk_06_c3_skip_all_steps_from_start_finishes_once() -> void:
	var ex := _executor(_plan_60_30_90())
	ex.start()
	ex.skip_step()
	ex.skip_step()
	assert_eq(ex.current_step_index(), 2)
	ex.skip_step()
	assert_true(ex.is_finished())
	assert_eq(_finished, 1)
	assert_eq(_step_events.size(), 3, "событие на каждый вход в шаг")
	assert_eq(ex.elapsed_sec(), 0)


func test_req_wrk_06_edge_skip_while_paused_defers_target_until_resume() -> void:
	_session = _session_for(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 10)
	_session.pause()
	var before := _trainer.commands.size()
	_session.skip_step()
	assert_eq(_session.executor.current_step_index(), 1, "шаг сменился и на паузе")
	assert_eq(_trainer.commands.size(), before, "на паузе команда не ушла (WRK-05.5)")
	_session.resume()
	var cmds := _trainer.commands.slice(before)
	assert_eq(cmds.size(), 1)
	assert_eq(cmds[0]["value"], 200, "цель нового шага ушла при resume")
	_tick_n(_session, 30)
	assert_eq(_session.executor.current_step_index(), 2)


func test_req_wrk_06_edge_skip_before_start_is_noop() -> void:
	var ex := _executor(_plan_60_30_90())
	ex.skip_step()
	assert_eq(ex.get_state(), IntervalExecutor.State.IDLE)
	assert_eq(_step_events.size(), 0)
	assert_eq(_finished, 0)


# ---------------------------------------------------------------------------
# REQ-WRK-07 — множитель интенсивности
# ---------------------------------------------------------------------------

func test_req_wrk_07_c1_intensity_range_50_150_step_5_default_100() -> void:
	var ex := _executor(_plan_60_30_90())
	assert_almost_eq(ex.intensity, 1.0, 1e-9, "по умолчанию 100 %")
	assert_almost_eq(IntervalExecutor.snap_intensity(0.3), 0.5, 1e-9, "ниже 50 % → 50 %")
	assert_almost_eq(IntervalExecutor.snap_intensity(2.0), 1.5, 1e-9, "выше 150 % → 150 %")
	assert_almost_eq(IntervalExecutor.snap_intensity(0.5), 0.5, 1e-9)
	assert_almost_eq(IntervalExecutor.snap_intensity(1.5), 1.5, 1e-9)
	assert_almost_eq(IntervalExecutor.snap_intensity(0.93), 0.95, 1e-9, "шаг 5 %: 93 → 95")
	assert_almost_eq(IntervalExecutor.snap_intensity(1.12), 1.1, 1e-9, "112 → 110")
	assert_almost_eq(IntervalExecutor.snap_intensity(1.1), 1.1, 1e-9)
	assert_almost_eq(IntervalExecutor.snap_intensity(-1.0), 0.5, 1e-9, "отрицательный → 50 %")
	assert_almost_eq(IntervalExecutor.snap_intensity(0.0), 0.5, 1e-9, "0 → 50 %")
	ex.set_intensity(0.07)
	assert_almost_eq(ex.intensity, 0.5, 1e-9)
	var ex2 := _executor(_plan_60_30_90(), 9.0)
	assert_almost_eq(ex2.intensity, 1.5, 1e-9, "множитель из конструктора тоже клампится")
	# Все 21 допустимое значение достижимы и устойчивы к повторному snap.
	for i in 21:
		var v := 0.5 + 0.05 * i
		assert_almost_eq(IntervalExecutor.snap_intensity(v), v, 1e-9, "snap(%.2f) стабилен" % v)


func test_req_wrk_07_c2_200w_at_110_sends_220() -> void:
	var w := Workout.make("c2", _steps([WorkoutStep.watts(60, 200.0), WorkoutStep.percent(60, 100.0)]))
	_session = _session_for(w)
	_session.start()
	_tick_n(_session, 5)
	_session.set_intensity(1.1)
	assert_eq(_trainer.target_power_w, 220, "цель 200 Вт при 110 % → 220 Вт")
	_tick_n(_session, 55)
	assert_eq(_trainer.target_power_w, 220, "и к % FTP: 100 % × 200 × 1.1 = 220")
	_session.set_intensity(0.5)
	assert_eq(_trainer.target_power_w, 100)
	_session.set_intensity(1.5)
	assert_eq(_trainer.target_power_w, 300)


func test_req_wrk_07_c3_set_intensity_in_erg_sends_new_target_same_second() -> void:
	_session = _session_for(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 10)
	_session.tick(0.25)
	var before := _trainer.commands.size()
	_session.set_intensity(0.9)
	var cmds := _trainer.commands.slice(before)
	assert_eq(cmds.size(), 1)
	assert_eq(cmds[0]["type"], FakeTrainer.CMD_TARGET_POWER)
	assert_eq(cmds[0]["value"], 117, "130 × 0.9 = 117")
	assert_almost_eq(float(cmds[0]["at_sec"]), 10.25, 1e-6, "немедленно (≤ 1 с)")
	_session.set_intensity(0.9)
	assert_eq(_trainer.commands.size(), before + 1, "тот же множитель — повторной команды нет")


func test_req_wrk_07_c3_set_intensity_outside_erg_sends_nothing() -> void:
	_session = _session_for(_plan_60_30_90())
	_session.erg_enabled = false
	_session.start()
	_tick_n(_session, 5)
	var before := _trainer.commands.size()
	_session.set_intensity(1.2)
	assert_eq(_trainer.commands.size(), before, "вне ERG цель не отправляется")
	assert_eq(_session.current_target_watts(), 156, "но цель сессии пересчитана (130 × 1.2)")


func test_req_wrk_07_c4_hud_target_and_profile_reflect_multiplier() -> void:
	_session = _session_for(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 5)
	assert_eq(_session.executor.current_target_watts(), 130)
	_session.set_intensity(1.1)
	assert_eq(_session.executor.current_target_watts(), 143, "цель для HUD-01 с множителем")
	assert_eq(_session.current_target_watts(), 143)
	var segs := _session.executor.workout.segments(FTP, _session.executor.intensity)
	assert_eq(segs[0]["start_watts"], 143, "профиль прогресса (HUD-07) с множителем")
	assert_eq(segs[1]["start_watts"], 220)
	assert_eq(segs[1]["zone"], 5, "зона сегмента пересчитана: 220 Вт → Z5")
	_tick_n(_session, 1)
	assert_eq(_session.samples.target_w[5], 143, "в потоке — цель с множителем")


# ---------------------------------------------------------------------------
# REQ-WRK-08 — поток 1 Гц
# ---------------------------------------------------------------------------

func test_req_wrk_08_c1_600s_gives_exactly_600_monotonic_slots() -> void:
	var w := Workout.make("600", _steps([WorkoutStep.percent(300, 50.0), WorkoutStep.percent(300, 75.0)]))
	_session = _session_for(w)
	_session.start()
	_tick_n(_session, 600)
	var s := _session.samples
	assert_eq(s.size(), 600, "ровно 600 слотов")
	assert_true(s.is_monotonic(), "метки монотонны с шагом 1 с")
	assert_eq(s.time_sec[0], 0)
	assert_eq(s.time_sec[599], 599)
	assert_eq(s.count_with_power(), 600)
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED)


func test_req_wrk_08_c1_600s_with_0_2s_frames_gives_600_slots() -> void:
	var w := Workout.make("600", _steps([WorkoutStep.percent(300, 50.0), WorkoutStep.percent(300, 75.0)]))
	_session = _session_for(w)
	_session.start()
	_tick_n(_session, 3000, 0.2)
	assert_eq(_session.samples.size(), 600, "600 слотов при кадре 200 мс")
	assert_true(_session.samples.is_monotonic())
	assert_eq(_session.samples.count_with_power(), 600, "каждая секунда получила телеметрию")


func test_req_wrk_08_c2_sample_contains_all_fields_and_no_data_flags() -> void:
	_trainer.set_heart_rate(140)
	_session = _session_for(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 61)
	var r := _session.samples.row(59)
	for key in ["time_sec", "power_w", "has_power", "heart_rate_bpm", "has_heart_rate",
			"cadence_rpm", "has_cadence", "speed_kmh", "has_speed", "target_w", "step_index", "erg_enabled"]:
		assert_true(r.has(key), "в сэмпле есть поле %s" % key)
	assert_eq(r["time_sec"], 59)
	assert_true(r["has_power"])
	assert_true(r["has_cadence"])
	assert_true(r["has_speed"])
	assert_gt(float(r["speed_kmh"]), 0.0)
	assert_true(r["has_heart_rate"])
	assert_eq(r["heart_rate_bpm"], 140)
	assert_eq(r["target_w"], 130)
	assert_eq(r["step_index"], 0)
	assert_true(r["erg_enabled"])
	var r60 := _session.samples.row(60)
	assert_eq(r60["step_index"], 1, "слот 60 — уже второй шаг")
	assert_eq(r60["target_w"], 200)


func test_req_wrk_08_c2_missing_heart_rate_is_no_data_not_zero() -> void:
	_session = _session_for(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 5)
	for i in 5:
		assert_false(_session.samples.has_heart_rate[i], "без датчика пульса — «нет данных»")
	_trainer.set_heart_rate_sequence([120, 125, 130] as Array[int])
	_tick_n(_session, 3)
	assert_true(_session.samples.has_heart_rate[5])
	assert_eq(_session.samples.heart_rate_bpm[5], 120)
	assert_eq(_session.samples.heart_rate_bpm[6], 125)
	assert_eq(_session.samples.heart_rate_bpm[7], 130, "последовательность 1 Гц попадает в слоты по порядку")


func test_req_wrk_08_c2_silence_gives_no_data_slots_without_repeating_last() -> void:
	_session = _session_for(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 10)
	var last_power := _session.samples.power_w[9]
	assert_gt(last_power, 0)
	_trainer.inject_silence(4.0)
	_tick_n(_session, 10)
	var s := _session.samples
	assert_eq(s.size(), 20, "слот на каждую секунду, даже без данных")
	assert_true(s.is_monotonic())
	for i in range(10, 14):
		assert_false(s.has_power[i], "слот %d — нет данных" % i)
		assert_false(s.has_cadence[i])
		# Скорость — модель (У-30): без мощности тяги нет, она убывает, а не повторяется (У-33).
		assert_true(s.speed_kmh[i] <= s.speed_kmh[i - 1] + 1e-4, "слот %d: скорость модели не растёт без мощности" % i)
		assert_ne(s.power_w[i], last_power, "последнее значение не повторяется")
	assert_true(s.has_power[14], "после тишины данные снова есть")
	assert_eq(s.count_with_power(), 16)


func test_req_wrk_08_c3_several_values_in_one_second_keep_last() -> void:
	_session = _session_for(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 3)
	_trainer.inject_silence(5.0)  # станок молчит — подаём телеметрию вручную
	_trainer.telemetry.emit(TrainerSample.full(3.2, 111, 71, 21.0))
	_trainer.heart_rate.emit(101)
	_trainer.telemetry.emit(TrainerSample.full(3.6, 222, 72, 22.0))
	_trainer.heart_rate.emit(102)
	_trainer.telemetry.emit(TrainerSample.full(3.9, 333, 73, 23.0))
	_trainer.heart_rate.emit(103)
	_session.tick(1.0)
	var r := _session.samples.row(3)
	assert_eq(r["power_w"], 333, "в сэмпл попало последнее значение мощности")
	assert_eq(r["cadence_rpm"], 73)
	assert_ne(float(r["speed_kmh"]), 23.0, "скорость станка в сэмпл не попадает (У-30) — модель")
	assert_eq(r["heart_rate_bpm"], 103, "последний пульс")
	_session.tick(1.0)
	assert_false(_session.samples.has_power[4], "значение не «перетекает» в следующий слот")
	assert_false(_session.samples.has_heart_rate[4])


func test_req_wrk_08_c6_irregular_frame_deltas_do_not_change_slot_count() -> void:
	_session = _session_for(_plan_60_30_90())
	_session.start()
	var deltas := [0.016, 0.3, 2.5, 0.7, 1.0, 0.05, 3.0, 0.45]
	var total := 0.0
	while total < 180.0:
		for d in deltas:
			_session.tick(d)
			total += d
	var s := _session.samples
	assert_eq(s.size(), 180, "180 слотов при рваных кадрах")
	assert_true(s.is_monotonic())
	assert_eq(s.count_with_power(), 180, "ни один слот не потерял телеметрию")
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED)
	var cmds := _targets_cmds()
	assert_eq(cmds.size(), 3)
	assert_almost_eq(float(cmds[1]["at_sec"]), 60.0, 1e-6, "граница 60 с точна и при рваных кадрах")
	assert_almost_eq(float(cmds[2]["at_sec"]), 90.0, 1e-6)


# ---------------------------------------------------------------------------
# REQ-DEV-08 — обрыв и восстановление связи
# ---------------------------------------------------------------------------

func test_req_dev_08_c2_dropout_keeps_timer_and_writes_no_data_slots() -> void:
	_session = _session_for(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 20)
	_trainer.inject_dropout(3.0)
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING)
	_tick_n(_session, 3)
	var s := _session.samples
	assert_eq(s.size(), 23, "запись сэмплов продолжается во время обрыва")
	assert_eq(_session.executor.elapsed_sec(), 23, "таймер сессии идёт")
	for i in range(20, 23):
		assert_false(s.has_power[i], "слот %d: «нет данных», а не 0 как значение" % i)
		assert_false(s.has_cadence[i])
		assert_true(s.speed_kmh[i] <= s.speed_kmh[i - 1] + 1e-4, "слот %d: скорость модели убывает без мощности (У-33)" % i)
	assert_eq(s.target_w[21], 130, "цель и шаг в слоте по-прежнему известны")
	assert_eq(s.step_index[21], 0)
	assert_true(s.is_monotonic(), "меток не потеряно")
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	_tick_n(_session, 1)
	assert_true(s.has_power[23], "после восстановления данные снова пишутся")


func test_req_dev_08_c3_reconnect_resends_current_target_within_same_second() -> void:
	_session = _session_for(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 20)
	_trainer.inject_dropout(3.0)
	var before := _trainer.commands.size()
	_tick_n(_session, 2)
	assert_eq(_trainer.commands.size(), before, "пока связи нет — не шлём")
	_session.tick(1.0)
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	var cmds := _trainer.commands.slice(before)
	assert_eq(cmds.size(), 2, "ERG + цель")
	assert_eq(cmds[0]["type"], FakeTrainer.CMD_ERG)
	assert_eq(cmds[0]["value"], true)
	assert_eq(cmds[1]["type"], FakeTrainer.CMD_TARGET_POWER)
	assert_eq(cmds[1]["value"], 130, "цель текущего интервала")
	assert_almost_eq(float(cmds[1]["at_sec"]), 23.0, 1e-6, "в ту же секунду, что connected")
	assert_eq(_trainer.target_power_w, 130)


func test_req_dev_08_c3_step_change_during_dropout_resends_new_target_on_reconnect() -> void:
	_session = _session_for(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 58)
	_trainer.inject_dropout(4.0)
	_tick_n(_session, 4)
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_session.executor.current_step_index(), 1, "граница 60 с прошла во время обрыва")
	var cmds := _targets_cmds()
	assert_eq(cmds.back()["value"], 200, "после восстановления — цель уже нового интервала")
	assert_almost_eq(float(cmds.back()["at_sec"]), 62.0, 1e-6)
	assert_eq(_trainer.target_power_w, 200)


func test_req_dev_08_c3_first_connection_after_start_resends_target() -> void:
	# Сессия стартует до того, как станок подключился: первая команда отклонена,
	# после CONNECTED цель уходит повторно (тот же механизм, что при переподключении).
	var t := FakeTrainer.new(SEED)
	t.connect_delay_sec = 0.5
	t.connect_device("late")
	assert_eq(t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTING)
	var errors: Array[int] = []
	t.error.connect(func(code: int, _m: String) -> void: errors.append(code))
	var s := WorkoutSession.new(_plan_60_30_90(), t, FTP)
	s.start()
	assert_eq(t.target_power_w, 0, "до подключения цель не применена")
	assert_true(errors.has(TrainerDevice.ErrorCode.NOT_CONNECTED))
	s.tick(0.5)
	assert_eq(t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(t.target_power_w, 130, "после connected цель отправлена повторно")
	var last: Dictionary = t.commands.back()
	assert_eq(last["type"], FakeTrainer.CMD_TARGET_POWER)
	assert_almost_eq(float(last["at_sec"]), 0.5, 1e-6, "в момент подключения")
	_tick_n(s, 180)
	assert_eq(s.get_state(), WorkoutSession.State.FINISHED)
	assert_eq(s.samples.size(), 180)


func test_req_dev_08_edge_reconnect_while_paused_resends_on_resume() -> void:
	# Наблюдение: при обрыве на паузе цель уходит не «≤ 1 с после connected», а при
	# resume — по решению В-4 (на паузе ничего не шлём). Фиксируем фактическое поведение.
	_session = _session_for(_plan_60_30_90())
	_session.start()
	_tick_n(_session, 10)
	_session.pause()
	_trainer.inject_dropout(2.0)
	var before := _trainer.commands.size()
	_tick_n(_session, 5)
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_trainer.commands.size(), before, "на паузе после переподключения не шлём")
	_session.resume()
	var cmds := _trainer.commands.slice(before)
	assert_eq(cmds.size(), 1)
	assert_eq(cmds[0]["value"], 130, "цель ушла при resume")


# ---------------------------------------------------------------------------
# REQ-DEV-09 крит. 6 — проигрывание тренировки на симуляторе
# ---------------------------------------------------------------------------

func test_req_dev_09_c6_session_plays_workout_on_fake_trainer_with_telemetry() -> void:
	_trainer.set_heart_rate(135)
	var w := Workout.make("dev", _steps([
		WorkoutStep.percent(30, 50.0), WorkoutStep.ramp_percent(30, 50.0, 100.0),
		WorkoutStep.free_ride(20), WorkoutStep.watts(20, 250.0)]))
	_session = _session_for(w)
	_session.start()
	_tick_n(_session, 100)
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED)
	assert_eq(_finished, 1)
	var s := _session.samples
	assert_eq(s.size(), 100)
	assert_eq(s.count_with_power(), 100)
	assert_true(s.has_heart_rate[50])
	assert_true(absi(s.power_w[29] - 100) <= 6, "ERG: мощность у цели 100 Вт (факт %d)" % s.power_w[29])
	assert_true(absi(s.power_w[99] - 250) <= 13, "ERG: мощность у цели 250 Вт (факт %d)" % s.power_w[99])
	assert_eq(s.step_index[70], 2)
	assert_eq(s.target_w[70], 0, "свободная езда — цель 0")
	assert_eq(_trainer.samples_emitted, 100)


# ---------------------------------------------------------------------------
# REQ-NFR-01 крит. 1 — задержка ≤ 1 с на всех переходах 20-интервального плана
# ---------------------------------------------------------------------------

func _assert_all_transitions_within_1s(w: Workout, label: String) -> void:
	var cmds := _targets_cmds()
	assert_eq(cmds.size(), 20, "%s: команда на каждый из 20 интервалов" % label)
	var max_lag := 0.0
	for i in cmds.size():
		var boundary := float(w.step_start_sec(i))
		var lag: float = float(cmds[i]["at_sec"]) - boundary
		max_lag = maxf(max_lag, absf(lag))
		assert_true(lag >= -1e-3 and lag <= 1.0, "%s: переход %d — задержка %.4f с" % [label, i, lag])
		assert_eq(cmds[i]["value"], 100 + 10 * i, "%s: цель интервала %d" % [label, i])
	assert_true(max_lag <= 1.0, "%s: максимальная задержка %.4f с ≤ 1 с" % [label, max_lag])


func test_req_nfr_01_c1_20_intervals_all_commands_within_1s_at_1hz() -> void:
	var w := _plan_20_intervals()
	_session = _session_for(w)
	_session.start()
	_tick_n(_session, 200)
	_assert_all_transitions_within_1s(w, "1 Гц")
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED)


func test_req_nfr_01_c1_20_intervals_all_commands_within_1s_at_200ms_frames() -> void:
	var w := _plan_20_intervals()
	_session = _session_for(w)
	_session.start()
	_tick_n(_session, 1000, 0.2)
	_assert_all_transitions_within_1s(w, "кадр 200 мс")
	assert_eq(_session.samples.size(), 200)


func test_req_nfr_01_c1_20_intervals_with_frozen_frames_within_1s() -> void:
	var w := _plan_20_intervals()
	_session = _session_for(w)
	_session.start()
	var total := 0.0
	var pattern := [0.2, 0.2, 2.0, 0.2, 1.4]
	while total < 200.0:
		for d in pattern:
			_session.tick(d)
			total += d
	_assert_all_transitions_within_1s(w, "заморозки 2 с")


# ---------------------------------------------------------------------------
# REQ-NFR-02 — независимость от цикла отрисовки
# ---------------------------------------------------------------------------

func test_req_nfr_02_c1_60_ticks_without_process_give_60_samples_and_transition() -> void:
	var w := Workout.make("nfr", _steps([WorkoutStep.watts(30, 150.0), WorkoutStep.watts(30, 250.0)]))
	_session = _session_for(w)
	_session.start()
	_tick_n(_session, 60)
	assert_eq(_session.samples.size(), 60, "60 тиков → 60 сэмплов")
	assert_eq(_session.samples.count_with_power(), 60)
	assert_eq(_session.samples.step_index[29], 0)
	assert_eq(_session.samples.step_index[30], 1, "переход на 30-й секунде")
	assert_eq(_session.samples.target_w[30], 250)
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED)


func test_req_nfr_02_c2_frame_freeze_2s_samples_present_with_correct_labels() -> void:
	_session = _session_for(_plan_150_250())
	_session.start()
	_tick_n(_session, 8)
	_session.tick(2.0)  # заморозка кадра на 2 с
	var s := _session.samples
	assert_eq(s.size(), 10, "сэмплы за замороженные секунды есть")
	assert_true(s.is_monotonic())
	assert_eq(s.time_sec[8], 8)
	assert_eq(s.time_sec[9], 9)
	assert_true(s.has_power[8] and s.has_power[9], "у каждого — своя телеметрия")
	var cmds := _targets_cmds()
	assert_eq(cmds.size(), 2)
	assert_almost_eq(float(cmds[1]["at_sec"]), 10.0, 1e-6, "команда перехода — на границе, а не в конце заморозки")
	_tick_n(_session, 10)
	assert_eq(s.size(), 20)
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED)


func test_req_nfr_02_c2_single_huge_tick_covers_whole_plan() -> void:
	_session = _session_for(_plan_60_30_90())
	_session.start()
	_session.tick(185.0)
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED)
	assert_eq(_session.samples.size(), 180, "все 180 слотов записаны постфактум")
	assert_true(_session.samples.is_monotonic())
	assert_eq(_session.samples.count_with_power(), 180)
	var cmds := _targets_cmds()
	assert_eq(cmds.size(), 3)
	assert_almost_eq(float(cmds[1]["at_sec"]), 60.0, 1e-6)
	assert_almost_eq(float(cmds[2]["at_sec"]), 90.0, 1e-6)
	assert_eq(_finished, 1)
