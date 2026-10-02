extends GutTest
## Тесты сглаживания мощности за 3 с (REQ-HUD-09).


func test_example_100_200_300_gives_200() -> void:
	var s := PowerSmoother.new()
	s.push(100)
	s.push(200)
	assert_eq(s.push(300), 200, "REQ-HUD-09 крит. 1")


func test_window_slides_then_300_gives_267() -> void:
	var s := PowerSmoother.new()
	s.push(100)
	s.push(200)
	s.push(300)
	assert_eq(s.push(300), 267, "(200+300+300)/3 = 266.67 → 267")
	assert_eq(s.sample_count(), 3)


func test_fewer_than_window_averages_available() -> void:
	var s := PowerSmoother.new()
	assert_eq(s.push(100), 100, "REQ-HUD-09 крит. 2")
	assert_eq(s.push(200), 150)


func test_missing_samples_excluded_from_average() -> void:
	var s := PowerSmoother.new()
	s.push(100)
	s.push_missing()
	assert_eq(s.push(300), 200, "пропуск не учитывается: (100+300)/2")
	assert_eq(s.sample_count(), 3)


func test_all_missing_gives_no_value() -> void:
	var s := PowerSmoother.new()
	assert_eq(s.value(), PowerSmoother.NO_VALUE, "пустое окно — нет значения")
	assert_false(s.has_value())
	s.push(250)
	assert_true(s.has_value())
	s.push_missing()
	s.push_missing()
	assert_eq(s.push_missing(), PowerSmoother.NO_VALUE, "REQ-HUD-09 крит. 3: все три — «—»")
	assert_false(s.has_value())


func test_missing_slot_pushes_old_samples_out_of_window() -> void:
	var s := PowerSmoother.new()
	s.push(100)
	s.push(200)
	s.push(300)
	s.push_missing()
	assert_eq(s.value(), 250, "100 выпал из окна: (200+300)/2")


func test_custom_window_size() -> void:
	var s := PowerSmoother.new(5)
	for p in [100, 200, 300, 400, 500]:
		s.push(p)
	assert_eq(s.value(), 300)
	assert_eq(s.push(600), 400, "(200+300+400+500+600)/5")
	var one := PowerSmoother.new(0)
	assert_eq(one.window_size, 1, "окно не меньше 1")
	one.push(100)
	assert_eq(one.push(300), 300)


func test_rounding_half_up() -> void:
	var s := PowerSmoother.new(2)
	s.push(100)
	assert_eq(s.push(101), 101, "100.5 → 101")


func test_reset_clears_window() -> void:
	var s := PowerSmoother.new()
	s.push(100)
	s.push(200)
	s.reset()
	assert_eq(s.sample_count(), 0)
	assert_false(s.has_value())
	assert_eq(s.push(50), 50)
