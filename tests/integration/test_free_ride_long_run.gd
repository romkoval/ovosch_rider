extends GutTest
## Долгие прогоны FreeRideSession на FakeTrainer: езда без лимита, оборачивание позиции,
## стык круга, набор за N кругов, частота команд SIM
## (REQ-FRD-07 крит. 1, 4; REQ-FRD-01 крит. 2; REQ-FRD-04 крит. 4, 5).

const WEIGHT: float = 75.0

var _ft: FakeTrainer
var _s: FreeRideSession


func before_each() -> void:
	_ft = FakeTrainer.new(11)
	_ft.connect_delay_sec = 0.0
	_ft.set_rider_power(250)
	_ft.connect_device("fake")


func after_each() -> void:
	if _s != null:
		_s.dispose()
		_s = null


static func _cmds(ft: FakeTrainer, type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in ft.commands:
		if str(c["type"]) == type:
			out.append(c)
	return out


func test_req_frd_07_c1_four_hours_250w_flat_no_limit_wraps_without_seam_jump() -> void:
	_s = FreeRideSession.new(_ft, RouteCatalog.FLAT, 50, WEIGHT, 250)
	_s.start()
	for i in 4 * 3600:
		_s.tick(1.0)
	assert_eq(_s.get_state(), WorkoutSession.State.RUNNING, "4 ч — сессия не завершилась сама")
	assert_eq(_s.elapsed_sec(), 4 * 3600)
	var st := _s.samples
	assert_eq(st.size(), 4 * 3600)
	var length: float = _s.route.profile.length_m()
	assert_gt(_s.distance_m(), 10.0 * length, "дистанция больше 10 кругов")
	assert_gt(_s.position.laps_completed(), 10)
	assert_lt(_s.position.s_m(), length, "s по модулю L")
	assert_gte(_s.position.s_m(), 0.0)
	var seams: int = 0
	var decreases: int = 0
	var max_seam_err: float = 0.0
	for i in range(1, st.size()):
		if st.distance_m[i] < st.distance_m[i - 1]:
			decreases += 1
		if floori(st.distance_m[i] / length) > floori(st.distance_m[i - 1] / length):
			seams += 1
			# Приращение высоты через стык — как по уклону, без скачка.
			var dd: float = st.distance_m[i] - st.distance_m[i - 1]
			var expected_dh: float = (st.grade_pct[i] + st.grade_pct[i - 1]) * 0.5 * dd / 100.0
			max_seam_err = maxf(max_seam_err, absf(st.altitude_m[i] - st.altitude_m[i - 1] - expected_dh))
	assert_eq(decreases, 0, "дистанция растёт монотонно")
	assert_eq(seams, _s.position.laps_completed(), "каждый стык круга пройден")
	assert_lte(max_seam_err, 0.1, "высота на стыке круга не прыгает больше 0.1 м")
	assert_eq(_cmds(_ft, FakeTrainer.CMD_TARGET_POWER).size(), 0, "Set Target Power ни разу за 4 ч")
	assert_eq(_ft.commands[0]["type"], FakeTrainer.CMD_SIM, "первая команда — SIM")


func test_req_frd_07_c4_ascent_of_n_laps_matches_route_ascent() -> void:
	var laps: int = 2
	_s = FreeRideSession.new(_ft, RouteCatalog.HILLS, 50, WEIGHT, 250)
	_s.start()
	var guard: int = 0
	while _s.position.laps_completed() < laps and guard < 6 * 3600:
		_s.tick(1.0)
		guard += 1
	assert_eq(_s.position.laps_completed(), laps, "проехано %d круга" % laps)
	_s.stop()
	var route_ascent: float = _s.route.profile.ascent_m()
	var ride_ascent: float = _s.samples.total_ascent_m()
	assert_almost_eq(ride_ascent, laps * route_ascent, 0.05 * laps * route_ascent,
		"набор %d кругов = N × набор трассы ± 5 %%" % laps)
	assert_almost_eq(float(_s.metadata()[FreeRideSession.META_TOTAL_ASCENT_M]), _s.position.ascent_m(), 1e-6)


func test_req_frd_04_c4_mountains_10min_sim_rate_limited() -> void:
	_s = FreeRideSession.new(_ft, RouteCatalog.MOUNTAINS, 100, WEIGHT, 250)
	_s.start()
	for i in 6000:
		_s.tick(0.1)
	var sims := _cmds(_ft, FakeTrainer.CMD_SIM)
	assert_gt(sims.size(), 1)
	assert_lte(sims.size(), 600, "команд 0x11 за 10 мин не больше 600")
	for i in range(1, sims.size()):
		var gap: float = float(sims[i]["at_sec"]) - float(sims[i - 1]["at_sec"])
		assert_gte(gap, 1.0 - 1e-6, "между командами SIM ≥ 1000 мс (%d)" % i)
	assert_eq(_cmds(_ft, FakeTrainer.CMD_TARGET_POWER).size(), 0)
