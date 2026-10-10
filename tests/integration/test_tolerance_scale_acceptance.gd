extends GutTest
## Acceptance of T-175 (tester): tolerance scale whenever ERG does not act on a step with a target
## (REQ-HUD-02 p.6, U-38), states with hysteresis and the acclimatisation window by the numbers of
## REQ-WRK-09 p.5 (б)–(г); HUD-02 p.1–5 unchanged while ERG acts.
## Trainer: FTMS on `StubBleBridge` with bit 3 of 0x2ACC = 0 (DEV-10 p.5 (d) fixture — exact power
## from Indoor Bike Data), `FakeTrainer` for the player's ERG switch. Power is held for 4 s at every
## value so that the 3 s smoothing (HUD-09) settles on it; intermediate smoothed values never leave
## the band the criterion is about unless stated.

const SCENE: String = "res://src/ui/workout/workout_screen.tscn"
const DEV: String = "ftms-175-acc"

var _now_usec: int = 0
var _bridge: StubBleBridge = null
var _ble: BleTrainer = null
var _power: int = 200
var _profile: Profile
var _state: AppState
var _locale: String


func before_each() -> void:
	_now_usec = 5_000_000
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_state = AppState.new(ProfileRepository.new("user://acc_t175_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]))
	_profile = Profile.create("Rider")
	_profile.ftp_w = 250
	_bridge = null
	_ble = null
	_power = 200


func after_each() -> void:
	TranslationServer.set_locale(_locale)
	if _ble != null:
		_ble.dispose()
	if _bridge != null:
		_bridge.dispose()


static func _hex(s: String) -> PackedByteArray:
	var out := PackedByteArray()
	for part in s.split(" ", false):
		out.append(part.hex_to_int())
	return out


## FTMS trainer; `no_erg` — 0x2ACC without bit 3.
func _ble_trainer(no_erg: bool) -> BleTrainer:
	_bridge = StubBleBridge.new()
	var chars := PackedStringArray(["2AD2", "2AD9", "2ADA", "2AD6"])
	_bridge.set_read_value("2AD6", _hex("00 00 E8 03 01 00"))
	if no_erg:
		chars.append("2ACC")
		_bridge.set_read_value("2ACC", _hex("00 00 00 00 04 20 00 00"))
	_bridge.set_device_services(DEV, {"1826": chars})
	_ble = BleTrainer.new(_bridge)
	_ble.connect_device(DEV)
	for i in 6:
		_bridge.pump()
	assert_eq(_ble.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "precondition: connected")
	return _ble


func _screen(plan: Workout, trainer: TrainerDevice) -> WorkoutScreen:
	var s: WorkoutScreen = load(SCENE).instantiate()
	s.clock_usec = func() -> int: return _now_usec
	s.keep_awake_setter = func(_on: bool) -> void: pass
	add_child_autofree(s)
	s.setup(plan, _profile, trainer, _state, null)
	assert_true(s.start(), "precondition: started")
	return s


func _second(s: WorkoutScreen) -> void:
	if _bridge != null:
		_bridge.emit_notification(DEV, "2AD2", FtmsCodec.encode_indoor_bike_data(30.0, 88.0, _power))
	_now_usec += 1_000_000
	s.ticker().poll()
	if _bridge != null:
		_bridge.pump()


## Hold `power` for `n` seconds; returns the deviation states seen after each second.
func _hold(s: WorkoutScreen, power: int, n: int = 4) -> Array[String]:
	_power = power
	var seen: Array[String] = []
	for i in n:
		_second(s)
		seen.append(_dev(s))
	return seen


func _dev(s: WorkoutScreen) -> String:
	return str(s.hud().state()["power_deviation"])


func _assert_state(s: WorkoutScreen, want: String, delta: String, msg: String) -> void:
	assert_eq(_dev(s), want, msg)
	if not delta.is_empty():
		assert_eq(s.metric_panel().deviation_delta_text(), delta, "%s: difference %s" % [msg, delta])
	assert_true(s.metric_panel().is_tolerance_scale_shown(), "%s: tolerance scale shown" % msg)


const ON: String = HudModel.DEVIATION_ON
const ABOVE: String = HudModel.DEVIATION_ABOVE
const BELOW: String = HudModel.DEVIATION_BELOW


# ===========================================================================
# REQ-WRK-09 p.5 (б) numbers in `smart` with ERG unavailable
# ===========================================================================

func test_req_wrk_09_c5_b_hysteresis_target_200_erg_unavailable() -> void:
	var s := _screen(Workout.make("h", [WorkoutStep.watts(300, 200.0)] as Array[WorkoutStep]), _ble_trainer(true))
	_hold(s, 200, 7)
	_assert_state(s, ON, "", "200 → on")
	var seen := _hold(s, 213)
	assert_false(seen.has(ABOVE), "from on, 213 → stays on: %s" % str(seen))
	_assert_state(s, ON, "", "213")
	_hold(s, 216)
	_assert_state(s, ABOVE, "+16", "216 → above ▲ +16")
	assert_eq(s.metric_panel().deviation_text(), "▲")
	seen = _hold(s, 212)
	assert_false(seen.has(ON), "from above, 212 → stays above: %s" % str(seen))
	_assert_state(s, ABOVE, "", "212")
	_hold(s, 210)
	_assert_state(s, ON, "", "210 → on")
	_hold(s, 184)
	_assert_state(s, BELOW, "−16", "from on 184 → below ▼ −16")
	assert_eq(s.metric_panel().deviation_text(), "▼")
	_hold(s, 216)
	_hold(s, 180)
	_assert_state(s, BELOW, "−20", "from above 180 → below")


func test_req_wrk_09_c5_b_hysteresis_target_300_and_100() -> void:
	var plan := Workout.make("h", [WorkoutStep.watts(60, 300.0), WorkoutStep.watts(60, 100.0)] as Array[WorkoutStep])
	var s := _screen(plan, _ble_trainer(true))
	_hold(s, 300, 7)
	_assert_state(s, ON, "", "300 → on")
	var seen := _hold(s, 322)
	assert_false(seen.has(ABOVE), "from on 322 → stays on: %s" % str(seen))
	_hold(s, 323)
	_assert_state(s, ABOVE, "+23", "323 → above")
	_hold(s, 270)
	_assert_state(s, BELOW, "−30", "precondition: below")
	_hold(s, 285)
	_assert_state(s, ON, "", "from below 285 → on")
	# Target 100 (tol 10, h 5).
	_power = 100
	while s.session().executor.elapsed_sec() < 70:
		_second(s)
	_assert_state(s, ON, "", "100 → on")
	seen = _hold(s, 115)
	assert_false(seen.has(ABOVE), "from on 115 → stays on: %s" % str(seen))
	_hold(s, 116)
	_assert_state(s, ABOVE, "+16", "116 → above")


# ===========================================================================
# REQ-WRK-09 p.5 (в) scale numbers, (г) window
# ===========================================================================

func test_req_wrk_09_c5_c_scale_marker_numbers() -> void:
	var plan := Workout.make("c", [WorkoutStep.watts(60, 200.0), WorkoutStep.watts(60, 300.0)] as Array[WorkoutStep])
	var s := _screen(plan, _ble_trainer(true))
	_hold(s, 180, 8)
	var p := s.metric_panel()
	assert_almost_eq(p.scale_marker_fraction(), 0.17, 0.01, "200/180 → 17 %")
	assert_eq(p.scale_marker_color(), UiTokens.HUD_DEV_BELOW, "marker colour = glyph «below»")
	_hold(s, 205)
	assert_eq(_dev(s), ON, "205 → on")
	assert_eq(p.scale_marker_color(), UiTokens.HUD_DEV_ON)
	_hold(s, 160)
	assert_eq(p.scale_edge(), -1, "160 → ◀ at the left edge")
	assert_false(p.is_scale_marker_shown(), "triangle instead of the marker")
	_power = 330
	while s.session().executor.elapsed_sec() < 70:
		_second(s)
	assert_almost_eq(p.scale_marker_fraction(), 0.83, 0.01, "300/330 → 83 %")
	assert_eq(_dev(s), ABOVE)
	assert_eq(p.scale_marker_color(), UiTokens.HUD_WARN, "marker colour = glyph «above»")


func test_req_wrk_09_c5_d_window_samples_1_to_5_hidden_6th_shown() -> void:
	var plan := Workout.make("w", [WorkoutStep.watts(10, 200.0), WorkoutStep.ramp_watts(20, 200.0, 260.0)] as Array[WorkoutStep])
	var s := _screen(plan, _ble_trainer(true))
	var seen := _hold(s, 250, 30)
	gut.p("states: %s" % str(seen))
	for i in 5:
		assert_eq(seen[i], HudModel.DEVIATION_HIDDEN, "step 1 sample %d: no glyph" % (i + 1))
	assert_ne(seen[5], HudModel.DEVIATION_HIDDEN, "step 1 sample 6: glyph")
	# seen[i] is the HUD after elapsed second i + 1; elapsed 10 = step 2 at offset 0 (no sample of
	# it yet), elapsed 15 = after its 5th sample, elapsed 16 = after its 6th.
	for i in range(9, 15):
		assert_eq(seen[i], HudModel.DEVIATION_HIDDEN, "ramp, %d samples in: window" % (i - 9))
	for i in range(15, 29):
		assert_ne(seen[i], HudModel.DEVIATION_HIDDEN, "ramp, %d samples in: the ramp itself opens no window" % (i - 9))


# ===========================================================================
# REQ-HUD-02 p.6: switching, first state without hysteresis, regression p.1–5
# ===========================================================================

func test_req_hud_02_c6_switch_first_state_without_hysteresis_both_ways() -> void:
	var s := _screen(Workout.make("sw", [WorkoutStep.watts(300, 200.0)] as Array[WorkoutStep]), _ble_trainer(false))
	_hold(s, 213, 10)
	assert_false(s.metric_panel().is_tolerance_scale_shown(), "ERG acts — zone bar")
	assert_eq(_dev(s), ABOVE, "HUD-02 p.2: 213 → above")
	s.toggle_erg()
	_bridge.pump()
	assert_true(s.metric_panel().is_tolerance_scale_shown(), "ERG off — scale not later than the next sample")
	_second(s)
	assert_true(s.metric_panel().is_tolerance_scale_shown())
	assert_eq(_dev(s), ABOVE, "first state after the switch: no hysteresis, no window (213 > 210 → above)")
	_hold(s, 205)
	assert_eq(_dev(s), ON)
	var seen := _hold(s, 213)
	assert_false(seen.has(ABOVE), "with the scale, from on 213 stays on (hysteresis): %s" % str(seen))
	s.toggle_erg()
	_second(s)
	assert_false(s.metric_panel().is_tolerance_scale_shown(), "ERG on — zone bar by the next sample")
	assert_eq(_dev(s), ABOVE, "HUD-02 p.2 again: 213 → above at once")


func test_req_hud_02_c1_5_regression_erg_acting_213_above_at_once_no_window() -> void:
	var s := _screen(Workout.make("r", [WorkoutStep.watts(60, 200.0)] as Array[WorkoutStep]), _ble_trainer(false))
	_hold(s, 213, 2)
	assert_false(s.metric_panel().is_tolerance_scale_shown(), "ERG acts — no scale")
	_hold(s, 213, 3)
	assert_eq(_dev(s), ABOVE, "213 vs 200 → above at once (HUD-02 p.2, no hysteresis, no window)")


func test_req_hud_02_c6_intensity_moves_target_and_center_next_sample() -> void:
	var s := _screen(Workout.make("i", [WorkoutStep.watts(120, 200.0)] as Array[WorkoutStep]), _ble_trainer(true))
	_hold(s, 220, 8)
	assert_eq(_dev(s), ABOVE, "220 vs 200 → above")
	s.session().set_intensity(1.1)
	_second(s)
	assert_eq(s.target_text(), "220 W", "target 220 by the next sample")
	assert_almost_eq(s.metric_panel().scale_marker_fraction(), 0.5, 0.01, "220 at the centre of the scale")
	assert_eq(_dev(s), ON, "220 vs 220 → on")
