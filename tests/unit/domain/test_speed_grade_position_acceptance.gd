extends GutTest
## Приёмка T-067 (tester): модель скорости с уклоном `SpeedModel` и позиция на трассе
## `RoutePosition`. REQ-FRD-04 крит. 2 (s — интеграл скорости по модулю L), крит. 7 (модель
## с уклоном: опорные значения, монотонность, ограничение изменения и торможение как
## D3D-02.3–4), крит. 8 (полный уклон, не сниженный крутизной); REQ-FRD-07 крит. 1
## (оборачивание s и монотонная дистанция на модели); регрессия REQ-D3D-02 крит. 1–4.
##
## Отличия от тестов разработчика: формула вводного абзаца FRD проверяется независимо
## (мощность, посчитанная тестом по найденной скорости, равна заданной) на сетке P × g × m,
## включая спуски; монотонность — на сетке, а не на паре точек; ограничение изменения —
## при резкой смене уклона в обе стороны и при скачке мощности на уклоне; торможение — на
## подъёмах разной крутизны; позиция — при переменной скорости и дробных dt против
## собственной суммы; 4 ч на «равнине» — по всем секундам, со стыком круга.

const W: float = 75.0
const RHO: float = 1.225
const CDA: float = 0.32
const CRR: float = 0.004
const G: float = 9.81


## Мощность по формуле вводного абзаца FRD: P = v·(m·g·(Crr·cos θ + sin θ) + ½·ρ·CdA·v²),
## θ = atan(g/100), m = вес + 8 кг. Считается тестом, не моделью.
static func _power_formula(v_kmh: float, weight_kg: float, grade_pct: float) -> float:
	var v: float = v_kmh / 3.6
	var m: float = weight_kg + 8.0
	var th: float = atan(grade_pct / 100.0)
	return v * (m * G * (CRR * cos(th) + sin(th)) + 0.5 * RHO * CDA * v * v)


# ---------------------------------------------------------------------------
# REQ-FRD-04 крит. 7 — опорные значения и формула
# ---------------------------------------------------------------------------

func test_req_frd_04_c7_reference_values_at_75kg() -> void:
	assert_almost_eq(SpeedModel.steady_speed_kmh(200.0, W, 0.0), 34.0, 3.0, "200 Вт, 0 %")
	assert_almost_eq(SpeedModel.steady_speed_kmh(200.0, W, 5.0), 15.2, 1.5, "200 Вт, 5 %")
	assert_almost_eq(SpeedModel.steady_speed_kmh(200.0, W, 10.0), 8.4, 1.0, "200 Вт, 10 %")
	assert_almost_eq(SpeedModel.steady_speed_kmh(0.0, W, -5.0), 49.8, 3.0, "0 Вт, −5 %")


func test_req_frd_04_c7_steady_speed_satisfies_power_equation_on_grid() -> void:
	var bad: Array[String] = []
	for p in [10.0, 50.0, 100.0, 200.0, 300.0, 450.0, 800.0]:
		for g in [-12.0, -8.0, -5.0, -2.0, -0.5, 0.0, 0.5, 2.0, 5.0, 8.0, 12.0, 20.0]:
			for m in [50.0, 75.0, 100.0]:
				var v: float = SpeedModel.steady_speed_kmh(p, m, g)
				var p_back: float = _power_formula(v, m, g)
				if absf(p_back - p) > 0.5:
					bad.append("P=%d g=%.1f m=%d: v=%.2f → P=%.2f" % [p, g, m, v, p_back])
	assert_eq(bad, [] as Array[String], "v(P, m, g) — корень уравнения вводного абзаца FRD")


func test_req_frd_04_c7_zero_power_descent_speed_satisfies_equation() -> void:
	for g in [-3.0, -5.0, -8.0, -12.0]:
		var v: float = SpeedModel.steady_speed_kmh(0.0, W, g)
		assert_gt(v, 0.0, "0 Вт на %.0f %% — накат ненулевой" % g)
		assert_almost_eq(_power_formula(v, W, g), 0.0, 0.5, "0 Вт на %.0f %%: сопротивление = скатывающей силе" % g)
	assert_eq(SpeedModel.steady_speed_kmh(0.0, W, -0.3), 0.0, "уклон −0.3 % слабее качения — стоим")


func test_req_frd_04_c7_monotonic_in_power_grade_and_mass_on_grid() -> void:
	var grades: Array[float] = [-10.0, -6.0, -3.0, -1.0, 0.0, 1.0, 3.0, 6.0, 10.0, 15.0]
	var powers: Array[float] = [0.0, 25.0, 50.0, 100.0, 150.0, 200.0, 300.0, 400.0, 600.0]
	var masses: Array[float] = [45.0, 60.0, 75.0, 90.0, 110.0]
	var bad: Array[String] = []
	for m in masses:
		for g in grades:
			for i in range(1, powers.size()):
				var a: float = SpeedModel.steady_speed_kmh(powers[i - 1], m, g)
				var b: float = SpeedModel.steady_speed_kmh(powers[i], m, g)
				if not (b > a or (b == a and b == 0.0)):
					bad.append("по P: m=%d g=%.0f P %d→%d: %.3f→%.3f" % [m, g, powers[i - 1], powers[i], a, b])
		for p in powers:
			for i in range(1, grades.size()):
				var a2: float = SpeedModel.steady_speed_kmh(p, m, grades[i - 1])
				var b2: float = SpeedModel.steady_speed_kmh(p, m, grades[i])
				if not (b2 < a2 or (b2 == a2 and b2 == 0.0)):
					bad.append("по g: m=%d P=%d g %.0f→%.0f: %.3f→%.3f" % [m, p, grades[i - 1], grades[i], a2, b2])
	for g in grades:
		if g <= 0.0:
			continue
		for p in powers:
			if p == 0.0:
				continue
			for i in range(1, masses.size()):
				var a3: float = SpeedModel.steady_speed_kmh(p, masses[i - 1], g)
				var b3: float = SpeedModel.steady_speed_kmh(p, masses[i], g)
				if not (b3 < a3):
					bad.append("по m в подъём: g=%.0f P=%d m %d→%d: %.3f→%.3f" % [g, p, masses[i - 1], masses[i], a3, b3])
	assert_eq(bad, [] as Array[String], "растёт по P, убывает по g, в подъём убывает по m")


# ---------------------------------------------------------------------------
# REQ-FRD-04 крит. 7 — ограничение изменения за сэмпл и торможение (как D3D-02.3–4)
# ---------------------------------------------------------------------------

func test_req_frd_04_c7_change_per_sample_at_most_5_kmh_on_grade_jumps() -> void:
	var cases: Array = [
		# [мощность, уклон до, уклон после, описание]
		[200.0, -10.0, 10.0, "спуск −10 % → подъём +10 %"],
		[200.0, 10.0, -10.0, "подъём +10 % → спуск −10 %"],
		[0.0, -12.0, 0.0, "накат с −12 % на ровное"],
		[400.0, 15.0, -8.0, "400 Вт: +15 % → −8 %"],
	]
	for c in cases:
		var m := SpeedModel.new()
		for i in 120:
			m.step(c[0], W, 1.0, c[1])
		var prev: float = m.speed_kmh
		var max_delta: float = 0.0
		for i in 120:
			var v: float = m.step(c[0], W, 1.0, c[2])
			max_delta = maxf(max_delta, absf(v - prev))
			prev = v
		assert_lte(max_delta, 5.0 + 1e-6, "%s: изменение за сэмпл %.2f км/ч" % [c[3], max_delta])
		assert_almost_eq(m.speed_kmh, SpeedModel.steady_speed_kmh(c[0], W, c[2]), 0.3,
			"%s: за 120 с выходит на установившуюся" % c[3])


func test_req_frd_04_c7_power_jump_0_to_400_on_grades_limited_to_5_kmh() -> void:
	for g in [-6.0, 0.0, 4.0, 9.0]:
		var m := SpeedModel.new()
		for i in 60:
			m.step(0.0, W, 1.0, g)
		var prev: float = m.speed_kmh
		for i in 60:
			var v: float = m.step(400.0, W, 1.0, g)
			assert_lte(absf(v - prev), 5.0 + 1e-6, "g=%.0f %%, сэмпл %d: %.2f → %.2f" % [g, i, prev, v])
			prev = v


func test_req_frd_04_c7_zero_power_from_30_kmh_stops_within_30_s_monotonically_on_flat_and_climbs() -> void:
	for g in [0.0, 1.0, 3.0, 6.0, 12.0]:
		var m := SpeedModel.new()
		m.reset(30.0)
		var prev: float = 30.0
		var stopped_at: int = -1
		for i in range(1, 61):
			var v: float = m.step(0.0, W, 1.0, g)
			assert_lte(v, prev + 1e-9, "g=%.0f %%: скорость не растёт (с %d)" % [g, i])
			prev = v
			if v == 0.0 and stopped_at < 0:
				stopped_at = i
		assert_between(stopped_at, 1, 30, "g=%.0f %%: остановка за %d с" % [g, stopped_at])


func test_req_frd_04_c7_step_with_fractional_dt_still_limited_and_converges() -> void:
	# Сцена/сессия могут шагать дробными dt: ограничение 5 км/ч за секунду не превышается.
	var m := SpeedModel.new()
	var t: float = 0.0
	var last_whole: float = 0.0
	var at_whole: float = 0.0
	while t < 60.0 - 1e-9:
		m.step(400.0, W, 0.25, 0.0)
		t += 0.25
		if absf(t - roundf(t)) < 1e-6:
			assert_lte(absf(m.speed_kmh - at_whole), 5.0 + 1e-6, "за секунду до %.0f с" % t)
			at_whole = m.speed_kmh
			last_whole = t
	assert_eq(last_whole, 60.0)
	assert_almost_eq(m.speed_kmh, SpeedModel.steady_speed_kmh(400.0, W, 0.0), 0.5)


# ---------------------------------------------------------------------------
# REQ-FRD-04 крит. 8 — модель берёт полный уклон
# ---------------------------------------------------------------------------

func test_req_frd_04_c8_free_ride_speed_does_not_depend_on_steepness() -> void:
	# Одна и та же трасса и мощность при крутизне 0 и 100 %: скорость, дистанция и высота
	# в каждом сэмпле совпадают — крутизна влияет только на нагрузку станка.
	var runs: Array[FreeRideSession] = []
	for k in [0, 100]:
		var ft := FakeTrainer.new(7)
		ft.connect_delay_sec = 0.0
		ft.power_noise_w = 0.0
		ft.set_rider_power(220)
		ft.connect_device("fake")
		var s := FreeRideSession.new(ft, RouteCatalog.MOUNTAINS, k, W, 250)
		s.start()
		for i in 2400:
			s.tick(1.0)
		runs.append(s)
	var a := runs[0].samples
	var b := runs[1].samples
	assert_eq(a.size(), b.size())
	var diff: int = 0
	for i in a.size():
		if absf(a.speed_kmh[i] - b.speed_kmh[i]) > 1e-4 or absf(a.distance_m[i] - b.distance_m[i]) > 1e-3:
			diff += 1
	assert_eq(diff, 0, "k = 0 % и k = 100 %: сэмплов с разной скоростью/дистанцией")
	# И скорость равна модели с ПОЛНЫМ уклоном позиции (а не g · k / 100).
	var profile: RouteProfile = RouteCatalog.get_route(RouteCatalog.MOUNTAINS).profile
	var ref := SpeedModel.new()
	var dist: float = 0.0
	var max_err: float = 0.0
	for i in a.size():
		var g: float = profile.grade_at(fposmod(dist, profile.length_m()))
		var v: float = ref.step(float(a.power_w[i]) if a.has_power[i] else 0.0, W, 1.0, g)
		dist += v / 3.6
		max_err = maxf(max_err, absf(v - a.speed_kmh[i]))
	assert_lt(max_err, 1e-3, "скорость сессии = SpeedModel со 100 %% уклона трассы (макс. расхождение %.5f)" % max_err)
	for s in runs:
		s.dispose()


# ---------------------------------------------------------------------------
# REQ-FRD-04 крит. 2 — s как интеграл скорости по модулю L
# ---------------------------------------------------------------------------

func test_req_frd_04_c2_position_is_integral_of_variable_speed_modulo_length() -> void:
	var profile: RouteProfile = RouteCatalog.get_route(RouteCatalog.SEASIDE).profile
	var L: float = profile.length_m()
	var pos := RoutePosition.new(profile)
	var total: float = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 20000:
		var v: float = rng.randf_range(0.0, 70.0)
		var dt: float = [0.1, 0.25, 1.0, 1.7][i % 4]
		pos.advance(v, dt)
		total += v / 3.6 * dt
	assert_almost_eq(pos.distance_m(), total, 1e-3 * maxf(total / 1000.0, 1.0), "дистанция = Σ v·dt")
	assert_almost_eq(pos.s_m(), fposmod(total, L), 0.01, "s = Σ v·dt mod L")
	assert_gt(total, 3.0 * L, "проехали больше трёх кругов")
	assert_eq(pos.laps_completed(), floori(total / L))
	assert_almost_eq(pos.height_m(), profile.height_at(pos.s_m()), 1e-9, "h(s) — из профиля")
	assert_almost_eq(pos.grade_pct(), profile.grade_at(pos.s_m()), 1e-9, "g(s) — полный уклон профиля")


func test_req_frd_04_c2_start_offset_and_exact_lap_boundary() -> void:
	var profile: RouteProfile = RouteCatalog.get_route(RouteCatalog.FLAT).profile
	var L: float = profile.length_m()
	var pos := RoutePosition.new(profile, L - 5.0)
	assert_almost_eq(pos.s_m(), L - 5.0, 1e-9)
	pos.advance(36.0, 1.0)  # +10 м: через стык
	assert_almost_eq(pos.s_m(), 5.0, 1e-6, "s оборачивается через стык от точки старта")
	assert_almost_eq(pos.distance_m(), 10.0, 1e-9, "дистанция — от старта, не по кругу")
	var exact := RoutePosition.new(profile)
	exact.advance(L * 3.6, 1.0)  # ровно один круг
	assert_almost_eq(exact.s_m(), 0.0, 1e-6, "ровно L → s = 0")
	assert_eq(exact.laps_completed(), 1)


# ---------------------------------------------------------------------------
# REQ-FRD-07 крит. 1 — 4 ч при 250 Вт на «равнине»: без конца трассы, стык без скачка
# ---------------------------------------------------------------------------

func test_req_frd_07_c1_four_hours_250w_flat_model_wraps_monotonic_seam_without_jump() -> void:
	var profile: RouteProfile = RouteCatalog.get_route(RouteCatalog.FLAT).profile
	var L: float = profile.length_m()
	var model := SpeedModel.new()
	var pos := RoutePosition.new(profile)
	var prev_dist: float = 0.0
	var prev_s: float = pos.s_m()
	var prev_h: float = pos.height_m()
	var wraps: int = 0
	var worst_seam: float = 0.0
	var non_monotonic: int = 0
	var out_of_lap: int = 0
	for t in 4 * 3600:
		var v: float = model.step(250.0, W, 1.0, pos.grade_pct())
		var moved: float = pos.advance(v, 1.0)
		if pos.distance_m() < prev_dist:
			non_monotonic += 1
		if pos.s_m() < 0.0 or pos.s_m() >= L:
			out_of_lap += 1
		if pos.s_m() < prev_s:
			wraps += 1
			# Скачок высоты на стыке сверх изменения, объяснимого уклоном на пройденном отрезке.
			var expected: float = absf(profile.grade_at(0.0)) / 100.0 * moved
			worst_seam = maxf(worst_seam, absf(pos.height_m() - prev_h) - expected)
		prev_dist = pos.distance_m()
		prev_s = pos.s_m()
		prev_h = pos.height_m()
	assert_gt(pos.distance_m(), 10.0 * L, "4 ч при 250 Вт: дистанция %.0f м > 10 L" % pos.distance_m())
	assert_eq(non_monotonic, 0, "дистанция не убывает")
	assert_eq(out_of_lap, 0, "s всегда в [0; L)")
	assert_eq(wraps, pos.laps_completed(), "s обернулась на каждом круге")
	assert_lte(worst_seam, 0.1, "скачок высоты на стыке сверх уклона: %.3f м" % worst_seam)
	assert_lte(absf(profile.height_at(L - 1e-6) - profile.height_at(0.0)), 0.1, "|h(L) − h(0)| ≤ 0.1 м")


# ---------------------------------------------------------------------------
# Регрессия REQ-D3D-02 крит. 1–4 (уклон 0 — прежняя модель)
# ---------------------------------------------------------------------------

func test_req_d3d_02_c1_c2_flat_reference_values_and_monotonicity() -> void:
	assert_almost_eq(SpeedModel.from_power(200.0, 75.0), 34.0, 3.0)
	assert_almost_eq(SpeedModel.from_power(100.0, 75.0), 26.0, 3.0)
	assert_almost_eq(SpeedModel.from_power(300.0, 75.0), 40.0, 3.0)
	assert_lt(SpeedModel.from_power(200.0, 95.0), SpeedModel.from_power(200.0, 75.0))
	assert_eq(SpeedModel.from_power(200.0, 75.0), SpeedModel.steady_speed_kmh(200.0, 75.0, 0.0),
		"вызов без уклона = уклон 0")
	var prev: float = -1.0
	for p in range(0, 1001, 25):
		var v: float = SpeedModel.from_power(float(p), 75.0)
		assert_true(v > prev or (p == 0 and v == 0.0), "растёт по P: %d Вт → %.3f" % [p, v])
		prev = v


func test_req_d3d_02_c3_c4_flat_decay_and_jump_limit() -> void:
	var m := SpeedModel.new()
	m.reset(30.0)
	var stopped: int = -1
	for i in range(1, 31):
		if m.step(0.0, 75.0, 1.0) == 0.0 and stopped < 0:
			stopped = i
	assert_between(stopped, 1, 30, "0 Вт с 30 км/ч — 0 за %d с" % stopped)
	var m2 := SpeedModel.new()
	var prev: float = 0.0
	for i in 40:
		var v: float = m2.step(400.0, 75.0, 1.0)
		assert_lte(v - prev, 5.0 + 1e-6, "скачок 0 → 400 Вт: сэмпл %d" % i)
		prev = v
