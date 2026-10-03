extends GutTest
## Тесты модели тренировки Workout (REQ-INT-03, REQ-INT-05, REQ-WRK-01, REQ-HUD-07).

const FTP: int = 200


func _three_steps() -> Workout:
	var steps: Array[WorkoutStep] = [
		WorkoutStep.percent(60, 50.0),
		WorkoutStep.percent(30, 100.0),
		WorkoutStep.percent(90, 60.0),
	]
	return Workout.make("test", steps)


func test_total_duration_sums_steps() -> void:
	assert_eq(_three_steps().total_duration_sec(), 180, "REQ-WRK-01 крит. 2: план 60/30/90 → 180 с")
	assert_eq(Workout.new().total_duration_sec(), 0)


func test_step_index_at_boundaries() -> void:
	var w := _three_steps()
	assert_eq(w.step_index_at(0.0), 0)
	assert_eq(w.step_index_at(59.9), 0)
	assert_eq(w.step_index_at(60.0), 1, "граница шагов → следующий шаг")
	assert_eq(w.step_index_at(89.0), 1)
	assert_eq(w.step_index_at(90.0), 2)
	assert_eq(w.step_index_at(179.0), 2)


func test_step_index_at_end_and_negative_is_minus_one() -> void:
	var w := _three_steps()
	assert_eq(w.step_index_at(180.0), -1, ">= total → -1 (тренировка завершена)")
	assert_eq(w.step_index_at(1000.0), -1)
	assert_eq(w.step_index_at(-1.0), -1)
	assert_eq(Workout.new().step_index_at(0.0), -1)


func test_step_offset_at() -> void:
	var w := _three_steps()
	assert_eq(w.step_offset_at(0.0), 0.0)
	assert_eq(w.step_offset_at(45.0), 45.0)
	assert_eq(w.step_offset_at(60.0), 0.0)
	assert_eq(w.step_offset_at(100.5), 10.5)
	assert_eq(w.step_offset_at(180.0), -1.0)


func test_step_start_sec() -> void:
	var w := _three_steps()
	assert_eq(w.step_start_sec(0), 0)
	assert_eq(w.step_start_sec(1), 60)
	assert_eq(w.step_start_sec(2), 90)
	assert_eq(w.step_start_sec(3), 180)
	assert_eq(w.step_start_sec(4), -1)
	assert_eq(w.step_start_sec(-1), -1)


func test_target_watts_at_elapsed() -> void:
	var w := _three_steps()
	assert_eq(w.target_watts_at(10.0, FTP), 100)
	assert_eq(w.target_watts_at(60.0, FTP), 200)
	assert_eq(w.target_watts_at(60.0, FTP, 1.1), 220)
	assert_eq(w.target_watts_at(180.0, FTP), 0)


func test_expand_repeat_flattens_and_copies() -> void:
	var block: Array[WorkoutStep] = [
		WorkoutStep.percent(30, 120.0, WorkoutStep.StepKind.INTERVAL_ON),
		WorkoutStep.percent(30, 50.0, WorkoutStep.StepKind.INTERVAL_OFF),
	]
	var out := Workout.expand_repeat(block, 3)
	assert_eq(out.size(), 6, "REQ-INT-03 крит. 5: повторы × шагов в блоке")
	assert_eq(out[0].kind, WorkoutStep.StepKind.INTERVAL_ON)
	assert_eq(out[1].kind, WorkoutStep.StepKind.INTERVAL_OFF)
	assert_eq(out[4].target_start, 120.0)
	assert_ne(out[0], out[2], "каждый повтор — отдельный экземпляр")
	out[0].target_start = 10.0
	assert_eq(out[2].target_start, 120.0)
	assert_eq(block[0].target_start, 120.0)


func test_expand_repeat_zero_or_negative_count_is_empty() -> void:
	var block: Array[WorkoutStep] = [WorkoutStep.percent(30, 50.0)]
	assert_eq(Workout.expand_repeat(block, 0).size(), 0)
	assert_eq(Workout.expand_repeat(block, -2).size(), 0)


func test_power_profile_steps_req_int_05() -> void:
	var steps: Array[WorkoutStep] = [WorkoutStep.percent(600, 50.0), WorkoutStep.percent(300, 100.0)]
	var w := Workout.make("preview", steps)
	var p := w.power_profile(FTP)
	assert_eq(p.size(), 900, "длина = total_duration_sec")
	assert_eq(p[0], 100)
	assert_eq(p[599], 100)
	assert_eq(p[600], 200)
	assert_eq(p[899], 200)


func test_power_profile_ramp_is_linear() -> void:
	var steps: Array[WorkoutStep] = [WorkoutStep.ramp_percent(100, 50.0, 100.0)]
	var p := Workout.make("ramp", steps).power_profile(FTP)
	assert_eq(p.size(), 100)
	assert_eq(p[0], 100, "начало = цель начала")
	assert_eq(p[50], 150)
	assert_eq(p[99], 199, "последняя точка — 99 % пути к концу")
	assert_eq(steps[0].end_watts(FTP), 200, "конечная точка = цель конца")


func test_power_profile_resolution_and_intensity() -> void:
	var steps: Array[WorkoutStep] = [WorkoutStep.percent(25, 50.0), WorkoutStep.percent(10, 100.0)]
	var w := Workout.make("res", steps)
	var p := w.power_profile(FTP, 10)
	assert_eq(p.size(), 4, "ceil(35/10)")
	assert_eq(p[0], 100)
	assert_eq(p[2], 100, "t=20 ещё в первом шаге")
	assert_eq(p[3], 200, "t=30 во втором")
	var p2 := w.power_profile(FTP, 1, 1.1)
	assert_eq(p2[0], 110)
	assert_eq(p2[30], 220)


func test_power_profile_free_ride_is_zero_and_empty_workout_is_empty() -> void:
	var steps: Array[WorkoutStep] = [WorkoutStep.free_ride(5)]
	var p := Workout.make("free", steps).power_profile(FTP)
	assert_eq(p.size(), 5)
	assert_eq(p[4], 0)
	assert_eq(Workout.new().power_profile(FTP).size(), 0)


func test_validate_empty_workout() -> void:
	var w := Workout.new()
	var errors := w.validate()
	assert_eq(errors.size(), 1)
	assert_false(w.is_valid())


func test_validate_reports_bad_steps_with_index() -> void:
	var steps: Array[WorkoutStep] = [
		WorkoutStep.percent(60, 50.0),
		WorkoutStep.percent(0, 50.0),
		WorkoutStep.watts(60, -1.0),
	]
	var errors := Workout.make("bad", steps).validate()
	assert_eq(errors.size(), 2)
	assert_string_contains(errors[0], "шаг 2")
	assert_string_contains(errors[1], "шаг 3")


func test_validate_unknown_source() -> void:
	var steps: Array[WorkoutStep] = [WorkoutStep.percent(60, 50.0)]
	var w := Workout.make("src", steps, "garmin")
	assert_eq(w.validate().size(), 1)
	for s in Workout.SOURCES:
		w.source = s
		assert_true(w.is_valid(), "источник '%s' допустим" % s)


func test_power_points_ramp_ends_at_end_target() -> void:
	var steps: Array[WorkoutStep] = [WorkoutStep.ramp_watts(60, 100.0, 200.0)]
	var pts := Workout.make("ramp", steps).power_points(FTP)
	assert_eq(pts.size(), 2)
	assert_eq(pts[0], Vector2(0.0, 100.0), "REQ-INT-05 крит. 2: начальная точка = цель начала")
	assert_eq(pts[1], Vector2(60.0, 200.0), "конечная точка = цель конца")


func test_power_points_two_steps_give_four_points_with_vertical_jump() -> void:
	var steps: Array[WorkoutStep] = [WorkoutStep.percent(600, 50.0), WorkoutStep.percent(300, 100.0)]
	var pts := Workout.make("two", steps).power_points(FTP)
	assert_eq(pts.size(), 4)
	assert_eq(pts[0], Vector2(0.0, 100.0))
	assert_eq(pts[1], Vector2(600.0, 100.0))
	assert_eq(pts[2], Vector2(600.0, 200.0), "скачок: та же t, другая мощность")
	assert_eq(pts[3], Vector2(900.0, 200.0))
	var pts_110 := Workout.make("two", steps).power_points(FTP, 1.1)
	assert_eq(pts_110[2], Vector2(600.0, 220.0), "множитель применяется")


func test_power_points_free_ride_and_empty() -> void:
	var steps: Array[WorkoutStep] = [WorkoutStep.free_ride(30)]
	var pts := Workout.make("free", steps).power_points(FTP)
	assert_eq(pts[0], Vector2(0.0, 0.0))
	assert_eq(pts[1], Vector2(30.0, 0.0))
	assert_eq(Workout.new().power_points(FTP).size(), 0)


func test_segments_for_progress_bar() -> void:
	var steps: Array[WorkoutStep] = [
		WorkoutStep.percent(60, 50.0),
		WorkoutStep.ramp_percent(30, 60.0, 100.0),
		WorkoutStep.percent(90, 110.0),
	]
	var w := Workout.make("seg", steps)
	var segs := w.segments(FTP)
	assert_eq(segs.size(), 3)
	assert_eq(segs[0]["index"], 0)
	assert_eq(segs[0]["start_sec"], 0)
	assert_eq(segs[0]["duration_sec"], 60)
	assert_eq(segs[0]["start_watts"], 100)
	assert_eq(segs[0]["end_watts"], 100)
	assert_eq(segs[0]["zone"], 1, "100 Вт при FTP 200 → Z1")
	assert_eq(segs[1]["start_sec"], 60)
	assert_eq(segs[1]["start_watts"], 120)
	assert_eq(segs[1]["end_watts"], 200)
	assert_eq(segs[1]["zone"], 2)
	assert_eq(segs[2]["start_sec"], 90)
	assert_eq(segs[2]["zone"], 5, "220 Вт → Z5")
	var total: int = 0
	for sg in segs:
		total += sg["duration_sec"]
	assert_eq(total, w.total_duration_sec(), "REQ-HUD-07 крит. 1: сумма длительностей = длительность плана")


func test_segments_zone_follows_intensity() -> void:
	var steps: Array[WorkoutStep] = [WorkoutStep.percent(60, 100.0)]
	var w := Workout.make("z", steps)
	assert_eq(w.segments(FTP)[0]["zone"], 4, "200 Вт → Z4")
	assert_eq(w.segments(FTP, 1.1)[0]["zone"], 5, "REQ-HUD-07 крит. 2: 220 Вт → Z5")
	assert_eq(w.segments(FTP, 0.5)[0]["zone"], 1)
	assert_eq(Workout.new().segments(FTP).size(), 0)


# ---------------------------------------------------------------------------
# Сериализация и метаданные (решение Н-6)
# ---------------------------------------------------------------------------

func test_to_dict_contains_schema_fields_metadata_and_steps() -> void:
	var w := _three_steps()
	w.description = "desc"
	w.source = "zwo"
	w.metadata = {"author": "A", "sport_type": "bike", "ftp_header": 250}
	var d := w.to_dict()
	assert_eq(int(d["schema"]), Workout.SCHEMA_VERSION)
	assert_eq(str(d["name"]), "test")
	assert_eq(str(d["description"]), "desc")
	assert_eq(str(d["source"]), "zwo")
	assert_eq(str(d["metadata"]["author"]), "A")
	assert_eq((d["steps"] as Array).size(), 3)
	assert_eq(int(d["steps"][1]["duration_sec"]), 30)
	var copied: Dictionary = d["metadata"]
	copied["author"] = "B"
	assert_eq(str(w.metadata["author"]), "A", "to_dict отдаёт копию метаданных")


func test_from_dict_round_trip_via_json_preserves_everything() -> void:
	var steps: Array[WorkoutStep] = [
		WorkoutStep.ramp_percent(300, 40.0, 65.0, WorkoutStep.StepKind.WARMUP),
		WorkoutStep.percent(600, 90.0),
		WorkoutStep.watts(120, 250.0, WorkoutStep.StepKind.INTERVAL_ON),
		WorkoutStep.free_ride(90),
	]
	steps[1].cadence_rpm = 95
	steps[1].text_cues.append(TextCue.make(15, "hold"))
	var w := Workout.make("All", steps, "erg")
	w.description = "d"
	w.metadata = {"author": "A", "source_file": "x.erg", "ftp_header": 250}
	var text := JSON.stringify(w.to_dict())
	var back := Workout.from_dict(JSON.parse_string(text))
	assert_not_null(back)
	assert_eq(back.name, "All")
	assert_eq(back.description, "d")
	assert_eq(back.source, "erg")
	assert_eq(str(back.metadata["author"]), "A")
	assert_eq(str(back.metadata["source_file"]), "x.erg")
	assert_eq(int(back.metadata["ftp_header"]), 250)
	assert_eq(back.steps.size(), 4)
	assert_eq(back.total_duration_sec(), w.total_duration_sec())
	assert_eq(back.steps[1].cadence_rpm, 95)
	assert_eq(back.steps[1].text_cues[0].text, "hold")
	assert_eq(back.steps[3].target_kind, WorkoutStep.TargetKind.NONE)
	assert_eq(back.power_points(FTP), w.power_points(FTP), "профиль мощности идентичен")
	assert_true(back.is_valid())


func test_from_dict_rejects_non_workout_and_skips_bad_steps() -> void:
	assert_null(Workout.from_dict({}))
	assert_null(Workout.from_dict({"name": "x"}), "без steps → null")
	var w := Workout.from_dict({"steps": [{"duration_sec": 60, "target_kind": "percent_ftp", "target_start": 50}, 7, {"no": "duration"}], "metadata": "garbage"})
	assert_eq(w.steps.size(), 1, "битые шаги пропущены")
	assert_eq(w.metadata, {}, "метаданные не словарь → пусто")
	assert_eq(w.source, "manual")
	assert_eq(Workout.new().metadata, {}, "по умолчанию пусто")
