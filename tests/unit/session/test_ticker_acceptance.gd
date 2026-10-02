extends GutTest
## Независимые приёмочные тесты `SessionTicker` (тестировщик, T-013).
## Покрытие: REQ-NFR-02 крит. 1 (тикер от системных часов: 60 опросов с неровными
## интервалами → сумма дельт = реальное время, 60 сэмплов) и крит. 2 (заморозка 2 с →
## сэмплы постфактум с верными метками). Границы: без `attach`, `time_scale` 0,
## `stop()`→`start()` без долга, часы назад, скачок часов, два тикера на одной сессии.

const FTP: int = 200

var _now_usec: int = 0
var _ticker: SessionTicker
var _trainer: FakeTrainer
var _session: WorkoutSession
var _ticked: Array[float] = []


func before_each() -> void:
	_now_usec = 10_000_000
	_ticked = []
	_trainer = FakeTrainer.new(7)
	_trainer.connect_delay_sec = 0.0
	_trainer.connect_device("ticker-acc")
	_session = WorkoutSession.new(_plan_600s(), _trainer, FTP)
	_ticker = SessionTicker.new(_clock)
	_ticker.ticked.connect(func(d: float) -> void: _ticked.append(d))
	_ticker.attach(_session)
	add_child_autofree(_ticker)


func _clock() -> int:
	return _now_usec


func _advance_real(sec: float) -> float:
	_now_usec += int(round(sec * 1_000_000.0))
	return _ticker.poll()


static func _plan_600s() -> Workout:
	var steps: Array[WorkoutStep] = [WorkoutStep.percent(600, 60.0, WorkoutStep.StepKind.STEADY)]
	return Workout.make("ticker-600", steps)


func _sum(values: Array[float]) -> float:
	var s := 0.0
	for v in values:
		s += v
	return s


# ===========================================================================
# REQ-NFR-02 крит. 1 — время от системных часов, а не от числа кадров
# ===========================================================================

func test_req_nfr_02_c1_60_irregular_polls_deliver_exactly_real_elapsed_and_60_samples() -> void:
	_session.start()
	_ticker.start()
	# 60 опросов с неровными интервалами, сумма ровно 60.0 с: 20 × (0.3 + 1.7 + 1.0)
	var pattern: Array[float] = [0.3, 1.7, 1.0]
	for i in 60:
		_advance_real(pattern[i % 3])
	assert_almost_eq(_ticker.real_elapsed_sec, 60.0, 1e-6, "учтено реальное время")
	assert_almost_eq(_ticker.delivered_sec, 60.0, 1e-6, "сумма доставленных дельт = реальное время (scale 1)")
	assert_almost_eq(_sum(_ticked), 60.0, 1e-6, "сигнал ticked согласован")
	assert_eq(_ticked.size(), 60)
	assert_eq(_session.samples.size(), 60, "60 секунд сессии → 60 сэмплов, независимо от длины «кадров»")
	assert_eq(_session.executor.elapsed_sec(), 60)
	assert_true(_session.samples.is_monotonic())
	assert_eq(_session.samples.time_sec[0], 0)
	assert_eq(_session.samples.time_sec[59], 59)
	assert_eq(_trainer.samples_emitted, 60, "эмулятор тоже прошёл ровно 60 с")


func test_req_nfr_02_c1_frame_like_polls_1_60s_for_10s_give_10_samples() -> void:
	_session.start()
	_ticker.start()
	var start_usec := _now_usec
	for i in 600:
		_advance_real(1.0 / 60.0) # 16 667 мкс на кадр → 10.0002 с всего
	var expected := float(_now_usec - start_usec) / 1_000_000.0
	assert_almost_eq(_ticker.real_elapsed_sec, expected, 1e-9, "учтено ровно то, что показали часы")
	assert_almost_eq(expected, 10.0, 1e-3)
	assert_eq(_session.samples.size(), 10)
	assert_eq(_session.samples.time_sec[9], 9)


func test_req_nfr_02_c1_poll_before_start_and_first_poll_after_start_deliver_zero() -> void:
	_session.start()
	_now_usec += 5_000_000
	assert_eq(_ticker.poll(), 0.0, "до start() ничего не доставляется")
	_ticker.start()
	assert_eq(_ticker.poll(), 0.0, "сразу после start() долга нет")
	_now_usec += 3_000_000
	assert_almost_eq(_ticker.poll(), 3.0, 1e-9, "после старта прошло 3 с → доставлено 3 с")
	assert_eq(_session.samples.size(), 3, "3 сэмпла, а не 8: 5 с до start() не догоняются")


func test_req_nfr_02_c1_clock_not_moving_or_moving_backwards_delivers_zero() -> void:
	_session.start()
	_ticker.start()
	assert_eq(_ticker.poll(), 0.0)
	assert_eq(_ticker.poll(), 0.0)
	_now_usec -= 2_000_000
	assert_eq(_ticker.poll(), 0.0, "часы назад → 0, не отрицательная дельта")
	assert_eq(_ticker.delivered_sec, 0.0)
	assert_eq(_session.samples.size(), 0)
	_advance_real(1.0)
	assert_eq(_session.samples.size(), 1, "после отката отсчёт идёт от новой отметки")


# ===========================================================================
# REQ-NFR-02 крит. 2 — заморозка кадра 2 с: сэмплы постфактум с верными метками
# ===========================================================================

func test_req_nfr_02_c2_two_second_freeze_delivers_one_delta_and_session_backfills_samples() -> void:
	_session.start()
	_ticker.start()
	_advance_real(1.0)
	_advance_real(1.0)
	assert_eq(_session.samples.size(), 2)
	var delta := _advance_real(2.0) # «кадр завис» на 2 с
	assert_almost_eq(delta, 2.0, 1e-9, "одна дельта 2.0")
	assert_eq(_session.samples.size(), 4, "две пропущенные секунды дописаны постфактум")
	assert_eq(Array(_session.samples.time_sec), [0, 1, 2, 3])
	assert_true(_session.samples.is_monotonic())
	assert_true(_session.samples.has_power[2] and _session.samples.has_power[3], "в дописанных сэмплах есть телеметрия эмулятора")
	_advance_real(0.5)
	_advance_real(0.5)
	assert_eq(Array(_session.samples.time_sec), [0, 1, 2, 3, 4], "после заморозки ряд продолжается без дублей")
	assert_eq(_trainer.samples_emitted, 5)


func test_req_nfr_02_c2_freeze_across_step_boundary_still_sends_target_on_boundary() -> void:
	var steps: Array[WorkoutStep] = [
		WorkoutStep.percent(3, 50.0, WorkoutStep.StepKind.WARMUP),
		WorkoutStep.percent(3, 100.0, WorkoutStep.StepKind.INTERVAL_ON),
	]
	var session := WorkoutSession.new(Workout.make("freeze-boundary", steps), _trainer, FTP)
	_ticker.attach(session)
	session.start()
	_ticker.start()
	_advance_real(2.0)
	_advance_real(3.0) # заморозка через границу 3 с
	var targets: Array = []
	for c in _trainer.commands:
		if c["type"] == FakeTrainer.CMD_TARGET_POWER:
			targets.append([c["value"], c["at_sec"]])
	assert_eq(targets, [[100, 0.0], [200, 3.0]], "вторая цель ушла с меткой ровно на границе, а не в конце заморозки")
	assert_eq(session.samples.size(), 5)


# ===========================================================================
# Границы: без attach, time_scale, stop/start, скачок часов, два тикера
# ===========================================================================

func test_req_nfr_02_poll_without_attach_does_not_crash_and_counts_time() -> void:
	var lone := SessionTicker.new(_clock)
	add_child_autofree(lone)
	var deltas: Array[float] = []
	lone.ticked.connect(func(d: float) -> void: deltas.append(d))
	assert_eq(lone.poll(), 0.0, "не запущен")
	lone.start()
	_now_usec += 1_500_000
	assert_almost_eq(lone.poll(), 1.5, 1e-9)
	assert_null(lone.session)
	assert_almost_eq(lone.delivered_sec, 1.5, 1e-9)
	assert_eq(deltas, [1.5])
	lone.attach(_session)
	_session.start()
	_now_usec += 1_000_000
	lone.poll()
	assert_eq(_session.samples.size(), 1, "после attach сессия получает время")


func test_req_nfr_02_time_scale_is_clamped_including_zero_and_negative() -> void:
	_ticker.set_time_scale(0.0)
	assert_eq(_ticker.time_scale, SessionTicker.MIN_TIME_SCALE, "0 → минимум (время не останавливается через scale)")
	_ticker.set_time_scale(-5.0)
	assert_eq(_ticker.time_scale, SessionTicker.MIN_TIME_SCALE)
	_ticker.set_time_scale(1e9)
	assert_eq(_ticker.time_scale, SessionTicker.MAX_TIME_SCALE)
	_ticker.set_time_scale(10.0)
	assert_eq(_ticker.time_scale, 10.0)
	_session.start()
	_ticker.start()
	assert_almost_eq(_advance_real(1.0), 10.0, 1e-9, "1 с реального = 10 с сессии")
	assert_eq(_session.samples.size(), 10)
	assert_almost_eq(_ticker.real_elapsed_sec, 1.0, 1e-9)
	assert_almost_eq(_ticker.delivered_sec, 10.0, 1e-9)


func test_req_nfr_02_stop_then_start_has_no_debt_and_no_delivery_while_stopped() -> void:
	_session.start()
	_ticker.start()
	_advance_real(2.0)
	_ticker.stop()
	assert_false(_ticker.is_running())
	_now_usec += 100_000_000
	assert_eq(_ticker.poll(), 0.0, "остановлен — ничего не доставляется")
	assert_eq(_session.samples.size(), 2)
	_ticker.start()
	assert_true(_ticker.is_running())
	assert_eq(_ticker.poll(), 0.0, "долг за 100 с не выплачивается")
	_advance_real(1.0)
	assert_eq(_session.samples.size(), 3, "после перезапуска доставлена только 1 с")
	assert_almost_eq(_ticker.delivered_sec, 3.0, 1e-9)


func test_req_nfr_02_huge_clock_jump_is_clamped_with_warning() -> void:
	_session.start()
	_ticker.start()
	var delivered := _advance_real(5000.0)
	assert_push_warning("скачок часов")
	assert_almost_eq(delivered, SessionTicker.MAX_DELTA_SEC, 1e-9)
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED, "план на 600 с завершён")
	assert_eq(_session.samples.size(), 600)


func test_req_nfr_02_default_clock_is_system_time_when_callable_invalid() -> void:
	var sys := SessionTicker.new(Callable())
	add_child_autofree(sys)
	sys.start()
	var d := sys.poll()
	assert_gte(d, 0.0)
	assert_lt(d, 1.0, "системные часы: с момента start прошло меньше секунды")


func test_req_nfr_02_in_tree_process_polls_injected_clock_without_manual_poll() -> void:
	_session.start()
	_ticker.start()
	_now_usec += 1_000_000
	await get_tree().process_frame
	await get_tree().process_frame
	assert_almost_eq(_ticker.delivered_sec, 1.0, 1e-6, "_process опросил подставленные часы")
	assert_eq(_session.samples.size(), 1)


func test_observation_two_tickers_on_one_session_double_the_session_time() -> void:
	# Критерием не запрещено; фиксируем поведение: каждый тикер доставляет своё реальное время.
	var second := SessionTicker.new(_clock)
	add_child_autofree(second)
	second.attach(_session)
	_session.start()
	_ticker.start()
	second.start()
	_now_usec += 5_000_000
	_ticker.poll()
	second.poll()
	assert_eq(_session.executor.elapsed_sec(), 10, "два тикера → сессия получила 2 × 5 с (наблюдение)")
	assert_eq(_session.samples.size(), 10)
