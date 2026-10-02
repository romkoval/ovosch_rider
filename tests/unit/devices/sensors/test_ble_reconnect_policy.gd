extends GutTest
## Тесты политики переподключения (REQ-DEV-08 крит. 1, решение 12).


func test_inactive_until_start() -> void:
	var p := BleReconnectPolicy.new(5.0)
	assert_false(p.active)
	assert_false(p.due(100.0))
	assert_eq(p.attempts, 0)


func test_first_attempt_immediate_then_every_interval() -> void:
	var p := BleReconnectPolicy.new(5.0)
	p.start(10.0)
	assert_true(p.due(10.0), "сразу")
	assert_false(p.due(14.9))
	assert_true(p.due(15.0))
	assert_false(p.due(19.0))
	assert_true(p.due(20.0))
	assert_eq(p.attempts, 3)
	assert_almost_eq(p.next_attempt_sec(), 25.0, 1e-9)


func test_stop_and_restart_resets_attempts() -> void:
	var p := BleReconnectPolicy.new(2.0)
	p.start(0.0)
	p.due(0.0)
	p.stop()
	assert_eq(p.attempts, 0, "stop() сбрасывает счётчик")
	assert_false(p.due(10.0))
	p.start(10.0)
	assert_eq(p.attempts, 0)
	assert_true(p.due(10.0))
	assert_true(p.due(12.0))
