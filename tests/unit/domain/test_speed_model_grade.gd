extends GutTest
## Модель скорости с уклоном (REQ-FRD-04 крит. 7, 8; регрессия REQ-D3D-02 крит. 1–4 на уклоне 0).

const WEIGHT_KG: float = 75.0


func test_reference_points_with_grade() -> void:
	assert_almost_eq(SpeedModel.steady_speed_kmh(200.0, WEIGHT_KG, 0.0), 34.0, 3.0, "200 Вт, 0 % → 34 ± 3 км/ч")
	assert_almost_eq(SpeedModel.steady_speed_kmh(200.0, WEIGHT_KG, 5.0), 15.2, 1.5, "200 Вт, 5 % → 15.2 ± 1.5 км/ч")
	assert_almost_eq(SpeedModel.steady_speed_kmh(200.0, WEIGHT_KG, 10.0), 8.4, 1.0, "200 Вт, 10 % → 8.4 ± 1.0 км/ч")
	assert_almost_eq(SpeedModel.steady_speed_kmh(0.0, WEIGHT_KG, -5.0), 49.8, 3.0, "0 Вт, −5 % → 49.8 ± 3 км/ч")


func test_zero_grade_matches_flat_model_exactly() -> void:
	for p: float in [0.0, 50.0, 100.0, 200.0, 300.0, 600.0]:
		for w: float in [50.0, 75.0, 95.0]:
			assert_eq(SpeedModel.steady_speed_kmh(p, w, 0.0), SpeedModel.steady_speed_kmh(p, w),
				"на 0 %% — те же значения D3D-02 (%d Вт, %d кг)" % [int(p), int(w)])
	for v: float in [0.0, 3.0, 9.5, 15.0]:
		assert_eq(SpeedModel.power_required_w(v, 83.0, 0.0), SpeedModel.power_required_w(v, 83.0))


func test_power_required_is_inverse_with_grade() -> void:
	for g: float in [-8.0, -3.0, 2.0, 6.0, 12.0]:
		var v_kmh := SpeedModel.steady_speed_kmh(250.0, 80.0, g)
		assert_almost_eq(SpeedModel.power_required_w(v_kmh / 3.6, 88.0, g), 250.0, 0.01, "уклон %.1f %%" % g)


func test_monotonic_in_power_for_each_grade() -> void:
	for g: float in [-10.0, -5.0, -1.0, 0.0, 3.0, 8.0, 15.0]:
		var prev: float = -1.0
		for p in range(0, 800, 25):
			var v := SpeedModel.steady_speed_kmh(float(p), WEIGHT_KG, g)
			assert_true(v >= prev, "скорость не убывает по мощности (%d Вт, %.0f %%)" % [p, g])
			prev = v


func test_decreasing_in_grade() -> void:
	for p: float in [0.0, 100.0, 200.0, 400.0]:
		var prev: float = INF
		var g: float = -12.0
		while g <= 15.0:
			var v := SpeedModel.steady_speed_kmh(p, WEIGHT_KG, g)
			if v > 0.0:
				assert_lt(v, prev, "скорость убывает по уклону (%d Вт, %.1f %%)" % [int(p), g])
			else:
				assert_true(v <= prev, "скорость не растёт по уклону (%d Вт, %.1f %%)" % [int(p), g])
			prev = v
			g += 0.5


func test_decreasing_in_mass_on_climb_and_flat() -> void:
	for g: float in [0.0, 2.0, 5.0, 10.0]:
		var prev: float = INF
		for m in range(40, 160, 10):
			var v := SpeedModel.steady_speed_kmh(200.0, float(m), g)
			assert_lt(v, prev, "в подъём тяжелее → медленнее (%d кг, %.0f %%)" % [m, g])
			prev = v


func test_zero_power_on_climb_or_flat_gives_zero_speed() -> void:
	assert_eq(SpeedModel.steady_speed_kmh(0.0, WEIGHT_KG, 0.0), 0.0)
	assert_eq(SpeedModel.steady_speed_kmh(0.0, WEIGHT_KG, 5.0), 0.0)
	assert_eq(SpeedModel.steady_speed_kmh(-30.0, WEIGHT_KG, 5.0), 0.0)
	# Спуск положе сопротивления качению (Crr 0.004 ≈ 0.4 %) — без педалей не едет.
	assert_eq(SpeedModel.steady_speed_kmh(0.0, WEIGHT_KG, -0.3), 0.0)


func test_negative_power_treated_as_zero_on_descent() -> void:
	assert_eq(SpeedModel.steady_speed_kmh(-50.0, WEIGHT_KG, -5.0), SpeedModel.steady_speed_kmh(0.0, WEIGHT_KG, -5.0))


func test_step_converges_to_grade_steady_speed() -> void:
	var m := SpeedModel.new()
	for t in 60:
		m.step(200.0, WEIGHT_KG, 1.0, 5.0)
	assert_almost_eq(m.speed_kmh, SpeedModel.steady_speed_kmh(200.0, WEIGHT_KG, 5.0), 0.1)


func test_step_change_limited_on_grade_change() -> void:
	# Резкая смена уклона 10 % → −10 % и обратно при 300 Вт: изменение за сэмпл ≤ 5 км/ч (D3D-02 крит. 4).
	var m := SpeedModel.new()
	for t in 60:
		m.step(300.0, WEIGHT_KG, 1.0, 10.0)
	var prev := m.speed_kmh
	for t in 30:
		var v := m.step(300.0, WEIGHT_KG, 1.0, -10.0)
		assert_true(absf(v - prev) <= SpeedModel.MAX_DELTA_KMH_PER_SEC + 1e-6, "Δ = %.2f км/ч" % (v - prev))
		prev = v
	for t in 30:
		var v := m.step(300.0, WEIGHT_KG, 1.0, 10.0)
		assert_true(absf(v - prev) <= SpeedModel.MAX_DELTA_KMH_PER_SEC + 1e-6, "Δ = %.2f км/ч" % (v - prev))
		prev = v


func test_coast_down_on_flat_and_climb_stops_within_30_seconds() -> void:
	for g: float in [0.0, 3.0, 8.0]:
		var m := SpeedModel.new()
		m.reset(30.0)
		var stopped_at: int = -1
		for t in range(1, 31):
			var prev := m.speed_kmh
			m.step(0.0, WEIGHT_KG, 1.0, g)
			assert_true(m.speed_kmh <= prev, "монотонно убывает (%.0f %%)" % g)
			if m.speed_kmh == 0.0 and stopped_at < 0:
				stopped_at = t
		assert_true(stopped_at > 0 and stopped_at <= 30, "остановка за ≤ 30 с на %.0f %%, факт %d" % [g, stopped_at])


func test_coasting_downhill_accelerates_to_descent_speed() -> void:
	var m := SpeedModel.new()
	for t in 120:
		m.step(0.0, WEIGHT_KG, 1.0, -5.0)
	assert_almost_eq(m.speed_kmh, 49.8, 3.0, "накат на −5 % без педалей")


func test_full_grade_not_steepness_scaled() -> void:
	# FRD-04 крит. 8: модель берёт полный уклон; при крутизне 50 % станок получает 4 %,
	# а скорость считается как на 8 %.
	var full := SpeedModel.steady_speed_kmh(200.0, WEIGHT_KG, 8.0)
	var scaled := SpeedModel.steady_speed_kmh(200.0, WEIGHT_KG, 4.0)
	assert_lt(full, scaled - 3.0, "скорость на полном уклоне заметно ниже, чем на «сниженном»")
