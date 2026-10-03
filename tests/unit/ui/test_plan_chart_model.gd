extends GutTest
## Тесты PlanChartModel: модель графика плана (REQ-HUD-10 крит. 1–5, REQ-WRK-07 — множитель,
## REQ-WRK-06 — пропуск, REQ-WRK-05 — пауза; `docs/game/hud.md` п. 7, 12.3).

const FTP: int = 200

var _trainer: FakeTrainer
var _session: WorkoutSession


func before_each() -> void:
	_trainer = FakeTrainer.new(7)
	_trainer.connect_delay_sec = 0.0
	_trainer.power_noise_w = 0.0
	_trainer.power_tau_sec = 0.01
	_trainer.cadence_noise_rpm = 0.0
	_trainer.connect_device("chart")


func _steps(arr: Array) -> Array[WorkoutStep]:
	var out: Array[WorkoutStep] = []
	for s in arr:
		out.append(s)
	return out


## 10 мин разминка 40 → 70 %, 5 мин 100 %, 2 мин свободно, 3 мин 120 %.
func _plan() -> Workout:
	return Workout.make("chart", _steps([
		WorkoutStep.ramp_percent(600, 40.0, 70.0, WorkoutStep.StepKind.WARMUP),
		WorkoutStep.percent(300, 100.0),
		WorkoutStep.free_ride(120),
		WorkoutStep.percent(180, 120.0),
	]))


func _session_for(plan: Workout) -> WorkoutSession:
	_session = WorkoutSession.new(plan, _trainer, FTP)
	return _session


func _ticks(n: int) -> void:
	for i in n:
		_session.tick(1.0)


func _pieces_of(model: PlanChartModel, step: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in model.pieces():
		if int(p["step_index"]) == step:
			out.append(p)
	return out


# ---------------------------------------------------------------------------
# Крит. 1 — сегменты
# ---------------------------------------------------------------------------

func test_segments_from_workout_with_targets_zones_and_free_flag() -> void:
	var m := PlanChartModel.new(_plan(), FTP)
	var segs := m.segments()
	assert_eq(segs.size(), 4)
	var total: int = 0
	for s in segs:
		total += int(s["duration_sec"])
	assert_eq(total, m.total_sec())
	assert_eq(m.total_sec(), 1200)
	assert_eq(int(segs[0]["start_sec"]), 0)
	assert_eq(int(segs[0]["start_watts"]), 80)
	assert_eq(int(segs[0]["end_watts"]), 140)
	assert_true(segs[0]["ramp"])
	assert_eq(int(segs[1]["start_sec"]), 600)
	assert_eq(int(segs[1]["start_watts"]), 200)
	assert_eq(int(segs[1]["end_watts"]), 200)
	assert_false(segs[1]["ramp"])
	assert_eq(int(segs[1]["zone"]), 4)
	assert_eq(str(segs[1]["zone_token"]), "z4")
	# Свободно: без зоны, нейтральный токен.
	assert_true(segs[2]["free"])
	assert_eq(int(segs[2]["zone"]), 0)
	assert_eq(str(segs[2]["zone_token"]), "")
	assert_eq(str(segs[2]["color_token"]), PlanChartModel.FREE_TOKEN)
	assert_eq(int(segs[3]["zone"]), 5)


func test_free_segment_covers_whole_step_at_30_percent_height() -> void:
	var m := PlanChartModel.new(_plan(), FTP)
	var free := _pieces_of(m, 2)
	assert_eq(free.size(), 1)
	assert_eq(float(free[0]["start_sec"]), 900.0)
	assert_eq(float(free[0]["end_sec"]), 1020.0)
	assert_almost_eq(float(free[0]["top_start"]), 0.30, 1e-6)
	assert_almost_eq(float(free[0]["top_end"]), 0.30, 1e-6)
	# Нет пустот по X: куски стыкуются от 0 до конца плана.
	var t: float = 0.0
	for p in m.pieces():
		assert_almost_eq(float(p["start_sec"]), t, 1e-6)
		t = float(p["end_sec"])
	assert_almost_eq(t, float(m.total_sec()), 1e-6)


func test_custom_zones_used_for_segment_zone() -> void:
	var zones := PowerZones.custom(FTP, [50.0, 95.0] as Array[float])  # 3 зоны
	var m := PlanChartModel.new(_plan(), FTP, 1.0, zones)
	assert_eq(int(m.segments()[1]["zone"]), 3)


# ---------------------------------------------------------------------------
# Крит. 2 — оси и множитель
# ---------------------------------------------------------------------------

func test_y_max_is_125_percent_of_max_target() -> void:
	var m := PlanChartModel.new(_plan(), FTP)
	assert_eq(m.max_target_w(), 240)
	assert_almost_eq(m.y_max(), 300.0, 1e-6)
	assert_almost_eq(m.ftp_fraction(), 200.0 / 300.0, 1e-6)
	assert_true(m.ftp_visible())
	assert_almost_eq(m.y_of(200.0, 120.0), 120.0 * (1.0 - 200.0 / 300.0), 1e-4)
	assert_almost_eq(m.y_of(0.0, 120.0), 120.0, 1e-6)
	assert_almost_eq(m.y_of(1000.0, 120.0), 0.0, 1e-6)


func test_x_axis_whole_plan_linear() -> void:
	var m := PlanChartModel.new(_plan(), FTP)
	var w: float = 1280.0
	assert_almost_eq(m.x_of(0.0, w), 0.0, 1.0)
	assert_almost_eq(m.x_of(1200.0, w), w, 1.0)
	assert_almost_eq(m.x_of(300.0, w), w * 0.25, 1.0)
	assert_almost_eq(m.x_of(900.0, w), w * 0.75, 1.0)
	# Любая длина плана помещается целиком.
	var long := Workout.make("long", _steps([WorkoutStep.percent(4 * 3600, 60.0)]))
	var lm := PlanChartModel.new(long, FTP)
	assert_almost_eq(lm.x_of(4.0 * 3600.0, w), w, 1.0)
	assert_eq(lm.time_labels().size(), 9)  # шаг 30 мин: 0…4:00


func test_intensity_recomputes_y_max_targets_and_zones() -> void:
	var m := PlanChartModel.new(_plan(), FTP)
	var rev: int = m.revision()
	assert_true(m.set_intensity(1.1))
	assert_eq(m.max_target_w(), 264)
	assert_almost_eq(m.y_max(), 330.0, 1e-6)
	assert_eq(int(m.segments()[1]["start_watts"]), 220)
	assert_eq(int(m.segments()[1]["zone"]), 5)  # 110 % → Z5
	assert_gt(m.revision(), rev)
	assert_false(m.set_intensity(1.1))


func test_intensity_from_session_applied_by_next_sample() -> void:
	_session_for(_plan())
	var m := PlanChartModel.for_session(_session)
	_session.start()
	_ticks(3)
	m.sync(_session)
	assert_almost_eq(m.y_max(), 300.0, 1e-6)
	_session.set_intensity(0.9)
	_ticks(1)
	m.sync(_session)
	assert_almost_eq(m.y_max(), 1.25 * 216.0, 1e-6)


func test_free_only_plan_falls_back_to_ftp() -> void:
	var m := PlanChartModel.new(Workout.make("free", _steps([WorkoutStep.free_ride(600)])), FTP)
	assert_eq(m.max_target_w(), 0)
	assert_almost_eq(m.y_max(), 250.0, 1e-6)


## HUD-10.2 (У-2): y_max = max(1.25 × максимальная цель, 1.1 × FTP); без целей — 1.25 × FTP.
## Примеры из требования при FTP 250: 150 Вт → 275, 300 Вт → 375, без целей → 312.5.
func test_y_max_floor_of_110_percent_ftp_examples_at_ftp_250() -> void:
	var low := PlanChartModel.new(Workout.make("low", _steps([WorkoutStep.watts(600, 150)])), 250)
	assert_eq(low.max_target_w(), 150)
	assert_almost_eq(low.y_max(), 275.0, 0.5)
	var high := PlanChartModel.new(Workout.make("high", _steps([WorkoutStep.watts(600, 300)])), 250)
	assert_almost_eq(high.y_max(), 375.0, 0.5)
	var free := PlanChartModel.new(Workout.make("free", _steps([WorkoutStep.free_ride(600)])), 250)
	assert_almost_eq(free.y_max(), 312.5, 0.5)


func test_ftp_dash_always_inside_field() -> void:
	# Восстановительный план 50 % FTP: без нижней границы потолок был бы ниже FTP.
	var m := PlanChartModel.new(Workout.make("easy", _steps([WorkoutStep.percent(600, 50.0)])), FTP)
	assert_almost_eq(m.y_max(), 1.1 * FTP, 1e-6)
	assert_true(m.ftp_visible())
	assert_lte(m.ftp_fraction(), 1.0)
	assert_almost_eq(m.ftp_fraction(), 1.0 / 1.1, 1e-6)
	# Множитель ниже 1 опускает цели, но не потолок ниже 1.1 × FTP.
	m.set_intensity(0.5)
	assert_almost_eq(m.y_max(), 1.1 * FTP, 1e-6)
	assert_true(m.ftp_visible())
	assert_false(PlanChartModel.new(_plan(), 0).ftp_visible(), "без FTP пунктира нет")


# ---------------------------------------------------------------------------
# Крит. 3 — рампы кусками по зонам
# ---------------------------------------------------------------------------

func test_ramp_40_to_70_gives_two_pieces_z1_z2() -> void:
	var m := PlanChartModel.new(_plan(), FTP)
	var ramp := _pieces_of(m, 0)
	assert_eq(ramp.size(), 2)
	assert_eq(int(ramp[0]["zone"]), 1)
	assert_eq(int(ramp[1]["zone"]), 2)
	assert_eq(str(ramp[0]["color_token"]), "z1")
	assert_eq(str(ramp[1]["color_token"]), "z2")
	# Граница 55 % = 110 Вт: (110 − 80) / (140 − 80) × 600 = 300 с.
	assert_almost_eq(float(ramp[0]["end_sec"]), 300.0, 1e-4)
	assert_almost_eq(float(ramp[1]["start_sec"]), 300.0, 1e-4)
	# Наклонный верх: высоты в начале и в конце — по целям.
	assert_almost_eq(float(ramp[0]["top_start"]), 80.0 / 300.0, 1e-6)
	assert_almost_eq(float(ramp[1]["top_end"]), 140.0 / 300.0, 1e-6)
	assert_almost_eq(float(ramp[0]["top_end"]), float(ramp[1]["top_start"]), 1e-6)
	# Ровный шаг — один кусок с горизонтальным верхом.
	var flat := _pieces_of(m, 1)
	assert_eq(flat.size(), 1)
	assert_almost_eq(float(flat[0]["top_start"]), float(flat[0]["top_end"]), 1e-6)


func test_ramp_pieces_equal_number_of_zones_crossed() -> void:
	var plan := Workout.make("r", _steps([
		WorkoutStep.ramp_percent(600, 40.0, 130.0),  # Z1…Z6
		WorkoutStep.ramp_percent(600, 100.0, 50.0),  # Z4, Z3, Z2, Z1 (спуск)
		WorkoutStep.ramp_percent(600, 30.0, 55.0),  # до границы включительно — Z1
	]))
	var m := PlanChartModel.new(plan, FTP)
	var up := _pieces_of(m, 0)
	assert_eq(up.size(), 6)
	for k in up.size():
		assert_eq(int(up[k]["zone"]), k + 1)
	var down := _pieces_of(m, 1)
	assert_eq(down.size(), 4)
	assert_eq(int(down[0]["zone"]), 4)
	assert_eq(int(down[3]["zone"]), 1)
	assert_eq(_pieces_of(m, 2).size(), 1)


# ---------------------------------------------------------------------------
# Крит. 5 — курсор и состояния
# ---------------------------------------------------------------------------

func test_cursor_follows_elapsed_and_states_split() -> void:
	_session_for(_plan())
	var m := PlanChartModel.for_session(_session)
	for s in m.segments():
		assert_eq(str(s["status"]), PlanChartModel.STATUS_UPCOMING)
	_session.start()
	_ticks(650)
	m.sync(_session)
	assert_almost_eq(m.cursor_sec(), 650.0, 1e-6)
	assert_almost_eq(m.x_of(m.cursor_sec(), 1200.0), 650.0, 1.0)
	assert_almost_eq(m.cursor_fraction(), 650.0 / 1200.0, 1e-6)
	var segs := m.segments()
	assert_eq(str(segs[0]["status"]), PlanChartModel.STATUS_DONE)
	assert_eq(str(segs[1]["status"]), PlanChartModel.STATUS_CURRENT)
	assert_eq(str(segs[2]["status"]), PlanChartModel.STATUS_UPCOMING)
	# Текущий шаг разрезан курсором: слева пройдено, справа предстоит.
	var cur := _pieces_of(m, 1)
	assert_eq(cur.size(), 2)
	assert_eq(str(cur[0]["status"]), PlanChartModel.STATUS_DONE)
	assert_eq(str(cur[1]["status"]), PlanChartModel.STATUS_UPCOMING)
	assert_true(cur[0]["current"])
	assert_almost_eq(float(cur[0]["end_sec"]), 650.0, 1e-6)
	for p in _pieces_of(m, 0):
		assert_eq(str(p["status"]), PlanChartModel.STATUS_DONE)
		assert_false(p["current"])


func test_cursor_stands_still_on_pause() -> void:
	_session_for(_plan())
	var m := PlanChartModel.for_session(_session)
	_session.start()
	_ticks(100)
	m.sync(_session)
	var rev: int = m.revision()
	_session.pause()
	_ticks(30)
	assert_false(m.sync(_session))
	assert_almost_eq(m.cursor_sec(), 100.0, 1e-6)
	_session.resume()
	_ticks(1)
	m.sync(_session)
	assert_almost_eq(m.cursor_sec(), 101.0, 1e-6)
	assert_eq(m.revision(), rev, "движение курсора не перестраивает сегменты")


func test_skipped_step_state_and_time_shift() -> void:
	_session_for(_plan())
	var m := PlanChartModel.for_session(_session)
	_session.start()
	_ticks(60)
	_session.skip_step()
	_ticks(1)
	m.sync(_session)
	var segs := m.segments()
	assert_eq(str(segs[0]["status"]), PlanChartModel.STATUS_SKIPPED)
	assert_eq(str(segs[1]["status"]), PlanChartModel.STATUS_CURRENT)
	for p in _pieces_of(m, 0):
		assert_eq(str(p["status"]), PlanChartModel.STATUS_SKIPPED)
	# Курсор — в текущем шаге: начало (600) + 1 с; сдвиг к активному времени — 540 с.
	assert_almost_eq(m.cursor_sec(), 601.0, 1e-6)
	assert_eq(m.time_shift_sec(), 540)
	assert_eq(m.shift_at(60), 0, "сэмпл до пропуска не сдвинут")
	assert_eq(m.shift_at(61), 540, "сэмпл после пропуска — сдвиг на остаток шага")


func test_shift_at_follows_skip_journal_not_sync_rate() -> void:
	_session_for(_plan())
	var m := PlanChartModel.for_session(_session)
	_session.start()
	_ticks(100)
	_session.skip_step()  # шаг 0 (до 600 с) на 100-й секунде: сдвиг 500
	_ticks(50)
	_session.skip_step()  # шаг 1 (до 900 с) на 150-й секунде, позиция 650: сдвиг 750
	_ticks(10)
	m.sync(_session)  # единственная синхронизация — журнал целиком
	assert_eq(m.shift_at(1), 0)
	assert_eq(m.shift_at(100), 0)
	assert_eq(m.shift_at(101), 500)
	assert_eq(m.shift_at(150), 500)
	assert_eq(m.shift_at(151), 750)
	assert_eq(m.shift_at(160), 750)
	assert_eq(m.shift_at(_session.executor.elapsed_sec()), m.time_shift_sec(),
			"сдвиг текущего сэмпла совпадает с текущим сдвигом курсора")
	assert_almost_eq(m.cursor_sec(), 910.0, 1e-6)


func test_two_skips_in_same_second_last_wins() -> void:
	_session_for(_plan())
	var m := PlanChartModel.for_session(_session)
	_session.start()
	_ticks(30)
	_session.skip_step()
	_session.skip_step()
	_ticks(5)
	m.sync(_session)
	assert_eq(m.shift_at(30), 0)
	assert_eq(m.shift_at(31), 900 - 30)
	assert_eq(m.shift_at(35), m.time_shift_sec())


func test_finished_plan_all_done_cursor_at_end() -> void:
	_session_for(Workout.make("short", _steps([WorkoutStep.percent(5, 50.0), WorkoutStep.percent(5, 60.0)])))
	var m := PlanChartModel.for_session(_session)
	_session.start()
	_ticks(12)
	m.sync(_session)
	assert_almost_eq(m.cursor_sec(), 10.0, 1e-6)
	for s in m.segments():
		assert_eq(str(s["status"]), PlanChartModel.STATUS_DONE)


func test_set_progress_clamps_cursor() -> void:
	var m := PlanChartModel.new(_plan(), FTP)
	m.set_progress(99999.0, -1)
	assert_almost_eq(m.cursor_sec(), 1200.0, 1e-6)
	m.set_progress(-5.0, 0)
	assert_almost_eq(m.cursor_sec(), 0.0, 1e-6)
