extends GutTest
## Тесты списка интервалов HUD: `IntervalListModel` и `IntervalList` (REQ-HUD-13 крит. 2, 3, 8;
## REQ-WRK-06 — пропуск, REQ-WRK-07 — множитель; `docs/game/hud.md` п. 6).

const FTP: int = 200
const UNIT: String = "Вт"
const FREE: String = "свободно"
const ACC_FULL: String = "res://tests/fixtures/workouts_acceptance/acc_full.zwo"

var _trainer: FakeTrainer
var _session: WorkoutSession


func before_each() -> void:
	_trainer = FakeTrainer.new(11)
	_trainer.connect_delay_sec = 0.0
	_trainer.power_noise_w = 0.0
	_trainer.power_tau_sec = 0.01
	_trainer.cadence_noise_rpm = 0.0
	_trainer.connect_device("list")


func _steps(arr: Array) -> Array[WorkoutStep]:
	var out: Array[WorkoutStep] = []
	for s in arr:
		out.append(s)
	return out


## 5:00 в 95 % FTP (Z4), рампа 5:00 62.5 → 112.5 %, 3:00 свободно, 2:00 150 Вт.
func _plan() -> Workout:
	return Workout.make("list", _steps([
		WorkoutStep.percent(300, 95.0),
		WorkoutStep.ramp_percent(300, 62.5, 112.5),
		WorkoutStep.free_ride(180),
		WorkoutStep.watts(120, 150.0),
	]))


## Две ступени разминки и блок 4 × (15 с 160 %, 45 с 62.5 %) — пример из HUD-13.8.
func _repeat_plan() -> Workout:
	var block: Array[WorkoutStep] = _steps([
		WorkoutStep.percent(15, 160.0, WorkoutStep.StepKind.INTERVAL_ON),
		WorkoutStep.percent(45, 62.5, WorkoutStep.StepKind.INTERVAL_OFF),
	])
	var steps: Array[WorkoutStep] = _steps([
		WorkoutStep.percent(60, 50.0, WorkoutStep.StepKind.WARMUP),
		WorkoutStep.percent(60, 60.0, WorkoutStep.StepKind.WARMUP),
	])
	steps.append_array(Workout.expand_repeat(block, 4))
	return Workout.make("repeats", steps)


## 30 шагов по 10 с с чередующейся целью.
func _long_plan(n: int = 30) -> Workout:
	var steps: Array[WorkoutStep] = []
	for i in n:
		steps.append(WorkoutStep.percent(10, 60.0 + float(i % 5) * 15.0))
	return Workout.make("long", steps)


func _start(plan: Workout, intensity: float = 1.0) -> WorkoutSession:
	_session = WorkoutSession.new(plan, _trainer, FTP, intensity)
	_session.start()
	return _session


func _ticks(n: int) -> void:
	for i in n:
		_session.tick(1.0)


func _statuses(model: IntervalListModel) -> Array[String]:
	var out: Array[String] = []
	for r in model.rows():
		out.append(str(r["status"]))
	return out


func _count(arr: Array[String], value: String) -> int:
	var n: int = 0
	for v in arr:
		if v == value:
			n += 1
	return n


func _texts(model: IntervalListModel) -> Array[String]:
	var out: Array[String] = []
	for r in model.rows():
		out.append(IntervalListModel.row_text(r, UNIT, FREE))
	return out


# ---------------------------------------------------------------------------
# Крит. 2 — строки
# ---------------------------------------------------------------------------

func test_req_hud_13_c2_row_per_step_with_duration_target_and_free() -> void:
	var m := IntervalListModel.new(_plan(), FTP)
	assert_eq(m.row_count(), 4)
	assert_eq(_texts(m), ["5:00  190 Вт", "5:00  125→225 Вт", "3:00  свободно", "2:00  150 Вт"] as Array[String])
	var rows := m.rows()
	assert_eq(int(rows[0]["zone"]), 4, "95 % FTP — Z4")
	assert_eq(str(rows[0]["color_token"]), "z4")
	assert_true(rows[1]["ramp"])
	assert_true(rows[2]["free"])
	assert_eq(str(rows[2]["color_token"]), IntervalListModel.FREE_TOKEN, "«свободно» — hud.free")
	assert_eq(int(rows[2]["zone"]), 0)


func test_req_hud_13_c2_watts_with_intensity_multiplier() -> void:
	var m := IntervalListModel.new(_plan(), FTP, 1.1)
	assert_eq(_texts(m)[0], "5:00  209 Вт", "190 × 1.1")
	var rev := m.revision()
	assert_true(m.set_intensity(1.0))
	assert_eq(_texts(m)[0], "5:00  190 Вт")
	assert_gt(m.revision(), rev, "смена множителя меняет версию строк")
	assert_false(m.set_intensity(1.0), "тот же множитель — без изменений")


func test_req_hud_13_c2_duration_format() -> void:
	assert_eq(IntervalListModel.format_duration(300), "5:00")
	assert_eq(IntervalListModel.format_duration(60), "1:00")
	assert_eq(IntervalListModel.format_duration(15), "0:15")
	assert_eq(IntervalListModel.format_duration(3599), "59:59")
	assert_eq(IntervalListModel.format_duration(3600), "1:00:00")
	assert_eq(IntervalListModel.format_duration(3909), "1:05:09")


func test_req_hud_13_c2_exactly_one_current_and_done_rows() -> void:
	var m := IntervalListModel.new(_plan(), FTP)
	assert_eq(_count(_statuses(m), IntervalListModel.STATUS_CURRENT), 0, "до старта текущей нет")
	_start(_plan())
	m.sync(_session)
	assert_eq(_statuses(m), ["current", "upcoming", "upcoming", "upcoming"] as Array[String])
	_ticks(300)
	m.sync(_session)
	assert_eq(_statuses(m), ["done", "current", "upcoming", "upcoming"] as Array[String])
	assert_eq(m.current_row(), 1)
	assert_eq(m.step_counter(), Vector2i(2, 4))


func test_req_hud_13_c2_skipped_step_is_skipped() -> void:
	var m := IntervalListModel.new(_plan(), FTP)
	_start(_plan())
	_ticks(30)
	_session.skip_step()
	m.sync(_session)
	assert_eq(_statuses(m), ["skipped", "current", "upcoming", "upcoming"] as Array[String])
	assert_eq(_count(_statuses(m), IntervalListModel.STATUS_CURRENT), 1)
	# Остаток пропущенного шага не входит в «осталось» (как у курсора графика).
	assert_eq(m.remaining_sec(), 300 + 180 + 120)


func test_req_hud_13_c3_selection_moves_not_later_than_next_sample() -> void:
	var m := IntervalListModel.new(_plan(), FTP)
	_start(_plan())
	_ticks(299)
	m.sync(_session)
	assert_eq(m.current_row(), 0)
	_ticks(1)  # следующий сэмпл — граница шага
	assert_true(m.sync(_session))
	assert_eq(m.current_row(), 1, "выделение на новой строке в первом же сэмпле нового шага")
	assert_eq(_count(_statuses(m), IntervalListModel.STATUS_CURRENT), 1)


func test_pause_keeps_selection_and_progress() -> void:
	var m := IntervalListModel.new(_plan(), FTP)
	_start(_plan())
	_ticks(150)
	m.sync(_session)
	var progress := m.current_progress()
	assert_almost_eq(progress, 0.5, 0.001)
	_session.pause()
	_ticks(20)
	assert_false(m.sync(_session), "на паузе ничего не меняется")
	assert_almost_eq(m.current_progress(), progress, 0.001)


func test_header_progress_and_remaining() -> void:
	var m := IntervalListModel.new(_plan(), FTP)
	assert_eq(m.title(), "list")
	assert_eq(m.total_sec(), 900)
	assert_eq(m.remaining_sec(), 900)
	_start(_plan())
	_ticks(450)
	m.sync(_session)
	assert_eq(m.remaining_sec(), 450)
	assert_almost_eq(m.progress(), 0.5, 0.001)


func test_finished_all_done() -> void:
	var m := IntervalListModel.new(_plan(), FTP)
	_start(_plan())
	_ticks(900)
	m.sync(_session)
	assert_eq(_statuses(m), ["done", "done", "done", "done"] as Array[String])
	assert_eq(m.remaining_sec(), 0)
	assert_eq(m.step_counter(), Vector2i(4, 4))


# ---------------------------------------------------------------------------
# Крит. 3 — окно ≤ 8 строк, текущая третья
# ---------------------------------------------------------------------------

func test_req_hud_13_c3_window_two_done_current_five_next() -> void:
	var m := IntervalListModel.new(_long_plan(), FTP)
	assert_eq(m.visible_window(), Vector2i(0, 6), "до старта: первая строка и 5 следующих")
	_start(_long_plan())
	m.sync(_session)
	assert_eq(m.visible_window(), Vector2i(0, 6))
	_ticks(10)
	m.sync(_session)
	assert_eq(m.visible_window(), Vector2i(0, 7))
	for step in range(2, 30):
		_ticks(10)
		m.sync(_session)
		var w := m.visible_window()
		assert_eq(m.current_row(), step)
		assert_lte(w.y, IntervalListModel.MAX_ROWS, "не больше 8 строк")
		assert_eq(m.current_row() - w.x, 2, "шаг %d: текущая — третья сверху" % step)
		assert_eq(w.y, mini(8, 30 - w.x), "до 5 следующих")


func test_req_hud_13_c3_thirty_steps_current_always_in_window() -> void:
	var m := IntervalListModel.new(_long_plan(), FTP)
	_start(_long_plan())
	for k in 300:
		_ticks(1)
		m.sync(_session)
		var cur := m.current_row()
		if cur < 0:
			break
		var w := m.visible_window()
		assert_true(cur >= w.x and cur < w.x + w.y, "текущая строка %d в окне %s" % [cur, w])


# ---------------------------------------------------------------------------
# Крит. 8 — повторы
# ---------------------------------------------------------------------------

func test_req_hud_13_c8_block_collapsed_before_start_expanded_after() -> void:
	var m := IntervalListModel.new(_repeat_plan(), FTP)
	assert_eq(m.repeat_blocks(), [{"first": 2, "last": 9, "period": 2, "count": 4}] as Array[Dictionary])
	assert_eq(m.row_count(), 3, "до начала блока — 3 строки")
	var rows := m.rows()
	assert_eq(str(rows[2]["kind"]), IntervalListModel.KIND_REPEAT)
	assert_eq(IntervalListModel.row_text(rows[2], UNIT, FREE), "4 × 0:15 320 / 0:45 125 Вт")
	assert_eq(str(rows[2]["color_token"]), "z7", "цвет — зона рабочего отрезка (160 % — Z7)")
	assert_eq(str(rows[2]["status"]), IntervalListModel.STATUS_UPCOMING)
	_start(_repeat_plan())
	_ticks(119)
	m.sync(_session)
	assert_eq(m.row_count(), 3, "последняя секунда разминки — блок ещё свёрнут")
	_ticks(1)
	m.sync(_session)
	assert_eq(m.row_count(), 2 + 8, "с начала блока — строка на шаг")
	assert_eq(m.current_row(), 2)
	assert_eq(_texts(m)[2], "0:15  320 Вт")
	assert_eq(_texts(m)[3], "0:45  125 Вт")
	assert_eq(_count(_statuses(m), IntervalListModel.STATUS_CURRENT), 1)


func test_req_hud_13_c8_zwo_intervals_block_from_parser() -> void:
	var result := ZwoParser.parse(FileAccess.get_file_as_string(ACC_FULL))
	assert_true(result.ok(), "фикстура разбирается")
	var m := IntervalListModel.new(result.workout, FTP)
	assert_eq(result.workout.steps.size(), 12)
	assert_eq(m.row_count(), 7, "IntervalsT × 3 свёрнут в одну строку")
	assert_eq(IntervalListModel.row_text(m.rows()[2], UNIT, FREE), "3 × 2:00 240 / 1:00 100 Вт")


func test_req_hud_13_c8_different_pairs_are_separate_blocks() -> void:
	var steps: Array[WorkoutStep] = _steps([
		WorkoutStep.percent(30, 120.0, WorkoutStep.StepKind.INTERVAL_ON),
		WorkoutStep.percent(30, 50.0, WorkoutStep.StepKind.INTERVAL_OFF),
		WorkoutStep.percent(30, 120.0, WorkoutStep.StepKind.INTERVAL_ON),
		WorkoutStep.percent(30, 50.0, WorkoutStep.StepKind.INTERVAL_OFF),
		WorkoutStep.percent(60, 130.0, WorkoutStep.StepKind.INTERVAL_ON),
		WorkoutStep.percent(30, 50.0, WorkoutStep.StepKind.INTERVAL_OFF),
		WorkoutStep.percent(60, 100.0, WorkoutStep.StepKind.INTERVAL_ON),
	])
	var blocks := IntervalListModel.detect_repeat_blocks(Workout.make("b", steps))
	assert_eq(blocks.size(), 2)
	assert_eq(int(blocks[0]["count"]), 2)
	assert_eq(int(blocks[1]["first"]), 4)
	assert_eq(int(blocks[1]["count"]), 1)
	var m := IntervalListModel.new(Workout.make("b", steps), FTP)
	assert_eq(m.row_count(), 3, "два блока и одиночный ON без пары")


func test_req_hud_13_c8_skipping_into_block_expands_it() -> void:
	var m := IntervalListModel.new(_repeat_plan(), FTP)
	_start(_repeat_plan())
	_session.skip_step()
	_session.skip_step()
	m.sync(_session)
	assert_eq(m.row_count(), 10)
	assert_eq(_statuses(m).slice(0, 3), ["skipped", "skipped", "current"] as Array[String])


func test_stopped_early_keeps_later_block_collapsed() -> void:
	var m := IntervalListModel.new(_repeat_plan(), FTP)
	_start(_repeat_plan())
	_ticks(30)
	m.sync(_session)  # сэмпл перед остановкой
	_session.stop()
	m.sync(_session)
	assert_eq(m.row_count(), 3)
	assert_eq(_statuses(m), ["done", "upcoming", "upcoming"] as Array[String])


# ---------------------------------------------------------------------------
# Компонент IntervalList
# ---------------------------------------------------------------------------

func _list(plan: Workout) -> IntervalList:
	var list := IntervalList.new()
	add_child_autofree(list)
	list.list_width = 282.0
	_start(plan)
	list.setup(_session)
	return list


func test_view_width_from_parameter_and_rows_inside() -> void:
	var list := _list(_long_plan())
	assert_eq(list.size.x, 282.0)
	list.list_width = 266.0
	assert_eq(list.size.x, 266.0, "ширина — параметр (w_l из HudLayout)")
	var area := list.rows_area_rect()
	assert_true(Rect2(Vector2.ZERO, list.size).encloses(area))
	assert_eq(list.visible_rows().size(), 6)


func test_view_current_row_taller_and_visible_after_each_step() -> void:
	var list := _list(_long_plan())
	var area := list.rows_area_rect()
	for step in 30:
		if step > 0:
			_ticks(10)
		list.sync(_session)
		list.skip_animation()
		area = list.rows_area_rect()
		var rect := list.current_row_rect()
		assert_true(rect.has_area(), "шаг %d: текущая строка видна" % step)
		assert_true(area.encloses(rect), "шаг %d: целиком в области строк" % step)
		assert_eq(rect.size.y, IntervalList.ROW_HEIGHT[IntervalListModel.STATUS_CURRENT], "текущая выше")
		assert_lte(list.visible_rows().size(), IntervalListModel.MAX_ROWS)
		if step >= 2:
			assert_eq(list.visible_rows()[2], step, "текущая — третья видимая строка")


func test_view_scroll_animates_then_settles() -> void:
	var list := _list(_long_plan())
	_ticks(30)
	list.sync(_session)
	assert_true(list.is_animating(), "смена шага — анимация прокрутки")
	var settle_frames: int = 0
	while list.is_animating() and settle_frames < 100:
		list._process(1.0 / 60.0)
		settle_frames += 1
	assert_false(list.is_animating())
	assert_lte(settle_frames, ceili(IntervalList.SCROLL_SEC * 60.0) + 1, "прокрутка за 300 мс")
	assert_true(list.rows_area_rect().encloses(list.current_row_rect()))


func test_view_max_height_caps_size() -> void:
	var list := _list(_long_plan())
	_ticks(50)
	list.sync(_session)
	list.skip_animation()
	var full := list.size.y
	list.max_height = 200.0
	assert_lte(list.size.y, 200.0)
	assert_lt(list.size.y, full)
