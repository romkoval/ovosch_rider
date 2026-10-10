extends GutTest
## Acceptance of the T-161 rework (tester): a controllable trainer without ERG rides on fixed
## resistance at the user's level (U-36), fallback target range 0..2000 W (U-35).
## REQ-DEV-10 p.5 (a), (d), (e), p.7; REQ-DEV-11 p.7 (b), p.8; REQ-WRK-02 p.7; REQ-WRK-04 p.5.
## Trainer — `BleTrainer` over `StubBleBridge` (FTMS and FE-C fixtures), `WorkoutSession` on top;
## WRK-02 p.7 also on `FakeTrainer`. Time runs in 0.25 s pieces, every bridge write is stamped
## with the session clock to check the "within 1 s" deadlines.

const DEV: String = "trainer-u36"
const FEC1: String = "6E40FEC1-B5A3-F393-E0A9-E50E24DCCA9E"
const FEC2: String = "6E40FEC2-B5A3-F393-E0A9-E50E24DCCA9E"
const FEC3: String = "6E40FEC3-B5A3-F393-E0A9-E50E24DCCA9E"
## Fitness Machine Feature: second uint32 (Target Setting Features) = 0x2004 — bits 2, 13, no bit 3.
const FEATURES_NO_ERG: String = "00 00 00 00 04 20 00 00"
## Same with bit 3 (Power Target Setting Supported).
const FEATURES_ERG: String = "00 00 00 00 0C 20 00 00"
## Supported Resistance Level Range 0..100.0, step 0.1.
const RES_RANGE_0_100: String = "00 00 E8 03 01 00"
const PIECE: float = 0.25

var _bridge: StubBleBridge
var _trainer: TrainerDevice = null
var _clock: float = 0.0
## Stamped bridge writes: {t, char, bytes}.
var _log: Array[Dictionary] = []
var _seen_writes: int = 0


func before_each() -> void:
	_bridge = StubBleBridge.new()
	_trainer = null
	_clock = 0.0
	_log = []
	_seen_writes = 0


func after_each() -> void:
	if _trainer != null and _trainer.has_method("dispose"):
		_trainer.call("dispose")
	_bridge.dispose()


# ---------------------------------------------------------------------------
# Bytes and fixtures
# ---------------------------------------------------------------------------

static func _hex(s: String) -> PackedByteArray:
	var out := PackedByteArray()
	for part in s.split(" ", false):
		out.append(part.hex_to_int())
	return out


static func _to_hex(b: PackedByteArray) -> String:
	var parts: Array[String] = []
	for x in b:
		parts.append("%02X" % x)
	return " ".join(parts)


## ANT message by the criterion text: `A4 09 <id> 05 <page> <XOR of 12 bytes>`.
static func _msg(page: Array, msg_id: int = 0x4E) -> PackedByteArray:
	var out := PackedByteArray([0xA4, 0x09, msg_id, 0x05])
	for x in page:
		out.append(int(x))
	var cs := 0
	for x in out:
		cs ^= x
	out.append(cs)
	return out


## FTMS trainer; `features` — 0x2ACC value ("" — not declared); `res_range` — 0x2AD6 ("" — none).
func _ftms(features: String, res_range: String = RES_RANGE_0_100) -> BleTrainer:
	var chars := PackedStringArray(["2AD2", "2AD9", "2ADA"])
	if not features.is_empty():
		chars.append("2ACC")
		_bridge.set_read_value("2ACC", _hex(features))
	if not res_range.is_empty():
		chars.append("2AD6")
		_bridge.set_read_value("2AD6", _hex(res_range))
	_bridge.set_device_services(DEV, {"1826": chars})
	var t := BleTrainer.new(_bridge)
	_trainer = t
	t.connect_device(DEV)
	for i in 6:
		_bridge.pump()
	assert_eq(t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "precondition: FTMS connected")
	_stamp()
	return t


## FE-C trainer; `caps` — byte 7 of page 0x36 (< 0 — no answer, 2 s timeout).
func _fec(caps: int) -> BleTrainer:
	_bridge.set_device_services(DEV, {"180A": PackedStringArray(["2A29"]), FEC1: PackedStringArray([FEC2, FEC3])})
	var t := BleTrainer.new(_bridge)
	_trainer = t
	t.connect_device(DEV)
	_bridge.pump()
	if caps >= 0:
		_bridge.emit_notification(DEV, FEC2, _msg([0x36, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, caps]))
		_bridge.pump()
	else:
		for i in 25:
			t.tick(0.1)
			_bridge.pump()
	assert_eq(t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "precondition: FE-C connected")
	_stamp()
	return t


func _fec_status(status: int) -> void:
	_bridge.emit_notification(DEV, FEC2, _msg([0x47, 0x31, 0xFF, status, 0xFF, 0xFF, 0xFF, 0xFF]))
	_bridge.pump()
	_stamp()


## New bridge writes get the current clock.
func _stamp() -> void:
	var writes := _bridge.calls_of("write")
	for i in range(_seen_writes, writes.size()):
		var c: Dictionary = writes[i]
		_log.append({"t": _clock, "char": BleUuids.normalize(str(c["char"])), "bytes": c["bytes"]})
	_seen_writes = writes.size()


## Run the session until `until_sec` of the clock; `hook(clock)` after every piece.
func _run(s: WorkoutSession, until_sec: float, hook: Callable = Callable()) -> void:
	while _clock < until_sec - 1e-6:
		if is_equal_approx(fmod(_clock, 1.0), 0.0) and _trainer is BleTrainer and (_trainer as BleTrainer).protocol == BleTrainer.PROTOCOL_FTMS:
			_bridge.emit_notification(DEV, "2AD2", FtmsCodec.encode_indoor_bike_data(30.0, 88.0, 150))
		s.tick(PIECE)
		_clock += PIECE
		_bridge.pump()
		_stamp()
		if hook.is_valid():
			hook.call(_clock)


## FTMS Control Point writes with opcode `op`: [{t, hex}].
func _cp(op: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cp := BleUuids.normalize("2AD9")
	for w in _log:
		var b: PackedByteArray = w["bytes"]
		if w["char"] == cp and b.size() > 0 and b[0] == op:
			out.append({"t": float(w["t"]), "hex": _to_hex(b)})
	return out


## FE-C pages written to FEC3 (byte 4), without 0x46 requests: [{t, page, hex, b7}].
func _pages(page: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var fec3 := BleUuids.normalize(FEC3)
	for w in _log:
		var b: PackedByteArray = w["bytes"]
		if w["char"] == fec3 and b.size() == 13 and b[4] == page:
			out.append({"t": float(w["t"]), "hex": _to_hex(b), "b67": "%02X %02X" % [b[10], b[11]], "b7": b[11]})
	return out


static func _first_at_or_after(list: Array[Dictionary], t: float) -> Dictionary:
	for e in list:
		if float(e["t"]) >= t - 1e-6:
			return e
	return {}


## First entry at or after `t` whose `key` equals `value` (the user-level command may be preceded
## by a mode-switch write with the trainer's previous level — observation O-1 of the verdict).
static func _first_value_after(list: Array[Dictionary], t: float, key: String, value: Variant) -> Dictionary:
	for e in list:
		if float(e["t"]) >= t - 1e-6 and e[key] == value:
			return e
	return {}


static func _count_after(list: Array[Dictionary], t: float) -> int:
	var n := 0
	for e in list:
		if float(e["t"]) > t + 1e-6:
			n += 1
	return n


static func _plan_150_fr_250() -> Workout:
	return Workout.make("u36a", [WorkoutStep.watts(60, 150.0), WorkoutStep.free_ride(60),
		WorkoutStep.watts(60, 250.0)] as Array[WorkoutStep])


static func _plan_150_250() -> Workout:
	return Workout.make("u36b", [WorkoutStep.watts(60, 150.0), WorkoutStep.watts(60, 250.0)] as Array[WorkoutStep])


func _session(plan: Workout, level: int = 50) -> WorkoutSession:
	var s := WorkoutSession.new(plan, _trainer, 200)
	s.resistance_level = level
	return s


## Sample targets of seconds [a; b] (sample index = session second).
static func _targets(s: WorkoutSession, a: int, b: int) -> Array[int]:
	var out: Array[int] = []
	for i in range(a, b + 1):
		out.append(s.samples.target_w[i])
	return out


static func _all(n: int, v: int) -> Array[int]:
	var out: Array[int] = []
	for i in n:
		out.append(v)
	return out


# ===========================================================================
# REQ-DEV-10 p.5 (a), (d) — FTMS
# ===========================================================================

func test_req_dev_10_c5_d_ftms_bit3_zero_04_80_within_1s_no_05_targets_150_none_250() -> void:
	_ftms(FEATURES_NO_ERG)
	assert_false(_trainer.is_erg_available(), "bit 3 = 0 — ERG unavailable from the connection")
	var s := _session(_plan_150_fr_250())
	s.start()
	_bridge.pump()
	_stamp()
	_run(s, 182.0)
	var res := _cp(0x04)
	gut.p("0x04: %s" % str(res))
	var lvl := _first_value_after(res, 0.0, "hex", "04 80")
	assert_false(lvl.is_empty(), "Set Target Resistance Level with the user level 50 % → 04 80")
	if not lvl.is_empty():
		assert_lte(float(lvl["t"]), 1.0, "not later than 1 s after the start")
	assert_eq(_cp(0x05), [] as Array[Dictionary], "no 0x05 during the whole ride")
	assert_eq(s.samples.size(), 180)
	assert_eq(_targets(s, 0, 59), _all(60, 150), "step 1 target 150 (plan, not sent to the trainer)")
	for i in range(60, 120):
		assert_lte(s.samples.target_w[i], 0, "FreeRide: target «no data» at %d" % i)
	assert_eq(_targets(s, 120, 179), _all(60, 250), "step 3 target 250")
	assert_eq(s.get_state(), WorkoutSession.State.FINISHED, "timer and plan not interrupted")
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "stays connected (DEV-07)")


func test_req_dev_10_c5_d_ftms_80_05_02_at_61st_second_04_80_within_1s_then_no_05() -> void:
	_ftms(FEATURES_ERG)
	assert_true(_trainer.is_erg_available())
	var s := _session(_plan_150_250())
	var errors: Array[int] = []
	_trainer.error.connect(func(c: int, _m: String) -> void: errors.append(c))
	s.start()
	_bridge.pump()
	_stamp()
	var armed := [false]
	_run(s, 122.0, func(clock: float) -> void:
		if not armed[0] and clock >= 59.5:
			armed[0] = true
			_bridge.fail_next_control_point(FtmsCodec.RESULT_NOT_SUPPORTED))
	var p05 := _cp(0x05)
	gut.p("0x05: %s; 0x04: %s" % [str(p05), str(_cp(0x04))])
	assert_eq(p05.size(), 2, "05 96 00, then 05 FA 00 refused — nothing more")
	if p05.size() >= 2:
		assert_eq(p05[0]["hex"], "05 96 00")
		assert_eq(p05[1]["hex"], "05 FA 00")
		var refused_at: float = float(p05[1]["t"])
		assert_between(refused_at, 60.0, 61.0, "the 250 W target goes on the 61st second")
		var res := _first_value_after(_cp(0x04), refused_at, "hex", "04 80")
		assert_false(res.is_empty(), "Set Target Resistance Level 04 80 after the refusal")
		if not res.is_empty():
			assert_lte(float(res["t"]) - refused_at, 1.0, "not later than 1 s after the answer")
		assert_eq(_count_after(p05, refused_at), 0, "no 0x05 after the refusal")
	assert_false(s.erg_available(), "ERG unavailable until the end of the connection")
	assert_eq(_targets(s, 0, 59), _all(60, 150))
	assert_eq(_targets(s, 62, 119), _all(58, 250), "t ≥ 62: plan target 250")
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "no connection error")


# ===========================================================================
# REQ-DEV-11 p.7 (b), p.8 — FE-C
# ===========================================================================

func test_req_dev_11_c8_fec_caps_without_bit1_page_30_instead_no_31() -> void:
	_fec(0x05)  # 36 FF FF FF FF 00 00 05 — bits 0 and 2
	assert_false(_trainer.is_erg_available())
	var s := _session(_plan_150_fr_250())
	s.start()
	_bridge.pump()
	_stamp()
	_run(s, 182.0)
	var p30 := _pages(0x30)
	gut.p("0x30: %s" % str(p30.map(func(e: Dictionary) -> String: return "%s@%.2f" % [e["hex"], e["t"]])))
	var lvl := _first_value_after(p30, 0.0, "hex", "A4 09 4F 05 30 FF FF FF FF FF FF 64 B3")
	assert_false(lvl.is_empty(), "page 0x30 with 50 % — bytes of DEV-11 p.9 (a)")
	if not lvl.is_empty():
		assert_lte(float(lvl["t"]), 1.0, "not later than 1 s after the start")
	assert_eq(_pages(0x31).size(), 0, "no 0x31 during the ride")
	assert_eq(_targets(s, 0, 59), _all(60, 150))
	assert_eq(_targets(s, 120, 179), _all(60, 250))


func test_req_dev_11_c7_b_fec_status_02_on_31_page_30_within_1s_no_more_31() -> void:
	_fec(0x07)
	var s := _session(_plan_150_250())
	s.start()
	_bridge.pump()
	_stamp()
	var refused := [-1.0]
	_run(s, 122.0, func(clock: float) -> void:
		if refused[0] < 0.0:
			for e in _pages(0x31):
				if e["b67"] == "E8 03":  # 250 W
					refused[0] = clock
					_fec_status(0x02)
					break)
	var p31 := _pages(0x31)
	gut.p("0x31: %s; refused at %.2f" % [str(p31.map(func(e: Dictionary) -> String: return "%s@%.2f" % [e["b67"], e["t"]])), refused[0]])
	assert_gt(refused[0], 0.0, "0x31 with 250 W was written")
	var res := _first_value_after(_pages(0x30), refused[0], "b7", 0x64)
	assert_false(res.is_empty(), "page 0x30 with the user level 50 % after Not supported")
	if not res.is_empty():
		assert_lte(float(res["t"]) - refused[0], 1.0, "not later than 1 s after the 0x47 answer")
	assert_eq(_count_after(p31, refused[0]), 0, "no 0x31 after the refusal")
	assert_false(s.erg_available())
	assert_eq(_targets(s, 0, 59), _all(60, 150))
	assert_eq(_targets(s, 62, 119), _all(58, 250))


func test_req_dev_11_c8_fec_without_36_answer_modes_available_refusal_by_47() -> void:
	_fec(-1)
	assert_true(_trainer.is_erg_available(), "no 0x36 answer — all modes available")
	var s := _session(_plan_150_250())
	s.start()
	_bridge.pump()
	_stamp()
	_run(s, 1.0)
	assert_eq(_pages(0x31).size(), 1, "ERG works: 0x31 with 150 W")
	_fec_status(0x02)
	var t_ref := _clock
	_run(s, 70.0)
	assert_false(_first_at_or_after(_pages(0x30), t_ref).is_empty(), "0x30 after Not supported")
	assert_eq(_count_after(_pages(0x31), t_ref), 0, "no 0x31 after the refusal (step boundary at 60 s included)")


func test_req_dev_11_c8_u35_fec_fallback_range_2400_is_40_1f_and_2000_in_sample() -> void:
	_fec(0x07)
	var s := _session(Workout.make("fb", [WorkoutStep.watts(10, 2400.0)] as Array[WorkoutStep]))
	s.start()
	_bridge.pump()
	_stamp()
	_run(s, 4.0)
	var p31 := _pages(0x31)
	assert_false(p31.is_empty())
	if not p31.is_empty():
		assert_eq(p31[0]["b67"], "40 1F", "2400 W → 2000 W → bytes 6–7 40 1F")
	assert_eq(s.current_target_watts(), 2000, "session (HUD) target 2000")
	assert_eq(s.samples.target_w[s.samples.size() - 1], 2000, "sample target 2000")


func test_req_dev_10_c7_u35_ftms_without_2ad8_fallback_05_d0_07() -> void:
	_ftms("")
	var s := _session(Workout.make("fb", [WorkoutStep.watts(10, 2400.0)] as Array[WorkoutStep]))
	s.start()
	_bridge.pump()
	_stamp()
	_run(s, 3.0)
	var p05 := _cp(0x05)
	assert_eq(p05.size(), 1)
	if p05.size() == 1:
		assert_eq(p05[0]["hex"], "05 D0 07", "2400 → 2000 (fallback 0..2000, step 1)")
	assert_eq(s.samples.target_w[s.samples.size() - 1], 2000)


# ===========================================================================
# REQ-WRK-02 p.7 — no ERG commands at all while ERG is unavailable
# ===========================================================================

func test_req_wrk_02_c7_fake_trainer_ramp_freeride_intensity_pause_no_power_commands() -> void:
	var f := FakeTrainer.new(3)
	f.connect_delay_sec = 0.0
	f.power_noise_w = 0.0
	f.erg_supported = false
	f.connect_device("fake")
	_trainer = f
	var plan := Workout.make("w27", [WorkoutStep.ramp_watts(20, 100.0, 200.0), WorkoutStep.free_ride(10),
		WorkoutStep.watts(20, 180.0), WorkoutStep.watts(20, 220.0)] as Array[WorkoutStep])
	var s := _session(plan, 40)
	s.start()
	for sec in range(1, 71):
		f.tick(1.0)
		s.tick(1.0)
		if sec == 35:
			s.set_intensity(1.1)
		if sec == 45:
			s.pause()
			for k in 5:
				f.tick(1.0)
				s.tick(1.0)
			s.resume()
	var power_cmds: Array = []
	var erg_on_cmds: Array = []
	var res_cmds: Array = []
	for c in f.commands:
		match str(c.get("type", "")):
			FakeTrainer.CMD_TARGET_POWER:
				power_cmds.append(c)
			FakeTrainer.CMD_ERG:
				if bool(c.get("value", false)):
					erg_on_cmds.append(c)
			FakeTrainer.CMD_RESISTANCE:
				res_cmds.append(c)
	gut.p("commands: %s" % str(f.commands))
	assert_eq(power_cmds.size(), 0, "no Set Target Power: ramp, step boundaries, intensity, resume")
	assert_eq(erg_on_cmds.size(), 0, "no set_erg_enabled(true) after the FreeRide step")
	assert_gt(res_cmds.size(), 0, "fixed resistance at the user level")
	for c in res_cmds:
		assert_eq(int(c.get("value", -1)), 40, "user level 40 %")
	# The step target is still counted for HUD and sample (WRK-02 p.1, 3, 4).
	var ramp_targets := _targets(s, 0, 19)
	assert_eq(ramp_targets[0], 100)
	assert_gt(ramp_targets[19], 180, "ramp target recalculated every second")
	assert_eq(s.samples.target_w[s.samples.size() - 1], 242, "220 W × 110 % in the sample")


func test_req_wrk_02_c7_ftms_bit3_zero_resume_resends_level_not_target() -> void:
	_ftms(FEATURES_NO_ERG)
	var s := _session(Workout.make("p", [WorkoutStep.watts(60, 150.0), WorkoutStep.watts(60, 200.0)] as Array[WorkoutStep]))
	s.start()
	_bridge.pump()
	_stamp()
	_run(s, 10.0)
	s.pause()
	var paused_at := _clock
	_run(s, 20.0)
	var during_pause := 0
	for w in _log:
		if float(w["t"]) > paused_at + 1e-6:
			during_pause += 1
	assert_eq(during_pause, 0, "nothing written on pause (WRK-05 p.5)")
	s.resume()
	var resumed_at := _clock
	_bridge.pump()
	_stamp()
	_run(s, 22.0)
	var res := _first_value_after(_cp(0x04), resumed_at, "hex", "04 80")
	assert_false(res.is_empty(), "resume repeats the level 04 80 (WRK-05 p.3)")
	if not res.is_empty():
		assert_lte(float(res["t"]) - resumed_at, 1.0)
	assert_eq(_cp(0x05).size(), 0, "no 0x05 after resume")


# ===========================================================================
# REQ-WRK-04 p.5 — profile level, `+` sent at once and saved in the profile
# ===========================================================================

func test_req_wrk_04_c5_ftms_level_35_is_04_59_plus_40_is_04_66_saved_in_profile() -> void:
	_ftms(FEATURES_NO_ERG)
	var profile := Profile.create("R")
	profile.ftp_w = 200
	profile.resistance_level_default = 35
	var screen: WorkoutScreen = load("res://src/ui/workout/workout_screen.tscn").instantiate()
	var now := [3_000_000]
	screen.clock_usec = func() -> int: return now[0]
	screen.keep_awake_setter = func(_on: bool) -> void: pass
	add_child_autofree(screen)
	var dir := "user://acc_u36_%d/" % Time.get_ticks_usec()
	screen.setup(Workout.make("p", [WorkoutStep.watts(120, 150.0)] as Array[WorkoutStep]), profile, _trainer,
		AppState.new(ProfileRepository.new(dir + "profiles/")), null)
	assert_true(screen.start())
	_bridge.pump()
	_stamp()
	var res := _cp(0x04)
	gut.p("0x04 at the start: %s" % str(res))
	assert_false(_first_value_after(res, 0.0, "hex", "04 59").is_empty(), "35 % × 25.5 = 8.9 → 04 59 right after the start")
	for i in 3:
		now[0] += 1_000_000
		screen.ticker().poll()
		_bridge.pump()
	_stamp()
	var n_before := _cp(0x04).size()
	assert_true(screen.toolbar().trigger(HudToolbar.ACTION_PLUS), "`+` handled")
	_bridge.pump()
	_stamp()
	var after := _cp(0x04).slice(n_before)
	assert_false(after.is_empty(), "`+` sent at once (WRK-04 p.3 does not apply)")
	if not after.is_empty():
		assert_eq(after[after.size() - 1]["hex"], "04 66", "40 % → 10.2 → 04 66")
	assert_eq(profile.resistance_level_default, 40, "40 % saved in the profile")
	assert_eq(_cp(0x05).size(), 0)


func test_req_wrk_04_c5_fec_without_bit1_page_30_byte7_46_then_50() -> void:
	_fec(0x05)
	var s := _session(Workout.make("p", [WorkoutStep.watts(60, 150.0)] as Array[WorkoutStep]), 35)
	s.start()
	_bridge.pump()
	_stamp()
	assert_false(_first_value_after(_pages(0x30), 0.0, "b7", 0x46).is_empty(), "0x30 at the start: 35 % → 46")
	_run(s, 3.0)
	var t_plus := _clock
	s.set_resistance_level(40)
	_bridge.pump()
	_stamp()
	var after := _first_at_or_after(_pages(0x30), t_plus)
	assert_false(after.is_empty(), "40 % sent at once")
	if not after.is_empty():
		assert_eq(int(after["b7"]), 0x50, "40 % → 50")
	assert_eq(_pages(0x31).size(), 0)


# ===========================================================================
# REQ-DEV-10 p.5 (e) — reconnect: capabilities determined again
# ===========================================================================

## Disconnect and run until CONNECTED again; returns the clock of CONNECTED (-1 — not reconnected).
func _reconnect(s: WorkoutSession, features: String) -> float:
	_bridge.set_read_value("2ACC", _hex(features))
	_bridge.emit_disconnected(DEV)
	_bridge.pump()
	_stamp()
	var t_conn := [-1.0]
	var limit := _clock + 30.0
	_run(s, limit, func(clock: float) -> void:
		if t_conn[0] < 0.0 and _trainer.get_connection_state() == TrainerDevice.ConnectionState.CONNECTED:
			t_conn[0] = clock)
	return t_conn[0]


func test_req_dev_10_c5_e_reconnect_with_bit3_one_brings_erg_back_within_1s() -> void:
	_ftms(FEATURES_ERG)
	var s := _session(Workout.make("p", [WorkoutStep.watts(300, 150.0)] as Array[WorkoutStep]))
	s.start()
	_bridge.pump()
	_stamp()
	_run(s, 5.0)
	# The trainer refuses the next power target.
	_bridge.fail_next_control_point(FtmsCodec.RESULT_NOT_SUPPORTED)
	s.set_intensity(1.1)
	_run(s, 8.0)
	assert_false(s.erg_available(), "refused — resistance")
	var t_conn := _reconnect(s, FEATURES_ERG)
	assert_gt(t_conn, 0.0, "reconnected")
	_run(s, t_conn + 3.0)
	assert_true(s.erg_available(), "capabilities re-read: ERG available again")
	var p05 := _first_at_or_after(_cp(0x05), t_conn - 1.0)
	gut.p("connected at %.2f; 0x05 after: %s" % [t_conn, str(p05)])
	assert_false(p05.is_empty(), "Set Target Power of the current step after the reconnect")
	if not p05.is_empty():
		assert_eq(p05["hex"], "05 A5 00", "150 W × 110 % = 165 W")
		assert_lte(float(p05["t"]) - t_conn, 1.0, "not later than 1 s after connected")
	assert_true(s.is_erg_active_on_trainer())


func test_req_dev_10_c5_e_reconnect_with_bit3_zero_no_05_level_sent() -> void:
	_ftms(FEATURES_ERG)
	var s := _session(Workout.make("p", [WorkoutStep.watts(300, 150.0)] as Array[WorkoutStep]))
	s.start()
	_bridge.pump()
	_stamp()
	_run(s, 5.0)
	_bridge.fail_next_control_point(FtmsCodec.RESULT_NOT_SUPPORTED)
	s.set_intensity(1.1)
	_run(s, 8.0)
	var n05 := _cp(0x05).size()
	var t_conn := _reconnect(s, FEATURES_NO_ERG)
	assert_gt(t_conn, 0.0, "reconnected")
	_run(s, t_conn + 5.0)
	assert_false(s.erg_available())
	assert_eq(_cp(0x05).size(), n05, "no 0x05 after the reconnect")
	var res := _first_value_after(_cp(0x04), t_conn - 1.0, "hex", "04 80")
	assert_false(res.is_empty(), "0x04 with the user level after the reconnect")
	if not res.is_empty():
		assert_lte(float(res["t"]) - t_conn, 1.0)


func test_req_dev_10_c5_e_unavailable_from_connection_then_reconnect_with_erg() -> void:
	_ftms(FEATURES_NO_ERG)
	var s := _session(Workout.make("p", [WorkoutStep.watts(300, 150.0)] as Array[WorkoutStep]))
	s.start()
	_bridge.pump()
	_stamp()
	_run(s, 5.0)
	assert_eq(_cp(0x05).size(), 0)
	var t_conn := _reconnect(s, FEATURES_ERG)
	assert_gt(t_conn, 0.0)
	_run(s, t_conn + 3.0)
	var p05 := _first_at_or_after(_cp(0x05), t_conn - 1.0)
	assert_false(p05.is_empty(), "ERG returns: Set Target Power after the reconnect")
	if not p05.is_empty():
		assert_eq(p05["hex"], "05 96 00")
		assert_lte(float(p05["t"]) - t_conn, 1.0)


# ===========================================================================
# Open question (developer): FE-C 0x36 re-requested on a reconnect during pause —
# DEV-10 p.5 (e) "capabilities determined again after `connected`" vs DEV-11 p.9 (c) "no FEC3
# writes on pause". Fact only: no mode page on pause; what else is written is printed for the verdict.
# ===========================================================================

func test_dev_11_c9_c_fact_reconnect_on_pause_fec3_writes() -> void:
	_fec(0x07)
	var s := _session(Workout.make("p", [WorkoutStep.watts(120, 150.0)] as Array[WorkoutStep]))
	s.start()
	_bridge.pump()
	_stamp()
	_run(s, 5.0)
	s.pause()
	var paused_at := _clock
	_bridge.emit_disconnected(DEV)
	_bridge.pump()
	_stamp()
	_run(s, 12.0)
	var on_pause: Array[String] = []
	var fec3 := BleUuids.normalize(FEC3)
	for w in _log:
		if float(w["t"]) >= paused_at and w["char"] == fec3:
			on_pause.append(_to_hex(w["bytes"]))
	gut.p("FEC3 writes on pause after the reconnect: %s" % str(on_pause))
	for h in on_pause:
		var page := h.substr(12, 2)
		assert_false(page in ["30", "31", "32", "33"], "no mode page on pause: %s" % h)
