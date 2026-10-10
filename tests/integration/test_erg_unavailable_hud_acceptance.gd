extends GutTest
## Acceptance of the T-162 rework (tester): U-37 — every HUD target follows the trainer while ERG
## acts (REQ-HUD-01 p.7, HUD-10 p.1, HUD-13 p.2, p.9, DEV-10 p.6); U-36 / `hud.md` p. 17 — ERG
## unavailable on the HUD (REQ-WRK-03 p.6 (a)–(c), DEV-10 p.5 (b)). Edge cases beyond the
## developer's `test_erg_unavailable_hud.gd`: the switch of rule on a trainer refusal, intensity ×
## range on every target, the FreeRide step, the phone toolbar on the real screen, a step cue
## that comes during the notice after a mid-ride refusal.

const SCENE: String = "res://src/ui/workout/workout_screen.tscn"
const DEV: String = "ftms-u37-acc"
const LONG_EN: String = "Trainer does not support ERG — fixed resistance, hold the target yourself"
const SHORT_EN: String = "No ERG: hold the target yourself"
const FEATURES_NO_ERG: String = "00 00 00 00 04 20 00 00"

var _now_usec: int = 0
var _bridge: StubBleBridge = null
var _ble: BleTrainer = null
var _profile: Profile
var _state: AppState
var _locale: String
var _runtime: UiScale = null
var _prev_device: UiScale.Device = UiScale.Device.DESKTOP


func before_each() -> void:
	_now_usec = 3_000_000
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	var dir := "user://acc_u37_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_state = AppState.new(ProfileRepository.new(dir + "profiles/"))
	_profile = Profile.create("Rider")
	_profile.ftp_w = 200
	_bridge = null
	_ble = null
	_runtime = TouchTarget.default_runtime()
	if _runtime != null:
		_prev_device = _runtime.device


func after_each() -> void:
	TranslationServer.set_locale(_locale)
	if _runtime != null:
		_runtime.device = _prev_device
	if _ble != null:
		_ble.dispose()
	if _bridge != null:
		_bridge.dispose()


static func _hex(s: String) -> PackedByteArray:
	var out := PackedByteArray()
	for part in s.split(" ", false):
		out.append(part.hex_to_int())
	return out


## FTMS trainer: range 25..1500 W step 5 (`with_range`), 0x2ACC (`features`, "" — not declared).
func _ble_trainer(with_range: bool = true, features: String = "") -> BleTrainer:
	_bridge = StubBleBridge.new()
	var chars := PackedStringArray(["2AD2", "2AD9", "2ADA", "2AD6"])
	_bridge.set_read_value("2AD6", _hex("00 00 E8 03 01 00"))
	if with_range:
		chars.append("2AD8")
		_bridge.set_read_value("2AD8", _hex("19 00 DC 05 05 00"))
	if not features.is_empty():
		chars.append("2ACC")
		_bridge.set_read_value("2ACC", _hex(features))
	_bridge.set_device_services(DEV, {"1826": chars})
	_ble = TrainerFactory.create_ble(_bridge) as BleTrainer
	_ble.connect_device(DEV)
	for i in 6:
		_bridge.pump()
	assert_eq(_ble.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "precondition: connected")
	return _ble


func _fake(erg_supported: bool) -> FakeTrainer:
	var f := FakeTrainer.new(9)
	f.connect_delay_sec = 0.0
	f.power_noise_w = 0.0
	f.power_range = {"min_w": 25, "max_w": 1500, "increment_w": 5}
	f.erg_supported = erg_supported
	f.connect_device("fake")
	return f


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
		_bridge.emit_notification(DEV, "2AD2", FtmsCodec.encode_indoor_bike_data(30.0, 88.0, 150))
	_now_usec += 1_000_000
	s.ticker().poll()
	if _bridge != null:
		_bridge.pump()


func _advance_to(s: WorkoutScreen, sec: int) -> void:
	while s.session().executor.elapsed_sec() < sec and s.session().get_state() == WorkoutSession.State.RUNNING:
		_second(s)


func _rows(s: WorkoutScreen) -> Array[String]:
	var out: Array[String] = []
	for row in s.interval_list().model.rows():
		out.append(IntervalListModel.row_text(row, "W", ""))
	return out


func _bar(s: WorkoutScreen, index: int) -> Array[int]:
	for seg in s.chart().plan_model().segments():
		if int(seg["index"]) == index:
			return [int(seg["start_watts"]), int(seg["end_watts"])] as Array[int]
	return [] as Array[int]


static func _visible_texts(s: WorkoutScreen) -> Array[String]:
	var out: Array[String] = []
	for n in s.find_children("*", "Label", true, false):
		var l := n as Label
		if l.is_visible_in_tree() and not l.text.is_empty():
			out.append(l.text)
	return out


static func _names(buttons: Array[Button]) -> Array[String]:
	var out: Array[String] = []
	for b in buttons:
		out.append(str(b.name))
	return out


# ===========================================================================
# U-37: the rule switches on a trainer refusal, on intensity, on a FreeRide step
# ===========================================================================

## HUD-01 p.7: "a refusal of the trainer changes all HUD targets not later than the next sample".
func test_req_hud_01_c7_refusal_switches_all_targets_to_plan_by_next_sample() -> void:
	var t := _ble_trainer()
	var plan := Workout.make("r", [WorkoutStep.watts(30, 132.0), WorkoutStep.watts(30, 1600.0)] as Array[WorkoutStep])
	var s := _screen(plan, t)
	_advance_to(s, 10)
	assert_eq(_rows(s), ["0:30  130 W", "0:30  1500 W"] as Array[String], "by the trainer while ERG acts")
	assert_eq(s.target_text(), "130 W")
	_bridge.fail_next_control_point(FtmsCodec.RESULT_NOT_SUPPORTED)
	s.session().set_intensity(1.05)  # a new 0x05 goes and is refused
	_bridge.pump()
	_second(s)
	assert_false(s.session().erg_available(), "refused")
	assert_eq(s.target_text(), "139 W", "card: plan × 105 % (138.6 → 139), not clamped")
	assert_eq(_rows(s), ["0:30  139 W", "0:30  1680 W"] as Array[String], "list: plan targets with the multiplier")
	assert_eq(_bar(s, 1), [1680, 1680] as Array[int], "bar of the 1600 W step: 1680")
	assert_eq(s.chart().plan_model().max_target_w(), 1680, "y_max by plan targets")
	var last := s.session().samples.size() - 1
	assert_eq(s.session().samples.target_w[last], 139, "sample: plan target")


## DEV-10 p.6 / HUD-01 p.7 with WRK-07: 110 % of 1400 = 1540 → 1500 on every target.
func test_req_hud_01_c7_intensity_110_of_1400_clamped_on_list_bars_next() -> void:
	var s := _screen(Workout.make("i", [WorkoutStep.watts(20, 200.0), WorkoutStep.watts(20, 1400.0)] as Array[WorkoutStep]), _fake(true))
	_second(s)
	s.session().set_intensity(1.1)
	_second(s)
	assert_eq(_rows(s), ["0:20  220 W", "0:20  1500 W"] as Array[String], "list: 1540 → 1500")
	assert_eq(_bar(s, 1), [1500, 1500] as Array[int], "bar: 1500")
	assert_eq(s.chart().plan_model().max_target_w(), 1500, "y_max: 1500")
	_advance_to(s, 16)
	assert_true(s.next_chip().is_shown(), "NEXT shown")
	assert_string_contains(s.next_chip().line_text(), "1500")
	assert_false(s.next_chip().line_text().contains("1540"), "NEXT: no unclamped target")


## HUD-01 p.7 (rev. 61d807f, hud.md 17.3): the display rule follows the ERG mode, not the step — a
## FreeRide step keeps trainer-limited targets on rows, bars and y_max; the sample flag is off.
func test_req_hud_01_c7_freeride_step_keeps_trainer_limited_targets() -> void:
	var plan := Workout.make("fr", [WorkoutStep.watts(300, 132.0), WorkoutStep.free_ride(60), WorkoutStep.watts(300, 1600.0)] as Array[WorkoutStep])
	var s := _screen(plan, _fake(true))
	var checks := {}
	for at in [299, 330, 361]:
		_advance_to(s, at)
		checks[at] = {"rows": _rows(s), "bar2": _bar(s, 2), "y_max": s.chart().plan_model().max_target_w(), "card": s.target_text()}
	gut.p("before / during / after FreeRide: %s" % str(checks))
	for at in checks:
		var c: Dictionary = checks[at]
		var rows: Array = c["rows"]
		assert_eq(str(rows[0]), "5:00  130 W", "%d: row of step 1 — 130" % at)
		assert_eq(str(rows[2]), "5:00  1500 W", "%d: row of step 3 — 1500" % at)
		assert_eq(c["bar2"], [1500, 1500] as Array[int], "%d: bar of step 3 — 1500" % at)
		assert_eq(int(c["y_max"]), 1500, "%d: y_max by 1500" % at)
	assert_false(str(checks[330]["card"]).contains("W"), "during FreeRide the card shows no target: %s" % str(checks[330]["card"]))
	var flag_during: bool = s.session().samples.erg_enabled[330]
	assert_false(flag_during, "sample ERG flag during the FreeRide step is off (WRK-08 p.7)")


# ===========================================================================
# WRK-03 p.7 (61d807f): `+` / `−` = resistance whenever ERG does not act
# ===========================================================================

func _fake35() -> FakeTrainer:
	_profile.resistance_level_default = 35
	return _fake(true)


static func _res_cmds(f: FakeTrainer) -> int:
	var n := 0
	for c in f.commands:
		if str(c.get("type", "")) == FakeTrainer.CMD_RESISTANCE:
			n += 1
	return n


func test_req_wrk_03_c7_plus_is_resistance_when_player_turned_erg_off_intensity_when_on() -> void:
	var f := _fake35()
	var s := _screen(Workout.make("k", [WorkoutStep.watts(300, 150.0)] as Array[WorkoutStep]), f)
	_second(s)
	s.toggle_erg()
	_second(s)
	var n := _res_cmds(f)
	s.toolbar().trigger(HudToolbar.ACTION_PLUS)
	_second(s)
	assert_eq(s.session().resistance_level, 40, "ERG off by the player: `+` → resistance 40 %")
	assert_almost_eq(s.session().intensity(), 1.0, 0.001, "intensity stays 100 %")
	assert_gt(_res_cmds(f), n, "Set Target Resistance Level within 1 s")
	s.toggle_erg()
	_second(s)
	s.toolbar().trigger(HudToolbar.ACTION_PLUS)
	_second(s)
	assert_almost_eq(s.session().intensity(), 1.05, 0.001, "ERG on: `+` → intensity 105 %")
	assert_eq(s.session().resistance_level, 40, "resistance stays 40 %")


func test_req_wrk_03_c7_plus_on_freeride_step_with_erg_on_is_intensity() -> void:
	var f := _fake35()
	var s := _screen(Workout.make("k", [WorkoutStep.watts(10, 150.0), WorkoutStep.free_ride(60)] as Array[WorkoutStep]), f)
	_advance_to(s, 20)
	var n := _res_cmds(f)
	s.toolbar().trigger(HudToolbar.ACTION_PLUS)
	_second(s)
	assert_almost_eq(s.session().intensity(), 1.05, 0.001, "FreeRide, ERG on: `+` → intensity 105 %")
	assert_eq(s.session().resistance_level, 35, "resistance unchanged")
	assert_eq(_res_cmds(f), n, "no Set Target Resistance Level from the key")


func test_req_wrk_03_c7_plus_is_resistance_when_erg_unavailable() -> void:
	_profile.resistance_level_default = 35
	var s := _screen(Workout.make("k", [WorkoutStep.watts(300, 150.0)] as Array[WorkoutStep]), _fake(false))
	_second(s)
	s.toolbar().trigger(HudToolbar.ACTION_PLUS)
	_second(s)
	assert_eq(s.session().resistance_level, 40)
	assert_almost_eq(s.session().intensity(), 1.0, 0.001)


# ===========================================================================
# WRK-03 p.6 (c) (61d807f): hint slot priority NEXT > ERG notice > step hint
# ===========================================================================

## Per elapsed second: {next, notice, cue}.
func _slot_trace(s: WorkoutScreen, to_sec: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	while s.session().executor.elapsed_sec() < to_sec and s.session().get_state() == WorkoutSession.State.RUNNING:
		_second(s)
		var texts := _visible_texts(s)
		out.append({"t": s.session().executor.elapsed_sec(), "next": s.next_chip().is_shown(),
			"notice": texts.has(LONG_EN), "cue": s.cue_text() if not texts.has(LONG_EN) else ""})
	return out


static func _secs(trace: Array[Dictionary], key: String) -> Array[int]:
	var out: Array[int] = []
	for e in trace:
		if bool(e[key]):
			out.append(int(e["t"]))
	return out


static func _cue_secs(trace: Array[Dictionary], text: String) -> Array[int]:
	var out: Array[int] = []
	for e in trace:
		if str(e["cue"]) == text:
			out.append(int(e["t"]))
	return out


static func _step(sec: int, watts: float, cue: String) -> WorkoutStep:
	var st := WorkoutStep.watts(sec, watts)
	st.text_cues.append(TextCue.make(0, cue))
	return st


func test_req_wrk_03_c6_c_priority_refusal_then_next_chip_first() -> void:
	var t := _ble_trainer(false)
	var plan := Workout.make("p", [_step(60, 150.0, "S1"), _step(6, 250.0, "S2"), _step(60, 200.0, "S3")] as Array[WorkoutStep])
	var s := _screen(plan, t)
	_advance_to(s, 59)
	_bridge.fail_next_control_point(FtmsCodec.RESULT_NOT_SUPPORTED)
	var trace := _slot_trace(s, 90)
	var next := _secs(trace, "next")
	var notice := _secs(trace, "notice")
	gut.p("NEXT %s; notice %s; S3 cue %s" % [str(next), str(notice), str(_cue_secs(trace, "S3"))])
	assert_false(next.is_empty(), "NEXT chip of step 3 visible 61–66 (it has priority over the notice)")
	for sec in notice:
		assert_false(next.has(sec), "never NEXT and notice at once (second %d)" % sec)
	assert_false(notice.is_empty(), "notice shown")
	if not notice.is_empty():
		assert_between(notice[0], 65, 67, "notice starts when the NEXT chip of step 3 disappears (66 ± 0.5)")
		assert_between(notice.size(), 7, 9, "full 8 s")
	var s3 := _cue_secs(trace, "S3")
	assert_false(s3.is_empty(), "step-3 hint shown")
	if not s3.is_empty() and not notice.is_empty():
		assert_gt(s3[0], notice[notice.size() - 1], "step-3 hint after the notice (from 74)")


func test_req_wrk_03_c6_c_priority_unavailable_from_connection_next_interrupts_and_notice_reshows_full() -> void:
	var plan := Workout.make("p", [_step(6, 150.0, "S1"), _step(60, 250.0, "S2")] as Array[WorkoutStep])
	var s := _screen(plan, _fake(false))
	assert_true(_visible_texts(s).has(LONG_EN), "notice visible at 0")
	var trace := _slot_trace(s, 30)
	var next := _secs(trace, "next")
	var notice := _secs(trace, "notice")
	gut.p("NEXT %s; notice %s; S2 cue %s" % [str(next), str(notice), str(_cue_secs(trace, "S2"))])
	assert_false(next.is_empty(), "NEXT chip of step 2 visible 1–6 (it interrupts the notice)")
	for sec in notice:
		assert_false(next.has(sec), "never NEXT and notice at once (second %d)" % sec)
	var after: Array[int] = []
	for sec in notice:
		if sec >= 6:
			after.append(sec)
	assert_between(after.size(), 7, 9, "re-shown for a full 8 s after the NEXT chip (6–14)")
	if not after.is_empty():
		assert_between(after[0], 6, 7, "re-show starts when the chip disappears")
	var s2 := _cue_secs(trace, "S2")
	assert_false(s2.is_empty(), "step-2 hint shown after the notice")
	if not s2.is_empty() and not after.is_empty():
		assert_gt(s2[0], after[after.size() - 1])


# ===========================================================================
# WRK-03 p.6 (b): phone toolbar on the real screen
# ===========================================================================

func test_req_wrk_03_c6_b_phone_toolbar_on_screen_without_erg() -> void:
	if _runtime == null:
		pending("no UiScale runtime in this run")
		return
	var s := _screen(Workout.make("p", [WorkoutStep.watts(120, 150.0)] as Array[WorkoutStep]), _fake(false))
	_runtime.device = UiScale.Device.PHONE
	s.refresh()
	_second(s)
	var tb := s.toolbar()
	gut.p("phone toolbar: %s rows %d" % [str(_names(tb.visible_buttons())), tb.button_row_count()])
	assert_false(tb.button(&"erg").visible, "no ERG button")
	assert_false(_names(tb.visible_buttons()).has("ErgButton"))
	assert_true(s.is_resistance_row_visible(), "resistance stays")
	assert_eq(s.cue_text(), SHORT_EN, "phone: the short notice")


# ===========================================================================
# WRK-03 p.6 (c): a step cue during the notice after a mid-ride refusal
# ===========================================================================

func test_req_wrk_03_c6_c_mid_ride_refusal_cue_of_new_step_after_notice() -> void:
	var t := _ble_trainer(false)
	var step2 := WorkoutStep.watts(60, 250.0)
	step2.text_cues.append(TextCue.make(2, "Hold it"))
	var plan := Workout.make("c", [WorkoutStep.watts(60, 150.0), step2] as Array[WorkoutStep])
	var s := _screen(plan, t)
	_advance_to(s, 59)
	_bridge.fail_next_control_point(FtmsCodec.RESULT_NOT_SUPPORTED)
	var notice: Array[int] = []
	var cue: Array[int] = []
	while s.session().executor.elapsed_sec() < 85:
		_second(s)
		var now := s.session().executor.elapsed_sec()
		var texts := _visible_texts(s)
		if texts.has(LONG_EN):
			notice.append(now)
		if texts.has("Hold it"):
			cue.append(now)
	gut.p("notice: %s; cue: %s" % [str(notice), str(cue)])
	assert_false(notice.is_empty(), "notice shown")
	if not notice.is_empty():
		assert_between(notice[0], 60, 61, "from the 61–62nd second (elapsed 60–61)")
		assert_between(notice.size(), 7, 9, "8 s (±0.5 s, sampled per second)")
	assert_false(cue.is_empty(), "the step cue is shown")
	if not cue.is_empty() and not notice.is_empty():
		assert_gt(cue[0], notice[notice.size() - 1], "the cue comes after the notice")
	var events: Array = s.session().events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == WorkoutSession.EVENT_ERG_UNAVAILABLE)
	assert_eq(events.size(), 1, "one ride event")
	if events.size() == 1:
		assert_almost_eq(float(events[0]["at_sec"]), 61.0, 1.0)


func test_req_wrk_03_c6_c_from_connection_ble_notice_8s_once_freeride_pause_no_repeat() -> void:
	var t := _ble_trainer(false, FEATURES_NO_ERG)
	var plan := Workout.make("n", [WorkoutStep.watts(20, 150.0), WorkoutStep.free_ride(20), WorkoutStep.watts(20, 200.0)] as Array[WorkoutStep])
	var s := _screen(plan, t)
	assert_true(_visible_texts(s).has(LONG_EN), "shown from the start of the ride")
	assert_eq(s.mode_chip_text(), "RES.")
	var shown: Array[int] = []
	while s.session().executor.elapsed_sec() < 50:
		if s.session().executor.elapsed_sec() == 30:
			s.toggle_pause()
			_second(s)
			s.toggle_pause()
		_second(s)
		if _visible_texts(s).has(LONG_EN):
			shown.append(s.session().executor.elapsed_sec())
	gut.p("shown at: %s" % str(shown))
	assert_eq(shown, [1, 2, 3, 4, 5, 6, 7] as Array[int], "seconds 0..7 — 8 s, never again (FreeRide, pause)")
