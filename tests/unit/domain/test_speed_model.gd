extends GutTest
## Тесты модели скорости SpeedModel (REQ-D3D-02 крит. 1–4; источник «модель» для REQ-WRK-08 крит. 5).


func test_reference_points_on_flat_road() -> void:
	assert_almost_eq(SpeedModel.steady_speed_kmh(200.0, 75.0), 34.0, 3.0, "200 Вт / 75 кг → 34 ± 3 км/ч")
	assert_almost_eq(SpeedModel.steady_speed_kmh(100.0, 75.0), 26.0, 3.0, "100 Вт → 26 ± 3")
	assert_almost_eq(SpeedModel.steady_speed_kmh(300.0, 75.0), 40.0, 3.0, "300 Вт → 40 ± 3")
	assert_lt(SpeedModel.steady_speed_kmh(200.0, 95.0), SpeedModel.steady_speed_kmh(200.0, 75.0), "тяжелее → медленнее")
	assert_eq(SpeedModel.from_power(200.0, 75.0), SpeedModel.steady_speed_kmh(200.0, 75.0))


func test_monotonic_in_power_and_mass() -> void:
	var prev: float = 0.0
	for p in range(0, 800, 25):
		var v := SpeedModel.steady_speed_kmh(float(p), 75.0)
		assert_true(v >= prev, "скорость не убывает с мощностью (%d Вт)" % p)
		prev = v
	prev = 1000.0
	for m in range(40, 160, 10):
		var v := SpeedModel.steady_speed_kmh(200.0, float(m))
		assert_true(v <= prev, "скорость не растёт с массой (%d кг)" % m)
		prev = v


func test_zero_or_negative_power_gives_zero_steady_speed() -> void:
	assert_eq(SpeedModel.steady_speed_kmh(0.0, 75.0), 0.0)
	assert_eq(SpeedModel.steady_speed_kmh(-50.0, 75.0), 0.0)


func test_power_required_matches_inverse() -> void:
	var v_kmh := SpeedModel.steady_speed_kmh(250.0, 80.0)
	assert_almost_eq(SpeedModel.power_required_w(v_kmh / 3.6, 88.0), 250.0, 0.01)


func test_coast_down_from_30_kmh_stops_within_30_seconds() -> void:
	var m := SpeedModel.new()
	m.reset(30.0)
	var stopped_at: int = -1
	for t in range(1, 31):
		var prev := m.speed_kmh
		m.step(0.0, 75.0, 1.0)
		assert_true(m.speed_kmh <= prev, "монотонно убывает")
		if m.speed_kmh == 0.0 and stopped_at < 0:
			stopped_at = t
	assert_true(stopped_at > 0 and stopped_at <= 30, "D3D-02 крит. 3: остановка за ≤ 30 с, факт %d" % stopped_at)


func test_step_change_limited_to_5_kmh_per_second() -> void:
	var m := SpeedModel.new()
	var prev: float = 0.0
	for t in 20:
		var v := m.step(400.0, 75.0, 1.0)
		assert_true(v - prev <= SpeedModel.MAX_DELTA_KMH_PER_SEC + 1e-6, "D3D-02 крит. 4: ≤ 5 км/ч за сэмпл (t=%d, Δ=%.2f)" % [t, v - prev])
		prev = v
	assert_gt(prev, 30.0, "за 20 с разогнался к установившейся")


func test_step_converges_to_steady_speed() -> void:
	var m := SpeedModel.new()
	for t in 60:
		m.step(200.0, 75.0, 1.0)
	assert_almost_eq(m.speed_kmh, SpeedModel.steady_speed_kmh(200.0, 75.0), 0.1)


func test_step_with_non_positive_dt_is_noop() -> void:
	var m := SpeedModel.new()
	m.reset(10.0)
	assert_eq(m.step(300.0, 75.0, 0.0), 10.0)
	assert_eq(m.step(300.0, 75.0, -1.0), 10.0)
