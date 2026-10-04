extends GutTest
## T-149: `SteadyState` с диапазоном `PowerLow`/`PowerHigh` без `Power` (экспорт Intervals.icu)
## (REQ-IMP-01 п.1, 4–6; регрессия REQ-IMP-05 п.2, REQ-IMP-04 п.6).
## Фикстуры — пара одного плана из экспорта Intervals.icu «Активация: 3x6 мин на гоночной мощности»:
## `intervals_icu_3x6.zwo` (без `<author>`) и `intervals_icu_3x6.mrc`.

const FIXTURES: String = "res://tests/fixtures/workouts/"
const ZWO: String = "intervals_icu_3x6.zwo"
const MRC: String = "intervals_icu_3x6.mrc"
## Длительности шагов по файлу (с).
const DURATIONS: Array[int] = [900, 360, 240, 360, 240, 360, 240, 600, 600]
## Середины диапазонов .zwo, % FTP.
const ZWO_TARGETS: Array[float] = [52.5, 93.0, 54.0, 93.0, 54.0, 93.0, 54.0, 63.0, 46.5]
## Допуск сравнения с .mrc (округление сервиса), % FTP.
const TOLERANCE_PCT: float = 1.0


static func _read(name: String) -> String:
	return FileAccess.get_file_as_string(FIXTURES + name)


static func _wrap(body: String) -> String:
	return "<workout_file>\n<name>T</name>\n<workout>\n%s\n</workout>\n</workout_file>" % body


func _parse_zwo() -> ParseResult:
	return ZwoParser.parse(_read(ZWO))


func test_fixture_zwo_imports_without_errors() -> void:
	var r := _parse_zwo()
	assert_true(r.ok(), "T-149: экспорт Intervals.icu импортируется: " + str(r.error_messages()))
	assert_eq(r.errors.size(), 0, "ни одной ошибки «нет атрибута Power»")
	assert_not_null(r.workout)
	if r.workout == null:
		return
	assert_eq(r.workout.name, "Активация: 3x6 мин на гоночной мощности")
	assert_eq(r.workout.source, "zwo")


func test_fixture_show_avg_and_empty_tags_give_no_warnings() -> void:
	var r := _parse_zwo()
	assert_eq(r.warnings.size(), 0, "show_avg и <tags/> не дают предупреждений: " + str(r.warnings))


func test_fixture_steps_are_steady_midpoints_of_ranges() -> void:
	var r := _parse_zwo()
	if not r.ok():
		fail_test(str(r.error_messages()))
		return
	var steps := r.workout.steps
	assert_eq(steps.size(), DURATIONS.size(), "9 шагов")
	for i in mini(steps.size(), DURATIONS.size()):
		var s: WorkoutStep = steps[i]
		assert_eq(s.duration_sec, DURATIONS[i], "шаг %d: длительность" % i)
		assert_eq(s.target_kind, WorkoutStep.TargetKind.PERCENT_FTP, "шаг %d: доля FTP" % i)
		assert_false(s.is_ramp(), "шаг %d: постоянная цель, не рампа" % i)
		assert_eq(s.kind, WorkoutStep.StepKind.STEADY, "шаг %d: SteadyState" % i)
		assert_almost_eq(s.target_start, ZWO_TARGETS[i], 0.001, "шаг %d: середина диапазона" % i)
		assert_eq(s.target_end, s.target_start, "шаг %d: начало = конец" % i)
	assert_eq(r.workout.total_duration_sec(), 3900, "65 мин")


func test_fixture_zwo_matches_mrc_step_by_step() -> void:
	var z := _parse_zwo()
	var m := ErgMrcParser.parse(_read(MRC), "mrc")
	assert_true(z.ok(), str(z.error_messages()))
	assert_true(m.ok(), str(m.error_messages()))
	if not z.ok() or not m.ok():
		return
	var zs := z.workout.steps
	var ms := m.workout.steps
	assert_eq(zs.size(), ms.size(), "число шагов .zwo = .mrc")
	assert_eq(z.workout.total_duration_sec(), m.workout.total_duration_sec(), "общая длительность")
	for i in mini(zs.size(), ms.size()):
		assert_eq(zs[i].duration_sec, ms[i].duration_sec, "шаг %d: длительность .zwo = .mrc" % i)
		assert_eq(ms[i].target_kind, WorkoutStep.TargetKind.PERCENT_FTP, "шаг %d: .mrc в %% FTP" % i)
		assert_almost_eq(zs[i].target_start, ms[i].target_start, TOLERANCE_PCT,
				"шаг %d: цель .zwo %.1f %% ≈ .mrc %.1f %%" % [i, zs[i].target_start, ms[i].target_start])
	# Пример из карточки: 0.90…0.96 → 93 %, в .mrc 92.9.
	if zs.size() > 1 and ms.size() > 1:
		assert_almost_eq(zs[1].target_start, 93.0, 0.001)
		assert_almost_eq(ms[1].target_start, 92.9, 0.001)


func test_fixture_text_events_bound_to_their_steps_at_offset_zero() -> void:
	var r := _parse_zwo()
	if not r.ok():
		fail_test(str(r.error_messages()))
		return
	var expected := {1: "1/3", 3: "2/3", 5: "3/3"}
	for i in r.workout.steps.size():
		var cues: Array[TextCue] = r.workout.steps[i].text_cues
		if expected.has(i):
			assert_eq(cues.size(), 1, "шаг %d: одна подсказка" % i)
			if cues.size() == 1:
				assert_eq(cues[0].text, str(expected[i]), "шаг %d: текст подсказки" % i)
				assert_eq(cues[0].at_sec, 0, "шаг %d: textevent без timeoffset → смещение 0" % i)
		else:
			assert_eq(cues.size(), 0, "шаг %d: без подсказок" % i)


func test_fixture_text_events_same_absolute_time_as_mrc() -> void:
	var z := _parse_zwo()
	var m := ErgMrcParser.parse(_read(MRC), "mrc")
	if not z.ok() or not m.ok():
		fail_test("фикстуры не разобраны")
		return
	assert_eq(_absolute_cues(z.workout), _absolute_cues(m.workout), "подсказки .zwo и .mrc в те же секунды")


static func _absolute_cues(w: Workout) -> Array[String]:
	var out: Array[String] = []
	for i in w.steps.size():
		for c in w.steps[i].text_cues:
			out.append("%d:%s" % [w.step_start_sec(i) + c.at_sec, c.text])
	return out


func test_fixture_serialization_round_trip_without_loss() -> void:
	var r := _parse_zwo()
	if not r.ok():
		fail_test(str(r.error_messages()))
		return
	var data := r.workout.to_dict()
	var back := Workout.from_dict(data)
	assert_not_null(back)
	if back == null:
		return
	assert_eq(back.to_dict(), data, "to_dict()/from_dict() без потерь")
	assert_eq(back.steps.size(), r.workout.steps.size())
	for i in back.steps.size():
		assert_true(back.steps[i].same_as(r.workout.steps[i]), "шаг %d совпадает после round-trip" % i)
	var via_json := WorkoutSerializer.from_json(WorkoutSerializer.to_json(r.workout))
	assert_not_null(via_json)
	if via_json != null:
		assert_eq(via_json.power_points(250), r.workout.power_points(250), "JSON библиотеки: тот же профиль мощности")


func test_power_takes_precedence_over_range() -> void:
	var r := ZwoParser.parse(_wrap("<SteadyState Duration=\"300\" Power=\"0.75\" PowerLow=\"0.5\" PowerHigh=\"0.6\"/>"))
	assert_true(r.ok(), str(r.error_messages()))
	if r.ok():
		assert_almost_eq(r.workout.steps[0].target_start, 75.0, 0.001, "Power главнее диапазона")
		assert_false(r.workout.steps[0].is_ramp())


func test_range_with_cadence_and_cue_offset() -> void:
	var r := ZwoParser.parse(_wrap(
			"<SteadyState Duration=\"120\" PowerLow=\"0.80\" PowerHigh=\"0.90\" Cadence=\"92\" show_avg=\"1\">\n"
			+ "<textevent timeoffset=\"30\" message=\"Держи\"/>\n</SteadyState>"))
	assert_true(r.ok(), str(r.error_messages()))
	if not r.ok():
		return
	var s := r.workout.steps[0]
	assert_almost_eq(s.target_start, 85.0, 0.001)
	assert_eq(s.cadence_rpm, 92)
	assert_eq(s.text_cues.size(), 1)
	if s.text_cues.size() == 1:
		assert_eq(s.text_cues[0].at_sec, 30, "timeoffset учитывается как раньше")


func test_single_bound_without_power_is_error_with_line() -> void:
	for attr in ["PowerLow=\"0.5\"", "PowerHigh=\"0.6\""]:
		var r := ZwoParser.parse(_wrap("<SteadyState Duration=\"60\" Power=\"0.5\"/>\n<SteadyState Duration=\"300\" %s/>" % attr))
		assert_false(r.ok(), attr + ": одна граница без Power — ошибка")
		assert_null(r.workout)
		assert_eq(r.errors.size(), 1, attr + ": одна ошибка")
		if r.errors.size() == 1:
			var e: Dictionary = r.errors[0]
			assert_eq(str(e.get("key", "")), "missing_attribute")
			assert_eq(str(e.get("element", "")), "SteadyState")
			assert_eq(int(e.get("line", 0)), 5, attr + ": номер строки элемента")
			assert_string_contains(str(e.get("message", "")), "нет атрибута Power (или пары PowerLow/PowerHigh)")


func test_no_power_and_no_range_is_error() -> void:
	var r := ZwoParser.parse(_wrap("<SteadyState Duration=\"300\" show_avg=\"1\"/>"))
	assert_false(r.ok())
	assert_eq(r.errors.size(), 1)
	if r.errors.size() == 1:
		assert_eq(str(r.errors[0].get("key", "")), "missing_attribute")
		assert_eq(int(r.errors[0].get("line", 0)), 4)


func test_non_numeric_bound_is_single_bad_number_error() -> void:
	var r := ZwoParser.parse(_wrap("<SteadyState Duration=\"300\" PowerLow=\"abc\" PowerHigh=\"0.6\"/>"))
	assert_false(r.ok())
	assert_eq(r.errors.size(), 1, "только ошибка числа, без лишней «нет атрибута»: " + str(r.error_messages()))
	if r.errors.size() == 1:
		assert_eq(str(r.errors[0].get("key", "")), "bad_number")
