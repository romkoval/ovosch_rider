extends GutTest
## Приёмка T-077 (tester): `FreeRideSession` — сессия свободной езды без плана и контракт
## записи `RideRecorder`. REQ-FRD-01 крит. 1–3; REQ-FRD-04 крит. 5 (старт, пауза,
## переподключение), крит. 9 (скорость — модель, согласованность позиции, дистанции и
## уклона станка); REQ-FRD-05 крит. 5, 6; REQ-FRD-07 крит. 1–4.
##
## Отличия от тестов разработчика: две одинаковые сессии (одна с переключениями режима и
## крутизны) сравниваются посэмплово; обрыв связи начинается до паузы и заканчивается на
## паузе; станок пропадает насовсем — сессия сама не завершается; одна дельта на час;
## каждая команда SIM сверяется с уклоном позиции в её момент; набор N кругов — на всех
## четырёх трассах; запись — шпион `RideRepository.save` и чтение заезда с диска.
##
## Видимость режима и крутизны на HUD (FRD-05.6 вторая половина) — T-084, здесь только
## состояние сессии.

const W: float = 75.0
const FTP: int = 250
const EPS: float = 1e-6


class SpyRepository extends FileRideRepository:
	var save_calls: int = 0
	var saved_in_progress: Array[bool] = []

	func save(ride: Ride) -> String:
		save_calls += 1
		saved_in_progress.append(bool(ride.metadata.get("in_progress", false)))
		return super.save(ride)


var _dir: String = ""
var _sessions: Array[FreeRideSession] = []


func after_each() -> void:
	for s in _sessions:
		s.dispose()
	_sessions.clear()
	if not _dir.is_empty():
		_remove_tree(ProjectSettings.globalize_path(_dir))
		_dir = ""


static func _remove_tree(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	var d := DirAccess.open(abs_path)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(abs_path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(abs_path.path_join(sub))
	DirAccess.remove_absolute(abs_path)


static func _trainer(seed: int = 21, power: int = 250) -> FakeTrainer:
	var ft := FakeTrainer.new(seed)
	ft.connect_delay_sec = 0.0
	ft.set_rider_power(power)
	ft.connect_device("fake")
	return ft


func _session(ft: FakeTrainer, route: String = RouteCatalog.HILLS, k: int = 50,
		mode: SimController.Mode = SimController.Mode.SIM, level: int = 50) -> FreeRideSession:
	var s := FreeRideSession.new(ft, route, k, W, FTP, mode, level)
	_sessions.append(s)
	return s


static func _run(s: FreeRideSession, sec: float, dt: float = 0.25) -> void:
	for i in roundi(sec / dt):
		s.tick(dt)


static func _cmds(ft: FakeTrainer, type: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in ft.commands:
		if type.is_empty() or c["type"] == type:
			out.append(c)
	return out


static func _events(s: FreeRideSession, type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in s.events:
		if e["type"] == type:
			out.append(e)
	return out


# ---------------------------------------------------------------------------
# REQ-FRD-01 крит. 1–3
# ---------------------------------------------------------------------------

func test_req_frd_01_c1_no_executor_no_step_events_no_targets() -> void:
	var ft := _trainer()
	var s := _session(ft, RouteCatalog.SEASIDE)
	assert_false("executor" in s, "у сессии свободной езды нет исполнителя интервалов")
	s.start()
	_run(s, 300.0)
	s.toggle_mode()
	_run(s, 30.0)
	s.toggle_mode()
	s.pause()
	_run(s, 5.0)
	s.resume()
	_run(s, 30.0)
	s.stop()
	var allowed: Array[String] = [WorkoutSession.EVENT_START, WorkoutSession.EVENT_PAUSE, WorkoutSession.EVENT_RESUME,
		WorkoutSession.EVENT_STOP, WorkoutSession.EVENT_FINISH, WorkoutSession.EVENT_DISCONNECT,
		WorkoutSession.EVENT_RECONNECT, SimController.EVENT_MODE, SimController.EVENT_STEEPNESS,
		SimController.EVENT_RESISTANCE, FreeRideSession.EVENT_SIM_UNAVAILABLE]
	for e in s.events:
		assert_true(allowed.has(str(e["type"])), "событие %s — не событие шага плана" % e["type"])
	for i in s.samples.size():
		if s.samples.step_index[i] != -1 or s.samples.target_w[i] != 0:
			fail_test("сэмпл %d: шаг %d, цель %d" % [i, s.samples.step_index[i], s.samples.target_w[i]])
			return
	assert_eq(_cmds(ft, FakeTrainer.CMD_TARGET_POWER).size(), 0, "цели мощности нет")


func test_req_frd_01_c2_no_target_power_through_dropouts_pause_and_mode_switches() -> void:
	var ft := _trainer()
	var s := _session(ft, RouteCatalog.MOUNTAINS, 70)
	s.start()
	assert_eq(_cmds(ft)[0]["type"], FakeTrainer.CMD_SIM, "первая команда — 0x11")
	for round in 6:
		_run(s, 120.0)
		ft.inject_dropout(3.0 + round)
		_run(s, 10.0)
		s.toggle_mode()
		_run(s, 20.0)
		s.set_resistance_level(30 + round * 10)
		s.toggle_mode()
		s.pause()
		_run(s, 4.0)
		s.resume()
	assert_eq(_cmds(ft, FakeTrainer.CMD_TARGET_POWER).size(), 0, "Set Target Power — ни одной")
	for c in _cmds(ft, FakeTrainer.CMD_ERG):
		assert_false(bool(c["value"]), "ERG не включается")


func test_req_frd_01_c3_session_has_no_network_dependency() -> void:
	# Сессия не принимает и не создаёт сетевых клиентов: в её коде нет HTTP и интеграций.
	var code := FileAccess.get_file_as_string("res://src/session/free_ride_session.gd")
	for needle in ["HTTPRequest", "HTTPClient", "IntervalsClient", "Intervals", "Strava", "HttpTransport"]:
		assert_false(code.contains(needle), "free_ride_session.gd не ссылается на %s" % needle)
	var http := MockHttpTransport.new()
	http.offline = true
	var s := _session(_trainer())
	s.start()
	_run(s, 20.0)
	assert_eq(s.get_state(), WorkoutSession.State.RUNNING)
	assert_eq(s.samples.size(), 20)
	assert_eq(http.requests.size(), 0)


# ---------------------------------------------------------------------------
# REQ-FRD-04 крит. 5 — старт, возобновление, переподключение (в т.ч. обрыв на паузе)
# ---------------------------------------------------------------------------

func test_req_frd_04_c5_dropout_spanning_pause_sends_nothing_until_resume_then_within_1s() -> void:
	var ft := _trainer()
	var s := _session(ft, RouteCatalog.HILLS, 50)
	s.start()
	_run(s, 60.0)
	ft.inject_dropout(8.0)
	_run(s, 2.0)
	s.pause()
	var n: int = ft.commands.size()
	var dist: float = s.distance_m()
	var elapsed: int = s.elapsed_sec()
	var samples: int = s.samples.size()
	_run(s, 15.0)  # связь восстановилась на паузе
	assert_eq(ft.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	s.set_steepness(80)
	_run(s, 5.0)
	assert_eq(ft.commands.size(), n, "на паузе (и при восстановлении на паузе) команд нет")
	assert_eq(s.distance_m(), dist, "на паузе дистанция стоит")
	assert_eq(s.elapsed_sec(), elapsed, "на паузе время стоит")
	assert_eq(s.samples.size(), samples, "на паузе сэмплов нет")
	var t_resume: float = ft.get_time_sec()
	# Уклон позиции в момент возобновления (позиция на паузе стоит).
	var expected: float = SimController.transmitted_grade(s.route_grade_pct(), 80, ft.inclination_range())
	s.resume()
	_run(s, 1.0)
	var after := ft.commands.slice(n)
	assert_gte(after.size(), 1, "после возобновления команда ушла")
	if after.size() >= 1:
		assert_eq(after[0]["type"], FakeTrainer.CMD_SIM)
		assert_almost_eq(float(after[0]["value"]), expected, 0.0101, "текущий уклон с новой крутизной 80 %")
		assert_lte(float(after[0]["at_sec"]) - t_resume, 1.0 + EPS)
	assert_eq(_events(s, WorkoutSession.EVENT_RECONNECT).size(), 1, "восстановление записано")
	assert_eq(_events(s, WorkoutSession.EVENT_DISCONNECT).size(), 1, "обрыв записан")


func test_req_frd_04_c5_reconnect_while_running_resends_within_1s() -> void:
	var ft := _trainer()
	var s := _session(ft, RouteCatalog.FLAT, 50)
	s.start()
	_run(s, 30.0)
	var n_sim: int = _cmds(ft, FakeTrainer.CMD_SIM).size()
	ft.inject_dropout(5.0)
	var back_at: float = ft.get_time_sec() + 5.0
	_run(s, 7.0)
	var sims := _cmds(ft, FakeTrainer.CMD_SIM)
	var resent: Array[Dictionary] = []
	for i in range(n_sim, sims.size()):
		if float(sims[i]["at_sec"]) >= back_at - EPS:
			resent.append(sims[i])
	assert_gte(resent.size(), 1, "после восстановления уклон отправлен заново (без порога)")
	if resent.size() >= 1:
		assert_lte(float(resent[0]["at_sec"]) - back_at, 1.0 + EPS)


# ---------------------------------------------------------------------------
# REQ-FRD-04 крит. 9 — модель, а не скорость станка; согласованность с командами SIM
# ---------------------------------------------------------------------------

func test_req_frd_04_c9_every_sim_command_matches_grade_of_position_at_that_moment() -> void:
	var ft := _trainer(4, 280)
	ft.emit_speed = true  # станок даёт свою скорость — сессия её не берёт
	var s := _session(ft, RouteCatalog.MOUNTAINS, 60)
	s.start()
	_run(s, 1800.0)
	var st := s.samples
	# Скорость станка FakeTrainer — k·∛P (34 км/ч при 200 Вт) без уклона; на подъёме модель
	# с уклоном заметно медленнее. Ни один сэмпл на подъёме > 3 % не равен скорости станка.
	var trainer_speed_used: int = 0
	var climb_samples: int = 0
	for i in st.size():
		if st.grade_pct[i] > 3.0 and st.has_power[i]:
			climb_samples += 1
			var trainer_kmh: float = FakeTrainer.SPEED_COEFF * pow(float(st.power_w[i]), 1.0 / 3.0)
			if absf(st.speed_kmh[i] - trainer_kmh) < 3.0:
				trainer_speed_used += 1
	assert_gt(climb_samples, 300, "в подъёме больше 5 мин")
	assert_eq(trainer_speed_used, 0, "скорость сэмплов в подъём — не скорость станка (модель с уклоном)")
	var bad: Array[String] = []
	for c in _cmds(ft, FakeTrainer.CMD_SIM):
		var t: float = float(c["at_sec"])
		# Сессия и станок стартовали вместе: секунда t закрыта → позиция = сэмпл t − 1.
		var idx: int = clampi(floori(t + EPS) - 1, -1, st.size() - 1)
		var g: float = st.grade_pct[idx] if idx >= 0 else s.route.profile.grade_at(0.0)
		var expected: float = SimController.transmitted_grade(g, 60, ft.inclination_range())
		if absf(float(c["value"]) - expected) > 0.0101:
			bad.append("t=%.2f: ушло %.2f, по позиции %.2f" % [t, float(c["value"]), expected])
	assert_eq(bad, [] as Array[String], "уклон станка = g(позиции сэмпла) × k")
	assert_eq(st.speed_source, SampleStream.SPEED_SOURCE_MODEL)
	# Позиция и дистанция — один интеграл.
	assert_almost_eq(s.position.s_m(), fposmod(st.distance_m[st.size() - 1], s.route.profile.length_m()), 0.05)


# ---------------------------------------------------------------------------
# REQ-FRD-05 крит. 5, 6 — переключения не трогают таймер, запись и позицию; события
# ---------------------------------------------------------------------------

func test_req_frd_05_c5_switches_do_not_change_timer_samples_position_compared_to_twin_session() -> void:
	var ft_a := _trainer(77, 230)
	var ft_b := _trainer(77, 230)
	var a := _session(ft_a, RouteCatalog.HILLS, 50)
	var b := _session(ft_b, RouteCatalog.HILLS, 50)
	a.start()
	b.start()
	for sec in 1500:
		for i in 4:
			a.tick(0.25)
			b.tick(0.25)
			if sec % 37 == 5 and i == 1:
				b.toggle_mode()
			if sec % 53 == 11 and i == 2:
				b.set_steepness([0, 25, 50, 75, 100][sec % 5])
			if sec % 41 == 7 and i == 3:
				b.set_resistance_level(20 + sec % 60)
		if sec == 700:
			assert_true(b.position.s_m() == a.position.s_m(), "в момент переключений позиция та же")
	assert_eq(b.elapsed_sec(), a.elapsed_sec(), "таймер не останавливается")
	assert_eq(b.samples.size(), a.samples.size(), "запись не прерывается")
	var diff: Array[String] = []
	for i in a.samples.size():
		if a.samples.time_sec[i] != b.samples.time_sec[i] or absf(a.samples.distance_m[i] - b.samples.distance_m[i]) > 1e-3 \
				or absf(a.samples.speed_kmh[i] - b.samples.speed_kmh[i]) > 1e-4 \
				or absf(a.samples.altitude_m[i] - b.samples.altitude_m[i]) > 1e-4:
			diff.append("сэмпл %d" % i)
	assert_eq(diff.slice(0, 5), [] as Array[String], "сэмплы с переключениями = без переключений (FIXED считает уклон)")
	assert_gt(_events(b, SimController.EVENT_MODE).size(), 30, "переключений было много")


func test_req_frd_05_c6_each_switch_logged_with_session_time_and_state_visible() -> void:
	var ft := _trainer()
	var s := _session(ft, RouteCatalog.FLAT, 50, SimController.Mode.SIM, 40)
	s.start()
	_run(s, 10.5)
	s.toggle_mode()
	assert_eq(s.mode(), SimController.Mode.FIXED, "режим для HUD — FIXED")
	_run(s, 5.0)
	s.set_resistance_level(60)
	assert_eq(s.resistance_level(), 60)
	_run(s, 4.5)
	s.toggle_mode()
	s.set_steepness(75)
	assert_eq(s.mode(), SimController.Mode.SIM)
	assert_eq(s.steepness_pct(), 75, "крутизна для HUD")
	var got: Array = []
	for e in s.events:
		if str(e["type"]) in [SimController.EVENT_MODE, SimController.EVENT_STEEPNESS, SimController.EVENT_RESISTANCE]:
			got.append([e["type"], e["value"], snappedf(float(e["at_sec"]), 0.01)])
	assert_eq(got, [
		[SimController.EVENT_MODE, "fixed", 10.5],
		[SimController.EVENT_RESISTANCE, 60, 15.5],
		[SimController.EVENT_MODE, "sim", 20.0],
		[SimController.EVENT_STEEPNESS, 75, 20.0],
	], "каждое переключение — событие заезда со временем сессии")


# ---------------------------------------------------------------------------
# REQ-FRD-07 крит. 1, 2 — без лимита, только ручное завершение, пауза
# ---------------------------------------------------------------------------

func test_req_frd_07_c1_trainer_lost_for_good_does_not_finish_session() -> void:
	var ft := _trainer()
	var s := _session(ft, RouteCatalog.FLAT)
	var finished: Array[int] = []
	s.state_changed.connect(func(st: int) -> void: finished.append(st))
	s.start()
	_run(s, 60.0)
	ft.disconnect_device()
	_run(s, 600.0, 1.0)
	assert_eq(s.get_state(), WorkoutSession.State.RUNNING, "станок пропал — сессия не завершается сама")
	assert_false(finished.has(WorkoutSession.State.FINISHED))
	assert_eq(s.elapsed_sec(), 660, "время идёт")
	assert_eq(s.samples.size(), 660, "сэмплы «нет данных» пишутся")


func test_req_frd_07_c1_one_hour_single_tick_and_mixed_dt_are_sliced_into_seconds() -> void:
	var s := _session(_trainer(), RouteCatalog.FLAT)
	s.start()
	s.tick(3600.0)
	assert_eq(s.elapsed_sec(), 3600)
	assert_eq(s.samples.size(), 3600)
	for dt in [0.016, 0.033, 0.1, 0.5, 1.3]:
		for i in 200:
			s.tick(dt)
	var total: float = 3600.0 + 200.0 * (0.016 + 0.033 + 0.1 + 0.5 + 1.3)
	assert_eq(s.elapsed_sec(), floori(total + 1e-6), "целые секунды активного времени")
	assert_eq(s.samples.size(), s.elapsed_sec())
	for i in s.samples.size():
		if s.samples.time_sec[i] != i:
			fail_test("сэмпл %d с меткой %d" % [i, s.samples.time_sec[i]])
			return
	assert_eq(s.get_state(), WorkoutSession.State.RUNNING)


func test_req_frd_07_c2_pause_mid_second_freezes_and_resume_continues_without_gap() -> void:
	var ft := _trainer()
	var s := _session(ft, RouteCatalog.HILLS)
	s.start()
	_run(s, 30.0)
	s.tick(0.6)
	s.pause()
	var t: float = s.session_time_sec()
	_run(s, 20.0)
	assert_almost_eq(s.session_time_sec(), t, EPS, "на паузе время не идёт")
	s.resume()
	s.tick(0.4)
	assert_eq(s.elapsed_sec(), 31, "доля секунды до паузы учтена")
	_run(s, 10.0)
	assert_eq(s.elapsed_sec(), 41)
	assert_true(s.samples.is_monotonic())
	assert_eq(s.samples.time_sec[s.samples.size() - 1], 40, "без пропусков и повторов")
	var pauses := _events(s, WorkoutSession.EVENT_PAUSE)
	assert_eq(pauses.size(), 1)
	assert_almost_eq(float(pauses[0].get("duration_sec", -1.0)), 20.0, 1e-3, "длительность паузы")
	assert_almost_eq(float(s.metadata()["paused_total_sec"]), 20.0, 1e-3)


func test_req_frd_07_c2_stop_only_explicit_and_saved_via_repository_save_after_stop() -> void:
	_dir = "user://acc_free_ride_%d/" % Time.get_ticks_usec()
	var repo := SpyRepository.new(_dir + "rides/")
	var profile := Profile.create("Тест")
	var ft := _trainer()
	var s := _session(ft, RouteCatalog.SEASIDE, 40)
	var rec := RideRecorder.new(repo, profile, s)
	s.start()
	_run(s, 3 * 3600.0, 1.0)
	assert_eq(s.get_state(), WorkoutSession.State.RUNNING, "3 ч — сессия идёт")
	assert_true(rec.is_recording())
	var saves_before_stop: int = repo.save_calls
	assert_true(repo.saved_in_progress.all(func(v: bool) -> bool: return v), "до stop() — только записи «в процессе»")
	var on_disk := FileRideRepository.new(_dir + "rides/").get_ride(rec.ride_id())
	assert_not_null(on_disk)
	if on_disk != null:
		assert_true(on_disk.is_in_progress(), "во время езды заезд на диске помечен «в процессе»")
		assert_gte(on_disk.samples.size(), 3 * 3600 - 10, "на диске не старше 10 с")
	s.stop()
	assert_eq(s.get_state(), WorkoutSession.State.FINISHED)
	assert_eq(repo.save_calls, saves_before_stop + 1, "после stop() — RideRepository.save")
	assert_false(repo.saved_in_progress.back(), "финальная запись — не «в процессе»")
	var n: int = ft.commands.size()
	_run(s, 10.0)
	assert_eq(ft.commands.size(), n, "после stop() на станок ничего")


# ---------------------------------------------------------------------------
# REQ-FRD-07 крит. 3, 4 — метаданные, сэмплы с позицией, набор N кругов
# ---------------------------------------------------------------------------

func test_req_frd_07_c3_saved_metadata_free_ride_route_start_steepness_totals_no_plan() -> void:
	_dir = "user://acc_free_ride_meta_%d/" % Time.get_ticks_usec()
	var repo := FileRideRepository.new(_dir + "rides/")
	var profile := Profile.create("Тест")
	var s := _session(_trainer(), RouteCatalog.MOUNTAINS, 35)
	var rec := RideRecorder.new(repo, profile, s)
	s.start()
	_run(s, 600.0, 1.0)
	s.set_steepness(90)
	s.toggle_mode()
	_run(s, 300.0, 1.0)
	s.stop()
	var r := FileRideRepository.new(_dir + "rides/").get_ride(rec.ride_id())
	assert_not_null(r)
	if r == null:
		return
	assert_true(r.is_free_ride(), "тип «свободная езда»")
	assert_eq(r.metadata.get(Ride.KEY_RIDE_TYPE), Ride.RIDE_TYPE_FREE_RIDE)
	assert_eq(r.route_id(), RouteCatalog.MOUNTAINS, "идентификатор трассы")
	assert_almost_eq(r.sim_steepness_start_pct(), 35.0, EPS, "крутизна на старте, а не текущая")
	assert_almost_eq(r.total_distance_m(), s.distance_m(), 0.05, "итоговая дистанция, м")
	assert_almost_eq(r.total_ascent_m(), s.samples.total_ascent_m(), 0.01, "набор высоты, м")
	assert_gt(r.total_ascent_m(), 50.0, "на «Перевале» за 15 мин набор есть")
	assert_eq(r.speed_source(), SampleStream.SPEED_SOURCE_MODEL, "speed_source = модель")
	assert_eq(r.name, "", "названия плана нет")
	assert_true(r.workout.is_empty(), "плана нет")
	assert_false(r.metadata.has("workout_name"))
	assert_eq(r.samples.size(), 900)
	var mid: int = 450
	assert_true(r.samples.has_route[mid])
	assert_almost_eq(r.samples.distance_m[mid], s.samples.distance_m[mid], 0.01)
	assert_almost_eq(r.samples.altitude_m[mid], s.samples.altitude_m[mid], 0.01)
	assert_almost_eq(r.samples.grade_pct[mid], s.samples.grade_pct[mid], 0.01)


func test_req_frd_07_c4_ascent_of_n_full_laps_on_every_route() -> void:
	var laps_by_route := {RouteCatalog.FLAT: 3, RouteCatalog.HILLS: 2, RouteCatalog.MOUNTAINS: 1, RouteCatalog.SEASIDE: 2}
	for route in laps_by_route.keys():
		var s := _session(_trainer(13, 260), route, 50)
		var prof: RouteProfile = s.route.profile
		var n_laps: int = int(laps_by_route[route])
		var target_m: float = prof.length_m() * float(n_laps)
		s.start()
		var guard: int = 0
		while s.distance_m() < target_m and guard < 6 * 3600:
			s.tick(1.0)
			guard += 1
		# Набор по сэмплам до отметки N·L: сумма положительных приращений высоты.
		var st := s.samples
		var ascent: float = 0.0
		var prev_h: float = prof.height_at(0.0)
		for i in st.size():
			var h: float = st.altitude_m[i]
			if h > prev_h:
				ascent += h - prev_h
			prev_h = h
		var expected: float = float(n_laps) * prof.ascent_m()
		assert_almost_eq(ascent, expected, 0.05 * expected,
			"%s: %d кругов — набор %.1f м против %d × %.1f м" % [route, n_laps, ascent, n_laps, prof.ascent_m()])
		assert_almost_eq(s.ascent_m(), ascent, 0.5, "%s: набор сессии = по сэмплам" % route)
		for i in st.size():
			var sm: float = fposmod(st.distance_m[i], prof.length_m())
			if absf(st.altitude_m[i] - prof.height_at(sm)) > 0.01 or absf(st.grade_pct[i] - prof.grade_at(sm)) > 0.01:
				fail_test("%s: сэмпл %d не на профиле" % [route, i])
				break
