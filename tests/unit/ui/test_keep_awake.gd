extends GutTest
## Тесты KeepAwake (REQ-NFR-04 крит. 1, 2) через подставляемый вызов вместо DisplayServer.

var _calls: Array[bool] = []
var _trainer: FakeTrainer
var _session: WorkoutSession


func before_each() -> void:
	_calls = []
	_trainer = FakeTrainer.new(3)
	_trainer.connect_delay_sec = 0.0
	_trainer.connect_device("ka")
	var steps: Array[WorkoutStep] = [WorkoutStep.watts(5, 150.0), WorkoutStep.watts(5, 200.0)]
	_session = WorkoutSession.new(Workout.make("ka", steps), _trainer, 200)


func _setter(on: bool) -> void:
	_calls.append(on)


func _keep() -> KeepAwake:
	var k := KeepAwake.new(_setter)
	k.attach(_session)
	return k


func test_idle_session_does_not_call_setter() -> void:
	var k := _keep()
	assert_false(k.is_on())
	assert_eq(_calls, [], "в IDLE снимать нечего — лишних вызовов нет")


func test_start_sets_keep_on_and_finish_releases() -> void:
	var k := _keep()
	_session.start()
	assert_true(k.is_on())
	assert_eq(_calls, [true], "REQ-NFR-04 крит. 1: запрет при старте")
	for i in 10:
		_session.tick(1.0)
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED)
	assert_false(k.is_on())
	assert_eq(_calls, [true, false], "снятие при завершении")


func test_pause_keeps_the_lock() -> void:
	var k := _keep()
	_session.start()
	_session.pause()
	assert_true(k.is_on(), "REQ-NFR-04 крит. 2")
	_session.resume()
	assert_true(k.is_on())
	assert_eq(_calls, [true], "на паузе/возобновлении сеттер не дёргается")


func test_stop_early_releases() -> void:
	var k := _keep()
	_session.start()
	_session.tick(2.0)
	_session.stop()
	assert_false(k.is_on())
	assert_eq(_calls, [true, false])


func test_screen_exit_releases_and_enter_restores_while_running() -> void:
	var k := _keep()
	_session.start()
	k.on_screen_exited()
	assert_false(k.is_on(), "уход с экрана тренировки снимает запрет")
	k.on_screen_entered()
	assert_true(k.is_on(), "возврат на экран при RUNNING восстанавливает")
	assert_eq(_calls, [true, false, true])


func test_attach_to_already_running_session_applies_immediately() -> void:
	_session.start()
	var k := KeepAwake.new(_setter)
	k.attach(_session)
	assert_true(k.is_on())
	assert_eq(_calls, [true])


func test_detach_releases_and_stops_following_session() -> void:
	var k := _keep()
	_session.start()
	k.detach()
	assert_false(k.is_on())
	_session.pause()
	_session.resume()
	assert_eq(_calls, [true, false], "после detach сессия больше не влияет")


func test_changed_signal_mirrors_setter() -> void:
	var k := _keep()
	var seen: Array[bool] = []
	k.changed.connect(func(on: bool) -> void: seen.append(on))
	_session.start()
	_session.stop()
	assert_eq(seen, [true, false])


func test_wants_keep_on_rule() -> void:
	assert_false(KeepAwake.wants_keep_on(WorkoutSession.State.IDLE))
	assert_true(KeepAwake.wants_keep_on(WorkoutSession.State.RUNNING))
	assert_true(KeepAwake.wants_keep_on(WorkoutSession.State.PAUSED))
	assert_false(KeepAwake.wants_keep_on(WorkoutSession.State.FINISHED))


func test_default_setter_is_display_server_call_and_does_not_crash_headless() -> void:
	var k := KeepAwake.new()
	k.attach(_session)
	_session.start()
	assert_true(k.is_on())
	_session.stop()
	assert_false(k.is_on())
