extends GutTest
## T-162 follow-up (U-37, `hud.md` p. 17): while ERG acts, every HUD target follows the trainer
## (card, interval list, NEXT chip, all chart bars, y_max); ERG unavailable — "RES." chip, no ERG
## button, `+`/`−` change resistance, an 8 s notice once per connection and an "erg_unavailable"
## ride event (REQ-HUD-01 p.7, HUD-10 p.1, HUD-13 p.2, p.9, DEV-10 p.5 (b), p.6, WRK-03 p.6 (a)–(c),
## LOC-01 p.4).

const SCENE: String = "res://src/ui/workout/workout_screen.tscn"
const TOOLBAR_SCENE: String = "res://src/ui/hud/hud_toolbar.tscn"
const DEV: String = "ftms-erg-hud"
## Target Setting Features without bit 3 (resistance only).
const FEATURES_NO_ERG: String = "0000000004200000"
const LONG_EN: String = "Trainer does not support ERG — fixed resistance, hold the target yourself"
const SHORT_EN: String = "No ERG: hold the target yourself"
const LONG_RU: String = "Станок не поддерживает ERG — фиксированное сопротивление, цель держите сами"
const SHORT_RU: String = "Нет ERG: держите цель сами"

var _now_usec: int = 0
var _bridge: StubBleBridge = null
var _ble: BleTrainer = null
var _profile: Profile
var _state: AppState
var _dir: String
var _locale: String
var _runtime: UiScale = null
var _prev_device: UiScale.Device = UiScale.Device.DESKTOP


func before_each() -> void:
	_now_usec = 3_000_000
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_dir = "user://erg_unavailable_hud_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_state = AppState.new(ProfileRepository.new(_dir + "profiles/"))
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


func _clock() -> int:
	return _now_usec


func _keep(_on: bool) -> void:
	pass


func _fake(erg_supported: bool = true, limited: bool = true) -> FakeTrainer:
	var f := FakeTrainer.new(5)
	f.connect_delay_sec = 0.0
	f.power_noise_w = 0.0
	if limited:
		f.power_range = {"min_w": 25, "max_w": 1500, "increment_w": 5}
	f.erg_supported = erg_supported
	f.connect_device("fake")
	return f


## FTMS trainer on the stub bridge; `features_hex` — 0x2ACC value (empty — not declared).
func _ble_trainer(features_hex: String = "") -> BleTrainer:
	_bridge = StubBleBridge.new()
	var chars := PackedStringArray(["2AD2", "2AD9", "2ADA", "2AD6"])
	if not features_hex.is_empty():
		chars.append("2ACC")
		_bridge.set_read_value("2ACC", BleBytes.from_hex(features_hex))
	_bridge.set_device_services(DEV, {"1826": chars})
	_ble = TrainerFactory.create_ble(_bridge) as BleTrainer
	_ble.connect_device(DEV)
	for i in 4:
		_bridge.pump()
	assert_eq(_ble.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "precondition: connected")
	return _ble


func _screen(plan: Workout, trainer: TrainerDevice) -> WorkoutScreen:
	var s: WorkoutScreen = load(SCENE).instantiate()
	s.clock_usec = _clock
	s.keep_awake_setter = _keep
	add_child_autofree(s)
	s.setup(plan, _profile, trainer, _state, null)
	assert_true(s.start(), "precondition: screen started")
	return s


## One second: a trainer packet (BLE) and a screen tick.
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


func _bar(s: WorkoutScreen, index: int) -> Array[int]:
	for seg in s.chart().plan_model().segments():
		if int(seg["index"]) == index:
			return [int(seg["start_watts"]), int(seg["end_watts"])] as Array[int]
	return [] as Array[int]


func _row_texts(s: WorkoutScreen) -> Array[String]:
	var out: Array[String] = []
	for row in s.interval_list().model.rows():
		out.append(IntervalListModel.row_text(row, "W", ""))
	return out


func _last_sample_target(s: WorkoutScreen) -> int:
	var samples := s.session().samples
	return samples.target_w[samples.size() - 1]


func _events(s: WorkoutScreen, type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in s.session().events:
		if str(e["type"]) == type:
			out.append(e)
	return out


func _resistance_writes() -> int:
	var n := 0
	for w in _bridge.writes_to("2AD9"):
		var b: PackedByteArray = w["bytes"]
		if b.size() > 0 and b[0] == FtmsCodec.OP_SET_TARGET_RESISTANCE:
			n += 1
	return n


func _power_writes() -> int:
	var n := 0
	for w in _bridge.writes_to("2AD9"):
		var b: PackedByteArray = w["bytes"]
		if b.size() > 0 and b[0] == FtmsCodec.OP_SET_TARGET_POWER:
			n += 1
	return n


static func _names(buttons: Array[Button]) -> Array[String]:
	var out: Array[String] = []
	for b in buttons:
		out.append(str(b.name))
	return out


static func _plan_u37() -> Workout:
	return Workout.make("u37", [WorkoutStep.watts(300, 132.0), WorkoutStep.watts(300, 1600.0),
		WorkoutStep.ramp_watts(300, 100.0, 1600.0)] as Array[WorkoutStep])


# ---------------------------------------------------------------------------
# U-37: targets by the trainer everywhere
# ---------------------------------------------------------------------------

func _assert_by_trainer(s: WorkoutScreen, where: String) -> void:
	assert_eq(_row_texts(s), ["5:00  130 W", "5:00  1500 W", "5:00  100→1500 W"] as Array[String], "%s: list" % where)
	assert_eq(_bar(s, 1), [1500, 1500] as Array[int], "%s: bar of the 1600 W step" % where)
	assert_eq(_bar(s, 2), [100, 1500] as Array[int], "%s: ramp bar" % where)
	assert_eq(s.chart().plan_model().max_target_w(), 1500, "%s: y_max follows 1500" % where)


func test_req_hud_01_c7_hud_10_c1_targets_by_trainer_everywhere_and_back_on_erg_toggle() -> void:
	var s := _screen(_plan_u37(), _fake())
	_second(s)
	assert_eq(s.target_text(), "130 W", "card")
	assert_eq(_last_sample_target(s), 130, "sample")
	assert_eq(_bar(s, 0), [130, 130] as Array[int], "current bar")
	_assert_by_trainer(s, "step 1")
	assert_almost_eq(s.chart().plan_model().y_max(), 1500.0 * PlanChartModel.Y_MAX_FACTOR, 0.01)
	# ERG off: plan targets everywhere by the next sample.
	s.toggle_erg()
	_second(s)
	assert_eq(s.target_text(), "132 W", "ERG off: card")
	assert_eq(_last_sample_target(s), 132, "ERG off: sample")
	assert_eq(_row_texts(s), ["5:00  132 W", "5:00  1600 W", "5:00  100→1600 W"] as Array[String], "ERG off: list")
	assert_eq(_bar(s, 1), [1600, 1600] as Array[int], "ERG off: bar")
	assert_eq(s.chart().plan_model().max_target_w(), 1600, "ERG off: y_max follows 1600")
	# ERG on again: by the trainer.
	s.toggle_erg()
	_second(s)
	assert_eq(s.target_text(), "130 W", "ERG on: card")
	_assert_by_trainer(s, "ERG on again")
	# NEXT 5 s before the end of step 1 — 1500.
	_advance_to(s, 295)
	assert_true(s.next_chip().is_shown(), "NEXT is shown")
	assert_string_contains(s.next_chip().line_text(), "1500")
	assert_false(s.next_chip().line_text().contains("1600"), "NEXT: no plan target")
	_advance_to(s, 400)
	assert_eq(s.target_text(), "1500 W", "during step 2")
	_assert_by_trainer(s, "during step 2")
	_advance_to(s, 650)
	_assert_by_trainer(s, "after step 2")


func test_hud_01_c7_without_limit_targets_equal_plan() -> void:
	var s := _screen(_plan_u37(), _fake(true, false))
	_second(s)
	assert_eq(s.target_text(), "132 W")
	assert_eq(_row_texts(s), ["5:00  132 W", "5:00  1600 W", "5:00  100→1600 W"] as Array[String])
	assert_eq(_bar(s, 1), [1600, 1600] as Array[int])


func test_req_wrk_03_c6_d_erg_unavailable_targets_follow_plan() -> void:
	var s := _screen(_plan_u37(), _fake(false))
	_second(s)
	assert_eq(s.target_text(), "132 W", "HUD-01 p.7: plan target")
	assert_eq(_row_texts(s), ["5:00  132 W", "5:00  1600 W", "5:00  100→1600 W"] as Array[String])
	assert_eq(_bar(s, 1), [1600, 1600] as Array[int])


# ---------------------------------------------------------------------------
# WRK-03 p.6 (a), (b): mode chip, toolbar, keys
# ---------------------------------------------------------------------------

func test_req_wrk_03_c6_a_res_chip_text2_dot_no_erg_text() -> void:
	var s := _screen(_plan_u37(), _fake(false))
	_advance_to(s, 60)
	assert_eq(s.mode_chip_text(), "RES.", "chip names the fixed-resistance mode")
	assert_eq(s.mode_chip_dot(), UiTokens.HUD_TEXT2)
	for n in s.find_children("*", "Label", true, false):
		var l := n as Label
		if l.is_visible_in_tree():
			assert_false(l.text.contains("ERG"), "no visible \"ERG\" on the HUD: %s" % l.text)
	TranslationServer.set_locale("ru")
	s.refresh()
	assert_eq(s.mode_chip_text(), "СОПР.")


func test_req_wrk_03_c5_erg_available_chip_still_erg() -> void:
	var s := _screen(_plan_u37(), _fake())
	_second(s)
	assert_eq(s.mode_chip_text(), "ERG")
	assert_true(s.toolbar().button(&"erg").visible)


func test_req_wrk_03_c6_b_erg_button_hidden_toolbar_composition() -> void:
	var s := _screen(_plan_u37(), _fake(false))
	_second(s)
	var tb := s.toolbar()
	assert_false(tb.button(&"erg").visible, "ERG button hidden, not just disabled")
	var bar: HudToolbar = load(TOOLBAR_SCENE).instantiate()
	add_child_autofree(bar)
	bar.set_mode(HudToolbar.Mode.PLAN)
	bar.set_controls_trainer(true)
	bar.set_erg_available(false)
	assert_eq(_names(bar.visible_buttons()), ["IntensityDown", "IntensityUp", "ResistanceDown", "ResistanceUp",
		"SkipButton", "FinishButton"] as Array[String], "desktop column")
	bar.set_compact(true)
	assert_eq(_names(bar.visible_buttons()), ["SkipButton", "FinishButton", "ResistanceDown", "ResistanceUp"] as Array[String],
		"phone: row 1 skip · finish, row 2 resistance")
	assert_eq(bar.button_row_count(), 2)
	bar.set_erg_available(true)
	assert_true(bar.button(&"erg").visible, "ERG back after a reconnect that accepts the target")


func test_req_wrk_03_c6_b_e_key_inert_plus_minus_resistance_within_1s() -> void:
	var t := _ble_trainer(FEATURES_NO_ERG)
	assert_false(t.is_erg_available())
	var s := _screen(_plan_u37(), t)
	_second(s)
	var erg_before: bool = s.session().erg_enabled
	var writes_before: int = _bridge.calls_of("write").size()
	assert_false(s.toolbar().trigger(HudToolbar.ACTION_TOGGLE), "E is not handled")
	_bridge.pump()
	assert_eq(s.session().erg_enabled, erg_before, "E changes nothing")
	assert_eq(_bridge.calls_of("write").size(), writes_before, "E writes nothing to the bridge")
	assert_eq(_events(s, WorkoutSession.EVENT_ERG_ON).size() + _events(s, WorkoutSession.EVENT_ERG_OFF).size(), 0)
	var level: int = s.session().resistance_level
	var intensity: float = s.session().intensity()
	var res_before := _resistance_writes()
	assert_true(s.toolbar().trigger(HudToolbar.ACTION_PLUS))
	_second(s)
	assert_eq(s.session().resistance_level, level + HudToolbar.RESISTANCE_STEP_PCT, "`+` raises the resistance level")
	assert_almost_eq(s.session().intensity(), intensity, 0.0001, "intensity unchanged")
	assert_gt(_resistance_writes(), res_before, "Set Target Resistance Level within 1 s")
	assert_eq(_power_writes(), 0, "no Set Target Power at all")


# ---------------------------------------------------------------------------
# WRK-03 p.6 (c), DEV-10 p.5 (b): notice 8 s once per connection; LOC-01 p.4 event
# ---------------------------------------------------------------------------

func _shown_seconds(s: WorkoutScreen, from_sec: int, to_sec: int) -> Array[int]:
	var out: Array[int] = []
	while s.session().executor.elapsed_sec() < to_sec:
		var now: int = s.session().executor.elapsed_sec()
		if now >= from_sec and s.hud().is_erg_notice_shown():
			out.append(now)
		_second(s)
	return out


func test_req_wrk_03_c6_c_notice_from_start_8s_long_text_then_cue() -> void:
	var step := WorkoutStep.watts(120, 150.0)
	step.text_cues.append(TextCue.make(3, "Spin up"))
	var s := _screen(Workout.make("n", [step] as Array[WorkoutStep]), _fake(false))
	assert_true(s.hud().is_erg_notice_shown(), "shown from the start")
	assert_eq(s.cue_text(), LONG_EN)
	assert_false(s.next_chip().is_shown())
	var shown := _shown_seconds(s, 0, 8)
	assert_eq(shown, [0, 1, 2, 3, 4, 5, 6, 7] as Array[int], "8 s")
	assert_false(s.hud().is_erg_notice_shown(), "gone at 8 s")
	assert_eq(s.cue_text(), "Spin up", "the step cue that came meanwhile follows the notice")
	assert_eq(_shown_seconds(s, 8, 20), [] as Array[int], "not shown again")
	var events := _events(s, WorkoutSession.EVENT_ERG_UNAVAILABLE)
	assert_eq(events.size(), 1, "one ride event")
	if events.size() == 1:
		assert_almost_eq(float(events[0]["at_sec"]), 0.0, 0.01)
	assert_eq(_events(s, WorkoutSession.EVENT_ERG_ON).size() + _events(s, WorkoutSession.EVENT_ERG_OFF).size(), 0,
		"not an ERG toggle event")
	# Pause and resume do not repeat it.
	s.toggle_pause()
	s.toggle_pause()
	_second(s)
	assert_false(s.hud().is_erg_notice_shown(), "pause / resume do not repeat the notice")


func test_req_wrk_03_c6_c_notice_texts_ru_and_phone() -> void:
	TranslationServer.set_locale("ru")
	var s := _screen(_plan_u37(), _fake(false))
	s.refresh()
	assert_eq(s.cue_text(), LONG_RU)
	if _runtime != null:
		_runtime.device = UiScale.Device.PHONE
		s.refresh()
		assert_eq(s.cue_text(), SHORT_RU)
		TranslationServer.set_locale("en")
		s.refresh()
		assert_eq(s.cue_text(), SHORT_EN)
	assert_ne(tr("ui.workout.notice.erg_unavailable"), "ui.workout.notice.erg_unavailable", "key translated")


func test_req_dev_10_c5_b_refusal_mid_ride_notice_from_that_second_once_per_connection() -> void:
	var t := _ble_trainer()
	var plan := Workout.make("r", [WorkoutStep.watts(61, 150.0), WorkoutStep.watts(60, 200.0),
		WorkoutStep.free_ride(20), WorkoutStep.watts(60, 220.0)] as Array[WorkoutStep])
	var s := _screen(plan, t)
	_advance_to(s, 59)
	assert_false(s.hud().is_erg_notice_shown())
	_bridge.fail_next_control_point(FtmsCodec.RESULT_NOT_SUPPORTED)
	var shown := _shown_seconds(s, 0, 100)
	assert_false(s.session().erg_available(), "refused at the step boundary")
	assert_eq(shown.size(), 8, "8 s: %s" % str(shown))
	if shown.size() > 0:
		assert_between(shown[0], 61, 62, "from the second of the refusal")
	var events := _events(s, WorkoutSession.EVENT_ERG_UNAVAILABLE)
	assert_eq(events.size(), 1)
	if events.size() == 1:
		assert_almost_eq(float(events[0]["at_sec"]), 61.0, 1.0)
	# FreeRide step, pause, the rest of the ride — no repeat.
	s.toggle_pause()
	s.toggle_pause()
	assert_eq(_shown_seconds(s, 100, 200), [] as Array[int], "no repeat within the connection")
	assert_eq(_events(s, WorkoutSession.EVENT_ERG_UNAVAILABLE).size(), 1)


func test_n_77_a_new_connection_refusal_shows_notice_again() -> void:
	var f := _fake()
	var s := _screen(Workout.make("c", [WorkoutStep.watts(300, 150.0)] as Array[WorkoutStep]), f)
	_second(s)
	f.set_erg_supported(false)
	_second(s)
	assert_true(s.hud().is_erg_notice_shown())
	_advance_to(s, 20)
	assert_false(s.hud().is_erg_notice_shown())
	# A new connection: ERG is accepted again, then refused again.
	f.set_erg_supported(true)
	f.inject_dropout(2.0)
	for i in 4:
		_second(s)
	assert_eq(f.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "precondition: reconnected")
	f.set_erg_supported(false)
	_second(s)
	assert_true(s.hud().is_erg_notice_shown(), "shown again in a new connection")
	assert_eq(_events(s, WorkoutSession.EVENT_ERG_UNAVAILABLE).size(), 2)
