extends GutTest
## T-175: tolerance scale and hysteresis — the numbers of REQ-WRK-09 p.5 (б), (в) (`hud.md` p. 16.2–16.3).

const ON := HudModel.DEVIATION_ON
const ABOVE := HudModel.DEVIATION_ABOVE
const BELOW := HudModel.DEVIATION_BELOW
const FIRST := HudModel.DEVIATION_HIDDEN


func test_req_wrk_09_c5_b_hysteresis_target_200() -> void:
	assert_eq(ToleranceScale.next_state(ON, 213, 200), ON, "213 stays on")
	assert_eq(ToleranceScale.next_state(ON, 216, 200), ABOVE, "216 above")
	assert_eq(ToleranceScale.next_state(ON, 184, 200), BELOW, "184 below")
	assert_eq(ToleranceScale.next_state(ABOVE, 212, 200), ABOVE, "212 stays above")
	assert_eq(ToleranceScale.next_state(ABOVE, 210, 200), ON, "210 on")
	assert_eq(ToleranceScale.next_state(ABOVE, 180, 200), BELOW, "above → below at once")


func test_req_wrk_09_c5_b_hysteresis_target_300_and_100() -> void:
	assert_eq(ToleranceScale.next_state(ON, 322, 300), ON)
	assert_eq(ToleranceScale.next_state(ON, 323, 300), ABOVE)
	assert_eq(ToleranceScale.next_state(BELOW, 285, 300), ON)
	assert_eq(ToleranceScale.next_state(ON, 115, 100), ON)
	assert_eq(ToleranceScale.next_state(ON, 116, 100), ABOVE)


func test_req_wrk_09_c5_b_first_state_without_hysteresis() -> void:
	assert_eq(ToleranceScale.next_state(FIRST, 213, 200), ABOVE, "first state: plain threshold")
	assert_eq(ToleranceScale.next_state(FIRST, 210, 200), ON)
	var sc := ToleranceScale.new()
	assert_eq(sc.update(205, 200, true, false), ON)
	assert_eq(sc.update(213, 200, true, false), ON, "hysteresis from on")
	assert_eq(sc.update(213, 200, false, false), FIRST, "no data — hidden")
	assert_eq(sc.update(213, 200, true, false), ABOVE, "after no data — no hysteresis")
	assert_eq(sc.update(205, 200, true, true), ToleranceScale.STATE_WINDOW, "window")
	assert_eq(sc.update(213, 200, true, false), ABOVE, "after the window — no hysteresis")


func test_req_wrk_09_c5_c_scale_positions() -> void:
	assert_almost_eq(ToleranceScale.marker_fraction(180, 200), 1.0 / 6.0, 0.01, "180 → 17 %")
	assert_eq(ToleranceScale.edge(180, 200), 0)
	assert_eq(ToleranceScale.next_state(FIRST, 205, 200), ON, "205 on")
	assert_eq(ToleranceScale.edge(160, 200), -1, "160 → ◀")
	assert_almost_eq(ToleranceScale.marker_fraction(330, 300), 5.0 / 6.0, 0.01, "330 → 83 %")
	assert_eq(ToleranceScale.edge(330, 300), 0)
	assert_eq(ToleranceScale.edge(240, 200), 1, "240 → ▶")
	assert_eq(ToleranceScale.band(), Vector2(1.0 / 3.0, 2.0 / 3.0), "band — middle third")
	assert_almost_eq(ToleranceScale.half_range(200), 30.0, 0.001, "200: 170…230")
	assert_almost_eq(ToleranceScale.half_range(300), 45.0, 0.001, "300: 255…345")
