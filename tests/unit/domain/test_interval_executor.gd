extends GutTest
## Тесты исполнителя интервалов IntervalExecutor (REQ-WRK-01, WRK-05, WRK-06, WRK-07, NFR-02).

const FTP: int = 200

var _ex: IntervalExecutor
## Журнал событий: словари {type, ...} в порядке испускания.
var _log: Array[Dictionary] = []


func before_each() -> void:
	_log = []


func _plan_60_30_90() -> Workout:
	var steps: Array[WorkoutStep] = [
		WorkoutStep.percent(60, 65.0),
		WorkoutStep.percent(30, 100.0),
		WorkoutStep.percent(90, 50.0),
	]
	return Workout.make("60/30/90", steps)


func _make(w: Workout, intensity: float = 1.0) -> IntervalExecutor:
	var ex := IntervalExecutor.new(w, FTP, intensity)
	ex.step_changed.connect(func(i: int, s: WorkoutStep) -> void:
		_log.append({"type": "step", "index": i, "step": s, "elapsed": ex.elapsed_sec()}))
	ex.target_changed.connect(func(w_: int) -> void:
		_log.append({"type": "target", "watts": w_, "elapsed": ex.elapsed_sec()}))
	ex.second_elapsed.connect(func(e: int, o: int, r: int) -> void:
		_log.append({"type": "second", "elapsed": e, "offset": o, "remaining": r}))
	ex.cue.connect(func(t: String) -> void:
		_log.append({"type": "cue", "text": t, "elapsed": ex.elapsed_sec()}))
	ex.finished.connect(func() -> void:
		_log.append({"type": "finished", "elapsed": ex.elapsed_sec()}))
	ex.state_changed.connect(func(st: int) -> void:
		_log.append({"type": "state", "state": st}))
	return ex


func _of_type(type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _log:
		if e["type"] == type:
			out.append(e)
	return out


func _tick_n(ex: IntervalExecutor, n: int, delta: float = 1.0) -> void:
	for i in n:
		ex.tick(delta)


# ---------------------------------------------------------------------------
# Запуск и переходы
# ---------------------------------------------------------------------------

func test_initial_state_idle_and_getters_empty() -> void:
	_ex = _make(_plan_60_30_90())
	assert_eq(_ex.get_state(), IntervalExecutor.State.IDLE)
	assert_eq(_ex.current_step_index(), -1)
	assert_null(_ex.current_step())
	assert_eq(_ex.elapsed_sec(), 0)
	assert_eq(_ex.total_remaining_sec(), 0)
	assert_eq(_ex.current_target_watts(), 0)
	assert_false(_ex.is_finished())


func test_start_enters_first_step_and_emits_target() -> void:
	_ex = _make(_plan_60_30_90())
	_ex.start()
	assert_eq(_ex.get_state(), IntervalExecutor.State.RUNNING)
	assert_eq(_ex.current_step_index(), 0)
	var steps := _of_type("step")
	assert_eq(steps.size(), 1)
	assert_eq(steps[0]["index"], 0)
	assert_eq((steps[0]["step"] as WorkoutStep).duration_sec, 60, "REQ-WRK-01 крит. 4: событие несёт шаг")
	var targets := _of_type("target")
	assert_eq(targets.size(), 1)
	assert_eq(targets[0]["watts"], 130, "65 % FTP 200 → 130 Вт (REQ-WRK-02 крит. 1)")
	assert_eq(_ex.current_target_watts(), 130)
	assert_eq(_ex.total_remaining_sec(), 180)


func test_transitions_on_exact_ticks_and_finishes_at_180() -> void:
	_ex = _make(_plan_60_30_90())
	_ex.start()
	_tick_n(_ex, 59)
	assert_eq(_ex.current_step_index(), 0)
	_ex.tick(1.0)
	assert_eq(_ex.current_step_index(), 1, "переход на тике 60, когда offset >= duration")
	_tick_n(_ex, 30)
	assert_eq(_ex.current_step_index(), 2)
	_tick_n(_ex, 89)
	assert_false(_ex.is_finished())
	_ex.tick(1.0)
	assert_true(_ex.is_finished(), "REQ-WRK-01 крит. 2: план 60/30/90 завершается на тике 180")
	assert_eq(_ex.elapsed_sec(), 180)
	var fin := _of_type("finished")
	assert_eq(fin.size(), 1, "finished ровно один раз")
	assert_eq(fin[0]["elapsed"], 180)
	var steps := _of_type("step")
	assert_eq(steps.size(), 3)
	assert_eq(steps[1]["elapsed"], 60)
	assert_eq(steps[2]["elapsed"], 90)
	var targets := _of_type("target")
	assert_eq(targets.size(), 3, "постоянные шаги: цель только на границах")
	assert_eq(targets[1]["watts"], 200)
	assert_eq(targets[1]["elapsed"], 60, "цель — в ту же секунду, что граница шага (REQ-NFR-01)")
	assert_eq(targets[2]["watts"], 100)


func test_second_elapsed_values_and_order_at_boundary() -> void:
	_ex = _make(_plan_60_30_90())
	_ex.start()
	_ex.tick(1.0)
	var sec := _of_type("second")
	assert_eq(sec[0]["elapsed"], 1)
	assert_eq(sec[0]["offset"], 1)
	assert_eq(sec[0]["remaining"], 59)
	_log = []
	_tick_n(_ex, 59)
	# На секунде 60: second_elapsed(60, 60, 0) идёт ДО step_changed(1).
	var types: Array[String] = []
	for e in _log:
		if e["elapsed"] == 60 and e["type"] != "state":
			types.append(e["type"])
	assert_eq(types, ["second", "step", "target"] as Array[String])
	var last_sec: Dictionary = _of_type("second").back()
	assert_eq(last_sec["offset"], 60)
	assert_eq(last_sec["remaining"], 0)
	assert_eq(_ex.step_offset_sec(), 0)
	assert_eq(_ex.step_remaining_sec(), 30)


func test_fractional_ticks_accumulate_to_whole_seconds() -> void:
	_ex = _make(_plan_60_30_90())
	_ex.start()
	_ex.tick(-1.0)
	_ex.tick(0.0)
	assert_eq(_ex.elapsed_sec(), 0, "delta <= 0 игнорируется")
	_tick_n(_ex, 3, 0.25)
	assert_eq(_ex.elapsed_sec(), 0, "0.75 с — ещё нет целой секунды")
	assert_eq(_of_type("second").size(), 0)
	_ex.tick(0.25)
	assert_eq(_ex.elapsed_sec(), 1)
	_log = []
	_tick_n(_ex, 295, 0.2)
	assert_eq(_ex.elapsed_sec(), 60, "1 + 295 × 0.2 = 60 с без накопления ошибки")
	assert_eq(_ex.current_step_index(), 1)


func test_large_delta_catches_up_multiple_seconds() -> void:
	_ex = _make(_plan_60_30_90())
	_ex.start()
	_ex.tick(2.5)
	assert_eq(_ex.elapsed_sec(), 2, "REQ-NFR-02: пропущенные секунды догоняются")
	assert_eq(_of_type("second").size(), 2)
	_ex.tick(0.5)
	assert_eq(_ex.elapsed_sec(), 3, "остаток 0.5 сохранён")


func test_tick_ignored_when_idle_or_finished_and_start_twice_ignored() -> void:
	_ex = _make(_plan_60_30_90())
	_ex.tick(5.0)
	assert_eq(_ex.elapsed_sec(), 0)
	_ex.start()
	_ex.start()
	assert_eq(_of_type("step").size(), 1, "повторный start игнорируется")
	_tick_n(_ex, 180)
	_log = []
	_ex.tick(5.0)
	assert_eq(_log.size(), 0)
	assert_eq(_ex.elapsed_sec(), 180)


func test_empty_workout_finishes_immediately() -> void:
	_ex = _make(Workout.new())
	_ex.start()
	assert_true(_ex.is_finished())
	assert_eq(_of_type("finished").size(), 1)
	assert_eq(_of_type("step").size(), 0)


func test_zero_duration_step_is_skipped_over() -> void:
	var steps: Array[WorkoutStep] = [
		WorkoutStep.percent(10, 50.0),
		WorkoutStep.percent(0, 100.0),
		WorkoutStep.percent(10, 75.0),
	]
	_ex = _make(Workout.make("zero", steps))
	_ex.start()
	_tick_n(_ex, 10)
	assert_eq(_ex.current_step_index(), 2, "шаг нулевой длительности не может «идти»")
	assert_eq(_of_type("target").back()["watts"], 150)


# ---------------------------------------------------------------------------
# Пауза, пропуск, стоп
# ---------------------------------------------------------------------------

func test_pause_freezes_time_and_events_resume_continues() -> void:
	_ex = _make(_plan_60_30_90())
	_ex.start()
	_tick_n(_ex, 10)
	_ex.pause()
	assert_eq(_ex.get_state(), IntervalExecutor.State.PAUSED)
	_log = []
	_tick_n(_ex, 100)
	assert_eq(_log.size(), 0, "REQ-WRK-05 крит. 1: на паузе ни событий, ни времени")
	assert_eq(_ex.elapsed_sec(), 10)
	assert_eq(_ex.step_remaining_sec(), 50)
	_ex.resume()
	assert_eq(_ex.get_state(), IntervalExecutor.State.RUNNING)
	_tick_n(_ex, 50)
	assert_eq(_ex.current_step_index(), 1, "возобновление с того же остатка (крит. 3)")
	assert_eq(_ex.elapsed_sec(), 60)


func test_pause_keeps_fractional_accumulator() -> void:
	_ex = _make(_plan_60_30_90())
	_ex.start()
	_ex.tick(0.5)
	_ex.pause()
	_ex.tick(0.5)
	_ex.resume()
	assert_eq(_ex.elapsed_sec(), 0)
	_ex.tick(0.5)
	assert_eq(_ex.elapsed_sec(), 1)


func test_pause_resume_only_from_valid_states() -> void:
	_ex = _make(_plan_60_30_90())
	_ex.pause()
	assert_eq(_ex.get_state(), IntervalExecutor.State.IDLE)
	_ex.resume()
	assert_eq(_ex.get_state(), IntervalExecutor.State.IDLE)
	_ex.start()
	_ex.resume()
	assert_eq(_ex.get_state(), IntervalExecutor.State.RUNNING)


func test_skip_step_moves_immediately_and_shrinks_remaining() -> void:
	_ex = _make(_plan_60_30_90())
	_ex.start()
	_tick_n(_ex, 10)
	_log = []
	_ex.skip_step()
	assert_eq(_ex.current_step_index(), 1)
	assert_eq(_ex.elapsed_sec(), 10, "прошедшее время не прыгает")
	assert_eq(_ex.total_remaining_sec(), 120, "REQ-WRK-06 крит. 1: минус остаток 50 с")
	assert_eq(_of_type("target")[0]["watts"], 200, "крит. 2: новая цель сразу")
	_tick_n(_ex, 30)
	assert_eq(_ex.current_step_index(), 2)


func test_skip_last_step_finishes() -> void:
	_ex = _make(_plan_60_30_90())
	_ex.start()
	_ex.skip_step()
	_ex.skip_step()
	assert_eq(_ex.current_step_index(), 2)
	_ex.skip_step()
	assert_true(_ex.is_finished(), "REQ-WRK-06 крит. 3")
	assert_eq(_of_type("finished").size(), 1)
	assert_false(_ex.stopped_early)
	_ex.skip_step()
	assert_eq(_of_type("finished").size(), 1)


func test_skip_allowed_while_paused() -> void:
	_ex = _make(_plan_60_30_90())
	_ex.start()
	_ex.pause()
	_ex.skip_step()
	assert_eq(_ex.current_step_index(), 1)
	assert_eq(_ex.get_state(), IntervalExecutor.State.PAUSED)


func test_stop_finishes_early_once() -> void:
	_ex = _make(_plan_60_30_90())
	_ex.start()
	_tick_n(_ex, 5)
	_ex.stop()
	assert_true(_ex.is_finished())
	assert_true(_ex.stopped_early)
	assert_eq(_of_type("finished").size(), 1)
	_ex.stop()
	_tick_n(_ex, 10)
	assert_eq(_of_type("finished").size(), 1)
	assert_eq(_ex.elapsed_sec(), 5)
	assert_eq(_ex.current_step_index(), -1)
	assert_eq(_ex.total_remaining_sec(), 0)


func test_stop_from_idle_is_noop() -> void:
	_ex = _make(_plan_60_30_90())
	_ex.stop()
	assert_eq(_ex.get_state(), IntervalExecutor.State.IDLE)
	assert_eq(_of_type("finished").size(), 0)


# ---------------------------------------------------------------------------
# Интенсивность, рампы, подсказки
# ---------------------------------------------------------------------------

func test_snap_intensity_clamps_and_rounds_to_step() -> void:
	assert_almost_eq(IntervalExecutor.snap_intensity(0.3), 0.5, 1e-9, "REQ-WRK-07 крит. 1: нижняя граница")
	assert_almost_eq(IntervalExecutor.snap_intensity(2.0), 1.5, 1e-9)
	assert_almost_eq(IntervalExecutor.snap_intensity(0.93), 0.95, 1e-9, "шаг 5 %")
	assert_almost_eq(IntervalExecutor.snap_intensity(1.1), 1.1, 1e-9)
	assert_almost_eq(IntervalExecutor.snap_intensity(0.9), 0.9, 1e-9)
	assert_almost_eq(IntervalExecutor.new(Workout.new(), FTP).intensity, 1.0, 1e-9, "по умолчанию 100 %")


func test_set_intensity_emits_new_target() -> void:
	var steps: Array[WorkoutStep] = [WorkoutStep.watts(60, 200.0)]
	_ex = _make(Workout.make("w", steps))
	_ex.start()
	_log = []
	_ex.set_intensity(1.1)
	assert_eq(_of_type("target").size(), 1)
	assert_eq(_of_type("target")[0]["watts"], 220, "REQ-WRK-07 крит. 2: 200 Вт × 110 % → 220")
	_ex.set_intensity(1.1)
	assert_eq(_of_type("target").size(), 1, "без изменения цели — нет события")
	_ex.set_intensity(0.9)
	assert_eq(_of_type("target").back()["watts"], 180)


func test_intensity_from_constructor_applies_at_start() -> void:
	_ex = _make(_plan_60_30_90(), 0.9)
	_ex.start()
	assert_eq(_of_type("target")[0]["watts"], 117, "130 × 0.9 = 117")


func test_ramp_emits_target_each_second_when_changed_by_1w() -> void:
	var steps: Array[WorkoutStep] = [WorkoutStep.ramp_watts(60, 100.0, 160.0), WorkoutStep.watts(10, 50.0)]
	_ex = _make(Workout.make("ramp", steps))
	_ex.start()
	_tick_n(_ex, 59)
	var targets := _of_type("target")
	assert_eq(targets.size(), 60, "1 Вт/с → событие каждую секунду, не чаще 1 Гц (REQ-WRK-02 крит. 3)")
	assert_eq(targets[0]["watts"], 100)
	assert_eq(targets[30]["watts"], 130)
	assert_eq(targets[59]["watts"], 159)
	for i in range(1, targets.size()):
		assert_true(absi(targets[i]["watts"] - targets[i - 1]["watts"]) >= 1)
	_ex.tick(1.0)
	assert_eq(_of_type("target").back()["watts"], 50, "граница рампы → цель следующего шага")


func test_ramp_with_small_slope_emits_only_on_1w_change() -> void:
	# 100 → 110 Вт за 60 с: 0.1667 Вт/с — событие не каждую секунду.
	var steps: Array[WorkoutStep] = [WorkoutStep.ramp_watts(60, 100.0, 110.0)]
	_ex = _make(Workout.make("slow", steps))
	_ex.start()
	_tick_n(_ex, 59)
	var targets := _of_type("target")
	assert_lt(targets.size(), 20)
	assert_gt(targets.size(), 5)
	for i in range(1, targets.size()):
		assert_true(absi(targets[i]["watts"] - targets[i - 1]["watts"]) >= 1)


func test_free_ride_step_emits_zero_target() -> void:
	var steps: Array[WorkoutStep] = [WorkoutStep.free_ride(30), WorkoutStep.percent(30, 80.0)]
	_ex = _make(Workout.make("free", steps))
	_ex.start()
	assert_eq(_of_type("target")[0]["watts"], 0)
	assert_true(_ex.current_step().is_free_ride())
	_tick_n(_ex, 30)
	assert_eq(_of_type("target").back()["watts"], 160)


func test_cues_emitted_at_offsets() -> void:
	var s := WorkoutStep.percent(30, 50.0)
	s.text_cues.append(TextCue.make(0, "Старт"))
	s.text_cues.append(TextCue.make(10, "Держи каденс"))
	var steps: Array[WorkoutStep] = [s]
	_ex = _make(Workout.make("cues", steps))
	_ex.start()
	assert_eq(_of_type("cue").size(), 1)
	assert_eq(_of_type("cue")[0]["text"], "Старт")
	_tick_n(_ex, 9)
	assert_eq(_of_type("cue").size(), 1)
	_ex.tick(1.0)
	assert_eq(_of_type("cue").size(), 2)
	assert_eq(_of_type("cue")[1]["text"], "Держи каденс")
	assert_eq(_of_type("cue")[1]["elapsed"], 10)


func test_state_changed_sequence() -> void:
	_ex = _make(_plan_60_30_90())
	_ex.start()
	_ex.pause()
	_ex.resume()
	_ex.stop()
	var states: Array[int] = []
	for e in _of_type("state"):
		states.append(e["state"])
	assert_eq(states, [IntervalExecutor.State.RUNNING, IntervalExecutor.State.PAUSED,
		IntervalExecutor.State.RUNNING, IntervalExecutor.State.FINISHED] as Array[int])


func test_pending_fraction_tracks_accumulator() -> void:
	_ex = _make(_plan_60_30_90())
	_ex.start()
	assert_almost_eq(_ex.pending_fraction_sec(), 0.0, 1e-9)
	_ex.tick(0.3)
	assert_almost_eq(_ex.pending_fraction_sec(), 0.3, 1e-9)
	_ex.tick(0.7)
	assert_almost_eq(_ex.pending_fraction_sec(), 0.0, 1e-9)
	_ex.tick(1.25)
	assert_almost_eq(_ex.pending_fraction_sec(), 0.25, 1e-9)
