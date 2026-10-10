extends GutTest
## Acceptance of the T-177 spike (tester), only what the coordinator asked: the mini-HUD toggle
## does not disturb the session (samples keep flowing at 1 Hz with no gap or duplicate across the
## switches, pause state survives the return, finish returns to the full window) and the switch
## button is hidden when the native helper is absent. Native ObjC++ behaviour — owner's manual check.
## Regression: REQ-WRK-05, REQ-WRK-08 p.1.

const SCENE: String = "res://src/ui/workout/workout_screen.tscn"

var _now_usec: int = 0
var _state: AppState
var _profile: Profile
var _locale: String
var _screen: WorkoutScreen = null
var _window: Window = null


func before_each() -> void:
	_now_usec = 5_000_000
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_state = AppState.new(ProfileRepository.new("user://acc_t177_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]))
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


func after_each() -> void:
	if _screen != null and is_instance_valid(_screen):
		_screen.exit_mini_hud()
	_screen = null
	TranslationServer.set_locale(_locale)


func _start() -> WorkoutScreen:
	var f := FakeTrainer.new(21)
	f.connect_delay_sec = 0.0
	f.power_noise_w = 0.0
	f.connect_device("fake")
	var s: WorkoutScreen = load(SCENE).instantiate()
	s.clock_usec = func() -> int: return _now_usec
	s.keep_awake_setter = func(_on: bool) -> void: pass
	add_child_autofree(s)
	s.setup(Workout.make("m", [WorkoutStep.watts(30, 150.0), WorkoutStep.watts(30, 200.0)] as Array[WorkoutStep]),
		_profile, f, _state, null)
	assert_true(s.start())
	s.mini_hud_window = _window
	_screen = s
	return s


func _second(s: WorkoutScreen) -> void:
	_now_usec += 1_000_000
	s.ticker().poll()


func test_t177_toggles_keep_samples_continuous_and_pause_survives_return() -> void:
	var s := _start()
	for i in 5:
		_second(s)
	for round in 3:
		assert_true(s.enter_mini_hud(), "enter (round %d)" % round)
		for i in 4:
			_second(s)
		s.exit_mini_hud()
		_second(s)
	var times: Array[int] = []
	for i in s.session().samples.size():
		times.append(int(s.session().samples.row(i)["time_sec"]))
	var want: Array[int] = []
	for i in times.size():
		want.append(i)
	assert_eq(times, want, "samples 0..n-1 at 1 Hz, no gap or duplicate across switches")
	assert_eq(s.session().samples.size(), s.session().executor.elapsed_sec())
	# Pause in the mini-HUD, return: still paused, pause card back on the full HUD.
	s.enter_mini_hud()
	s.mini_hud().button(&"pause").pressed.emit()
	var n := s.session().samples.size()
	_second(s)
	s.exit_mini_hud()
	assert_eq(s.session().get_state(), WorkoutSession.State.PAUSED, "pause survives the return")
	assert_true(s.pause_overlay().visible, "pause card shown on the full HUD")
	assert_eq(s.session().samples.size(), n, "no samples on pause (WRK-05 p.2)")
	s.toggle_pause()
	while s.session().get_state() == WorkoutSession.State.RUNNING:
		_second(s)
	assert_eq(s.session().samples.size(), 60, "60 s plan → 60 samples")


func test_t177_finish_in_mini_hud_returns_to_full_window() -> void:
	var s := _start()
	s.enter_mini_hud()
	while s.session().get_state() != WorkoutSession.State.FINISHED:
		_second(s)
	assert_false(s.is_mini_hud(), "finish returns to the full window")
	assert_false(_window.always_on_top, "window flags restored")


func test_t177_button_hidden_without_native_helper() -> void:
	assert_false(ClassDB.class_exists(OverlayWindow.NATIVE_CLASS), "precondition: no extension in this build")
	assert_false(OverlayWindow.native_available())
	var s := _start()
	_second(s)
	assert_false(s.mini_hud_supported)
	assert_false(s.mini_hud_button().is_visible_in_tree(), "«Mini» hidden without the native helper")
