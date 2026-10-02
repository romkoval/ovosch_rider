extends GutTest
## Тесты ZwoParser (REQ-IMP-01 крит. 1–7, REQ-IMP-05 крит. 1–4, REQ-NFR-09 крит. 3).

const FIXTURES: String = "res://tests/fixtures/workouts/"
const FTP: int = 200


static func _fixture(name: String) -> String:
	return FileAccess.get_file_as_string(FIXTURES + name)


static func _parse_fixture(name: String) -> ParseResult:
	return ZwoParser.parse(_fixture(name))


static func _wrap(workout_xml: String) -> String:
	return "<workout_file><name>t</name><workout>%s</workout></workout_file>" % workout_xml


# ---------------------------------------------------------------------------
# simple.zwo (REQ-IMP-01 крит. 1, 2, 3, 5, 6)
# ---------------------------------------------------------------------------

func test_simple_fixture_step_count_and_total_duration() -> void:
	var r := _parse_fixture("simple.zwo")
	assert_true(r.ok(), "разбор успешен: %s" % str(r.error_messages()))
	assert_eq(r.workout.steps.size(), 4, "REQ-IMP-01 крит. 6: 4 шага")
	assert_eq(r.workout.total_duration_sec(), 300 + 1200 + 120 + 180, "REQ-IMP-01 крит. 6: суммарная длительность")
	assert_eq(r.workout.source, "zwo")


func test_metadata_name_description_author_sport_type() -> void:
	var r := _parse_fixture("simple.zwo")
	assert_eq(r.workout.name, "Simple Endurance", "REQ-IMP-01 крит. 5: name")
	assert_eq(r.workout.description, "Разминка, ровный блок, заминка.", "REQ-IMP-01 крит. 5: description")
	assert_eq(str(r.metadata.get("author")), "ovosch-rider tests", "REQ-IMP-01 крит. 5: author")
	assert_eq(str(r.metadata.get("sport_type")), "bike")


func test_steady_state_power_fraction_becomes_percent_ftp() -> void:
	var r := _parse_fixture("simple.zwo")
	var s: WorkoutStep = r.workout.steps[1]
	assert_eq(s.target_kind, WorkoutStep.TargetKind.PERCENT_FTP)
	assert_almost_eq(s.target_start, 65.0, 0.0001, "REQ-IMP-01 крит. 1: 0.65 → 65 %")
	assert_eq(s.duration_sec, 1200)
	assert_eq(s.kind, WorkoutStep.StepKind.STEADY)
	# 0.65 при FTP 200 → 130 Вт, в середине шага (300 + 600 с от старта)
	assert_eq(r.workout.target_watts_at(900.0, FTP), 130, "REQ-IMP-01 крит. 1: 130 Вт при FTP 200")


func test_warmup_is_ramp_from_power_low_to_power_high() -> void:
	var r := _parse_fixture("simple.zwo")
	var s: WorkoutStep = r.workout.steps[0]
	assert_eq(s.kind, WorkoutStep.StepKind.WARMUP)
	assert_true(s.is_ramp(), "REQ-IMP-01 крит. 1: Warmup — рампа")
	assert_almost_eq(s.target_start, 40.0, 0.0001)
	assert_almost_eq(s.target_end, 65.0, 0.0001)
	assert_eq(s.start_watts(FTP), 80)
	assert_eq(s.end_watts(FTP), 130)


func test_cooldown_is_descending_ramp() -> void:
	var r := _parse_fixture("simple.zwo")
	var s: WorkoutStep = r.workout.steps[3]
	assert_eq(s.kind, WorkoutStep.StepKind.COOLDOWN)
	assert_almost_eq(s.target_start, 55.0, 0.0001)
	assert_almost_eq(s.target_end, 35.0, 0.0001)
	assert_eq(s.duration_sec, 180)


func test_free_ride_has_no_target() -> void:
	var r := _parse_fixture("simple.zwo")
	var s: WorkoutStep = r.workout.steps[2]
	assert_eq(s.target_kind, WorkoutStep.TargetKind.NONE, "REQ-IMP-01 крит. 2: FreeRide без цели")
	assert_true(s.is_free_ride())
	assert_eq(s.duration_sec, 120)
	assert_eq(r.workout.target_watts_at(1500.0 + 10.0, FTP), 0, "цель 0 Вт на свободном шаге")


func test_cadence_attribute_is_transferred() -> void:
	var r := _parse_fixture("simple.zwo")
	assert_eq(r.workout.steps[1].cadence_rpm, 90, "REQ-IMP-01 крит. 3: Cadence")
	assert_eq(r.workout.steps[0].cadence_rpm, 0, "каденс не задан → 0")


# ---------------------------------------------------------------------------
# intervals_textevent.zwo (REQ-IMP-01 крит. 1, 3, 4, 6)
# ---------------------------------------------------------------------------

func test_intervals_fixture_expands_repeat_into_flat_steps() -> void:
	var r := _parse_fixture("intervals_textevent.zwo")
	assert_true(r.ok(), "разбор успешен: %s" % str(r.error_messages()))
	# Warmup + 3×(on, off) + Ramp + SteadyState + Cooldown
	assert_eq(r.workout.steps.size(), 1 + 6 + 1 + 1 + 1, "REQ-IMP-01 крит. 1/6: IntervalsT 3×(240/120) → 6 шагов")
	assert_eq(r.workout.total_duration_sec(), 600 + 3 * (240 + 120) + 300 + 60 + 300, "REQ-IMP-01 крит. 6")


func test_intervals_on_off_power_cadence_and_kind() -> void:
	var r := _parse_fixture("intervals_textevent.zwo")
	for i in 3:
		var on: WorkoutStep = r.workout.steps[1 + i * 2]
		var off: WorkoutStep = r.workout.steps[2 + i * 2]
		assert_eq(on.duration_sec, 240, "повтор %d: OnDuration" % i)
		assert_almost_eq(on.target_start, 105.0, 0.0001, "повтор %d: OnPower 1.05 → 105 %%" % i)
		assert_eq(on.cadence_rpm, 95, "повтор %d: Cadence" % i)
		assert_eq(on.kind, WorkoutStep.StepKind.INTERVAL_ON)
		assert_eq(off.duration_sec, 120, "повтор %d: OffDuration" % i)
		assert_almost_eq(off.target_start, 50.0, 0.0001, "повтор %d: OffPower" % i)
		assert_eq(off.cadence_rpm, 80, "повтор %d: CadenceResting (REQ-IMP-01 крит. 3)" % i)
		assert_eq(off.kind, WorkoutStep.StepKind.INTERVAL_OFF)


func test_cadence_low_high_midpoint() -> void:
	var r := _parse_fixture("intervals_textevent.zwo")
	assert_eq(r.workout.steps[0].cadence_rpm, 90, "REQ-IMP-01 крит. 3: (85+95)/2")


func test_textevents_attached_to_step_by_offset() -> void:
	var r := _parse_fixture("intervals_textevent.zwo")
	var warmup: WorkoutStep = r.workout.steps[0]
	assert_eq(warmup.text_cues.size(), 2, "REQ-IMP-01 крит. 4: две подсказки в Warmup")
	assert_eq(warmup.text_cues[0].at_sec, 10)
	assert_eq(warmup.text_cues[0].text, "Разогреваемся")
	assert_eq(warmup.text_cues[1].at_sec, 590, "атрибут duration игнорируется, timeoffset сохранён")
	assert_eq(warmup.text_cues[1].text, "Скоро первый интервал")


func test_textevents_inside_intervals_repeat_per_rep() -> void:
	var r := _parse_fixture("intervals_textevent.zwo")
	for i in 3:
		var on: WorkoutStep = r.workout.steps[1 + i * 2]
		var off: WorkoutStep = r.workout.steps[2 + i * 2]
		assert_eq(on.text_cues.size(), 1, "повтор %d: подсказка на on-шаге" % i)
		assert_eq(on.text_cues[0].text, "Жми!")
		assert_eq(off.text_cues.size(), 1, "повтор %d: подсказка 240 с → off-шаг" % i)
		assert_eq(off.text_cues[0].at_sec, 0)
		assert_eq(off.text_cues[0].text, "Отдых")


func test_ramp_element_and_unsupported_attributes_give_warnings_not_errors() -> void:
	var r := _parse_fixture("intervals_textevent.zwo")
	var ramp: WorkoutStep = r.workout.steps[7]
	assert_eq(ramp.kind, WorkoutStep.StepKind.RAMP)
	assert_almost_eq(ramp.target_start, 75.0, 0.0001)
	assert_almost_eq(ramp.target_end, 95.0, 0.0001)
	var msgs := r.warning_messages()
	assert_eq(r.errors.size(), 0)
	assert_true(msgs.any(func(m: String) -> bool: return m.contains("pace")), "предупреждение про pace: %s" % str(msgs))
	assert_true(msgs.any(func(m: String) -> bool: return m.contains("overunder")), "предупреждение про OverUnder: %s" % str(msgs))


# ---------------------------------------------------------------------------
# Ошибки (REQ-IMP-01 крит. 7, REQ-IMP-05 крит. 1–4, REQ-NFR-09 крит. 3)
# ---------------------------------------------------------------------------

func test_unknown_element_gives_error_with_name_and_line_and_no_workout() -> void:
	var r := _parse_fixture("unknown_element.zwo")
	assert_false(r.ok())
	assert_null(r.workout, "REQ-IMP-05 крит. 2: частичный план не возвращается")
	assert_eq(r.errors.size(), 1)
	var e: Dictionary = r.errors[0]
	assert_eq(str(e["element"]), "SolidState")
	assert_eq(int(e["line"]), 6, "REQ-IMP-05 крит. 1: номер строки")
	assert_eq(str(e["key"]), "unknown_element")
	assert_string_contains(str(e["message"]), "SolidState")
	assert_string_contains(str(e["message"]), "не поддерживается")
	var user := ParseResult.format_entry(e, "unknown_element.zwo")
	assert_string_contains(user, "unknown_element.zwo", "REQ-IMP-05 крит. 1: имя файла")
	assert_string_contains(user, "строка 6", "REQ-IMP-05 крит. 2: «(строка N)»")


func test_not_xml_gives_single_error() -> void:
	var r := _parse_fixture("not_xml.zwo")
	assert_false(r.ok())
	assert_null(r.workout)
	assert_eq(r.errors.size(), 1, "REQ-IMP-01 крит. 7: одна ошибка")
	assert_eq(str(r.errors[0]["key"]), "not_zwo")


func test_truncated_xml_is_rejected() -> void:
	var r := _parse_fixture("truncated.zwo")
	assert_false(r.ok())
	assert_null(r.workout)
	assert_eq(str(r.errors[0]["key"]), "invalid_xml")
	assert_string_contains(str(r.errors[0]["message"]), "workout_file")


func test_mismatched_closing_tag_is_rejected() -> void:
	var r := ZwoParser.parse("<workout_file><workout><SteadyState Duration=\"60\" Power=\"0.5\"></workout></workout_file>")
	assert_false(r.ok())
	assert_eq(str(r.errors[0]["key"]), "invalid_xml")


func test_empty_text_and_wrong_root_are_errors() -> void:
	assert_false(ZwoParser.parse("").ok())
	assert_eq(str(ZwoParser.parse("   \n").errors[0]["key"]), "empty_file")
	var r := ZwoParser.parse("<html><body/></html>")
	assert_false(r.ok())
	assert_eq(str(r.errors[0]["key"]), "not_zwo")


func test_missing_duration_and_bad_number_report_line() -> void:
	var r := ZwoParser.parse("<workout_file>\n<workout>\n<SteadyState Power=\"0.5\"/>\n<SteadyState Duration=\"abc\" Power=\"0.5\"/>\n</workout>\n</workout_file>")
	assert_false(r.ok())
	assert_eq(r.errors.size(), 2)
	assert_eq(int(r.errors[0]["line"]), 3)
	assert_eq(str(r.errors[0]["key"]), "missing_attribute")
	assert_eq(int(r.errors[1]["line"]), 4)
	assert_eq(str(r.errors[1]["key"]), "bad_number")


func test_max_effort_is_free_ride_with_warning() -> void:
	var r := ZwoParser.parse(_wrap("<MaxEffort Duration=\"30\"/>"))
	assert_true(r.ok(), str(r.error_messages()))
	assert_eq(r.workout.steps[0].target_kind, WorkoutStep.TargetKind.NONE)
	assert_eq(r.workout.steps[0].duration_sec, 30)
	assert_eq(r.warnings.size(), 1)
	assert_eq(str(r.warnings[0]["key"]), "max_effort_as_free_ride")


func test_element_and_attribute_names_are_case_insensitive() -> void:
	var r := ZwoParser.parse(_wrap("<steadystate duration=\"120\" power=\"0.8\" cadence=\"100\"/><TEXTEVENT/>"))
	assert_true(r.ok(), str(r.error_messages()))
	assert_eq(r.workout.steps.size(), 1)
	assert_almost_eq(r.workout.steps[0].target_start, 80.0, 0.0001)
	assert_eq(r.workout.steps[0].cadence_rpm, 100)


func test_workout_without_steps_is_error() -> void:
	var r := ZwoParser.parse("<workout_file><workout></workout></workout_file>")
	assert_false(r.ok())
	assert_eq(str(r.errors[0]["key"]), "no_steps")


func test_cue_beyond_step_duration_is_warning_not_error() -> void:
	var r := ZwoParser.parse(_wrap("<SteadyState Duration=\"60\" Power=\"0.5\"><textevent timeoffset=\"60\" message=\"late\"/></SteadyState>"))
	assert_true(r.ok(), str(r.error_messages()))
	assert_eq(r.workout.steps[0].text_cues.size(), 0)
	assert_eq(str(r.warnings[0]["key"]), "cue_out_of_step")


func test_error_messages_contain_no_stacktrace_or_class_names() -> void:
	for name in ["unknown_element.zwo", "not_xml.zwo", "truncated.zwo"]:
		var r := _parse_fixture(name)
		for m in r.error_messages():
			assert_false(m.contains("res://") or m.contains(".gd") or m.contains("ZwoParser") or m.contains("at:"),
					"REQ-IMP-05 крит. 3: '%s' без стека и имён классов" % m)
			assert_gt(m.length(), 5, "сообщение не пустое")


func test_parsed_workout_is_valid_for_domain() -> void:
	for name in ["simple.zwo", "intervals_textevent.zwo"]:
		var r := _parse_fixture(name)
		assert_true(r.workout.is_valid(), "%s: %s" % [name, str(r.workout.validate())])
