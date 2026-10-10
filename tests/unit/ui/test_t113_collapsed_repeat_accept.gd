extends GutTest
## Tester acceptance of T-113 — colour of a collapsed repeat row and `repeat_blocks` of ZWO
## `IntervalsT` (REQ-HUD-13 p.8, regression REQ-IMP-01, REQ-NFR-09 p.3). Paths beyond the
## developer tests and the earlier acceptance (ab2c444): the work step of a block where «Off» is
## harder than «On», recolouring of the collapsed row by intensity, FTP and profile zones, and
## invalid `IntervalsT` that must not leave a broken block next to valid ones.

const FTP: int = 200


func _zwo(body: String) -> ParseResult:
	return ZwoParser.parse("<workout_file><name>T</name><workout>%s</workout></workout_file>" % body)


func _repeat_row(model: IntervalListModel) -> Dictionary:
	for r in model.rows():
		if str(r.get("kind", "")) == IntervalListModel.KIND_REPEAT:
			return r
	return {}


## Spec «work segment» = the step of the block with the highest target, whichever side it is on.
func test_collapsed_colour_is_the_harder_step_even_when_off_is_harder() -> void:
	var res := _zwo('<Warmup Duration="60" PowerLow="0.4" PowerHigh="0.6"/>' +
		'<IntervalsT Repeat="3" OnDuration="60" OnPower="0.55" OffDuration="120" OffPower="1.2"/>')
	assert_true(res.ok(), "precondition: parsed: %s" % str(res.errors))
	assert_eq(res.workout.repeat_blocks.size(), 1, "IntervalsT keeps its block")
	var model := IntervalListModel.new(res.workout, FTP)
	var row := _repeat_row(model)
	assert_false(row.is_empty(), "block collapsed before it starts")
	var zones := PowerZones.coggan(FTP)
	assert_eq(int(row["zone"]), zones.zone_of(240), "colour of the 120 %% step (240 W), not of the first (On) step")
	assert_eq(int(row["repeat_count"]), 3)
	assert_eq(model.row_count(), 2, "warm-up + one collapsed row")


## The colour follows what the rider will get: intensity (WRK-07), FTP and the profile zones.
func test_collapsed_colour_follows_intensity_ftp_and_profile_zones() -> void:
	var w := Workout.make("4x", [
		WorkoutStep.watts(60, 100.0, WorkoutStep.StepKind.WARMUP),
		WorkoutStep.watts(60, 125.0, WorkoutStep.StepKind.INTERVAL_OFF),
		WorkoutStep.watts(120, 300.0, WorkoutStep.StepKind.INTERVAL_ON),
	] as Array[WorkoutStep])
	var steps: Array[WorkoutStep] = [w.steps[0]]
	steps.append_array(Workout.expand_repeat([w.steps[1], w.steps[2]] as Array[WorkoutStep], 4))
	var plan := Workout.make("4x", steps)
	plan.repeat_blocks = [Workout.repeat_block(1, 2, 4)]
	var model := IntervalListModel.new(plan, FTP)
	var coggan := PowerZones.coggan(FTP)
	assert_eq(int(_repeat_row(model)["zone"]), coggan.zone_of(300), "zone of 300 W at 100 %%")
	model.set_intensity(0.8)
	assert_eq(int(_repeat_row(model)["start_watts"]), 240, "target of the work step × 0.8")
	assert_eq(int(_repeat_row(model)["zone"]), coggan.zone_of(240), "zone of 240 W after intensity 80 %%")
	model.set_intensity(1.0)
	model.set_ftp(300)
	assert_eq(int(_repeat_row(model)["zone"]), PowerZones.coggan(300).zone_of(300), "zone of 300 W at FTP 300")
	var custom := PowerZones.custom(300, [0.5, 0.6, 0.7, 0.8, 0.9, 1.05] as Array[float])
	assert_not_null(custom, "precondition: custom zones")
	assert_eq(custom.validate(), [] as Array[String], "precondition: custom zones valid")
	assert_ne(custom.zone_of(300), PowerZones.coggan(300).zone_of(300), "precondition: custom zones differ at 300 W")
	model.set_zones(custom)
	assert_eq(int(_repeat_row(model)["zone"]), custom.zone_of(300), "profile zones apply to the collapsed row")
	assert_eq(str(_repeat_row(model)["zone_token"]), ZonePalette.power_token(custom.zone_of(300)))


## NFR-09 p.3 / IMP-01: invalid IntervalsT is an error, adds no block; a valid IntervalsT after
## it gets a block that points at its own steps; every stored block is consistent with steps.
func test_invalid_intervals_t_leave_no_broken_block() -> void:
	var bad := {
		"repeat 0": '<IntervalsT Repeat="0" OnDuration="30" OnPower="1.1" OffDuration="30" OffPower="0.5"/>',
		"repeat negative": '<IntervalsT Repeat="-2" OnDuration="30" OnPower="1.1" OffDuration="30" OffPower="0.5"/>',
		"repeat text": '<IntervalsT Repeat="many" OnDuration="30" OnPower="1.1" OffDuration="30" OffPower="0.5"/>',
		"no OnPower": '<IntervalsT Repeat="3" OnDuration="30" OffDuration="30" OffPower="0.5"/>',
		"zero duration": '<IntervalsT Repeat="3" OnDuration="0" OnPower="1.1" OffDuration="30" OffPower="0.5"/>',
		"huge repeat": '<IntervalsT Repeat="1000000000" OnDuration="30" OnPower="1.1" OffDuration="30" OffPower="0.5"/>',
	}
	var good := '<IntervalsT Repeat="2" OnDuration="40" OnPower="1.0" OffDuration="20" OffPower="0.5"/>'
	for name in bad:
		var res := _zwo('<SteadyState Duration="60" Power="0.6"/>' + str(bad[name]) + good)
		assert_false(res.ok() and res.errors.is_empty(), "%s: reported as an error" % name)
		if res.workout == null:
			continue
		var steps := res.workout.steps
		for b in res.workout.repeat_blocks:
			assert_true(int(b["first"]) >= 0 and int(b["last"]) < steps.size(), "%s: block %s inside the plan" % [name, str(b)])
			assert_eq(int(b["last"]), int(b["first"]) + int(b["period"]) * int(b["count"]) - 1, "%s: block shape" % name)
			for k in range(int(b["first"]), int(b["last"]) + 1):
				var s: WorkoutStep = steps[k]
				assert_true(s.kind in [WorkoutStep.StepKind.INTERVAL_ON, WorkoutStep.StepKind.INTERVAL_OFF],
					"%s: block %s covers only interval steps" % [name, str(b)])
		var restored := Workout.from_dict(res.workout.to_dict())
		assert_eq(restored.repeat_blocks, res.workout.repeat_blocks, "%s: blocks survive to_dict/from_dict" % name)
		var model := IntervalListModel.new(res.workout, FTP)
		assert_gt(model.row_count(), 0, "%s: list model builds" % name)
