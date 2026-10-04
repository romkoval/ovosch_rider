extends GutTest
## T-113: ZWO `IntervalsT` пишет `Workout.repeat_blocks` (как Intervals.icu `Nx` в T-099), список
## интервалов HUD берёт сохранённые блоки; цвет свёрнутой строки — зона рабочего отрезка (шаг
## повтора с наибольшей целью), а не первого шага (REQ-HUD-13 п.8; регрессия REQ-IMP-01,
## REQ-NFR-09 п.3). Планы без сохранённых блоков сворачиваются прежней эвристикой ON/OFF.

const FTP: int = 200
const UNIT: String = "Вт"
const FREE: String = "свободно"

## Пример HUD-13.8: 2 шага разминки + 4 × (15 с 160 %, 45 с 62.5 %).
const ZWO_HUD_13_C8: String = """<workout_file><name>rep</name><workout>
<SteadyState Duration="60" Power="0.5"/>
<SteadyState Duration="60" Power="0.6"/>
<IntervalsT Repeat="4" OnDuration="15" OnPower="1.6" OffDuration="45" OffPower="0.625"/>
</workout></workout_file>"""

var _trainer: FakeTrainer
var _session: WorkoutSession


func before_each() -> void:
	_trainer = FakeTrainer.new(7)
	_trainer.connect_delay_sec = 0.0
	_trainer.power_noise_w = 0.0
	_trainer.power_tau_sec = 0.01
	_trainer.cadence_noise_rpm = 0.0
	_trainer.connect_device("t113")


static func _wrap(workout_xml: String) -> String:
	return "<workout_file><name>t</name><workout>%s</workout></workout_file>" % workout_xml


func _parse_zwo(xml: String) -> Workout:
	var result := ZwoParser.parse(xml)
	assert_true(result.ok(), "план разбирается: %s" % str(result.error_messages()))
	return result.workout


func _parse_icu(text: String) -> Workout:
	var result := IntervalsIcuWorkoutParser.parse({"id": 1, "name": "rep", "description": text})
	assert_true(result.ok(), "план разбирается: %s" % str(result.errors))
	return result.workout


func _texts(model: IntervalListModel) -> Array[String]:
	var out: Array[String] = []
	for r in model.rows():
		out.append(IntervalListModel.row_text(r, UNIT, FREE))
	return out


## Токен цвета шага с целью `watts` Вт (по той же модели, без знания границ зон).
func _token_of_watts(watts: int) -> String:
	var w := Workout.make("one", [WorkoutStep.watts(60, float(watts))] as Array[WorkoutStep])
	return str(IntervalListModel.new(w, FTP).rows()[0]["color_token"])


func _assert_hud_13_c8(plan: Workout, where: String) -> void:
	var m := IntervalListModel.new(plan, FTP)
	assert_eq(m.repeat_blocks(), [{"first": 2, "last": 9, "period": 2, "count": 4}] as Array[Dictionary], where)
	assert_eq(m.row_count(), 3, "%s: до начала блока — 3 строки" % where)
	if m.row_count() != 3:
		return
	assert_eq(str(m.rows()[2]["kind"]), IntervalListModel.KIND_REPEAT, where)
	assert_eq(_texts(m)[2], "4 × 0:15 320 / 0:45 125 Вт", where)
	assert_eq(str(m.rows()[2]["color_token"]), _token_of_watts(320), "%s: цвет — зона рабочего отрезка" % where)
	_session = WorkoutSession.new(plan, _trainer, FTP)
	_session.start()
	for i in 119:
		_session.tick(1.0)
	m.sync(_session)
	assert_eq(m.row_count(), 3, "%s: последняя секунда разминки — блок ещё свёрнут" % where)
	_session.tick(1.0)
	m.sync(_session)
	assert_eq(m.row_count(), 2 + 8, "%s: с начала блока — строка на шаг" % where)
	assert_eq(m.current_row(), 2, where)


# ---------------------------------------------------------------------------
# ZWO: метаданные блока
# ---------------------------------------------------------------------------

func test_intervals_t_writes_repeat_block() -> void:
	var w := _parse_zwo(ZWO_HUD_13_C8)
	assert_eq(w.steps.size(), 10, "план по-прежнему плоский")
	assert_eq(w.repeat_blocks, [Workout.repeat_block(2, 2, 4)] as Array[Dictionary])
	assert_eq(w.valid_repeat_blocks(), w.repeat_blocks, "блок согласован с шагами")


func test_intervals_t_blocks_survive_to_dict_and_json() -> void:
	var w := _parse_zwo(ZWO_HUD_13_C8)
	var d := w.to_dict()
	assert_eq(d["repeat_blocks"], [{"first": 2, "last": 9, "period": 2, "count": 4}])
	var back := Workout.from_dict(d)
	assert_eq(back.repeat_blocks, w.repeat_blocks, "to_dict()/from_dict()")
	var via_json := Workout.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_eq(via_json.repeat_blocks, w.repeat_blocks, "через JSON")
	assert_eq(via_json.valid_repeat_blocks(), w.repeat_blocks)


func test_several_intervals_t_each_own_block() -> void:
	var w := _parse_zwo(_wrap(
		'<SteadyState Duration="300" Power="0.6"/>'
		+ '<IntervalsT Repeat="3" OnDuration="60" OnPower="1.2" OffDuration="60" OffPower="0.5"/>'
		+ '<IntervalsT Repeat="2" OnDuration="60" OnPower="1.2" OffDuration="60" OffPower="0.5"/>'
		+ '<IntervalsT Repeat="1" OnDuration="30" OnPower="1.5" OffDuration="90" OffPower="0.4"/>'
		+ '<SteadyState Duration="300" Power="0.5"/>'))
	assert_eq(w.repeat_blocks, [Workout.repeat_block(1, 2, 3), Workout.repeat_block(7, 2, 2),
			Workout.repeat_block(11, 2, 1)] as Array[Dictionary])
	var m := IntervalListModel.new(w, FTP)
	assert_eq(_texts(m), ["5:00  120 Вт", "3 × 1:00 240 / 1:00 100 Вт", "2 × 1:00 240 / 1:00 100 Вт",
			"1 × 0:30 300 / 1:30 80 Вт", "5:00  100 Вт"] as Array[String],
			"соседние IntervalsT с теми же параметрами — отдельные строки, как в файле")


func test_plan_without_intervals_t_has_no_blocks() -> void:
	var w := _parse_zwo(_wrap('<Warmup Duration="300" PowerLow="0.4" PowerHigh="0.7"/><SteadyState Duration="600" Power="0.8"/>'))
	assert_true(w.repeat_blocks.is_empty())
	assert_false(w.to_dict().has("repeat_blocks"), "словарь прежнего вида")


# ---------------------------------------------------------------------------
# HUD-13 п.8: ZWO и Intervals.icu
# ---------------------------------------------------------------------------

func test_req_hud_13_c8_zwo() -> void:
	_assert_hud_13_c8(_parse_zwo(ZWO_HUD_13_C8), "zwo")


func test_req_hud_13_c8_zwo_after_json_round_trip() -> void:
	var w := _parse_zwo(ZWO_HUD_13_C8)
	_assert_hud_13_c8(Workout.from_dict(JSON.parse_string(JSON.stringify(w.to_dict()))), "zwo json")


func test_req_hud_13_c8_intervals_icu() -> void:
	_assert_hud_13_c8(_parse_icu("- 1m 50%\n- 1m 60%\n4x (15s 160%, 45s 62.5%)\n"), "intervals.icu")


func test_old_saved_zwo_plan_without_blocks_uses_heuristic() -> void:
	var d := _parse_zwo(ZWO_HUD_13_C8).to_dict()
	d.erase("repeat_blocks")
	var old := Workout.from_dict(d)
	assert_true(old.repeat_blocks.is_empty(), "сохранённый до T-113 план — без блоков")
	_assert_hud_13_c8(old, "zwo без repeat_blocks")


# ---------------------------------------------------------------------------
# Цвет свёрнутой строки — зона рабочего отрезка
# ---------------------------------------------------------------------------

func test_block_starting_with_rest_colored_by_work_step() -> void:
	# 4 × (1:00 125 Вт / 2:00 300 Вт): первый шаг — отдых.
	var w := _parse_icu("- 5m 100w\n4x (1m 125w, 2m 300w)\n")
	var m := IntervalListModel.new(w, FTP)
	assert_eq(m.row_count(), 2, "до начала блока — шаг и одна строка блока")
	if m.row_count() != 2:
		return
	var row: Dictionary = m.rows()[1]
	assert_eq(str(row["kind"]), IntervalListModel.KIND_REPEAT)
	assert_eq(_texts(m)[1], "4 × 1:00 125 / 2:00 300 Вт", "текст — шаги по порядку")
	assert_eq(str(row["color_token"]), _token_of_watts(300), "цвет — зона 300 Вт")
	assert_ne(str(row["color_token"]), _token_of_watts(125), "не зона отдыха")
	assert_eq(int(row["start_watts"]), 300, "цель строки — рабочий отрезок")


func test_owner_example_rest_first_block_percent() -> void:
	# «3x (2m 50%, 1m 120%)» — пример из карточки T-113.
	var w := _parse_icu("3x (2m 50%, 1m 120%)\n")
	var m := IntervalListModel.new(w, FTP)
	assert_eq(m.row_count(), 1)
	if m.row_count() == 1:
		assert_eq(str(m.rows()[0]["color_token"]), _token_of_watts(240), "цвет — зона 120 % FTP")


func test_zwo_off_harder_than_on_colored_by_harder_step() -> void:
	var w := _parse_zwo(_wrap('<IntervalsT Repeat="3" OnDuration="60" OnPower="0.5" OffDuration="120" OffPower="1.1"/>'))
	var m := IntervalListModel.new(w, FTP)
	assert_eq(m.row_count(), 1)
	if m.row_count() == 1:
		assert_eq(str(m.rows()[0]["color_token"]), _token_of_watts(220))


func test_block_with_free_ride_and_ramp_colored_by_highest_target() -> void:
	# Повтор: свободно, рампа 100→260 Вт, 200 Вт — рабочий отрезок рампа (по большему концу).
	var block: Array[WorkoutStep] = [WorkoutStep.free_ride(60), WorkoutStep.ramp_watts(120, 100.0, 260.0),
			WorkoutStep.watts(60, 200.0)]
	var w := Workout.make("mix", Workout.expand_repeat(block, 2))
	w.repeat_blocks = [Workout.repeat_block(0, 3, 2)]
	var m := IntervalListModel.new(w, FTP)
	assert_eq(m.row_count(), 1)
	if m.row_count() == 1:
		var row: Dictionary = m.rows()[0]
		assert_true(bool(row["ramp"]), "цель строки — рампа")
		assert_eq(int(row["end_watts"]), 260)
		assert_false(bool(row["free"]), "не свободный шаг")


func test_all_free_block_keeps_free_color() -> void:
	var block: Array[WorkoutStep] = [WorkoutStep.free_ride(60), WorkoutStep.free_ride(30)]
	var w := Workout.make("free", Workout.expand_repeat(block, 3))
	w.repeat_blocks = [Workout.repeat_block(0, 2, 3)]
	var m := IntervalListModel.new(w, FTP)
	assert_eq(m.row_count(), 1)
	if m.row_count() == 1:
		assert_eq(str(m.rows()[0]["color_token"]), IntervalListModel.FREE_TOKEN)
