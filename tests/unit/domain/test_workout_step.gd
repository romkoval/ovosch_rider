extends GutTest
## Тесты шага тренировки WorkoutStep (REQ-INT-03, REQ-WRK-07).

const FTP: int = 200


func test_percent_step_keeps_duration_and_target() -> void:
	var s := WorkoutStep.percent(600, 65.0)
	assert_eq(s.duration_sec, 600)
	assert_eq(s.target_kind, WorkoutStep.TargetKind.PERCENT_FTP)
	assert_eq(s.target_start, 65.0)
	assert_eq(s.target_end, 65.0)
	assert_false(s.is_ramp())


func test_percent_target_watts_65pct_of_200_is_130() -> void:
	var s := WorkoutStep.percent(600, 65.0)
	assert_eq(s.target_watts_at(0.0, FTP), 130)
	assert_eq(s.target_watts_at(300.0, FTP), 130, "постоянный шаг — одинаково на всём протяжении")


func test_watts_step_ignores_ftp() -> void:
	var s := WorkoutStep.watts(300, 250.0)
	assert_eq(s.target_kind, WorkoutStep.TargetKind.WATTS)
	assert_eq(s.target_watts_at(0.0, 200), 250)
	assert_eq(s.target_watts_at(0.0, 350), 250)


func test_intensity_multiplier_applies_to_percent_and_watts() -> void:
	var pct := WorkoutStep.percent(60, 65.0)
	assert_eq(pct.target_watts_at(0.0, FTP, 0.9), 117)
	assert_eq(pct.target_watts_at(0.0, FTP, 1.1), 143)
	var w := WorkoutStep.watts(60, 200.0)
	assert_eq(w.target_watts_at(0.0, FTP, 1.1), 220, "REQ-WRK-07 крит. 2")
	assert_eq(w.target_watts_at(0.0, FTP, 0.9), 180)


func test_ramp_interpolates_linearly() -> void:
	var r := WorkoutStep.ramp_percent(60, 50.0, 100.0)
	assert_true(r.is_ramp())
	assert_eq(r.target_value_at(30.0), 75.0)
	assert_eq(r.target_watts_at(0.0, FTP), 100)
	assert_eq(r.target_watts_at(30.0, FTP), 150)
	assert_eq(r.target_watts_at(60.0, FTP), 200)


func test_ramp_clamps_offset_outside_step() -> void:
	var r := WorkoutStep.ramp_watts(100, 100.0, 300.0)
	assert_eq(r.target_watts_at(-10.0, FTP), 100)
	assert_eq(r.target_watts_at(150.0, FTP), 300)


func test_ramp_rounds_to_whole_watts() -> void:
	# 10 % → 11 % за 3 с при FTP 200: t=1 → 10.333 % → 20.67 Вт → 21.
	var r := WorkoutStep.ramp_percent(3, 10.0, 11.0)
	assert_eq(r.target_watts_at(1.0, FTP), 21)
	assert_eq(r.target_watts_at(2.0, FTP), 21, "10.667 % → 21.33 → 21")


func test_none_target_gives_zero_watts_and_is_free_ride() -> void:
	var f := WorkoutStep.free_ride(300)
	assert_true(f.is_free_ride())
	assert_false(f.is_ramp())
	assert_eq(f.target_watts_at(0.0, FTP), 0)
	assert_eq(f.target_watts_at(100.0, FTP, 1.5), 0)
	assert_false(WorkoutStep.percent(60, 50.0).is_free_ride())


func test_start_and_end_watts() -> void:
	var r := WorkoutStep.ramp_percent(120, 40.0, 80.0)
	assert_eq(r.start_watts(FTP), 80)
	assert_eq(r.end_watts(FTP), 160)
	assert_eq(r.end_watts(FTP, 0.5), 80)


func test_cadence_and_cues_default_empty() -> void:
	var s := WorkoutStep.percent(60, 50.0)
	assert_eq(s.cadence_rpm, 0)
	assert_eq(s.text_cues.size(), 0)
	s.cadence_rpm = 90
	s.text_cues.append(TextCue.make(10, "Держи 90 об/мин"))
	assert_eq(s.cadence_rpm, 90)
	assert_eq(s.text_cues[0].at_sec, 10)
	assert_eq(s.text_cues[0].text, "Держи 90 об/мин")


func test_duplicate_is_deep_copy() -> void:
	var s := WorkoutStep.percent(60, 50.0, WorkoutStep.StepKind.INTERVAL_ON)
	s.cadence_rpm = 95
	s.text_cues.append(TextCue.make(5, "Go"))
	var c := s.duplicate_step()
	assert_ne(c, s)
	assert_eq(c.duration_sec, 60)
	assert_eq(c.kind, WorkoutStep.StepKind.INTERVAL_ON)
	assert_eq(c.cadence_rpm, 95)
	assert_eq(c.text_cues.size(), 1)
	assert_ne(c.text_cues[0], s.text_cues[0], "подсказки копируются, а не разделяются")
	c.text_cues[0].text = "Stop"
	assert_eq(s.text_cues[0].text, "Go")


func test_validate_ok_for_normal_step() -> void:
	assert_eq(WorkoutStep.percent(60, 50.0).validate().size(), 0)
	assert_eq(WorkoutStep.free_ride(60).validate().size(), 0)


func test_validate_reports_zero_duration_and_negative_target() -> void:
	var zero := WorkoutStep.percent(0, 50.0)
	assert_eq(zero.validate().size(), 1)
	var neg := WorkoutStep.ramp_watts(60, -10.0, 200.0)
	assert_eq(neg.validate().size(), 1)
	var both := WorkoutStep.watts(0, -5.0)
	assert_eq(both.validate().size(), 2)


func test_validate_reports_cue_outside_step() -> void:
	var s := WorkoutStep.percent(60, 50.0)
	s.text_cues.append(TextCue.make(60, "late"))
	assert_eq(s.validate().size(), 1)
