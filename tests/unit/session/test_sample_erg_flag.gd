extends GutTest
## T-176: the sample ERG flag is "ERG acts on the trainer in this second", not the player's toggle
## (REQ-WRK-08 p.2, p.7); the saved ride's ERG mark comes from the sample flags (LOC-01 p.4).
## Plan "60 s 150 W, 60 s FreeRide, 60 s 200 W".

const DEV: String = "ftms-176"
## Target Setting Features without bit 3 (resistance only).
const FEATURES_NO_ERG: String = "0000000004200000"

var _bridge: StubBleBridge = null
var _ble: BleTrainer = null
var _disposables: Array = []


func before_each() -> void:
	_bridge = StubBleBridge.new()
	_ble = null
	_disposables = []


func after_each() -> void:
	for d: Variant in _disposables:
		if d != null and (d as Object).has_method("dispose"):
			(d as Object).call("dispose")
	_disposables = []
	if _ble != null:
		_ble.dispose()
	_bridge.dispose()


static func _plan() -> Workout:
	return Workout.make("f", [WorkoutStep.watts(60, 150.0), WorkoutStep.free_ride(60),
		WorkoutStep.watts(60, 200.0)] as Array[WorkoutStep])


func _ftms(features_hex: String = "") -> BleTrainer:
	var chars := PackedStringArray(["2AD2", "2AD9", "2ADA", "2AD6"])
	if not features_hex.is_empty():
		chars.append("2ACC")
		_bridge.set_read_value("2ACC", BleBytes.from_hex(features_hex))
	_bridge.set_device_services(DEV, {"1826": chars})
	_ble = BleTrainer.new(_bridge)
	_ble.connect_device(DEV)
	for i in 4:
		_bridge.pump()
	assert_eq(_ble.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "precondition: connected")
	return _ble


func _fake() -> FakeTrainer:
	var f := FakeTrainer.new(7)
	f.connect_delay_sec = 0.0
	f.connect_device("fake")
	return f


## Run `seconds` seconds; `at` — {second: Callable} actions after that second.
func _ride(s: WorkoutSession, seconds: int, at: Dictionary = {}) -> void:
	s.start()
	for sec in range(1, seconds + 1):
		s.tick(1.0)
		_bridge.pump()
		if at.has(sec):
			(at[sec] as Callable).call()


## Sample flags as 1-based seconds that were "on".
static func _on_seconds(s: WorkoutSession) -> Array[int]:
	var out: Array[int] = []
	for i in s.samples.size():
		if s.samples.erg_enabled[i]:
			out.append(i + 1)
	return out


static func _range(a: int, b: int) -> Array[int]:
	var out: Array[int] = []
	for i in range(a, b + 1):
		out.append(i)
	return out


func _events(s: WorkoutSession, type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in s.events:
		if str(e["type"]) == type:
			out.append(e)
	return out


func test_req_wrk_08_c7_ftms_toggle_untouched_free_ride_is_off() -> void:
	var s := WorkoutSession.new(_plan(), _ftms(), 200)
	_ride(s, 180)
	assert_eq(s.samples.size(), 180)
	assert_eq(_on_seconds(s), _range(1, 60) + _range(121, 180), "on in 1-60 and 121-180, off in 61-120")
	assert_true(s.erg_enabled, "the toggle itself stays on")


func test_req_wrk_08_c7_player_toggles_off_at_30_on_at_150() -> void:
	var s := WorkoutSession.new(_plan(), _ftms(), 200)
	_ride(s, 180, {30: s.toggle_erg, 149: s.toggle_erg})
	var on := _on_seconds(s)
	assert_eq(on, _range(1, 30) + _range(150, 180), "off in 31-149: %s" % str(on))


func test_req_wrk_08_c7_ftms_bit3_zero_all_off() -> void:
	var s := WorkoutSession.new(_plan(), _ftms(FEATURES_NO_ERG), 200)
	_ride(s, 180)
	assert_eq(_on_seconds(s), [] as Array[int], "off in all 180 with the toggle on")
	assert_true(s.erg_enabled)
	assert_false(s.metadata()["erg_enabled"], "LOC-01 p.4: no ERG mark on the ride")
	assert_eq(_events(s, WorkoutSession.EVENT_ERG_UNAVAILABLE).size(), 1, "the event is kept")


func test_req_wrk_08_c7_emulator_without_erg_all_off() -> void:
	var f := _fake()
	f.erg_supported = false
	var s := WorkoutSession.new(_plan(), f, 200)
	_ride(s, 180)
	assert_eq(_on_seconds(s), [] as Array[int])


func test_req_wrk_08_c7_80_05_02_mid_ride() -> void:
	var t := _ftms()
	var s := WorkoutSession.new(Workout.make("r", [WorkoutStep.watts(61, 150.0), WorkoutStep.watts(60, 200.0)] as Array[WorkoutStep]), t, 200)
	_ride(s, 120, {60: _bridge.fail_next_control_point.bind(FtmsCodec.RESULT_NOT_SUPPORTED)})
	assert_false(s.erg_available(), "refused at the step boundary")
	var on := _on_seconds(s)
	assert_true(on.has(60) and on.slice(0, 60) == _range(1, 60), "on up to 60: %s" % str(on))
	for sec in range(62, 121):
		assert_false(on.has(sec), "off at %d" % sec)


func test_req_wrk_08_c7_power_meter_all_off() -> void:
	var pm := FakePowerMeter.new(_bridge)
	pm.set_power(180)
	pm.set_cadence(90)
	var hub := SensorHub.new(null)
	hub.set_power_meter(pm)
	pm.connect_device("cps")
	var dev := UncontrolledTrainer.new(hub, SensorHub.SOURCE_POWER_METER)
	_disposables.push_front(dev)
	_disposables.append(pm)
	var s := WorkoutSession.new(_plan(), dev, 200)
	_ride(s, 180)
	assert_eq(s.samples.size(), 180)
	assert_eq(_on_seconds(s), [] as Array[int])
	assert_false(s.metadata()["erg_enabled"])


func test_req_wrk_08_c7_dropout_does_not_change_flag() -> void:
	var f := _fake()
	var s := WorkoutSession.new(Workout.make("d", [WorkoutStep.watts(120, 150.0)] as Array[WorkoutStep]), f, 200)
	s.start()
	for sec in range(1, 121):
		f.tick(1.0)
		s.tick(1.0)
		if sec == 40:
			f.inject_dropout(30.0)
	assert_eq(_on_seconds(s), _range(1, 120), "flag unchanged by the dropout")
	assert_gt(_events(s, WorkoutSession.EVENT_DISCONNECT).size(), 0, "the dropout is a separate event")


func test_req_loc_01_c4_ride_with_erg_has_mark() -> void:
	var s := WorkoutSession.new(_plan(), _ftms(), 200)
	_ride(s, 180)
	assert_true(s.metadata()["erg_enabled"])
	var restored := SampleStream.from_dict(s.samples.to_dict())
	assert_eq(Array(restored.erg_enabled), Array(s.samples.erg_enabled), "flags survive storage")


func test_wrk_08_c2_sample_row_keeps_fields() -> void:
	var s := WorkoutSession.new(_plan(), _ftms(FEATURES_NO_ERG), 200)
	_ride(s, 3)
	var row := s.samples.row(0)
	for key in ["time_sec", "power_w", "heart_rate_bpm", "cadence_rpm", "speed_kmh", "target_w", "step_index", "erg_enabled"]:
		assert_true(row.has(key), key)
	assert_false(bool(row["erg_enabled"]))
	assert_eq(int(row["target_w"]), 150, "plan target while ERG does not act")
