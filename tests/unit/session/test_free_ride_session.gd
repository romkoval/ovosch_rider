extends GutTest
## FreeRideSession: сессия свободной езды без плана — тики, модель скорости с уклоном,
## позиция на трассе, SimController, пауза, переподключение, события, запись
## (REQ-FRD-01 крит. 1–3, REQ-FRD-04 крит. 5, 9, REQ-FRD-05 крит. 5, 6, REQ-FRD-07 крит. 2–4).

const DT: float = 0.1
const WEIGHT: float = 75.0
const FTP: int = 250

var _ft: FakeTrainer
var _s: FreeRideSession
var _logged: Array[Dictionary] = []
var _states: Array[int] = []
var _seconds: Array[int] = []
var _unavailable: int = 0
var _finished: int = 0
var _modes: Array[int] = []
var _steepness: Array[int] = []
var _dir: String = ""


func before_each() -> void:
	_logged = []
	_states = []
	_seconds = []
	_unavailable = 0
	_finished = 0
	_modes = []
	_steepness = []
	_ft = _make_trainer()


func after_each() -> void:
	if _s != null:
		_s.dispose()
		_s = null
	if not _dir.is_empty():
		_remove_tree(ProjectSettings.globalize_path(_dir))
		_dir = ""


static func _make_trainer(seed: int = 42) -> FakeTrainer:
	var ft := FakeTrainer.new(seed)
	ft.connect_delay_sec = 0.0
	ft.set_rider_power(250)
	ft.connect_device("fake")
	return ft


func _make(route_id: String = RouteCatalog.FLAT, steepness: int = 50,
		mode: SimController.Mode = SimController.Mode.SIM, level: int = 50) -> FreeRideSession:
	_s = FreeRideSession.new(_ft, route_id, steepness, WEIGHT, FTP, mode, level)
	_s.event_logged.connect(_on_event)
	_s.state_changed.connect(_on_state)
	_s.second_elapsed.connect(_on_second)
	_s.simulation_unavailable.connect(_on_unavailable)
	_s.mode_changed.connect(_on_mode)
	_s.steepness_changed.connect(_on_steepness)
	return _s


func _on_event(event: Dictionary) -> void:
	_logged.append(event)


func _on_state(state: int) -> void:
	_states.append(state)


func _on_second(elapsed: int) -> void:
	_seconds.append(elapsed)


func _on_unavailable() -> void:
	_unavailable += 1


func _on_finished() -> void:
	_finished += 1


func _on_mode(mode: int) -> void:
	_modes.append(mode)


func _on_steepness(percent: int) -> void:
	_steepness.append(percent)


static func _run(session: FreeRideSession, sec: float, dt: float = DT) -> void:
	var n: int = roundi(sec / dt)
	for i in n:
		session.tick(dt)


static func _cmds(ft: FakeTrainer, type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in ft.commands:
		if str(c["type"]) == type:
			out.append(c)
	return out


func _events_of(type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _s.events:
		if str(e["type"]) == type:
			out.append(e)
	return out


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


# ---------------------------------------------------------------------------
# REQ-FRD-01 крит. 1–3: сессия без исполнителя, первая команда, без сети
# ---------------------------------------------------------------------------

func test_req_frd_01_c1_session_without_executor_runs_and_has_no_step_events() -> void:
	_make()
	assert_eq(_s.get_state(), WorkoutSession.State.IDLE)
	assert_null(_s.get("executor"), "исполнителя интервалов нет")
	_s.start()
	assert_eq(_s.get_state(), WorkoutSession.State.RUNNING)
	assert_eq(_states, [WorkoutSession.State.RUNNING] as Array[int])
	_run(_s, 30.0)
	assert_eq(_s.elapsed_sec(), 30)
	assert_eq(_s.samples.size(), 30)
	assert_true(_s.samples.is_monotonic())
	for i in _s.samples.size():
		assert_eq(_s.samples.step_index[i], -1, "сэмпл вне плана")
		assert_eq(_s.samples.target_w[i], 0, "целевой мощности нет")
	assert_eq(_events_of(WorkoutSession.EVENT_SKIP).size(), 0)
	assert_eq(_s.events[0]["type"], WorkoutSession.EVENT_START)


func test_req_frd_01_c2_first_command_is_sim_and_never_target_power() -> void:
	_make(RouteCatalog.HILLS, 50)
	_s.start()
	assert_gt(_ft.commands.size(), 0, "на старте ушла команда")
	assert_eq(_ft.commands[0]["type"], FakeTrainer.CMD_SIM, "первая команда — SIM 0x11")
	var expected: float = SimController.transmitted_grade(_s.route.profile.grade_at(0.0), 50, _ft.inclination_range())
	assert_almost_eq(float(_ft.commands[0]["value"]), expected, 1e-6, "уклон точки старта × крутизна")
	_run(_s, 600.0)
	assert_eq(_cmds(_ft, FakeTrainer.CMD_TARGET_POWER).size(), 0, "Set Target Power ни разу")
	assert_eq(_cmds(_ft, FakeTrainer.CMD_ERG).size(), 0, "ERG не трогается в SIM")
	assert_gt(_cmds(_ft, FakeTrainer.CMD_SIM).size(), 1, "уклон меняется по трассе")


func test_req_frd_01_c2_fixed_preselected_first_command_is_resistance() -> void:
	_make(RouteCatalog.HILLS, 50, SimController.Mode.FIXED, 40)
	_s.start()
	assert_eq(_ft.commands[0]["type"], FakeTrainer.CMD_RESISTANCE, "первая команда — 0x04")
	assert_eq(int(_ft.commands[0]["value"]), 40)
	_run(_s, 120.0)
	assert_eq(_cmds(_ft, FakeTrainer.CMD_SIM).size(), 0, "в фиксированном режиме SIM нет")
	assert_eq(_cmds(_ft, FakeTrainer.CMD_TARGET_POWER).size(), 0)
	for c in _cmds(_ft, FakeTrainer.CMD_ERG):
		assert_false(bool(c["value"]), "ERG только выключается")


func test_req_frd_01_c3_starts_with_network_unavailable() -> void:
	var http := MockHttpTransport.new()
	http.offline = true
	_make()
	_s.start()
	_run(_s, 10.0, 1.0)
	assert_eq(_s.get_state(), WorkoutSession.State.RUNNING, "сессия стартует без сети")
	assert_eq(_s.samples.size(), 10)
	assert_gt(_s.distance_m(), 0.0)
	assert_eq(http.requests.size(), 0, "к сети сессия не обращается")


# ---------------------------------------------------------------------------
# REQ-FRD-04 крит. 9, 8: скорость — модель с полным уклоном; позиция согласована
# ---------------------------------------------------------------------------

func test_req_frd_04_c9_speed_from_model_with_full_grade_not_trainer() -> void:
	_make(RouteCatalog.HILLS, 0)
	_s.start()
	_run(_s, 300.0, 1.0)
	var ref_model := SpeedModel.new()
	var ref_pos := RoutePosition.new(_s.route.profile)
	var st := _s.samples
	var slower_on_climb: bool = false
	for i in st.size():
		var p: float = float(st.power_w[i]) if st.has_power[i] else 0.0
		var g_before: float = ref_pos.grade_pct()
		var v: float = ref_model.step(p, WEIGHT, 1.0, g_before)
		ref_pos.advance(v, 1.0)
		assert_almost_eq(st.speed_kmh[i], v, 1e-3, "скорость сэмпла %d — модель с уклоном" % i)
		assert_almost_eq(st.distance_m[i], ref_pos.distance_m(), 1e-2, "дистанция сэмпла %d — интеграл модели" % i)
		if g_before > 3.0 and st.has_power[i] and v < SpeedModel.steady_speed_kmh(p, WEIGHT, 0.0) - 5.0:
			slower_on_climb = true
	assert_true(slower_on_climb, "в подъём модель медленнее, чем на ровном (крутизна 0 — уклон в модели полный)")
	assert_eq(st.speed_source, SampleStream.SPEED_SOURCE_MODEL)
	assert_eq(_s.metadata()["speed_source"], SampleStream.SPEED_SOURCE_MODEL)


func test_req_frd_07_c4_sample_carries_distance_altitude_grade_of_position() -> void:
	_make(RouteCatalog.HILLS)
	_s.start()
	_run(_s, 120.0, 1.0)
	var prof: RouteProfile = _s.route.profile
	var st := _s.samples
	for i in st.size():
		assert_true(st.has_route[i])
		var s_m: float = fposmod(st.distance_m[i], prof.length_m())
		assert_almost_eq(st.altitude_m[i], prof.height_at(s_m), 0.01, "h(s) в сэмпле %d" % i)
		assert_almost_eq(st.grade_pct[i], prof.grade_at(s_m), 0.01, "g(s) в сэмпле %d" % i)
	assert_almost_eq(st.total_distance_m(), _s.distance_m(), 0.01)
	assert_almost_eq(_s.route_grade_pct(), prof.grade_at(_s.position.s_m()), 1e-6)


func test_req_frd_04_c2_transmitted_grade_follows_position_with_steepness() -> void:
	_make(RouteCatalog.HILLS, 50)
	_s.start()
	_run(_s, 240.0)
	var last: Dictionary = _cmds(_ft, FakeTrainer.CMD_SIM).back()
	var expected: float = SimController.transmitted_grade(_s.route_grade_pct(), 50, _ft.inclination_range())
	assert_lt(absf(float(last["value"]) - expected), SimController.GRADE_THRESHOLD_PCT + 1e-6,
		"последний отправленный уклон = g(s) × k в пределах порога")


func test_large_delta_is_sliced_by_seconds() -> void:
	_make()
	_s.start()
	_s.tick(3.5)
	assert_eq(_s.samples.size(), 3, "заморозка кадра 3.5 с — три слота")
	assert_almost_eq(_s.session_time_sec(), 3.5, 1e-6)
	_s.tick(0.5)
	assert_eq(_s.samples.size(), 4)
	assert_true(_s.samples.is_monotonic())
	assert_eq(_seconds, [1, 2, 3, 4] as Array[int])
	for i in 4:
		assert_true(_s.samples.has_power[i], "телеметрия секунды попала в слот %d" % i)


# ---------------------------------------------------------------------------
# REQ-FRD-07 крит. 2, REQ-FRD-04 крит. 5: пауза и возобновление
# ---------------------------------------------------------------------------

func test_req_frd_07_c2_pause_freezes_time_distance_and_sends_nothing() -> void:
	_make(RouteCatalog.HILLS)
	_s.start()
	_run(_s, 60.0)
	_s.pause()
	assert_eq(_s.get_state(), WorkoutSession.State.PAUSED)
	var n_cmd: int = _ft.commands.size()
	var dist: float = _s.distance_m()
	var n: int = _s.samples.size()
	var elapsed: int = _s.elapsed_sec()
	var speed: float = _s.speed_kmh()
	_s.set_steepness(80)
	_run(_s, 30.0)
	assert_eq(_ft.commands.size(), n_cmd, "на паузе на станок ничего не уходит")
	assert_eq(_s.samples.size(), n, "на паузе слоты не пишутся")
	assert_eq(_s.elapsed_sec(), elapsed, "время стоит")
	assert_almost_eq(_s.distance_m(), dist, 1e-9, "дистанция стоит")
	assert_almost_eq(_s.speed_kmh(), speed, 1e-9, "модель скорости стоит")
	var resumed_at: float = _ft.get_time_sec()
	_s.resume()
	_run(_s, 1.0)
	var after: Array[Dictionary] = _ft.commands.slice(n_cmd)
	assert_gt(after.size(), 0, "при возобновлении — принудительная отправка")
	assert_eq(after[0]["type"], FakeTrainer.CMD_SIM)
	var expected: float = SimController.transmitted_grade(_s.route_grade_pct(), 80, _ft.inclination_range())
	assert_almost_eq(float(after[0]["value"]), expected, SimController.GRADE_THRESHOLD_PCT)
	assert_lte(float(after[0]["at_sec"]) - resumed_at, 1.0 + 1e-6, "не позже 1 с после возобновления")
	var pauses := _events_of(WorkoutSession.EVENT_PAUSE)
	assert_eq(pauses.size(), 1)
	assert_almost_eq(float(pauses[0]["duration_sec"]), 30.0, 1e-3, "длительность паузы по протиканному времени")
	assert_almost_eq(float(_s.metadata()["paused_total_sec"]), 30.0, 1e-3)
	assert_eq(_events_of(WorkoutSession.EVENT_RESUME).size(), 1)
	_run(_s, 10.0)
	assert_eq(_s.samples.size(), n + 11, "после возобновления слоты снова пишутся")
	assert_true(_s.samples.is_monotonic(), "время паузы не входит в активное")


func test_req_frd_04_c5_resume_sends_current_grade_even_below_threshold() -> void:
	_make(RouteCatalog.FLAT, 50)
	_s.start()
	_run(_s, 5.0)
	_s.pause()
	_run(_s, 5.0)
	var n_sim: int = _cmds(_ft, FakeTrainer.CMD_SIM).size()
	_s.resume()
	assert_eq(_cmds(_ft, FakeTrainer.CMD_SIM).size(), n_sim + 1, "уклон уходит сразу при возобновлении, без порога")


# ---------------------------------------------------------------------------
# REQ-FRD-04 крит. 5: обрыв и восстановление связи
# ---------------------------------------------------------------------------

func test_req_frd_04_c5_reconnect_forces_resend_within_1s_and_logs_events() -> void:
	_make(RouteCatalog.FLAT, 50)
	_s.start()
	_run(_s, 10.0)
	_ft.inject_dropout(3.0)
	_run(_s, 2.0)
	var n_sim: int = _cmds(_ft, FakeTrainer.CMD_SIM).size()
	_run(_s, 3.0)
	assert_eq(_ft.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	var sims := _cmds(_ft, FakeTrainer.CMD_SIM)
	assert_gt(sims.size(), n_sim, "после восстановления уклон отправлен заново")
	assert_eq(_events_of(WorkoutSession.EVENT_DISCONNECT).size(), 1, "обрыв — событие")
	var reconnect := _events_of(WorkoutSession.EVENT_RECONNECT)
	assert_eq(reconnect.size(), 1, "восстановление — событие")
	assert_eq(_cmds(_ft, FakeTrainer.CMD_TARGET_POWER).size(), 0)
	assert_eq(_s.get_state(), WorkoutSession.State.RUNNING, "обрыв сессию не останавливает")


# ---------------------------------------------------------------------------
# REQ-FRD-05 крит. 5, 6: смена режима и крутизны — события, не трогают таймер и позицию
# ---------------------------------------------------------------------------

func test_req_frd_05_c6_mode_and_steepness_changes_are_logged_with_time() -> void:
	_make(RouteCatalog.HILLS, 50)
	_s.start()
	_run(_s, 20.0)
	_s.set_steepness(70)
	_run(_s, 5.0)
	assert_true(_s.toggle_mode())
	assert_eq(_s.mode(), SimController.Mode.FIXED)
	_run(_s, 5.0)
	_s.set_resistance_level(60)
	_s.set_mode(SimController.Mode.SIM)
	var steep := _events_of(SimController.EVENT_STEEPNESS)
	assert_eq(steep.size(), 1)
	assert_eq(int(steep[0]["value"]), 70)
	assert_almost_eq(float(steep[0]["at_sec"]), 20.0, 1e-3, "время события — активное время сессии")
	var modes := _events_of(SimController.EVENT_MODE)
	assert_eq(modes.size(), 2)
	assert_eq(modes[0]["value"], SimController.MODE_NAME_FIXED)
	assert_almost_eq(float(modes[0]["at_sec"]), 25.0, 1e-3)
	assert_eq(modes[1]["value"], SimController.MODE_NAME_SIM)
	assert_eq(_events_of(SimController.EVENT_RESISTANCE).size(), 1)
	assert_eq(_modes, [SimController.Mode.FIXED, SimController.Mode.SIM] as Array[int], "сигнал режима для HUD")
	assert_eq(_steepness, [70] as Array[int], "сигнал крутизны для профиля")
	assert_eq(_s.steepness_pct(), 70)
	assert_eq(_s.resistance_level(), 60)
	assert_eq(_logged.size(), _s.events.size(), "каждое событие — сигналом")
	var meta := _s.metadata()
	assert_almost_eq(float(meta[FreeRideSession.META_SIM_STEEPNESS_START_PCT]), 50.0, 1e-6, "крутизна на старте")
	assert_eq(int(meta["sim_steepness_pct"]), 70)


func test_req_frd_05_c5_mode_and_steepness_do_not_change_timer_samples_position() -> void:
	var base := FreeRideSession.new(_make_trainer(7), RouteCatalog.HILLS, 50, WEIGHT, FTP)
	var ft_b: FakeTrainer = base.trainer as FakeTrainer
	_ft = _make_trainer(7)
	_make(RouteCatalog.HILLS, 50)
	base.start()
	_s.start()
	for i in 3000:
		base.tick(DT)
		_s.tick(DT)
		if i == 500:
			_s.set_steepness(100)
		elif i == 900:
			_s.toggle_mode()
		elif i == 1500:
			_s.set_resistance_level(80)
		elif i == 2000:
			_s.toggle_mode()
		elif i == 2500:
			_s.set_steepness(0)
	assert_eq(_s.elapsed_sec(), base.elapsed_sec(), "таймер не меняется")
	assert_eq(_s.samples.size(), base.samples.size(), "запись не прерывается")
	assert_almost_eq(_s.distance_m(), base.distance_m(), 1e-6, "позиция не меняется")
	assert_almost_eq(_s.ascent_m(), base.ascent_m(), 1e-6)
	for i in _s.samples.size():
		assert_eq(_s.samples.power_w[i], base.samples.power_w[i])
		assert_almost_eq(_s.samples.speed_kmh[i], base.samples.speed_kmh[i], 1e-6,
			"модель скорости в любом режиме считает полный уклон (сэмпл %d)" % i)
	assert_gt(_cmds(_ft, FakeTrainer.CMD_RESISTANCE).size(), 0, "переключения дошли до станка")
	assert_eq(_cmds(ft_b, FakeTrainer.CMD_RESISTANCE).size(), 0)
	base.dispose()


# ---------------------------------------------------------------------------
# REQ-FRD-04 крит. 6: станок без SIM
# ---------------------------------------------------------------------------

func test_req_frd_04_c6_no_sim_support_falls_back_to_fixed_and_logs_once() -> void:
	_ft.set_simulation_supported(false)
	_make(RouteCatalog.HILLS, 50, SimController.Mode.SIM, 45)
	_s.start()
	assert_eq(_s.mode(), SimController.Mode.FIXED)
	assert_eq(_unavailable, 1)
	assert_eq(_cmds(_ft, FakeTrainer.CMD_SIM).size(), 0)
	assert_eq(_ft.commands[0]["type"], FakeTrainer.CMD_RESISTANCE)
	assert_false(_s.set_mode(SimController.Mode.SIM), "без SIM возврат отклонён")
	assert_eq(_unavailable, 2)
	assert_eq(_events_of(FreeRideSession.EVENT_SIM_UNAVAILABLE).size(), 1, "событие «нет SIM» — один раз")
	_run(_s, 10.0)
	assert_eq(_s.get_state(), WorkoutSession.State.RUNNING, "сессия не прерывается")
	assert_eq(_s.samples.size(), 10)


func test_req_frd_04_c6_sim_rejected_by_trainer_falls_back() -> void:
	_make(RouteCatalog.FLAT, 50)
	_ft.fail_next_command(TrainerDevice.ErrorCode.SIMULATION_REJECTED)
	_s.start()
	_run(_s, 2.0)
	assert_eq(_s.mode(), SimController.Mode.FIXED)
	assert_eq(_unavailable, 1)
	assert_gt(_cmds(_ft, FakeTrainer.CMD_RESISTANCE).size(), 0, "уровень ушёл после отказа SIM")


# ---------------------------------------------------------------------------
# REQ-FRD-07 крит. 1, 2: без лимита, стоп — только явно
# ---------------------------------------------------------------------------

func test_req_frd_07_c2_stop_only_explicit_then_no_commands() -> void:
	_make(RouteCatalog.FLAT)
	_s.session_finished.connect(_on_finished)
	_s.start()
	_run(_s, 3600.0, 1.0)
	assert_eq(_s.get_state(), WorkoutSession.State.RUNNING, "через час сессия не завершилась сама")
	assert_eq(_finished, 0)
	_s.stop()
	assert_eq(_s.get_state(), WorkoutSession.State.FINISHED)
	assert_eq(_finished, 1)
	assert_eq(_states.back(), WorkoutSession.State.FINISHED)
	var types: Array[String] = []
	for e in _s.events:
		types.append(str(e["type"]))
	assert_eq(types.slice(-2), [WorkoutSession.EVENT_STOP, WorkoutSession.EVENT_FINISH] as Array[String])
	var n_cmd: int = _ft.commands.size()
	var n: int = _s.samples.size()
	_s.set_steepness(100)
	_s.toggle_mode()
	_run(_s, 10.0, 1.0)
	assert_eq(_ft.commands.size(), n_cmd, "после stop() команд нет")
	assert_eq(_s.samples.size(), n, "после stop() слотов нет")
	_s.start()
	assert_eq(_s.get_state(), WorkoutSession.State.FINISHED, "повторный старт невозможен")
	assert_push_warning("сессия уже запущена")


func test_req_frd_07_c2_stop_on_pause_closes_pause() -> void:
	_make()
	_s.start()
	_run(_s, 5.0)
	_s.pause()
	_run(_s, 4.0)
	_s.stop()
	var pauses := _events_of(WorkoutSession.EVENT_PAUSE)
	assert_almost_eq(float(pauses[0]["duration_sec"]), 4.0, 1e-3)
	assert_almost_eq(float(_s.metadata()["paused_total_sec"]), 4.0, 1e-3)
	assert_eq(_s.get_state(), WorkoutSession.State.FINISHED)


# ---------------------------------------------------------------------------
# REQ-FRD-07 крит. 3: метаданные; запись через RideRecorder
# ---------------------------------------------------------------------------

func test_req_frd_07_c3_metadata_keys_match_ride_free_ride_metadata() -> void:
	_make(RouteCatalog.MOUNTAINS, 35)
	_s.start()
	_run(_s, 30.0, 1.0)
	var meta := _s.metadata()
	var expected := Ride.free_ride_metadata(RouteCatalog.MOUNTAINS, 35.0)
	for key in expected.keys():
		assert_true(meta.has(key), "ключ %s" % key)
		assert_eq(meta[key], expected[key], "значение %s" % key)
	assert_eq(FreeRideSession.META_TOTAL_DISTANCE_M, Ride.KEY_TOTAL_DISTANCE_M)
	assert_eq(FreeRideSession.META_TOTAL_ASCENT_M, Ride.KEY_TOTAL_ASCENT_M)
	assert_false(meta.has("workout_name"), "названия плана нет")
	assert_almost_eq(float(meta[Ride.KEY_TOTAL_DISTANCE_M]), _s.distance_m(), 1e-6)
	assert_almost_eq(float(meta[Ride.KEY_TOTAL_ASCENT_M]), _s.ascent_m(), 1e-6)
	assert_eq(int(meta["ftp_w"]), FTP)
	assert_almost_eq(float(meta["weight_kg"]), WEIGHT, 1e-6)
	assert_eq(int(meta["elapsed_sec"]), 30)


func test_req_frd_07_c2_recorder_saves_free_ride_after_stop() -> void:
	_dir = "user://test_free_ride_session_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	var repo := FileRideRepository.new(_dir + "rides/")
	var profile := Profile.create("Райдер")
	_make(RouteCatalog.HILLS, 50)
	var recorder := RideRecorder.new(repo, profile, _s)
	_s.start()
	assert_true(recorder.is_recording(), "запись начата при старте")
	var id := recorder.ride_id()
	_run(_s, 95.0, 1.0)
	_s.pause()
	_run(_s, 3.0, 1.0)
	_s.resume()
	_run(_s, 25.0, 1.0)
	_s.toggle_mode()
	_run(_s, 5.0, 1.0)
	assert_true(recorder.is_recording())
	_s.stop()
	assert_false(recorder.is_recording(), "после stop() запись завершена")
	var back := FileRideRepository.new(_dir + "rides/").get_ride(id)
	assert_not_null(back)
	if back == null:
		return
	assert_false(back.is_in_progress())
	assert_true(back.is_free_ride())
	assert_eq(back.route_id(), RouteCatalog.HILLS)
	assert_almost_eq(back.sim_steepness_start_pct(), 50.0, 1e-6)
	assert_eq(back.samples.size(), 125)
	assert_almost_eq(back.total_distance_m(), _s.distance_m(), 0.05)
	assert_almost_eq(back.total_ascent_m(), _s.samples.total_ascent_m(), 1e-3)
	assert_eq(back.speed_source(), SampleStream.SPEED_SOURCE_MODEL)
	assert_eq(back.name, "")
	assert_eq(back.pause_events().size(), 1)
	assert_almost_eq(back.paused_total_sec(), 3.0, 1e-3)
	var mode_events: int = 0
	for e in back.events:
		if str(e["type"]) == SimController.EVENT_MODE:
			mode_events += 1
	assert_eq(mode_events, 1, "переключение режима сохранено в журнале заезда")


# ---------------------------------------------------------------------------
# Жизненный цикл
# ---------------------------------------------------------------------------

func test_unknown_route_falls_back_to_default() -> void:
	_make("nowhere")
	assert_eq(_s.route.id, RouteCatalog.DEFAULT_ID)
	assert_push_warning("трассы «nowhere» нет в каталоге")


func test_dispose_disconnects_trainer_and_controller() -> void:
	_make()
	_s.start()
	_run(_s, 3.0, 1.0)
	_s.dispose()
	assert_false(_ft.telemetry.is_connected(_s._on_telemetry))
	assert_false(_ft.heart_rate.is_connected(_s._on_heart_rate))
	assert_false(_ft.connection_state_changed.is_connected(_s._on_connection_state_changed))
	assert_false(_s.sim.ride_event.is_connected(_s._on_sim_event))
	assert_null(_s.sim.trainer, "контроллер освобождён")
	var n_cmd: int = _ft.commands.size()
	_run(_s, 3.0, 1.0)
	assert_eq(_ft.commands.size(), n_cmd, "после dispose() команд нет")


func test_heart_rate_zero_is_no_data() -> void:
	_ft.set_heart_rate_sequence([0, 140, 141] as Array[int])
	_make()
	_s.start()
	_run(_s, 3.0, 1.0)
	assert_false(_s.samples.has_heart_rate[0], "0 уд/мин — нет данных")
	assert_true(_s.samples.has_heart_rate[1])
	assert_eq(_s.samples.heart_rate_bpm[1], 140)
	assert_eq(_s.data_age_sec("heart_rate"), 0)
	assert_eq(_s.data_age_sec("power"), 0)
