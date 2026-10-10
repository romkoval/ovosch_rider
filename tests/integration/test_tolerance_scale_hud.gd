extends GutTest
## T-175: tolerance scale on the workout HUD whenever ERG does not act on a step with a target —
## ERG off by the player, ERG unavailable (from the connection or after `80 05 02`), `power_meter`;
## zone bar while ERG acts (REQ-HUD-02 p.1–6, REQ-WRK-09 p.5 (б)–(г)).

const SCENE: String = "res://src/ui/workout/workout_screen.tscn"
const DEV: String = "ftms-175"

var _now_usec: int = 0
var _state: AppState
var _profile: Profile
var _locale: String
var _bridge: StubBleBridge = null
var _ble: BleTrainer = null
var _disposables: Array = []
var _ble_power: int = 180


func before_each() -> void:
	_now_usec = 5_000_000
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_state = AppState.new(ProfileRepository.new("user://tol_scale_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]))
	_profile = Profile.create("Rider")
	_profile.ftp_w = 250
	_bridge = null
	_ble = null
	_disposables = []
	_ble_power = 180


func after_each() -> void:
	TranslationServer.set_locale(_locale)
	for d: Variant in _disposables:
		if d != null and (d as Object).has_method("dispose"):
			(d as Object).call("dispose")
	if _ble != null:
		_ble.dispose()
	if _bridge != null:
		_bridge.dispose()


func _clock() -> int:
	return _now_usec


func _keep(_on: bool) -> void:
	pass


func _fake(power: int, erg_supported: bool = true) -> FakeTrainer:
	var f := FakeTrainer.new(13)
	f.connect_delay_sec = 0.0
	f.power_noise_w = 0.0
	f.power_tau_sec = 0.01
	f.cadence_noise_rpm = 0.0
	f.erg_supported = erg_supported
	f.set_rider_power(power)
	f.connect_device("fake")
	return f


func _screen(plan: Workout, trainer: TrainerDevice) -> WorkoutScreen:
	var s: WorkoutScreen = load(SCENE).instantiate()
	s.clock_usec = _clock
	s.keep_awake_setter = _keep
	add_child_autofree(s)
	s.setup(plan, _profile, trainer, _state, null)
	assert_true(s.start(), "precondition: started")
	return s


func _second(s: WorkoutScreen) -> void:
	if _bridge != null and _ble_power >= 0:
		_bridge.emit_notification(DEV, "2AD2", FtmsCodec.encode_indoor_bike_data(30.0, 88.0, _ble_power))
	_now_usec += 1_000_000
	s.ticker().poll()
	if _bridge != null:
		_bridge.pump()


func _seconds(s: WorkoutScreen, n: int) -> void:
	for i in n:
		_second(s)


static func _plan_200() -> Workout:
	return Workout.make("t", [WorkoutStep.watts(120, 200.0), WorkoutStep.free_ride(30), WorkoutStep.watts(60, 200.0)] as Array[WorkoutStep])


func _scale(s: WorkoutScreen) -> Dictionary:
	return s.hud().state()["tolerance_scale"]


func _assert_below_180_scale(s: WorkoutScreen, where: String) -> void:
	var p := s.metric_panel()
	assert_true(p.is_tolerance_scale_shown(), "%s: scale in place of the zone bar" % where)
	assert_almost_eq(p.scale_marker_fraction(), 1.0 / 6.0, 0.01, "%s: 180 of 200 → 17 %%" % where)
	assert_eq(str(s.hud().state()["power_deviation"]), HudModel.DEVIATION_BELOW, "%s: below" % where)
	assert_eq(p.deviation_delta_text(), "−20", "%s: −20" % where)
	assert_eq(p.scale_marker_color(), UiTokens.HUD_DEV_BELOW, "%s: marker colour = glyph colour" % where)


func test_req_hud_02_c6_erg_off_scale_and_back_to_zone_bar() -> void:
	var s := _screen(_plan_200(), _fake(180))
	s.toggle_erg()
	_seconds(s, 10)
	_assert_below_180_scale(s, "ERG off")
	s.toggle_erg()
	assert_false(s.metric_panel().is_tolerance_scale_shown(), "ERG on: zone bar at once")
	assert_eq(str(s.hud().state()["power_deviation"]), HudModel.DEVIATION_BELOW, "HUD-02 p.2: below")
	assert_eq(s.metric_panel().deviation_delta_text(), "−20")
	s.toggle_erg()
	assert_true(s.metric_panel().is_tolerance_scale_shown(), "ERG off again: scale at once")
	assert_eq(str(s.hud().state()["power_deviation"]), HudModel.DEVIATION_BELOW,
		"first state right after the switch, no window opened (step offset > 5)")


func test_req_hud_02_c6_erg_unavailable_from_connection() -> void:
	var s := _screen(_plan_200(), _fake(180, false))
	_seconds(s, 10)
	_assert_below_180_scale(s, "ERG unavailable")


func test_req_hud_02_c6_erg_unavailable_after_80_05_02() -> void:
	_bridge = StubBleBridge.new()
	_bridge.set_device_services(DEV, {"1826": PackedStringArray(["2AD2", "2AD9", "2ADA", "2AD6"])})
	_ble = BleTrainer.new(_bridge)
	_ble.connect_device(DEV)
	for i in 4:
		_bridge.pump()
	_bridge.fail_next_control_point(FtmsCodec.RESULT_NOT_SUPPORTED)
	var s := _screen(_plan_200(), _ble)
	_seconds(s, 10)
	assert_false(s.session().erg_available(), "precondition: refused")
	_assert_below_180_scale(s, "after 80 05 02")


func test_req_hud_02_c6_erg_acting_keeps_zone_bar_without_hysteresis() -> void:
	_bridge = StubBleBridge.new()
	_bridge.set_device_services(DEV, {"1826": PackedStringArray(["2AD2", "2AD9", "2ADA", "2AD6"])})
	_ble = BleTrainer.new(_bridge)
	_ble.connect_device(DEV)
	for i in 4:
		_bridge.pump()
	_ble_power = 200
	var s := _screen(_plan_200(), _ble)
	_seconds(s, 2)
	assert_eq(str(s.hud().state()["power_deviation"]), HudModel.DEVIATION_ON, "no window while ERG acts")
	_ble_power = 213
	_seconds(s, 4)
	assert_false(s.metric_panel().is_tolerance_scale_shown())
	assert_eq(str(s.hud().state()["power_deviation"]), HudModel.DEVIATION_ABOVE, "213 → above at once (HUD-02 p.2)")


func test_req_wrk_09_c5_d_window_first_five_samples_of_each_step() -> void:
	var f := _fake(230)
	var s := _screen(Workout.make("w", [WorkoutStep.watts(20, 200.0), WorkoutStep.watts(20, 200.0)] as Array[WorkoutStep]), f)
	s.toggle_erg()
	var seen: Array[String] = []
	for i in 26:
		_second(s)
		seen.append(str(s.hud().state()["power_deviation"]))
	# samples 1…5 of step 1 hidden; then above; step 2 begins after sample 20.
	for i in 5:
		assert_eq(seen[i], HudModel.DEVIATION_HIDDEN, "sample %d of step 1: no glyph" % (i + 1))
	assert_eq(seen[5], HudModel.DEVIATION_ABOVE, "sample 6: glyph")
	for i in range(20, 25):
		assert_eq(seen[i], HudModel.DEVIATION_HIDDEN, "sample %d of step 2: window" % (i - 19))
	assert_eq(seen[25], HudModel.DEVIATION_ABOVE, "sample 6 of step 2")
	assert_eq(s.metric_panel().scale_marker_color(), UiTokens.HUD_WARN)


func test_req_wrk_09_c5_d_window_after_skip_and_marker_color_text() -> void:
	var s := _screen(Workout.make("k", [WorkoutStep.watts(60, 200.0), WorkoutStep.watts(60, 200.0)] as Array[WorkoutStep]), _fake(230))
	s.toggle_erg()
	_seconds(s, 10)
	s.skip_step()
	_second(s)
	assert_eq(str(s.hud().state()["power_deviation"]), HudModel.DEVIATION_HIDDEN, "skip opens the window")
	assert_eq(s.metric_panel().scale_marker_color(), UiTokens.HUD_TEXT, "marker in hud.text in the window")


func test_req_hud_02_c6_free_ride_step_zone_bar_and_intensity_shifts_center() -> void:
	var s := _screen(_plan_200(), _fake(180))
	s.toggle_erg()
	_seconds(s, 10)
	s.session().set_intensity(1.1)
	_second(s)
	var sc := _scale(s)
	assert_eq(int(sc["edge"]), -1, "220 target, 180 → beyond the left edge (◀)")
	assert_eq(s.metric_panel().scale_edge(), -1)
	s.session().set_intensity(1.0)
	_seconds(s, 115)
	assert_true(s.session().executor.current_step().is_free_ride(), "precondition: FreeRide step")
	assert_false(s.metric_panel().is_tolerance_scale_shown(), "no target — zone bar")


func test_req_wrk_09_c5_c_no_data_track_without_marker() -> void:
	_bridge = StubBleBridge.new()
	_bridge.set_device_services(DEV, {"1826": PackedStringArray(["2AD2", "2AD9", "2ADA", "2AD6"])})
	_ble = BleTrainer.new(_bridge)
	_ble.connect_device(DEV)
	for i in 4:
		_bridge.pump()
	_ble_power = -1
	var s := _screen(_plan_200(), _ble)
	s.toggle_erg()
	_seconds(s, 8)
	assert_true(s.metric_panel().is_tolerance_scale_shown(), "track and band")
	assert_false(s.metric_panel().is_scale_marker_shown(), "no marker")
	assert_eq(str(s.hud().state()["power_deviation"]), HudModel.DEVIATION_HIDDEN, "glyph and difference hidden")


func test_req_wrk_09_c5_power_meter_uses_the_same_scale() -> void:
	var pm_bridge := StubBleBridge.new()
	var pm := FakePowerMeter.new(pm_bridge)
	pm.set_power(180)
	pm.set_cadence(90)
	var hub := SensorHub.new(null)
	hub.set_power_meter(pm)
	pm.connect_device("cps")
	var dev := UncontrolledTrainer.new(hub, SensorHub.SOURCE_POWER_METER)
	_disposables.push_front(dev)
	_disposables.append(pm)
	_disposables.append(pm_bridge)
	var s := _screen(_plan_200(), dev)
	_seconds(s, 10)
	_assert_below_180_scale(s, "power_meter")
