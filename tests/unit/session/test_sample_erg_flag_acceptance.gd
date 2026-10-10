extends GutTest
## Acceptance of T-176 (tester): the sample ERG flag is "ERG acts on the trainer in this second"
## (REQ-WRK-08 p.7, p.2), the saved ride's ERG mark and events (REQ-LOC-01 p.4).
## Plan of the criterion: "60 s 150 W, 60 s FreeRide, 60 s 200 W". Sample index = session second
## (index i covers second i+1 of the criterion, "1–60" = indices 0..59).

const DEV: String = "ftms-176-acc"
const FEC1: String = "6E40FEC1-B5A3-F393-E0A9-E50E24DCCA9E"
const FEC2: String = "6E40FEC2-B5A3-F393-E0A9-E50E24DCCA9E"
const FEC3: String = "6E40FEC3-B5A3-F393-E0A9-E50E24DCCA9E"
const FEATURES_NO_ERG: String = "00 00 00 00 04 20 00 00"
const FEATURES_ERG: String = "00 00 00 00 0C 20 00 00"

var _bridge: StubBleBridge
var _disposables: Array = []
var _dir: String


func before_each() -> void:
	_bridge = StubBleBridge.new()
	_disposables = []
	_dir = "user://acc_t176_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]


func after_each() -> void:
	for d: Variant in _disposables:
		if d != null and (d as Object).has_method("dispose"):
			(d as Object).call("dispose")
	_disposables = []
	_bridge.dispose()


static func _hex(s: String) -> PackedByteArray:
	var out := PackedByteArray()
	for part in s.split(" ", false):
		out.append(part.hex_to_int())
	return out


static func _msg(page: Array) -> PackedByteArray:
	var out := PackedByteArray([0xA4, 0x09, 0x4E, 0x05])
	for x in page:
		out.append(int(x))
	var cs := 0
	for x in out:
		cs ^= x
	out.append(cs)
	return out


static func _plan() -> Workout:
	return Workout.make("flag", [WorkoutStep.watts(60, 150.0), WorkoutStep.free_ride(60),
		WorkoutStep.watts(60, 200.0)] as Array[WorkoutStep])


func _ftms(features: String = "") -> BleTrainer:
	var chars := PackedStringArray(["2AD2", "2AD9", "2ADA", "2AD6"])
	if not features.is_empty():
		chars.append("2ACC")
		_bridge.set_read_value("2ACC", _hex(features))
	_bridge.set_device_services(DEV, {"1826": chars})
	var t := BleTrainer.new(_bridge)
	_disposables.append(t)
	t.connect_device(DEV)
	for i in 6:
		_bridge.pump()
	assert_eq(t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "precondition: connected")
	return t


func _fec(caps: int) -> BleTrainer:
	_bridge.set_device_services(DEV, {FEC1: PackedStringArray([FEC2, FEC3])})
	var t := BleTrainer.new(_bridge)
	_disposables.append(t)
	t.connect_device(DEV)
	_bridge.pump()
	_bridge.emit_notification(DEV, FEC2, _msg([0x36, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, caps]))
	_bridge.pump()
	assert_eq(t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "precondition: FE-C connected")
	return t


## Seconds 1..`seconds`; `at[sec]` runs after that second.
func _ride(s: WorkoutSession, seconds: int, at: Dictionary = {}) -> void:
	if s.get_state() == WorkoutSession.State.IDLE:
		s.start()
		_bridge.pump()
	for sec in range(1, seconds + 1):
		_bridge.emit_notification(DEV, "2AD2", FtmsCodec.encode_indoor_bike_data(30.0, 88.0, 150))
		s.tick(1.0)
		_bridge.pump()
		if at.has(sec):
			(at[sec] as Callable).call()


## 1-based seconds whose sample flag is on.
static func _on(s: WorkoutSession) -> Array[int]:
	var out: Array[int] = []
	for i in s.samples.size():
		if s.samples.erg_enabled[i]:
			out.append(i + 1)
	return out


static func _span(a: int, b: int) -> Array[int]:
	var out: Array[int] = []
	for i in range(a, b + 1):
		out.append(i)
	return out


## Every second of [a; b] is on (`want`) or off.
func _assert_span(s: WorkoutSession, a: int, b: int, want: bool, msg: String) -> void:
	var bad: Array[int] = []
	for sec in range(a, b + 1):
		if s.samples.erg_enabled[sec - 1] != want:
			bad.append(sec)
	assert_eq(bad, [] as Array[int], "%s: seconds %d–%d must be %s" % [msg, a, b, "on" if want else "off"])


static func _events(s: WorkoutSession, type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in s.events:
		if str(e["type"]) == type:
			out.append(e)
	return out


# ===========================================================================
# REQ-WRK-08 p.7
# ===========================================================================

func test_req_wrk_08_c7_ftms_erg_available_toggle_untouched_freeride_off() -> void:
	var s := WorkoutSession.new(_plan(), _ftms(FEATURES_ERG), 200)
	_ride(s, 180)
	assert_eq(s.samples.size(), 180)
	_assert_span(s, 1, 60, true, "step 150 W")
	_assert_span(s, 61, 120, false, "FreeRide")
	_assert_span(s, 121, 180, true, "step 200 W")
	assert_true(s.erg_enabled, "the toggle itself stayed on")


func test_req_wrk_08_c7_player_off_at_30_on_at_150() -> void:
	var s := WorkoutSession.new(_plan(), _ftms(FEATURES_ERG), 200)
	_ride(s, 180, {30: func() -> void: s.set_erg_enabled(false), 150: func() -> void: s.set_erg_enabled(true)})
	_assert_span(s, 1, 30, true, "before the player's off")
	_assert_span(s, 32, 149, false, "player's off (±1 s at 31)")
	_assert_span(s, 151, 180, true, "after the player's on (±1 s at 150)")


func test_req_wrk_08_c7_ftms_bit3_zero_all_off_with_default_toggle() -> void:
	var s := WorkoutSession.new(_plan(), _ftms(FEATURES_NO_ERG), 200)
	assert_true(s.erg_enabled, "WRK-03 p.5: toggle on by default")
	_ride(s, 180)
	assert_eq(_on(s), [] as Array[int], "off in all 180 samples")


func test_req_wrk_08_c7_fec_without_bit1_all_off() -> void:
	var s := WorkoutSession.new(_plan(), _fec(0x05), 200)
	_ride(s, 180)
	assert_eq(s.samples.size(), 180)
	assert_eq(_on(s), [] as Array[int], "FE-C 36 … 05: off in all 180 samples")


func test_req_wrk_08_c7_dev_10_c5_d_refusal_on_61st_second() -> void:
	var plan := Workout.make("r", [WorkoutStep.watts(60, 150.0), WorkoutStep.watts(60, 250.0)] as Array[WorkoutStep])
	var s := WorkoutSession.new(plan, _ftms(FEATURES_ERG), 200)
	_ride(s, 120, {59: func() -> void: _bridge.fail_next_control_point(FtmsCodec.RESULT_NOT_SUPPORTED)})
	_assert_span(s, 1, 60, true, "t ≤ 60")
	_assert_span(s, 62, 120, false, "t ≥ 62")
	for i in range(62, 120):
		assert_eq(s.samples.target_w[i], 250, "plan target 250 at %d" % i)


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
	assert_eq(s.trainer_mode, TrainerDevice.MODE_POWER_METER)
	_ride(s, 180)
	assert_eq(s.samples.size(), 180)
	assert_eq(_on(s), [] as Array[int], "power_meter: off in all samples")


func test_req_wrk_08_c7_ble_dropout_30s_in_target_step_flag_unchanged_event_logged() -> void:
	var s := WorkoutSession.new(Workout.make("d", [WorkoutStep.watts(120, 150.0)] as Array[WorkoutStep]),
		_ftms(FEATURES_ERG), 200)
	_ride(s, 40)
	_bridge.auto_connect = false
	_bridge.emit_disconnected(DEV)
	_bridge.pump()
	for sec in 30:
		s.tick(1.0)
		_bridge.pump()
	_bridge.auto_connect = true
	_ride(s, 50)
	assert_eq(s.get_state(), WorkoutSession.State.FINISHED)
	assert_eq(_on(s), _span(1, 120), "flag on in all 120 samples — the dropout does not change it")
	assert_gt(_events(s, WorkoutSession.EVENT_DISCONNECT).size(), 0, "dropout logged as an event")


func test_req_wrk_08_c2_sample_fields_unchanged_flag_by_c7() -> void:
	var s := WorkoutSession.new(_plan(), _ftms(FEATURES_NO_ERG), 200)
	_ride(s, 3)
	var row := s.samples.row(1)
	var keys := row.keys()
	keys.sort()
	gut.p("sample keys: %s" % str(keys))
	for key in ["time_sec", "power_w", "heart_rate_bpm", "cadence_rpm", "speed_kmh", "target_w", "step_index", "erg_enabled"]:
		assert_true(row.has(key), "field %s" % key)
	assert_false(bool(row["erg_enabled"]))


# ===========================================================================
# REQ-LOC-01 p.4 — saved ride
# ===========================================================================

func _save(s: WorkoutSession, seconds: int, at: Dictionary = {}) -> Ride:
	var repo := FileRideRepository.new(_dir + "rides/")
	var rec := RideRecorder.new(repo, Profile.create("R"), s)
	_ride(s, seconds, at)
	if s.get_state() != WorkoutSession.State.FINISHED:
		s.stop()
	var id := rec.ride_id()
	return FileRideRepository.new(_dir + "rides/").get_ride(id)


func test_req_loc_01_c4_no_erg_trainer_toggle_on_ride_has_no_erg_mark_and_event_saved() -> void:
	var s := WorkoutSession.new(_plan(), _ftms(FEATURES_NO_ERG), 200)
	var ride := _save(s, 180)
	assert_not_null(ride, "ride saved")
	if ride == null:
		return
	assert_false(bool(ride.metadata.get("erg_enabled", true)), "no ERG mark in the saved ride")
	assert_false(Array(ride.samples.erg_enabled).has(true), "stored flags all off")
	var unavailable: Array = ride.events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == WorkoutSession.EVENT_ERG_UNAVAILABLE)
	assert_eq(unavailable.size(), 1, "the «ERG unavailable» event is saved")
	if unavailable.size() == 1:
		assert_almost_eq(float(unavailable[0]["at_sec"]), 0.0, 1.0)
	var toggles: Array = ride.events.filter(func(e: Dictionary) -> bool:
		return str(e["type"]) in [WorkoutSession.EVENT_ERG_ON, WorkoutSession.EVENT_ERG_OFF])
	assert_eq(toggles.size(), 0, "no ERG toggle events")


func test_req_loc_01_c4_ride_with_erg_has_mark_and_toggle_events_saved() -> void:
	var s := WorkoutSession.new(_plan(), _ftms(FEATURES_ERG), 200)
	var ride := _save(s, 180, {30: func() -> void: s.set_erg_enabled(false), 150: func() -> void: s.set_erg_enabled(true)})
	assert_not_null(ride)
	if ride == null:
		return
	assert_true(bool(ride.metadata.get("erg_enabled", false)), "ERG acted — mark present")
	var types: Array = ride.events.map(func(e: Dictionary) -> String: return str(e["type"]))
	assert_true(types.has(WorkoutSession.EVENT_ERG_OFF) and types.has(WorkoutSession.EVENT_ERG_ON), "toggle events saved: %s" % str(types))
	assert_false(types.has(WorkoutSession.EVENT_ERG_UNAVAILABLE))


func test_req_loc_01_c4_player_kept_erg_off_whole_ride_no_mark() -> void:
	var s := WorkoutSession.new(_plan(), _ftms(FEATURES_ERG), 200)
	s.set_erg_enabled(false)
	var ride := _save(s, 60)
	assert_not_null(ride)
	if ride == null:
		return
	assert_false(bool(ride.metadata.get("erg_enabled", true)), "the mark comes from the flags, not the toggle")


func test_req_loc_01_c4_refusal_mid_ride_event_at_61() -> void:
	var plan := Workout.make("r", [WorkoutStep.watts(60, 150.0), WorkoutStep.watts(60, 250.0)] as Array[WorkoutStep])
	var s := WorkoutSession.new(plan, _ftms(FEATURES_ERG), 200)
	var ride := _save(s, 120, {59: func() -> void: _bridge.fail_next_control_point(FtmsCodec.RESULT_NOT_SUPPORTED)})
	assert_not_null(ride)
	if ride == null:
		return
	var unavailable: Array = ride.events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == WorkoutSession.EVENT_ERG_UNAVAILABLE)
	assert_eq(unavailable.size(), 1)
	if unavailable.size() == 1:
		assert_almost_eq(float(unavailable[0]["at_sec"]), 61.0, 1.0, "session second of the refusal")
	assert_true(bool(ride.metadata.get("erg_enabled", false)), "ERG acted before the refusal")
