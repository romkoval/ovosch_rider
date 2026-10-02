extends GutTest
## Тесты SessionTicker (REQ-NFR-02 крит. 1, 2): дельты считаются от подставленных часов,
## а не от числа кадров; заморозка кадра даёт одну большую дельту; time_scale.

const FTP: int = 200

var _now_usec: int = 0
var _trainer: TrainerDevice
var _session: WorkoutSession
var _ticker: SessionTicker
var _deltas: Array[float] = []


func before_each() -> void:
	_now_usec = 1_000_000
	_deltas = []
	_trainer = TrainerFactory.create("fake")
	_trainer.set("connect_delay_sec", 0.0)
	_trainer.connect_device("ticker-fake")
	_session = WorkoutSession.new(_plan(), _trainer, FTP)
	_ticker = SessionTicker.new(_clock)
	_ticker.attach(_session)
	_ticker.ticked.connect(func(d: float) -> void: _deltas.append(d))


func after_each() -> void:
	if is_instance_valid(_ticker) and not _ticker.is_inside_tree():
		_ticker.free()


func _clock() -> int:
	return _now_usec


func _advance_sec(sec: float) -> void:
	_now_usec += int(round(sec * 1_000_000.0))


func _plan() -> Workout:
	var steps: Array[WorkoutStep] = [WorkoutStep.percent(60, 50.0), WorkoutStep.percent(30, 100.0), WorkoutStep.percent(90, 60.0)]
	return Workout.make("ticker", steps)


func test_poll_before_start_delivers_nothing() -> void:
	_advance_sec(5.0)
	assert_eq(_ticker.poll(), 0.0)
	assert_false(_ticker.is_running())
	assert_eq(_deltas, [])


func test_first_poll_after_start_is_zero_no_catch_up_of_past() -> void:
	_advance_sec(100.0)
	_ticker.start()
	assert_true(_ticker.is_running())
	assert_eq(_ticker.poll(), 0.0, "время до start() не догоняется")
	assert_eq(_ticker.delivered_sec, 0.0)


func test_sum_of_deltas_equals_real_elapsed_not_frame_count() -> void:
	_session.start()
	_ticker.start()
	var pattern: Array[float] = [0.016, 0.033, 0.5, 0.016, 2.0, 0.1, 0.016, 0.3]
	var total: float = 0.0
	for d in pattern:
		_advance_sec(d)
		_ticker.poll()
		total += d
	assert_eq(_deltas.size(), pattern.size(), "по одной дельте на опрос")
	assert_almost_eq(_ticker.delivered_sec, total, 1e-6, "сумма дельт = реальное время, а не 8 × кадр")
	assert_almost_eq(_ticker.real_elapsed_sec, total, 1e-6)
	assert_eq(_session.executor.elapsed_sec(), int(floor(total)), "сессия продвинулась на столько же секунд")


func test_frozen_frame_delivers_one_big_delta_and_session_catches_up() -> void:
	_session.start()
	_ticker.start()
	_advance_sec(1.0)
	_ticker.poll()
	_advance_sec(2.0)
	var d := _ticker.poll()
	assert_almost_eq(d, 2.0, 1e-6, "REQ-NFR-02 крит. 2: заморозка 2 с → дельта ~2.0")
	assert_eq(_session.executor.elapsed_sec(), 3)
	assert_eq(_session.samples.size(), 3, "сэмплы за замороженные секунды записаны постфактум")
	assert_eq(_deltas.size(), 2)


func test_time_scale_multiplies_session_time() -> void:
	_session.start()
	_ticker.start()
	_ticker.set_time_scale(10.0)
	_advance_sec(1.0)
	var d := _ticker.poll()
	assert_almost_eq(d, 10.0, 1e-6)
	assert_eq(_session.executor.elapsed_sec(), 10)
	assert_almost_eq(_ticker.real_elapsed_sec, 1.0, 1e-6)
	assert_almost_eq(_ticker.delivered_sec, 10.0, 1e-6)


func test_time_scale_is_clamped() -> void:
	_ticker.set_time_scale(0.0)
	assert_eq(_ticker.time_scale, SessionTicker.MIN_TIME_SCALE)
	_ticker.set_time_scale(-5.0)
	assert_eq(_ticker.time_scale, SessionTicker.MIN_TIME_SCALE)
	_ticker.set_time_scale(1e9)
	assert_eq(_ticker.time_scale, SessionTicker.MAX_TIME_SCALE)
	_ticker.set_time_scale(2.5)
	assert_eq(_ticker.time_scale, 2.5)


func test_stop_freezes_and_restart_does_not_catch_up() -> void:
	_session.start()
	_ticker.start()
	_advance_sec(1.0)
	_ticker.poll()
	_ticker.stop()
	_advance_sec(50.0)
	assert_eq(_ticker.poll(), 0.0, "остановленный тикер ничего не доставляет")
	_ticker.start()
	_advance_sec(1.0)
	assert_almost_eq(_ticker.poll(), 1.0, 1e-6, "после рестарта долг за остановку не доставляется")
	assert_eq(_session.executor.elapsed_sec(), 2)


func test_clock_not_moving_delivers_zero() -> void:
	_session.start()
	_ticker.start()
	assert_eq(_ticker.poll(), 0.0)
	assert_eq(_ticker.poll(), 0.0)
	assert_eq(_deltas, [])


func test_huge_clock_jump_is_clamped_with_warning() -> void:
	_ticker.start()
	_advance_sec(SessionTicker.MAX_DELTA_SEC * 3.0)
	var d := _ticker.poll()
	assert_push_warning("скачок часов")
	assert_almost_eq(d, SessionTicker.MAX_DELTA_SEC, 1e-6)


func test_poll_without_session_still_counts_time() -> void:
	var lone := SessionTicker.new(_clock)
	lone.start()
	_advance_sec(1.5)
	assert_almost_eq(lone.poll(), 1.5, 1e-6)
	assert_almost_eq(lone.delivered_sec, 1.5, 1e-6)
	lone.free()


func test_default_clock_is_system_ticks() -> void:
	var sys := SessionTicker.new()
	sys.start()
	var d := sys.poll()
	assert_true(d >= 0.0 and d < 1.0, "системные часы: малая неотрицательная дельта")
	sys.free()


func test_in_tree_process_polls_the_injected_clock() -> void:
	_session.start()
	add_child_autofree(_ticker)
	_ticker.start()
	_advance_sec(3.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_almost_eq(_ticker.delivered_sec, 3.0, 1e-6, "_process опросил подставленные часы ровно на прошедшее время")
	assert_eq(_session.executor.elapsed_sec(), 3)
	_advance_sec(0.25)
	await get_tree().process_frame
	assert_almost_eq(_ticker.delivered_sec, 3.25, 1e-6)
	_ticker.stop()
