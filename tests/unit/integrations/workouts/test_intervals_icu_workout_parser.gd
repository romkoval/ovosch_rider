extends GutTest
## Тесты IntervalsIcuWorkoutParser (REQ-INT-03 крит. 1–9, REQ-NFR-09 крит. 3).

const FIXTURES: String = "res://tests/fixtures/workouts/"


static func _event(name: String) -> Dictionary:
	var json := JSON.new()
	var err := json.parse(FileAccess.get_file_as_string(FIXTURES + name))
	assert(err == OK and json.data is Dictionary, "фикстура %s читается" % name)
	return json.data


# ---------------------------------------------------------------------------
# workout_doc (intervals_event_doc.json)
# ---------------------------------------------------------------------------

func test_doc_fixture_step_count_total_and_metadata() -> void:
	var r := IntervalsIcuWorkoutParser.parse(_event("intervals_event_doc.json"))
	assert_true(r.ok(), str(r.error_messages()))
	var w: Workout = r.workout
	assert_eq(w.steps.size(), 1 + 3 * 2 + 1 + 1, "REQ-INT-03 крит. 5: 3×2 вложенных шагов развёрнуты")
	assert_eq(w.total_duration_sec(), 3900)
	assert_eq(w.name, "Sweet Spot 3x10")
	assert_eq(w.source, "intervals_icu")
	assert_eq(int(r.metadata.get("id", 0)), 1001)
	assert_true(w.is_valid(), str(w.validate()))


func test_doc_warmup_ramp_with_text_cue() -> void:
	var r := IntervalsIcuWorkoutParser.parse(_event("intervals_event_doc.json"))
	var s: WorkoutStep = r.workout.steps[0]
	assert_eq(s.kind, WorkoutStep.StepKind.WARMUP)
	assert_true(s.is_ramp(), "REQ-INT-03 крит. 4: ramp:true со start/end → рампа")
	assert_eq(s.target_kind, WorkoutStep.TargetKind.PERCENT_FTP)
	assert_eq(s.target_start, 50.0)
	assert_eq(s.target_end, 70.0)
	assert_eq(s.duration_sec, 600)
	assert_eq(s.text_cues.size(), 1, "REQ-INT-03 крит. 7")
	assert_eq(s.text_cues[0].text, "Разминка")


func test_doc_range_without_ramp_flag_becomes_midpoint_and_repeats_expand() -> void:
	var r := IntervalsIcuWorkoutParser.parse(_event("intervals_event_doc.json"))
	for i in 3:
		var on: WorkoutStep = r.workout.steps[1 + i * 2]
		var off: WorkoutStep = r.workout.steps[2 + i * 2]
		assert_eq(on.duration_sec, 600)
		assert_false(on.is_ramp(), "диапазон без ramp — не рампа")
		assert_eq(on.target_start, 91.0, "REQ-INT-03 крит. 3: 88–94 % → 91 %")
		assert_eq(on.cadence_rpm, 90, "REQ-INT-03 крит. 6: каденс")
		assert_eq(on.text_cues[0].text, "Свит-спот", "подсказка повторяется в каждом повторе")
		assert_eq(off.duration_sec, 300)
		assert_eq(off.target_start, 55.0, "REQ-INT-03 крит. 1: value → постоянная")
		assert_eq(off.cadence_rpm, 0, "REQ-INT-03 крит. 6: каденс не задан → 0")


func test_doc_watts_units_and_cadence_range() -> void:
	var r := IntervalsIcuWorkoutParser.parse(_event("intervals_event_doc.json"))
	var s: WorkoutStep = r.workout.steps[7]
	assert_eq(s.target_kind, WorkoutStep.TargetKind.WATTS, "REQ-INT-03 крит. 2: units w → ватты")
	assert_eq(s.target_start, 180.0)
	assert_eq(s.cadence_rpm, 90, "каденс диапазоном 85–95 → 90")
	assert_eq(r.workout.target_watts_at(3300.0 + 10.0, 999), 180, "ватты не зависят от FTP")


func test_doc_low_high_midpoint_and_cooldown_kind() -> void:
	var r := IntervalsIcuWorkoutParser.parse(_event("intervals_event_doc.json"))
	var s: WorkoutStep = r.workout.steps[8]
	assert_eq(s.kind, WorkoutStep.StepKind.COOLDOWN)
	assert_eq(s.target_start, 50.0, "REQ-INT-03 крит. 3: low/high 40–60 → 50")
	assert_false(s.is_ramp())


func test_doc_duration_matches_declared_no_warning() -> void:
	var r := IntervalsIcuWorkoutParser.parse(_event("intervals_event_doc.json"))
	assert_false(r.warning_messages().any(func(m: String) -> bool: return m.contains("заявленной")),
			"REQ-INT-03 крит. 8: длительность совпадает, предупреждения нет: %s" % str(r.warning_messages()))


func test_declared_duration_mismatch_gives_warning() -> void:
	var event := {"name": "x", "duration": 1000, "workout_doc": {"steps": [{"duration": 600, "power": {"value": 60}}]}}
	var r := IntervalsIcuWorkoutParser.parse(event)
	assert_true(r.ok(), str(r.error_messages()))
	assert_eq(r.warnings.size(), 1)
	assert_eq(str(r.warnings[0]["key"]), "duration_mismatch", "REQ-INT-03 крит. 8")
	var within := IntervalsIcuWorkoutParser.parse({"duration": 601, "workout_doc": {"steps": [{"duration": 600, "power": {"value": 60}}]}})
	assert_eq(within.warnings.size(), 0, "допуск ±1 с")


func test_doc_freeride_and_numeric_power() -> void:
	var r := IntervalsIcuWorkoutParser.parse({"workout_doc": {"steps": [
		{"duration": 120, "freeride": true},
		{"duration": 60, "power": 75},
	]}})
	assert_true(r.ok(), str(r.error_messages()))
	assert_eq(r.workout.steps[0].target_kind, WorkoutStep.TargetKind.NONE)
	assert_eq(r.workout.steps[1].target_start, 75.0)


func test_doc_unsupported_units_is_error_with_position() -> void:
	var r := IntervalsIcuWorkoutParser.parse({"workout_doc": {"steps": [
		{"duration": 600, "power": {"value": 60}},
		{"reps": 2, "steps": [{"duration": 60, "power": {"value": 3, "units": "zone"}}]},
	]}})
	assert_false(r.ok())
	assert_null(r.workout, "REQ-INT-03 крит. 9: частичный план не возвращается")
	assert_eq(str(r.errors[0]["key"]), "unsupported_units")
	assert_eq(str(r.errors[0]["element"]), "steps[1].steps[0].power.units", "REQ-INT-03 крит. 9: позиция")
	assert_eq(int(r.errors[0]["line"]), 2, "номер шага верхнего уровня")


func test_doc_hr_target_and_bad_duration_are_errors() -> void:
	var hr := IntervalsIcuWorkoutParser.parse({"workout_doc": {"steps": [{"duration": 600, "hr": {"value": 140}}]}})
	assert_eq(str(hr.errors[0]["key"]), "unsupported_target")
	var dur := IntervalsIcuWorkoutParser.parse({"workout_doc": {"steps": [{"duration": 0, "power": {"value": 60}}]}})
	assert_eq(str(dur.errors[0]["key"]), "bad_duration")
	var empty := IntervalsIcuWorkoutParser.parse({"workout_doc": {"steps": []}})
	assert_eq(str(empty.errors[0]["key"]), "no_steps")


# ---------------------------------------------------------------------------
# Текстовое описание (intervals_event_text.json)
# ---------------------------------------------------------------------------

func test_text_fixture_used_when_no_workout_doc() -> void:
	var r := IntervalsIcuWorkoutParser.parse(_event("intervals_event_text.json"))
	assert_true(r.ok(), str(r.error_messages()))
	var w: Workout = r.workout
	assert_eq(w.steps.size(), 1 + 1 + 6 + 1 + 1 + 1)
	assert_eq(w.total_duration_sec(), 3360)
	assert_eq(w.name, "Threshold text only")
	assert_eq(w.source, "intervals_icu")
	assert_false(r.warning_messages().any(func(m: String) -> bool: return m.contains("заявленной")), "REQ-INT-03 крит. 8")
	assert_true(w.is_valid(), str(w.validate()))


func test_text_percent_step() -> void:
	var r := IntervalsIcuWorkoutParser.parse_description_text("- 10m 65%")
	assert_true(r.ok(), str(r.error_messages()))
	var s: WorkoutStep = r.workout.steps[0]
	assert_eq(s.duration_sec, 600, "REQ-INT-03 крит. 1: 10m → 600 с")
	assert_eq(s.target_kind, WorkoutStep.TargetKind.PERCENT_FTP)
	assert_eq(s.target_start, 65.0, "REQ-INT-03 крит. 1: 65 %")
	assert_eq(r.workout.target_watts_at(10.0, 200), 130)


func test_text_watts_step() -> void:
	var r := IntervalsIcuWorkoutParser.parse_description_text("- 5m 250w")
	var s: WorkoutStep = r.workout.steps[0]
	assert_eq(s.duration_sec, 300, "REQ-INT-03 крит. 2")
	assert_eq(s.target_kind, WorkoutStep.TargetKind.WATTS)
	assert_eq(s.target_start, 250.0)


func test_text_range_becomes_midpoint_with_cadence() -> void:
	var r := IntervalsIcuWorkoutParser.parse_description_text("- 10m 85-95% 90rpm")
	var s: WorkoutStep = r.workout.steps[0]
	assert_eq(s.target_start, 90.0, "REQ-INT-03 крит. 3: 85–95 % → 90 %")
	assert_false(s.is_ramp())
	assert_eq(s.cadence_rpm, 90, "REQ-INT-03 крит. 6")
	var rng := IntervalsIcuWorkoutParser.parse_description_text("- 4m 100% 80-90rpm")
	assert_eq(rng.workout.steps[0].cadence_rpm, 85, "каденс диапазоном → середина")


func test_text_ramp() -> void:
	var r := IntervalsIcuWorkoutParser.parse_description_text("- 8m ramp 50-75%")
	var s: WorkoutStep = r.workout.steps[0]
	assert_true(s.is_ramp(), "REQ-INT-03 крит. 4")
	assert_eq(s.target_start, 50.0)
	assert_eq(s.target_end, 75.0)
	assert_eq(s.duration_sec, 480)
	var suffix := IntervalsIcuWorkoutParser.parse_description_text("- 8m 200-300w ramp")
	assert_eq(suffix.workout.steps[0].target_kind, WorkoutStep.TargetKind.WATTS)
	assert_eq(suffix.workout.steps[0].target_end, 300.0)


func test_text_inline_repeat_expands() -> void:
	var r := IntervalsIcuWorkoutParser.parse_description_text("3x (4m 105%, 2m 50%)")
	assert_true(r.ok(), str(r.error_messages()))
	assert_eq(r.workout.steps.size(), 6, "REQ-INT-03 крит. 5: 3 × 2")
	for i in 3:
		assert_eq(r.workout.steps[i * 2].duration_sec, 240)
		assert_eq(r.workout.steps[i * 2].target_start, 105.0)
		assert_eq(r.workout.steps[i * 2 + 1].duration_sec, 120)
		assert_eq(r.workout.steps[i * 2 + 1].target_start, 50.0)


func test_text_block_repeat_until_blank_line() -> void:
	var r := IntervalsIcuWorkoutParser.parse_description_text("- 5m 50%\n\n3x\n- 4m 105%\n- 2m 50%\n\n- 5m 40%")
	assert_true(r.ok(), str(r.error_messages()))
	assert_eq(r.workout.steps.size(), 1 + 6 + 1, "REQ-INT-03 крит. 5: блок после «3x» повторён")
	assert_eq(r.workout.total_duration_sec(), 300 + 3 * 360 + 300)
	assert_eq(r.workout.steps[7].target_start, 40.0)


func test_text_lines_without_dash_become_cues_of_next_step() -> void:
	var r := IntervalsIcuWorkoutParser.parse(_event("intervals_event_text.json"))
	var first: WorkoutStep = r.workout.steps[0]
	assert_eq(first.text_cues.size(), 1, "REQ-INT-03 крит. 7")
	assert_eq(first.text_cues[0].text, "Warmup")
	assert_eq(first.text_cues[0].at_sec, 0)
	var last: WorkoutStep = r.workout.steps[r.workout.steps.size() - 1]
	assert_eq(last.text_cues[0].text, "Cooldown")
	assert_eq(r.workout.steps[1].text_cues.size(), 0)


func test_text_words_after_targets_become_step_cue() -> void:
	var r := IntervalsIcuWorkoutParser.parse_description_text("- 10m 65% Spin easy")
	assert_true(r.ok(), str(r.error_messages()))
	assert_eq(r.workout.steps[0].text_cues[0].text, "Spin easy")


func test_text_duration_formats() -> void:
	var r := IntervalsIcuWorkoutParser.parse_description_text("- 10:00 65%\n- 1h 60%\n- 1h30m 60%\n- 90s 100%\n- 1:00:30 55%")
	assert_true(r.ok(), str(r.error_messages()))
	assert_eq(r.workout.steps[0].duration_sec, 600)
	assert_eq(r.workout.steps[1].duration_sec, 3600)
	assert_eq(r.workout.steps[2].duration_sec, 5400)
	assert_eq(r.workout.steps[3].duration_sec, 90)
	assert_eq(r.workout.steps[4].duration_sec, 3630)


func test_text_unsupported_target_is_error_with_line_and_column() -> void:
	var r := IntervalsIcuWorkoutParser.parse(_event("intervals_event_unsupported.json"))
	assert_false(r.ok())
	assert_null(r.workout, "REQ-INT-03 крит. 9: частичный план не возвращается")
	assert_eq(r.errors.size(), 1)
	assert_eq(int(r.errors[0]["line"]), 2, "REQ-INT-03 крит. 9: строка")
	assert_gt(int(r.errors[0]["column"]), 0, "REQ-INT-03 крит. 9: позиция в строке")
	assert_eq(str(r.errors[0]["element"]), "140-150bpm")
	assert_string_contains(str(r.errors[0]["message"]), "не поддерживается")


func test_text_zone_and_pace_targets_are_errors() -> void:
	assert_eq(str(IntervalsIcuWorkoutParser.parse_description_text("- 10m Z2").errors[0]["key"]), "unsupported_element")
	assert_eq(str(IntervalsIcuWorkoutParser.parse_description_text("- 10m 4:30/km").errors[0]["key"]), "unsupported_element")


func test_text_missing_duration_and_empty_description_are_errors() -> void:
	var nodur := IntervalsIcuWorkoutParser.parse_description_text("- 65%")
	assert_eq(str(nodur.errors[0]["key"]), "missing_duration")
	assert_eq(int(nodur.errors[0]["line"]), 1)
	var empty := IntervalsIcuWorkoutParser.parse_description_text("   ")
	assert_eq(str(empty.errors[0]["key"]), "empty_description")
	var no_steps := IntervalsIcuWorkoutParser.parse_description_text("Just a note\nno steps here")
	assert_eq(str(no_steps.errors[0]["key"]), "no_steps")
	var no_doc := IntervalsIcuWorkoutParser.parse({"name": "x"})
	assert_false(no_doc.ok(), "событие без workout_doc и описания — ошибка")


func test_text_step_without_power_is_free_ride_with_warning() -> void:
	var r := IntervalsIcuWorkoutParser.parse_description_text("- 10m")
	assert_true(r.ok(), str(r.error_messages()))
	assert_eq(r.workout.steps[0].target_kind, WorkoutStep.TargetKind.NONE)
	assert_eq(str(r.warnings[0]["key"]), "no_target")


func test_error_messages_contain_no_stacktrace_or_class_names() -> void:
	var results: Array[ParseResult] = [
		IntervalsIcuWorkoutParser.parse(_event("intervals_event_unsupported.json")),
		IntervalsIcuWorkoutParser.parse_description_text("- 65%"),
		IntervalsIcuWorkoutParser.parse({"workout_doc": {"steps": [{"duration": 60, "power": {"units": "zone", "value": 1}}]}}),
	]
	for r in results:
		assert_false(r.ok())
		for m in r.error_messages():
			assert_false(m.contains("res://") or m.contains(".gd") or m.contains("IntervalsIcuWorkoutParser") or m.contains("at:"),
					"REQ-IMP-05 крит. 3: '%s'" % m)
