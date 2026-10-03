extends GutTest
## Пределы повторов при импорте (финальное ревью): число повторов ≤ 1000, шагов после
## разворачивания ≤ 10 000; проверка до `Workout.expand_repeat`, превышение — ошибка разбора
## с ключом `too_many_repeats`/`too_many_steps` (REQ-IMP-01 крит. 1, REQ-IMP-05 крит. 1, 2, REQ-INT-03 крит. 5, 9).

const CSV: String = "res://assets/i18n/strings.csv"


static func _keys(r: ParseResult) -> Array[String]:
	var out: Array[String] = []
	for e in r.errors:
		out.append(str(e.get("key", "")))
	return out


static func _zwo(body: String) -> String:
	return "<workout_file><name>Limits</name><sportType>bike</sportType><workout>%s</workout></workout_file>" % body


static func _intervals_t(repeat: String) -> String:
	return "<IntervalsT Repeat=\"%s\" OnDuration=\"10\" OffDuration=\"10\" OnPower=\"1.0\" OffPower=\"0.5\"/>" % repeat


func test_constants() -> void:
	assert_eq(ParseResult.MAX_REPEAT_COUNT, 1000)
	assert_eq(ParseResult.MAX_TOTAL_STEPS, 10000)


func test_zwo_repeat_at_limit_is_accepted() -> void:
	var r := ZwoParser.parse(_zwo(_intervals_t("1000")))
	assert_true(r.ok(), str(r.error_messages()))
	assert_eq(r.workout.steps.size(), 2000)


func test_zwo_repeat_over_limit_is_error() -> void:
	var r := ZwoParser.parse(_zwo(_intervals_t("1001")))
	assert_false(r.ok())
	assert_null(r.workout)
	assert_has(_keys(r), ParseResult.KEY_TOO_MANY_REPEATS)
	var huge := ZwoParser.parse(_zwo(_intervals_t("1e30")))
	assert_has(_keys(huge), ParseResult.KEY_TOO_MANY_REPEATS, "огромное значение не переполняет int")


func test_zwo_total_steps_over_limit_is_error_before_expansion() -> void:
	var body := ""
	for i in 6:
		body += _intervals_t("1000")  # 6 × 2000 = 12 000 шагов
	var r := ZwoParser.parse(_zwo(body))
	assert_false(r.ok())
	assert_has(_keys(r), ParseResult.KEY_TOO_MANY_STEPS)
	assert_eq(_keys(r).count(ParseResult.KEY_TOO_MANY_STEPS), 1, "одна ошибка о размере")


func test_intervals_doc_reps_over_limit_is_error() -> void:
	var r := IntervalsIcuWorkoutParser.parse({"workout_doc": {"steps": [
		{"reps": 5000, "steps": [{"duration": 60, "power": {"value": 50, "units": "%ftp"}}]},
	]}})
	assert_false(r.ok())
	assert_has(_keys(r), ParseResult.KEY_TOO_MANY_REPEATS)


func test_intervals_doc_nested_reps_hit_step_limit_without_expanding() -> void:
	var inner := {"reps": 1000, "steps": [{"duration": 10, "power": {"value": 90, "units": "%ftp"}}, {"duration": 10, "power": {"value": 50, "units": "%ftp"}}]}
	var started := Time.get_ticks_msec()
	var r := IntervalsIcuWorkoutParser.parse({"workout_doc": {"steps": [{"reps": 1000, "steps": [inner]}]}})
	assert_false(r.ok())
	assert_has(_keys(r), ParseResult.KEY_TOO_MANY_STEPS, "1000 × 1000 × 2 — больше 10 000 шагов")
	assert_lt(Time.get_ticks_msec() - started, 2000, "без разворачивания миллионов шагов")


func test_intervals_doc_at_limit_is_accepted() -> void:
	var r := IntervalsIcuWorkoutParser.parse({"workout_doc": {"steps": [
		{"reps": 1000, "steps": [{"duration": 10, "power": {"value": 90, "units": "%ftp"}}]},
	]}})
	assert_true(r.ok(), str(r.error_messages()))
	assert_eq(r.workout.steps.size(), 1000)


func test_intervals_text_repeat_over_limit_is_error() -> void:
	var inline := IntervalsIcuWorkoutParser.parse_description_text("1001x (1m 50%, 1m 60%)")
	assert_has(_keys(inline), ParseResult.KEY_TOO_MANY_REPEATS)
	var block := IntervalsIcuWorkoutParser.parse_description_text("99999999999999999999x\n- 1m 50%\n")
	assert_has(_keys(block), ParseResult.KEY_TOO_MANY_REPEATS, "длинное число не переполняет int")
	assert_null(block.workout)


func test_intervals_text_total_steps_over_limit_is_error() -> void:
	var text := ""
	for i in 6:
		text += "1000x\n- 10s 90%\n- 10s 50%\n\n"
	var r := IntervalsIcuWorkoutParser.parse_description_text(text)
	assert_false(r.ok())
	assert_has(_keys(r), ParseResult.KEY_TOO_MANY_STEPS)
	var ok := IntervalsIcuWorkoutParser.parse_description_text("1000x\n- 10s 90%\n- 10s 50%\n")
	assert_true(ok.ok(), str(ok.error_messages()))
	assert_eq(ok.workout.steps.size(), 2000)


func test_error_keys_are_translated_in_strings_csv() -> void:
	var text := FileAccess.get_file_as_string(CSV)
	for key in [ParseResult.KEY_TOO_MANY_REPEATS, ParseResult.KEY_TOO_MANY_STEPS]:
		var line := ""
		for l in text.split("\n"):
			if l.begins_with("ui.plan.import.error.%s," % key):
				line = l
		assert_ne(line, "", "ключ ui.plan.import.error.%s есть в strings.csv" % key)
		assert_eq(line.split(",").size() >= 3, true, "ru и en: %s" % line)
