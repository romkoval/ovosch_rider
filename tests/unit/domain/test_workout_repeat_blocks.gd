extends GutTest
## T-099: метаданные блоков повторов в `Workout` (`repeat_blocks`, `repeat_block`,
## `valid_repeat_blocks`) и сравнение шагов `WorkoutStep.same_as` (REQ-HUD-13 п.8, REQ-INT-03 п.5).


func _plan() -> Workout:
	var block: Array[WorkoutStep] = [
		WorkoutStep.percent(15, 160.0),
		WorkoutStep.percent(45, 62.5),
	]
	block[0].text_cues.append(TextCue.make(5, "go"))
	var steps: Array[WorkoutStep] = [WorkoutStep.percent(60, 50.0)]
	var w := Workout.make("rep", steps, "intervals_icu")
	w.repeat_blocks.append(Workout.repeat_block(w.steps.size(), block.size(), 3))
	w.steps.append_array(Workout.expand_repeat(block, 3))
	return w


func test_repeat_block_fields() -> void:
	assert_eq(Workout.repeat_block(2, 2, 4), {"first": 2, "last": 9, "period": 2, "count": 4})
	assert_eq(Workout.repeat_block(0, 3, 1), {"first": 0, "last": 2, "period": 3, "count": 1})


func test_same_as_compares_content() -> void:
	var a := WorkoutStep.ramp_percent(60, 50.0, 80.0)
	a.cadence_rpm = 90
	a.text_cues.append(TextCue.make(10, "spin"))
	var b := a.duplicate_step()
	assert_true(a.same_as(b), "копия совпадает")
	assert_false(a.same_as(null))
	b.cadence_rpm = 95
	assert_false(a.same_as(b), "другой каденс")
	b = a.duplicate_step()
	b.text_cues[0].text = "other"
	assert_false(a.same_as(b), "другая подсказка")
	b = a.duplicate_step()
	b.kind = WorkoutStep.StepKind.STEADY
	assert_false(a.same_as(b), "другой тип")
	assert_false(a.same_as(WorkoutStep.ramp_percent(60, 50.0, 81.0)), "другая цель")


func test_valid_repeat_blocks_matches_steps() -> void:
	var w := _plan()
	assert_eq(w.valid_repeat_blocks(), [{"first": 1, "last": 6, "period": 2, "count": 3}] as Array[Dictionary])
	w.steps[4].target_start = 70.0
	assert_true(w.valid_repeat_blocks().is_empty(), "повтор не совпадает с первым — блок отброшен")


func test_valid_repeat_blocks_drops_inconsistent_and_overlapping() -> void:
	var w := _plan()
	w.repeat_blocks = [
		{"first": 3, "last": 6, "period": 2, "count": 2},
		{"first": 1, "last": 6, "period": 2, "count": 3},
		{"first": -1, "last": 0, "period": 1, "count": 2},
		{"first": 1, "last": 5, "period": 2, "count": 3},
		{"first": 1, "last": 6, "period": 0, "count": 3},
		{"first": 5, "last": 8, "period": 2, "count": 2},
	]
	assert_eq(w.valid_repeat_blocks(), [{"first": 1, "last": 6, "period": 2, "count": 3}] as Array[Dictionary],
			"по first; пересекающийся {3..6} после {1..6} отброшен, битые — тоже")
	assert_eq(w.repeat_blocks.size(), 6, "valid_repeat_blocks не меняет repeat_blocks")


func test_to_dict_from_dict_round_trip_with_blocks() -> void:
	var w := _plan()
	var d := w.to_dict()
	assert_eq(d["repeat_blocks"], [{"first": 1, "last": 6, "period": 2, "count": 3}])
	var back := Workout.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_eq(back.repeat_blocks, w.repeat_blocks)
	assert_eq(back.valid_repeat_blocks(), w.valid_repeat_blocks())
	assert_eq(back.to_dict(), d)


func test_from_dict_old_format_without_blocks() -> void:
	var w := Workout.make("old", [WorkoutStep.watts(60, 200.0)] as Array[WorkoutStep])
	var d := w.to_dict()
	assert_false(d.has("repeat_blocks"), "без блоков словарь прежнего вида")
	var back := Workout.from_dict(d)
	assert_true(back.repeat_blocks.is_empty())
	assert_true(back.valid_repeat_blocks().is_empty())
	assert_eq(back.to_dict(), d)
