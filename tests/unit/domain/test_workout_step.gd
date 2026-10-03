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


# ---------------------------------------------------------------------------
# Сериализация (решение Н-6): to_dict/from_dict шага и подсказки
# ---------------------------------------------------------------------------

func test_to_dict_uses_string_enum_names_and_cues() -> void:
	var s := WorkoutStep.ramp_percent(300, 40.0, 65.0, WorkoutStep.StepKind.WARMUP)
	s.cadence_rpm = 90
	s.text_cues.append(TextCue.make(15, "hold"))
	var d := s.to_dict()
	assert_eq(int(d["duration_sec"]), 300)
	assert_eq(str(d["target_kind"]), "percent_ftp")
	assert_eq(str(d["kind"]), "warmup")
	assert_eq(float(d["target_start"]), 40.0)
	assert_eq(float(d["target_end"]), 65.0)
	assert_eq(int(d["cadence_rpm"]), 90)
	assert_eq((d["text_cues"] as Array).size(), 1)
	assert_eq(str(d["text_cues"][0]["text"]), "hold")
	assert_eq(int(d["text_cues"][0]["at_sec"]), 15)
	assert_eq(JSON.parse_string(JSON.stringify(d))["kind"], "warmup", "словарь JSON-совместим")


func test_from_dict_round_trips_every_target_and_step_kind() -> void:
	var steps: Array[WorkoutStep] = [
		WorkoutStep.ramp_percent(300, 40.0, 65.0, WorkoutStep.StepKind.WARMUP),
		WorkoutStep.percent(600, 90.0),
		WorkoutStep.watts(120, 250.0, WorkoutStep.StepKind.INTERVAL_ON),
		WorkoutStep.percent(60, 50.0, WorkoutStep.StepKind.INTERVAL_OFF),
		WorkoutStep.ramp_watts(60, 100.0, 200.0),
		WorkoutStep.free_ride(90),
		WorkoutStep.percent(30, 50.0, WorkoutStep.StepKind.COOLDOWN),
	]
	steps[1].cadence_rpm = 95
	steps[1].text_cues.append(TextCue.make(10, "a"))
	steps[1].text_cues.append(TextCue.make(20, "b"))
	for i in steps.size():
		var back := WorkoutStep.from_dict(steps[i].to_dict())
		assert_not_null(back, "шаг %d восстановлен" % i)
		assert_eq(back.duration_sec, steps[i].duration_sec, "шаг %d: длительность" % i)
		assert_eq(back.target_kind, steps[i].target_kind, "шаг %d: вид цели" % i)
		assert_eq(back.kind, steps[i].kind, "шаг %d: тип" % i)
		assert_eq(back.target_start, steps[i].target_start, "шаг %d: цель" % i)
		assert_eq(back.target_end, steps[i].target_end, "шаг %d: цель конца" % i)
		assert_eq(back.cadence_rpm, steps[i].cadence_rpm, "шаг %d: каденс" % i)
		assert_eq(back.text_cues.size(), steps[i].text_cues.size(), "шаг %d: подсказки" % i)
		assert_eq(back.target_watts_at(30.0, 200), steps[i].target_watts_at(30.0, 200), "шаг %d: ватты совпадают" % i)
	var cues := WorkoutStep.from_dict(steps[1].to_dict()).text_cues
	assert_eq(cues[1].at_sec, 20)
	assert_eq(cues[1].text, "b")


func test_from_dict_tolerates_garbage() -> void:
	assert_null(WorkoutStep.from_dict({}), "без duration_sec → null")
	var s := WorkoutStep.from_dict({"duration_sec": 60.0, "target_kind": "bogus", "kind": "bogus", "target_start": 70, "text_cues": [1, {"at_sec": 5}, {"at_sec": 7, "text": "ok"}]})
	assert_not_null(s)
	assert_eq(s.duration_sec, 60)
	assert_eq(s.target_kind, WorkoutStep.TargetKind.NONE, "неизвестное имя → NONE")
	assert_eq(s.kind, WorkoutStep.StepKind.STEADY, "неизвестное имя → STEADY")
	assert_eq(s.target_end, 70.0, "target_end по умолчанию = target_start")
	assert_eq(s.text_cues.size(), 1, "битые подсказки пропущены")
	assert_eq(s.text_cues[0].text, "ok")


func test_text_cue_to_dict_from_dict() -> void:
	var c := TextCue.make(42, "Жми!")
	var d := c.to_dict()
	assert_eq(d, {"at_sec": 42, "text": "Жми!"})
	var back := TextCue.from_dict(d)
	assert_eq(back.at_sec, 42)
	assert_eq(back.text, "Жми!")
	assert_null(TextCue.from_dict({"at_sec": 1}), "без text → null")
	assert_eq(TextCue.from_dict({"text": "x"}).at_sec, 0)
