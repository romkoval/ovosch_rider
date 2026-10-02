extends GutTest
## Тесты ErgMrcParser (REQ-IMP-02 крит. 1–6, REQ-IMP-05 крит. 1, 3, REQ-NFR-09 крит. 3).

const FIXTURES: String = "res://tests/fixtures/workouts/"


static func _fixture(name: String) -> String:
	return FileAccess.get_file_as_string(FIXTURES + name)


static func _erg(data_lines: String, header: String = "MINUTES WATTS") -> String:
	return "[COURSE HEADER]\nVERSION = 2\n%s\n[END COURSE HEADER]\n[COURSE DATA]\n%s\n[END COURSE DATA]\n" % [header, data_lines]


# ---------------------------------------------------------------------------
# ramp_jump.erg — CRLF, рампа, скачок, дробные минуты, FTP в заголовке
# ---------------------------------------------------------------------------

func test_erg_fixture_steps_ramp_jump_and_total() -> void:
	var r := ErgMrcParser.parse(_fixture("ramp_jump.erg"), "erg")
	assert_true(r.ok(), str(r.error_messages()))
	var w: Workout = r.workout
	assert_eq(w.steps.size(), 3, "REQ-IMP-02 крит. 1: скачки не создают шагов — 3 шага")
	assert_eq(w.total_duration_sec(), 300 + 600 + 150)
	assert_eq(w.source, "erg")
	var ramp: WorkoutStep = w.steps[0]
	assert_true(ramp.is_ramp(), "REQ-IMP-02 крит. 1: разные значения → рампа")
	assert_eq(ramp.target_kind, WorkoutStep.TargetKind.WATTS, "REQ-IMP-02 крит. 2: .erg → ватты")
	assert_eq(ramp.target_start, 100.0)
	assert_eq(ramp.target_end, 200.0)
	assert_eq(ramp.duration_sec, 300)
	var steady: WorkoutStep = w.steps[1]
	assert_false(steady.is_ramp(), "одинаковые значения → постоянный шаг")
	assert_eq(steady.target_start, 150.0)
	assert_eq(steady.duration_sec, 600)
	assert_eq(w.steps[2].target_start, 250.0)


func test_erg_fractional_minutes_give_seconds() -> void:
	var r := ErgMrcParser.parse(_fixture("ramp_jump.erg"), "erg")
	assert_eq(r.workout.steps[2].duration_sec, 150, "REQ-IMP-02 крит. 6: 17.5 − 15 = 2.5 мин → 150 с")


func test_erg_header_metadata_ftp_description_file_name() -> void:
	var r := ErgMrcParser.parse(_fixture("ramp_jump.erg"), "erg")
	assert_eq(int(r.metadata.get("ftp", 0)), 250, "REQ-IMP-02 крит. 4: FTP в метаданных")
	assert_eq(str(r.metadata.get("description")), "Ramp then steady with a jump")
	assert_eq(str(r.metadata.get("file_name")), "ramp_jump.erg")
	assert_eq(r.workout.name, "ramp_jump")
	assert_eq(r.workout.description, "Ramp then steady with a jump")
	assert_eq(r.workout.target_watts_at(400.0, 999), 150, "FTP заголовка не влияет на ватты .erg")


func test_erg_ten_minutes_150w_is_single_step() -> void:
	var r := ErgMrcParser.parse(_erg("0\t150\n10\t150"), "erg")
	assert_true(r.ok(), str(r.error_messages()))
	assert_eq(r.workout.steps.size(), 1)
	assert_eq(r.workout.steps[0].duration_sec, 600, "10 мин → 600 с")
	assert_eq(r.workout.steps[0].target_kind, WorkoutStep.TargetKind.WATTS)
	assert_eq(r.workout.steps[0].target_start, 150.0)
	assert_eq(r.workout.target_watts_at(100.0, 200), 150)


# ---------------------------------------------------------------------------
# sweet_spot_text.mrc — проценты, [COURSE TEXT]
# ---------------------------------------------------------------------------

func test_mrc_values_are_percent_ftp() -> void:
	var r := ErgMrcParser.parse(_fixture("sweet_spot_text.mrc"), "mrc")
	assert_true(r.ok(), str(r.error_messages()))
	var w: Workout = r.workout
	assert_eq(w.source, "mrc")
	assert_eq(w.steps.size(), 4)
	assert_eq(w.total_duration_sec(), 1500)
	var s: WorkoutStep = w.steps[2]
	assert_eq(s.target_kind, WorkoutStep.TargetKind.PERCENT_FTP, "REQ-IMP-02 крит. 2: .mrc → % FTP")
	assert_eq(s.target_start, 100.0, "100 % → PERCENT_FTP 100")
	assert_eq(w.target_watts_at(950.0, 250), 250, "100 % при FTP 250 → 250 Вт")
	assert_eq(w.target_watts_at(400.0, 200), 180, "90 % при FTP 200 → 180 Вт")


func test_mrc_course_text_becomes_cues() -> void:
	var r := ErgMrcParser.parse(_fixture("sweet_spot_text.mrc"), "mrc")
	var w: Workout = r.workout
	assert_eq(w.steps[0].text_cues.size(), 1, "REQ-IMP-02 крит. 3")
	assert_eq(w.steps[0].text_cues[0].text, "Разминка")
	assert_eq(w.steps[0].text_cues[0].at_sec, 0)
	assert_eq(w.steps[1].text_cues[0].text, "Свит-спот начинается")
	assert_eq(w.steps[1].text_cues[0].at_sec, 0, "300 с от старта = начало 2-го шага")
	assert_eq(w.steps[2].text_cues[0].text, "Последний блок: 100 %")
	assert_eq(w.steps[3].text_cues[0].text, "Заминка")


func test_course_text_with_offset_inside_step_and_space_separated() -> void:
	var text := _erg("0\t200\n10\t200") + "[COURSE TEXT]\n90 Hold steady 10\n[END COURSE TEXT]\n"
	var r := ErgMrcParser.parse(text, "erg")
	assert_true(r.ok(), str(r.error_messages()))
	assert_eq(r.workout.steps[0].text_cues.size(), 1)
	assert_eq(r.workout.steps[0].text_cues[0].at_sec, 90)
	assert_eq(r.workout.steps[0].text_cues[0].text, "Hold steady")


func test_cue_beyond_workout_is_warning() -> void:
	var text := _erg("0\t200\n1\t200") + "[COURSE TEXT]\n600\tToo late\t10\n[END COURSE TEXT]\n"
	var r := ErgMrcParser.parse(text, "erg")
	assert_true(r.ok())
	assert_eq(r.workout.steps[0].text_cues.size(), 0)
	assert_eq(str(r.warnings[0]["key"]), "cue_out_of_workout")


# ---------------------------------------------------------------------------
# Единицы: расширение главнее заголовка (REQ-IMP-02 крит. 2)
# ---------------------------------------------------------------------------

func test_extension_overrides_header_units_with_warning() -> void:
	var as_mrc := ErgMrcParser.parse(_erg("0\t100\n5\t100", "MINUTES WATTS"), "mrc")
	assert_true(as_mrc.ok())
	assert_eq(as_mrc.workout.steps[0].target_kind, WorkoutStep.TargetKind.PERCENT_FTP, "REQ-IMP-02 крит. 2: .mrc → %, несмотря на WATTS")
	assert_eq(str(as_mrc.warnings[0]["key"]), "units_mismatch")
	var as_erg := ErgMrcParser.parse(_erg("0\t100\n5\t100", "MINUTES PERCENT"), "erg")
	assert_eq(as_erg.workout.steps[0].target_kind, WorkoutStep.TargetKind.WATTS, "REQ-IMP-02 крит. 2: .erg → ватты, несмотря на PERCENT")
	assert_eq(as_erg.workout.source, "erg")


func test_auto_kind_detected_from_header() -> void:
	var pct := ErgMrcParser.parse(_erg("0\t100\n5\t100", "MINUTES PERCENT"), "auto")
	assert_eq(pct.workout.source, "mrc")
	assert_eq(pct.workout.steps[0].target_kind, WorkoutStep.TargetKind.PERCENT_FTP)
	var watts := ErgMrcParser.parse(_erg("0\t100\n5\t100", "MINUTES WATTS"), "")
	assert_eq(watts.workout.source, "erg")
	assert_eq(watts.workout.steps[0].target_kind, WorkoutStep.TargetKind.WATTS)


func test_decimal_comma_is_accepted_with_warning() -> void:
	var r := ErgMrcParser.parse(_fixture("decimal_comma.erg"), "erg")
	assert_true(r.ok(), str(r.error_messages()))
	assert_eq(r.workout.steps[0].duration_sec, 150, "2,5 мин → 150 с")
	assert_eq(str(r.warnings[0]["key"]), "decimal_comma")


func test_lf_and_crlf_give_same_result() -> void:
	var lf := _erg("0\t100\n5\t200")
	var crlf := lf.replace("\n", "\r\n")
	var a := ErgMrcParser.parse(lf, "erg")
	var b := ErgMrcParser.parse(crlf, "erg")
	assert_true(a.ok() and b.ok())
	assert_eq(a.workout.total_duration_sec(), b.workout.total_duration_sec())
	assert_eq(a.workout.steps[0].target_end, b.workout.steps[0].target_end)


# ---------------------------------------------------------------------------
# Ошибки (REQ-IMP-02 крит. 5, REQ-IMP-05, REQ-NFR-09 крит. 3)
# ---------------------------------------------------------------------------

func test_missing_course_data_is_error() -> void:
	var r := ErgMrcParser.parse(_fixture("no_course_data.erg"), "erg")
	assert_false(r.ok())
	assert_null(r.workout)
	assert_eq(str(r.errors[0]["key"]), "no_course_data", "REQ-IMP-02 крит. 5")


func test_non_monotonic_time_is_error_with_line_number() -> void:
	var r := ErgMrcParser.parse(_fixture("non_monotonic.erg"), "erg")
	assert_false(r.ok())
	assert_null(r.workout, "частичный план не возвращается")
	assert_eq(str(r.errors[0]["key"]), "non_monotonic_time", "REQ-IMP-02 крит. 5")
	assert_eq(int(r.errors[0]["line"]), 8, "REQ-IMP-05 крит. 1: строка с нарушением")
	assert_string_contains(ParseResult.format_entry(r.errors[0], "non_monotonic.erg"), "строка 8")


func test_non_numeric_value_is_error_with_line_number() -> void:
	var r := ErgMrcParser.parse(_erg("0\t100\n5\tabc\n10\t100"), "erg")
	assert_false(r.ok())
	assert_eq(str(r.errors[0]["key"]), "bad_number")
	assert_eq(int(r.errors[0]["line"]), 7)


func test_too_few_points_and_zero_length_are_errors() -> void:
	var one := ErgMrcParser.parse(_erg("0\t100"), "erg")
	assert_eq(str(one.errors[0]["key"]), "too_few_points")
	var same_time := ErgMrcParser.parse(_erg("0\t100\n0\t200"), "erg")
	assert_eq(str(same_time.errors[0]["key"]), "no_steps")


func test_empty_file_and_unknown_kind_are_errors() -> void:
	var empty := ErgMrcParser.parse(_fixture("empty.erg"), "erg")
	assert_false(empty.ok())
	assert_eq(str(empty.errors[0]["key"]), "empty_file")
	var bad_kind := ErgMrcParser.parse(_erg("0\t100\n5\t100"), "zwo")
	assert_eq(str(bad_kind.errors[0]["key"]), "unknown_kind")


func test_error_messages_contain_no_stacktrace_or_class_names() -> void:
	for name in ["no_course_data.erg", "non_monotonic.erg", "empty.erg"]:
		var r := ErgMrcParser.parse(_fixture(name), "erg")
		for m in r.error_messages():
			assert_false(m.contains("res://") or m.contains(".gd") or m.contains("ErgMrcParser") or m.contains("at:"),
					"REQ-IMP-05 крит. 3: '%s'" % m)


func test_parsed_workouts_are_valid_for_domain() -> void:
	assert_true(ErgMrcParser.parse(_fixture("ramp_jump.erg"), "erg").workout.is_valid())
	assert_true(ErgMrcParser.parse(_fixture("sweet_spot_text.mrc"), "mrc").workout.is_valid())
