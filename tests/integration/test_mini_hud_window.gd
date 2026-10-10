extends GutTest
## T-177 spike: mini-HUD — a compact always-on-top window with the workout numbers. Switch from the
## workout screen and back without touching the session; window flags set and restored; native
## helper called when present and skipped when absent; 3D rendering paused; the session keeps
## ticking at 1 Hz with ERG targets on step boundaries; overlay pause / skip act as on the full HUD.
## Regression: REQ-WRK-05, REQ-WRK-06, REQ-WRK-08, REQ-HUD-01.

const SCENE: String = "res://src/ui/workout/workout_screen.tscn"


## Test double of the GDExtension helper `OvoschWindow`.
class NativeStub:
	extends RefCounted
	var calls: Array = []

	func is_available() -> bool:
		return true

	func set_overlay(handle: int, enabled: bool) -> bool:
		calls.append(["set_overlay", handle, enabled])
		return true

	func begin_activity(reason: String) -> bool:
		calls.append(["begin_activity", reason])
		return true

	func end_activity() -> void:
		calls.append(["end_activity"])


var _now_usec: int = 0
var _state: AppState
var _profile: Profile
var _locale: String
var _screen: WorkoutScreen = null
var _window_before: Dictionary = {}
## The headless root window does not keep window flags; an embedded window does.
var _window: Window = null


func before_each() -> void:
	_now_usec = 5_000_000
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_state = AppState.new(ProfileRepository.new("user://mini_hud_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]))
	_profile = Profile.create("Rider")
	_profile.ftp_w = 200
	var host := SubViewport.new()
	host.gui_embed_subwindows = true
	host.size = Vector2i(1280, 720)
	add_child_autofree(host)
	_window = Window.new()
	_window.size = Vector2i(1280, 720)
	_window.content_scale_size = Vector2i(1280, 720)
	host.add_child(_window)
	_window_before = _window_flags(_window)


func after_each() -> void:
	if _screen != null and is_instance_valid(_screen):
		_screen.exit_mini_hud()
	_screen = null
	TranslationServer.set_locale(_locale)


func _clock() -> int:
	return _now_usec


func _keep(_on: bool) -> void:
	pass


static func _window_flags(w: Window) -> Dictionary:
	return {
		"size": w.size, "position": w.position, "borderless": w.borderless, "always_on_top": w.always_on_top,
		"transparent": w.transparent, "transparent_bg": w.transparent_bg, "unresizable": w.unresizable,
		"passthrough": w.mouse_passthrough_polygon, "content_scale_size": w.content_scale_size,
	}


func _fake() -> FakeTrainer:
	var f := FakeTrainer.new(9)
	f.connect_delay_sec = 0.0
	f.power_noise_w = 0.0
	f.connect_device("fake")
	return f


func _start(trainer: TrainerDevice) -> WorkoutScreen:
	var s: WorkoutScreen = load(SCENE).instantiate()
	s.clock_usec = _clock
	s.keep_awake_setter = _keep
	add_child_autofree(s)
	s.setup(Workout.make("m", [WorkoutStep.watts(60, 150.0), WorkoutStep.watts(60, 200.0)] as Array[WorkoutStep]),
		_profile, trainer, _state, null)
	assert_true(s.start(), "precondition: started")
	s.mini_hud_window = _window
	_screen = s
	return s


func _second(s: WorkoutScreen) -> void:
	_now_usec += 1_000_000
	s.ticker().poll()


func _snapshot(s: WorkoutScreen) -> Dictionary:
	var sess := s.session()
	return {"step": sess.executor.current_step_index(), "elapsed": sess.executor.elapsed_sec(),
		"target": sess.current_target_watts(), "state": sess.get_state(), "samples": sess.samples.size()}


func _targets(f: FakeTrainer) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in f.commands:
		if str(c.get("type", "")) == FakeTrainer.CMD_TARGET_POWER:
			out.append(c)
	return out


func test_switch_keeps_session_and_mini_values_equal_hud_model() -> void:
	var s := _start(_fake())
	for i in 10:
		_second(s)
	var before := _snapshot(s)
	assert_true(s.enter_mini_hud(NativeStub.new()), "entered")
	assert_true(s.is_mini_hud())
	assert_eq(_snapshot(s), before, "session untouched by the switch")
	var st := s.hud().state()
	var mini := s.mini_hud()
	assert_true(mini.is_visible_in_tree(), "plate shown")
	assert_eq(mini.power_text(), "%s W" % st["power_text"])
	assert_eq(mini.target_text(), "target %s W" % st["target_text"])
	assert_eq(mini.hr_text(), "%s bpm" % st["hr_text"])
	assert_eq(mini.cadence_text(), "%s rpm" % st["cadence_text"])
	assert_eq(mini.timer_text(), str(st["countdown_text"]))
	assert_eq(mini.next_text(), "Next: 1:00 · 200 W")
	_second(s)
	assert_eq(mini.timer_text(), str(s.hud().state()["countdown_text"]), "follows the model every tick")
	var mid := _snapshot(s)
	s.exit_mini_hud()
	assert_false(s.is_mini_hud())
	assert_eq(_snapshot(s), mid, "session untouched on return")
	assert_false(mini.visible, "plate hidden")
	assert_true(s.metric_panel().is_visible_in_tree(), "full HUD back")
	assert_eq(s.power_text(), mini.power_text(), "the same number as the plate showed")


func test_window_flags_set_and_restored_native_called() -> void:
	var s := _start(_fake())
	_second(s)
	var native := NativeStub.new()
	s.enter_mini_hud(native)
	var w := _window
	assert_true(w.always_on_top, "always on top")
	assert_true(w.borderless, "borderless")
	assert_true(w.transparent and w.transparent_bg, "transparent")
	assert_true(w.unresizable)
	assert_gt(w.mouse_passthrough_polygon.size(), 2, "clickable part set")
	assert_eq(w.content_scale_size, MiniHud.SIZE_LP, "canvas of the mini window")
	assert_true(s.overlay_window().is_native_applied())
	assert_eq(native.calls.size(), 2)
	if native.calls.size() == 2:
		assert_eq(native.calls[0][0], "set_overlay")
		assert_true(native.calls[0][2], "overlay on")
		assert_eq(native.calls[1][0], "begin_activity", "App Nap guard")
	s.exit_mini_hud()
	assert_eq(_window_flags(w), _window_before, "everything restored")
	assert_eq(native.calls.size(), 4)
	if native.calls.size() == 4:
		assert_eq(native.calls[2][0], "set_overlay")
		assert_false(native.calls[2][2], "overlay off")
		assert_eq(native.calls[3][0], "end_activity")


func test_without_native_extension_switch_works_and_skips_native() -> void:
	assert_false(ClassDB.class_exists(OverlayWindow.NATIVE_CLASS), "precondition: no extension in tests")
	var s := _start(_fake())
	_second(s)
	assert_false(s.mini_hud_supported, "switch button hidden without the native helper")
	assert_false(s.mini_hud_button().visible)
	assert_true(s.enter_mini_hud(), "still switches (flags only)")
	assert_true(_window.always_on_top)
	assert_false(s.overlay_window().is_native_applied(), "native part skipped")
	s.exit_mini_hud()
	assert_eq(_window_flags(_window), _window_before)


func test_switch_button_shown_when_supported_and_enters() -> void:
	var s := _start(_fake())
	s.mini_hud_supported = true
	_second(s)
	s.toolbar().poke()  # hud.md 18.1: the button appears with the toolbar
	assert_true(s.mini_hud_button().is_visible_in_tree(), "button on the full HUD")
	s.mini_hud_button().pressed.emit()
	assert_true(s.is_mini_hud(), "button enters the mini-HUD")
	assert_false(s.mini_hud_button().is_visible_in_tree())
	s.mini_hud().button(&"exit").pressed.emit()
	assert_false(s.is_mini_hud(), "overlay button returns to full")


func test_3d_paused_in_mini_hud_and_resumed() -> void:
	var s := _start(_fake())
	_second(s)
	var vp := s.ride_scene().get_viewport() as SubViewport
	var mode_before := vp.render_target_update_mode
	var process_before := s.ride_scene().process_mode
	s.enter_mini_hud(NativeStub.new())
	assert_eq(vp.render_target_update_mode, SubViewport.UPDATE_DISABLED, "3D not rendered")
	assert_eq(s.ride_scene().process_mode, Node.PROCESS_MODE_DISABLED, "world not processing")
	assert_false(s.ride_scene().can_process())
	s.exit_mini_hud()
	assert_eq(vp.render_target_update_mode, mode_before, "rendering back")
	assert_eq(s.ride_scene().process_mode, process_before)


func test_session_ticks_in_mini_hud_erg_boundary_pause_and_skip() -> void:
	var f := _fake()
	var s := _start(f)
	s.enter_mini_hud(NativeStub.new())
	for i in 121:
		_second(s)
	var sess := s.session()
	assert_eq(sess.get_state(), WorkoutSession.State.FINISHED, "ran to the end in the mini-HUD")
	assert_eq(sess.samples.size(), 120, "120 samples at 1 Hz")
	assert_false(s.is_mini_hud(), "the summary returns to the full window")
	var hit_200 := false
	for c in _targets(f):
		if int(c["value"]) == 200:
			hit_200 = true
			assert_almost_eq(float(c["at_sec"]) - float(_targets(f)[0]["at_sec"]), 60.0, 1.0, "200 W at the step boundary")
			break
	assert_true(hit_200, "ERG target 200 W sent: %s" % str(_targets(f)))


func test_overlay_pause_and_skip_act_like_full_hud() -> void:
	var s := _start(_fake())
	for i in 5:
		_second(s)
	s.enter_mini_hud(NativeStub.new())
	var mini := s.mini_hud()
	mini.button(&"pause").pressed.emit()
	assert_eq(s.session().get_state(), WorkoutSession.State.PAUSED, "pause (WRK-05)")
	var elapsed := s.session().executor.elapsed_sec()
	for i in 3:
		_second(s)
	assert_eq(s.session().executor.elapsed_sec(), elapsed, "timer stands on pause")
	assert_false(s.pause_overlay().visible, "pause card stays hidden in the mini window")
	mini.button(&"pause").pressed.emit()
	assert_eq(s.session().get_state(), WorkoutSession.State.RUNNING, "resume")
	mini.button(&"skip").pressed.emit()
	assert_eq(s.session().executor.current_step_index(), 1, "skip step (WRK-06)")
	s.exit_mini_hud()
	assert_true(s.metric_panel().is_visible_in_tree())


# ---------------------------------------------------------------------------
# hud.md 18.1 (game-designer, T-177 follow-up): button with the toolbar, desktop only, key M, icons
# ---------------------------------------------------------------------------

func _key_m() -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = KEY_M
	k.keycode = KEY_M
	k.pressed = true
	return k


func test_mini_button_follows_toolbar_and_sits_12_lp_left_of_pause() -> void:
	var s := _start(_fake())
	s.mini_hud_supported = true
	_second(s)
	assert_false(s.toolbar().is_shown(), "precondition: toolbar hidden at rest")
	assert_false(s.mini_hud_button().visible, "HUD at rest: no «Mini» (only Pause is always visible)")
	s.toolbar().poke()
	assert_true(s.mini_hud_button().visible, "shown together with the toolbar")
	var b := s.mini_hud_button()
	var pause := s.pause_button()
	assert_almost_eq(pause.position.x - (b.position.x + b.size.x), WorkoutScreen.MINI_BUTTON_GAP, 0.5, "left of Pause")
	assert_eq(WorkoutScreen.MINI_BUTTON_GAP, 12.0, "12 lp gap")
	assert_eq(b.icon, WorkoutScreen.ICON_MINI, "Lucide picture-in-picture-2")
	s.toolbar().tick(HudToolbar.HIDE_AFTER_SEC + 0.1)
	assert_false(s.mini_hud_button().visible, "hides together with the toolbar")


func test_mini_button_hidden_on_phone_and_tablet() -> void:
	var ui := TouchTarget.default_runtime()
	if ui == null:
		pending("no UiScale runtime")
		return
	var prev := ui.device
	var s := _start(_fake())
	s.mini_hud_supported = true
	for device in [UiScale.Device.PHONE, UiScale.Device.TABLET]:
		ui.device = device
		assert_false(s.mini_hud_available(), "not offered on a touch device (%d)" % device)
		s.toolbar().poke()
		_second(s)
		assert_false(s.mini_hud_button().visible, "hidden, not disabled, on a touch device (%d)" % device)
		assert_false(s.toggle_mini_hud(), "M does nothing there")
	ui.device = UiScale.Device.DESKTOP
	assert_true(s.mini_hud_available(), "desktop with the capability")
	ui.device = prev


func test_key_m_toggles_full_and_mini() -> void:
	var s := _start(_fake())
	s.mini_hud_supported = true
	_second(s)
	s._unhandled_key_input(_key_m())
	assert_true(s.is_mini_hud(), "M: full → mini")
	_second(s)
	s._unhandled_key_input(_key_m())
	assert_false(s.is_mini_hud(), "M: mini → full")
	s.mini_hud_supported = false
	s._unhandled_key_input(_key_m())
	assert_false(s.is_mini_hud(), "without the capability M does nothing")


func test_mini_hud_back_button_uses_maximize_2() -> void:
	var s := _start(_fake())
	var exit := s.mini_hud().button(&"exit")
	assert_eq(exit.icon, MiniHud.ICON_FULL)
	assert_eq(MiniHud.ICON_FULL.resource_path, "res://assets/icons/lucide/maximize-2.svg", "no chevron-up (hud.md 18.2)")
