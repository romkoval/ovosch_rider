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
