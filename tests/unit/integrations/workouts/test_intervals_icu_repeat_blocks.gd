extends GutTest
## T-099: блоки повторов Intervals.icu `Nx` сохраняются в `Workout.repeat_blocks` и сворачиваются
## в списке интервалов HUD, как ZWO `IntervalsT` (REQ-HUD-13 п.8; регрессия REQ-INT-03 п.5,
## REQ-NFR-09 п.3). Сериализация `Workout.to_dict()/from_dict()` сохраняет блоки.

const FTP: int = 200
const UNIT: String = "Вт"
const FREE: String = "свободно"

## 2 шага разминки + 4x (15 с 160 %, 45 с 62.5 %) — пример HUD-13.8 в синтаксисе Intervals.icu.
const TEXT_PLAN: String = "Warmup\n- 1m 50%\n- 1m 60%\n\n4x\n- 15s 160%\n- 45s 62.5%\n"
const TEXT_PLAN_INLINE: String = "- 1m 50%\n- 1m 60%\n4x (15s 160%, 45s 62.5%)\n"

var _trainer: FakeTrainer
var _session: WorkoutSession


func before_each() -> void:
	_trainer = FakeTrainer.new(7)
	_trainer.connect_delay_sec = 0.0
	_trainer.power_noise_w = 0.0
	_trainer.power_tau_sec = 0.01
	_trainer.cadence_noise_rpm = 0.0
	_trainer.connect_device("t099")


func _parse_text(text: String) -> Workout:
	var result := IntervalsIcuWorkoutParser.parse({"id": 1, "name": "rep", "description": text})
	assert_true(result.ok(), "план разбирается: %s" % str(result.errors))
	return result.workout


func _doc_event(steps: Array) -> Dictionary:
	return {"id": 2, "name": "doc", "workout_doc": {"steps": steps}}


func _texts(model: IntervalListModel) -> Array[String]:
	var out: Array[String] = []
	for r in model.rows():
		out.append(IntervalListModel.row_text(r, UNIT, FREE))
	return out


func _assert_hud_13_c8(plan: Workout) -> void:
	var m := IntervalListModel.new(plan, FTP)
	assert_eq(m.repeat_blocks(), [{"first": 2, "last": 9, "period": 2, "count": 4}] as Array[Dictionary])
	assert_eq(m.row_count(), 3, "до начала блока — 3 строки")
	assert_eq(str(m.rows()[2]["kind"]), IntervalListModel.KIND_REPEAT)
	assert_eq(_texts(m)[2], "4 × 0:15 320 / 0:45 125 Вт")
	assert_eq(str(m.rows()[2]["color_token"]), "z7", "цвет — зона рабочего отрезка")
	_session = WorkoutSession.new(plan, _trainer, FTP)
	_session.start()
	for i in 119:
		_session.tick(1.0)
	m.sync(_session)
	assert_eq(m.row_count(), 3, "последняя секунда разминки — блок ещё свёрнут")
	_session.tick(1.0)
	m.sync(_session)
	assert_eq(m.row_count(), 2 + 8, "с начала блока — строка на шаг")
	assert_eq(m.current_row(), 2)
	assert_eq(_texts(m)[2], "0:15  320 Вт")
	assert_eq(_texts(m)[3], "0:45  125 Вт")


# ---------------------------------------------------------------------------
# Разбор: метаданные блока
# ---------------------------------------------------------------------------

func test_text_repeat_block_metadata() -> void:
	var w := _parse_text(TEXT_PLAN)
	assert_eq(w.steps.size(), 10, "план по-прежнему плоский")
	assert_eq(w.repeat_blocks, [{"first": 2, "last": 9, "period": 2, "count": 4}] as Array[Dictionary])
	assert_eq(w.valid_repeat_blocks(), w.repeat_blocks)


func test_inline_repeat_block_metadata() -> void:
	var w := _parse_text(TEXT_PLAN_INLINE)
	assert_eq(w.steps.size(), 10)
	assert_eq(w.repeat_blocks, [Workout.repeat_block(2, 2, 4)] as Array[Dictionary])


func test_doc_repeat_block_metadata_and_nested_outer_only() -> void:
	var result := IntervalsIcuWorkoutParser.parse(_doc_event([
		{"duration": 60, "power": {"value": 50, "units": "%ftp"}},
		{"reps": 2, "steps": [
			{"reps": 3, "steps": [
				{"duration": 30, "power": {"value": 120, "units": "%ftp"}},
				{"duration": 30, "power": {"value": 50, "units": "%ftp"}},
			]},
			{"duration": 120, "power": {"value": 60, "units": "%ftp"}},
		]},
		{"reps": 3, "steps": [
			{"duration": 60, "power": {"value": 100, "units": "%ftp"}},
			{"duration": 60, "power": {"value": 80, "units": "%ftp"}},
			{"duration": 60, "power": {"value": 60, "units": "%ftp"}},
		]},
	]))
	assert_true(result.ok(), str(result.errors))
	var w := result.workout
	assert_eq(w.steps.size(), 1 + 2 * 7 + 9)
	assert_eq(w.repeat_blocks, [Workout.repeat_block(1, 7, 2), Workout.repeat_block(15, 3, 3)] as Array[Dictionary],
			"вложенный 3x не записывается — только внешний блок")
	var m := IntervalListModel.new(w, FTP)
	assert_eq(m.row_count(), 3, "шаг + два свёрнутых блока")
	assert_eq(_texts(m)[2], "3 × 1:00 200 / 1:00 160 / 1:00 120 Вт", "период из трёх шагов")


func test_plan_without_repeats_has_no_blocks() -> void:
	var w := _parse_text("- 10m 65%\n- 5m 250w\n")
	assert_true(w.repeat_blocks.is_empty())
	assert_false(w.to_dict().has("repeat_blocks"), "словарь прежнего вида")


# ---------------------------------------------------------------------------
# HUD-13 п.8 на планах Intervals.icu
# ---------------------------------------------------------------------------

func test_req_hud_13_c8_intervals_icu_text_block() -> void:
	_assert_hud_13_c8(_parse_text(TEXT_PLAN))


func test_req_hud_13_c8_intervals_icu_inline_block() -> void:
	_assert_hud_13_c8(_parse_text(TEXT_PLAN_INLINE))


func test_req_hud_13_c8_intervals_icu_doc_block() -> void:
	var result := IntervalsIcuWorkoutParser.parse(_doc_event([
		{"duration": 60, "power": {"value": 50, "units": "%ftp"}, "warmup": true},
		{"duration": 60, "power": {"value": 60, "units": "%ftp"}, "warmup": true},
		{"reps": 4, "steps": [
			{"duration": 15, "power": {"value": 160, "units": "%ftp"}},
			{"duration": 45, "power": {"value": 62.5, "units": "%ftp"}},
		]},
	]))
	assert_true(result.ok(), str(result.errors))
	_assert_hud_13_c8(result.workout)


func test_req_hud_13_c8_after_json_round_trip() -> void:
	var w := _parse_text(TEXT_PLAN)
	var back := Workout.from_dict(JSON.parse_string(JSON.stringify(w.to_dict())))
	_assert_hud_13_c8(back)


# ---------------------------------------------------------------------------
# Сериализация
# ---------------------------------------------------------------------------

func test_round_trip_preserves_repeat_blocks() -> void:
	var w := _parse_text(TEXT_PLAN)
	var d := w.to_dict()
	assert_eq(d["repeat_blocks"], [{"first": 2, "last": 9, "period": 2, "count": 4}])
	var back := Workout.from_dict(d)
	assert_eq(back.repeat_blocks, w.repeat_blocks)
	assert_eq(back.to_dict(), d, "from_dict(to_dict()).to_dict() без потерь")
	var via_json := Workout.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_eq(via_json.repeat_blocks, w.repeat_blocks, "числа из JSON — снова int")
	assert_eq(via_json.to_dict(), d)
	var copied: Array = d["repeat_blocks"]
	copied[0]["count"] = 99
	assert_eq(int(w.repeat_blocks[0]["count"]), 4, "to_dict отдаёт копию")


func test_old_dict_without_blocks_reads() -> void:
	var d := _parse_text(TEXT_PLAN).to_dict()
	d.erase("repeat_blocks")
	var back := Workout.from_dict(d)
	assert_not_null(back)
	assert_eq(back.steps.size(), 10)
	assert_true(back.repeat_blocks.is_empty())
	assert_true(back.is_valid())


func test_bad_blocks_from_dict_are_dropped_or_ignored() -> void:
	var d := _parse_text(TEXT_PLAN).to_dict()
	d["repeat_blocks"] = [
		"мусор",
		{"first": 2, "last": 9, "period": 2},  # нет count
		{"first": "2", "last": 9, "period": 2, "count": 4},  # строка вместо числа
		{"first": 0, "last": 3, "period": 2, "count": 2},  # шаги повторов разные
		{"first": 2, "last": 99, "period": 2, "count": 49},  # за пределами плана
		{"first": 2, "last": 9, "period": 2, "count": 4},
		{"first": 4, "last": 9, "period": 2, "count": 3},  # пересекается с предыдущим
	]
	var back := Workout.from_dict(d)
	assert_eq(back.repeat_blocks.size(), 4, "нечисловые записи отброшены при чтении")
	assert_eq(back.valid_repeat_blocks(), [{"first": 2, "last": 9, "period": 2, "count": 4}] as Array[Dictionary])
	assert_eq(IntervalListModel.new(back, FTP).row_count(), 3)
	assert_eq(Workout.from_dict({"steps": [], "repeat_blocks": "x"}).repeat_blocks.size(), 0)


func test_stale_block_after_step_edit_is_ignored() -> void:
	var w := _parse_text(TEXT_PLAN)
	w.steps[5].duration_sec = 20
	assert_true(w.valid_repeat_blocks().is_empty(), "повторы больше не совпадают — блок не показывается")
	var m := IntervalListModel.new(w, FTP)
	assert_eq(m.row_count(), 10, "без блока — строка на шаг")


func test_zwo_detection_still_works_alongside_explicit_blocks() -> void:
	var steps: Array[WorkoutStep] = [
		WorkoutStep.percent(30, 120.0, WorkoutStep.StepKind.INTERVAL_ON),
		WorkoutStep.percent(30, 50.0, WorkoutStep.StepKind.INTERVAL_OFF),
		WorkoutStep.percent(30, 120.0, WorkoutStep.StepKind.INTERVAL_ON),
		WorkoutStep.percent(30, 50.0, WorkoutStep.StepKind.INTERVAL_OFF),
		WorkoutStep.percent(60, 70.0),
		WorkoutStep.percent(60, 70.0),
	]
	var w := Workout.make("mix", steps)
	w.repeat_blocks = [Workout.repeat_block(4, 1, 2)]
	assert_eq(IntervalListModel.detect_repeat_blocks(w), [
		{"first": 0, "last": 3, "period": 2, "count": 2},
		{"first": 4, "last": 5, "period": 1, "count": 2},
	] as Array[Dictionary])
	# Явный блок поверх пар ON/OFF имеет приоритет над эвристикой.
	w.repeat_blocks = [Workout.repeat_block(0, 4, 1)]
	assert_eq(IntervalListModel.detect_repeat_blocks(w), [{"first": 0, "last": 3, "period": 4, "count": 1}] as Array[Dictionary])
