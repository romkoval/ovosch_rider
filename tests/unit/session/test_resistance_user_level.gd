extends GutTest
## T-161 — every resistance command carries the user's level (REQ-WRK-04 p.6, tester observation
## O-1): on every switch to fixed resistance the first FTMS `0x04` / FE-C page 0x30 already holds
## the user level; no command with another value (previous level, 0, default) before it or in the
## same second. `BleTrainer` over `StubBleBridge` with `WorkoutSession` on top; fixture `0x2AD6`
## 0..100.0 step 0.1, profile level 50 % (→ `04 80`, FE-C byte 7 `64`).

const DEV: String = "trainer-wrk04-6"
const FEC1: String = "6E40FEC1-B5A3-F393-E0A9-E50E24DCCA9E"
const FEC2: String = "6E40FEC2-B5A3-F393-E0A9-E50E24DCCA9E"
const FEC3: String = "6E40FEC3-B5A3-F393-E0A9-E50E24DCCA9E"
const FEATURES_NO_ERG: String = "00 00 00 00 04 20 00 00"
const FEATURES_ERG: String = "00 00 00 00 0C 20 00 00"
const RES_RANGE_0_100: String = "00 00 E8 03 01 00"
const PIECE: float = 0.25

var _bridge: StubBleBridge
var _trainer: BleTrainer = null
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
	if _trainer != null:
		_trainer.dispose()
	_bridge.dispose()


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


static func _ant(page: Array) -> PackedByteArray:
	var out := PackedByteArray([0xA4, 0x09, 0x4E, 0x05])
	for x in page:
		out.append(int(x))
	var cs := 0
	for x in out:
		cs ^= x
	out.append(cs)
	return out


func _ftms(features: String) -> void:
	var chars := PackedStringArray(["2AD2", "2AD9", "2ADA", "2AD6", "2ACC"])
	_bridge.set_read_value("2AD6", _hex(RES_RANGE_0_100))
	_bridge.set_read_value("2ACC", _hex(features))
	_bridge.set_device_services(DEV, {"1826": chars})
	_trainer = BleTrainer.new(_bridge)
	_trainer.connect_device(DEV)
	for i in 6:
		_bridge.pump()
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "precondition: FTMS connected")
	_stamp()


## FE-C trainer; `caps` — byte 7 of page 0x36.
func _fec(caps: int) -> void:
	_bridge.set_device_services(DEV, {"180A": PackedStringArray(["2A29"]), FEC1: PackedStringArray([FEC2, FEC3])})
	_trainer = BleTrainer.new(_bridge)
	_trainer.connect_device(DEV)
	_bridge.pump()
	_bridge.emit_notification(DEV, FEC2, _ant([0x36, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, caps]))
	_bridge.pump()
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "precondition: FE-C connected")
	_stamp()


func _stamp() -> void:
	var writes := _bridge.calls_of("write")
	for i in range(_seen_writes, writes.size()):
		var c: Dictionary = writes[i]
		_log.append({"t": _clock, "char": BleUuids.normalize(str(c["char"])), "bytes": c["bytes"]})
	_seen_writes = writes.size()


func _run(s: WorkoutSession, until_sec: float) -> void:
	while _clock < until_sec - 1e-6:
		if is_equal_approx(fmod(_clock, 1.0), 0.0) and _trainer.protocol == BleTrainer.PROTOCOL_FTMS:
			_bridge.emit_notification(DEV, "2AD2", FtmsCodec.encode_indoor_bike_data(30.0, 88.0, 150))
		s.tick(PIECE)
		_clock += PIECE
		_bridge.pump()
		_stamp()


func _start(plan: Workout, level: int = 50) -> WorkoutSession:
	var s := WorkoutSession.new(plan, _trainer, 200)
	s.resistance_level = level
	s.start()
	_bridge.pump()
	_stamp()
	return s


## FTMS `0x04` writes: [{t, hex}].
func _res04() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cp := BleUuids.normalize("2AD9")
	for w in _log:
		var b: PackedByteArray = w["bytes"]
		if w["char"] == cp and b.size() > 0 and b[0] == 0x04:
			out.append({"t": float(w["t"]), "hex": _to_hex(b)})
	return out


## FE-C page 0x30 writes: [{t, b7}].
func _p30() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var fec3 := BleUuids.normalize(FEC3)
	for w in _log:
		var b: PackedByteArray = w["bytes"]
		if w["char"] == fec3 and b.size() == 13 and b[4] == 0x30:
			out.append({"t": float(w["t"]), "b7": int(b[11])})
	return out


static func _in(list: Array[Dictionary], a: float, b: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in list:
		if float(e["t"]) >= a - 1e-6 and float(e["t"]) <= b + 1e-6:
			out.append(e)
	return out


static func _values(list: Array[Dictionary], key: String) -> Array:
	return list.map(func(e: Dictionary) -> Variant: return e[key])


static func _plan_120() -> Workout:
	return Workout.make("p", [WorkoutStep.watts(120, 150.0)] as Array[WorkoutStep])


# ===========================================================================
# REQ-WRK-04 p.6 tests (1)–(4)
# ===========================================================================

## (1) plan "120 s 150 W", ERG on, ERG off at 30 s → in [30; 31] exactly one 0x04 = `04 80`;
## no `04 00` in the whole log.
func test_req_wrk_04_c6_1_ftms_erg_off_at_30s_one_04_80_no_04_00() -> void:
	_ftms(FEATURES_ERG)
	var s := _start(_plan_120())
	_run(s, 30.0)
	s.set_erg_enabled(false)
	_bridge.pump()
	_stamp()
	_run(s, 40.0)
	var all := _res04()
	gut.p("0x04: %s" % str(all))
	assert_eq(_values(_in(all, 30.0, 31.0), "hex"), ["04 80"], "REQ-WRK-04 p.6 (1): exactly one 0x04 in [30; 31] — 04 80")
	assert_false(_values(all, "hex").has("04 00"), "REQ-WRK-04 p.6 (1): no 04 00 in the whole log")
	assert_eq(_values(all, "hex"), ["04 80"], "no other 0x04 at all")


## (2) bit 3 of 0x2ACC = 0, plan "60 s 150 W" → the first 0x04 after start is `04 80`, no other
## 0x04 before it.
func test_req_wrk_04_c6_2_ftms_erg_unavailable_first_04_is_user_level() -> void:
	_ftms(FEATURES_NO_ERG)
	var s := _start(Workout.make("p", [WorkoutStep.watts(60, 150.0)] as Array[WorkoutStep]))
	_run(s, 10.0)
	var all := _res04()
	gut.p("0x04: %s" % str(all))
	assert_false(all.is_empty(), "a resistance command went")
	if not all.is_empty():
		assert_eq(all[0]["hex"], "04 80", "REQ-WRK-04 p.6 (2): the first 0x04 is 04 80")
		assert_lte(float(all[0]["t"]), 1.0, "within 1 s of the start")
	for e in all:
		assert_eq(e["hex"], "04 80", "REQ-WRK-04 p.6 (2): no 0x04 with another level")


## (3) FE-C 0x36 without bit 1 → the first 0x30 has byte 7 `64`, no 0x30 with another byte 7 before it.
func test_req_wrk_04_c6_3_fec_without_bit1_first_30_is_user_level() -> void:
	_fec(0x05)
	var s := _start(Workout.make("p", [WorkoutStep.watts(60, 150.0)] as Array[WorkoutStep]))
	_run(s, 10.0)
	var all := _p30()
	gut.p("0x30 byte 7: %s" % str(_values(all, "b7")))
	assert_false(all.is_empty(), "page 0x30 went")
	if not all.is_empty():
		assert_eq(all[0]["b7"], 0x64, "REQ-WRK-04 p.6 (3): the first 0x30 has byte 7 64")
	for e in all:
		assert_eq(e["b7"], 0x64, "REQ-WRK-04 p.6 (3): no 0x30 with another level")


## (4) as (1) on FE-C → exactly one 0x30 in [30; 31], byte 7 `64`.
func test_req_wrk_04_c6_4_fec_erg_off_at_30s_one_30_with_64() -> void:
	_fec(0x07)
	var s := _start(_plan_120())
	_run(s, 30.0)
	s.set_erg_enabled(false)
	_bridge.pump()
	_stamp()
	_run(s, 40.0)
	var all := _p30()
	gut.p("0x30: %s" % str(all))
	assert_eq(_values(_in(all, 30.0, 31.0), "b7"), [0x64], "REQ-WRK-04 p.6 (4): exactly one 0x30 in [30; 31], byte 7 64")
	for e in all:
		assert_eq(e["b7"], 0x64, "no 0x30 with another level")


# ===========================================================================
# Other switches of p.6: FreeRide step, resume, reconnect; level 0 is legitimate
# ===========================================================================

func test_req_wrk_04_c6_freeride_step_and_resume_carry_user_level() -> void:
	_ftms(FEATURES_ERG)
	var s := _start(Workout.make("p", [WorkoutStep.watts(10, 150.0), WorkoutStep.free_ride(20),
		WorkoutStep.watts(30, 200.0)] as Array[WorkoutStep]))
	_run(s, 15.0)
	s.set_erg_enabled(false)
	_run(s, 16.0)
	s.pause()
	_run(s, 20.0)
	s.resume()
	_bridge.pump()
	_stamp()
	_run(s, 25.0)
	var all := _res04()
	gut.p("0x04: %s" % str(all))
	assert_false(_in(all, 10.0, 11.0).is_empty(), "FreeRide step at 10 s: resistance command")
	for e in all:
		assert_eq(e["hex"], "04 80", "every 0x04 carries the user level (t = %.2f)" % float(e["t"]))


func test_req_wrk_04_c6_reconnect_carries_user_level() -> void:
	_ftms(FEATURES_NO_ERG)
	var s := _start(Workout.make("p", [WorkoutStep.watts(300, 150.0)] as Array[WorkoutStep]))
	_run(s, 5.0)
	_bridge.emit_disconnected(DEV)
	_bridge.pump()
	_stamp()
	_run(s, 30.0)
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "precondition: reconnected")
	var all := _res04()
	gut.p("0x04: %s" % str(all))
	assert_gt(_in(all, 5.0, 30.0).size(), 0, "level re-sent after the reconnect")
	for e in all:
		assert_eq(e["hex"], "04 80", "every 0x04 carries the user level (t = %.2f)" % float(e["t"]))


func test_req_wrk_04_c6_user_level_0_legitimately_04_00() -> void:
	_ftms(FEATURES_NO_ERG)
	var s := _start(Workout.make("p", [WorkoutStep.watts(60, 150.0)] as Array[WorkoutStep]), 0)
	_run(s, 5.0)
	var all := _res04()
	assert_false(all.is_empty())
	for e in all:
		assert_eq(e["hex"], "04 00", "user level 0 % → 04 00")
