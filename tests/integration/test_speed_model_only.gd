extends GutTest
## T-169: скорость только по модели во всех режимах (REQ-D3D-02 п.6, REQ-WRK-08 п.5, У-30;
## подпись в карточке — предложение Н-72 (е)). Поле скорости станка (50.00 км/ч) не влияет ни на
## сэмпл, ни на дистанцию: прогоны с полем и без поля совпадают.

const HISTORY_SCENE: String = "res://src/ui/history/history_screen.tscn"
const WEIGHT: float = 75.0
const FTP: int = 200

var _dir: String = ""
var _disposables: Array = []


## Станок-фикстура: 200 Вт, 90 об/мин и (по флагу) поле скорости 50.00 км/ч каждую секунду.
class SpeedFieldTrainer extends TrainerDevice:
	var with_speed: bool = true
	var mode: String = TrainerDevice.MODE_SMART
	var _t: float = 0.0
	var _next: int = 1

	func _init(speed_field: bool, session_mode: String = TrainerDevice.MODE_SMART) -> void:
		with_speed = speed_field
		mode = session_mode

	func connect_device(_id: String) -> void:
		connection_state_changed.emit(ConnectionState.CONNECTED)

	func disconnect_device() -> void:
		pass

	func set_target_power(_watts: int) -> void:
		pass

	func set_erg_enabled(_enabled: bool) -> void:
		pass

	func is_erg_enabled() -> bool:
		return true

	func set_resistance_level(_percent: int) -> void:
		pass

	func set_simulation(_grade_pct: float, _wind_mps: float = DEFAULT_SIM_WIND_MPS,
			_crr: float = DEFAULT_SIM_CRR, _cw: float = DEFAULT_SIM_CW) -> void:
		pass

	func simulation_support() -> int:
		return SimulationSupport.SUPPORTED

	func inclination_range() -> Vector2:
		return Vector2(DEFAULT_INCLINATION_MIN_PCT, DEFAULT_INCLINATION_MAX_PCT)

	func trainer_mode() -> String:
		return mode

	func has_control() -> bool:
		return mode == TrainerDevice.MODE_SMART

	func set_control_allowed(_allowed: bool) -> void:
		pass

	func is_emulator() -> bool:
		return false

	func get_connection_state() -> int:
		return ConnectionState.CONNECTED

	func tick(delta_sec: float) -> void:
		_t += delta_sec
		while float(_next) <= _t + 1e-6:
			var s := TrainerSample.full(float(_next), 200, 90, 50.0)
			s.has_speed = with_speed
			telemetry.emit(s)
			_next += 1


func before_each() -> void:
	_dir = ""
	_disposables = []


func after_each() -> void:
	for d: Variant in _disposables:
		if d != null and (d as Object).has_method("dispose"):
			(d as Object).call("dispose")
	_disposables = []
	if not _dir.is_empty():
		_remove_tree(ProjectSettings.globalize_path(_dir))


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


func _plan_run(speed_field: bool, mode: String) -> WorkoutSession:
	var s := WorkoutSession.new(Workout.make("flat", [WorkoutStep.watts(120, 200.0)] as Array[WorkoutStep]),
		SpeedFieldTrainer.new(speed_field, mode), FTP, 1.0, WEIGHT, RouteCatalog.FLAT)
	s.start()
	while s.get_state() != WorkoutSession.State.FINISHED:
		s.tick(1.0)
	return s


func _free_run(speed_field: bool, mode: String) -> FreeRideSession:
	var s := FreeRideSession.new(SpeedFieldTrainer.new(speed_field, mode), RouteCatalog.FLAT, 50, WEIGHT, FTP)
	_disposables.append(s)
	s.start()
	for i in 120:
		s.tick(1.0)
	return s


func _assert_same_stream(a: SampleStream, b: SampleStream, what: String) -> void:
	assert_eq(a.size(), b.size(), what)
	assert_eq(a.speed_source, SampleStream.SPEED_SOURCE_MODEL, "%s: источник — модель" % what)
	for i in mini(a.size(), b.size()):
		assert_almost_eq(a.speed_kmh[i], b.speed_kmh[i], 0.01, "%s, сэмпл %d: скорость как без поля" % [what, i])
		assert_almost_eq(a.distance_m[i], b.distance_m[i], 0.01, "%s, сэмпл %d: дистанция как без поля" % [what, i])
		assert_true(a.speed_kmh[i] < 45.0, "%s, сэмпл %d: не 50 км/ч станка" % [what, i])
	var last := a.size() - 1
	assert_almost_eq(a.speed_kmh[last], 34.0, 3.0, "%s: 200 Вт / 75 кг → 34 ± 3 км/ч" % what)


func test_req_d3d_02_c6_plan_on_flat_ignores_trainer_speed_field_smart_and_power_meter() -> void:
	for mode in [TrainerDevice.MODE_SMART, TrainerDevice.MODE_POWER_METER]:
		var with_field := _plan_run(true, mode)
		var without := _plan_run(false, mode)
		_assert_same_stream(with_field.samples, without.samples, "план, %s" % mode)
		assert_eq(with_field.metadata()["speed_source"], SampleStream.SPEED_SOURCE_MODEL, "WRK-08 п.5: у нового заезда — модель")


func test_req_d3d_02_c6_free_ride_ignores_trainer_speed_field_smart_and_power_meter() -> void:
	for mode in [TrainerDevice.MODE_SMART, TrainerDevice.MODE_POWER_METER]:
		_assert_same_stream(_free_run(true, mode).samples, _free_run(false, mode).samples, "свободная езда, %s" % mode)


func test_req_d3d_02_c6_emulator_trainer_speed_is_ignored() -> void:
	var fake := FakeTrainer.new(5)
	fake.connect_delay_sec = 0.0
	fake.power_noise_w = 0.0
	fake.power_tau_sec = 0.001
	fake.set_rider_power(200)
	fake.connect_device("fake")
	var s := WorkoutSession.new(Workout.make("free", [WorkoutStep.free_ride(60)] as Array[WorkoutStep]), fake, FTP, 1.0, WEIGHT, "")
	s.start()
	while s.get_state() != WorkoutSession.State.FINISHED:
		s.tick(1.0)
	var model := SpeedModel.new()
	for i in s.samples.size():
		var want: float = model.step(float(s.samples.power_w[i]), WEIGHT, 1.0) if s.samples.has_power[i] \
			else model.step_without_power(WEIGHT, 1.0)
		assert_almost_eq(s.samples.speed_kmh[i], want, 0.01, "сэмпл %d: модель, не скорость эмулятора" % i)


## WRK-08 п.5, Н-72 (е): подпись «скорость: …» в карточке — только у старых заездов со скоростью станка.
func test_req_wrk_08_c5_ride_detail_speed_label_only_for_legacy_trainer_rides() -> void:
	TranslationServer.set_locale("en")
	_dir = "user://test_speed_model_only_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	var profiles := ProfileRepository.new(_dir + "profiles/")
	var rides := FileRideRepository.new(_dir + "rides/")
	rides.attach_to_profiles(profiles)
	var p := profiles.create("Rider")
	p.ftp_w = FTP
	profiles.save(p)
	var state := AppState.new(profiles)
	state.select_profile(p.id)
	var fresh := _ride(p, 1_790_000_000, SampleStream.SPEED_SOURCE_MODEL)
	var legacy := _ride(p, 1_790_100_000, Ride.SPEED_SOURCE_TRAINER_LEGACY)
	rides.save(fresh)
	rides.save(legacy)
	var loaded := rides.get_ride(legacy.id)
	assert_eq(loaded.speed_source(), Ride.SPEED_SOURCE_TRAINER_LEGACY, "старый заезд со «станок» читается как есть")
	assert_eq(loaded.samples.speed_source, Ride.SPEED_SOURCE_TRAINER_LEGACY)
	assert_almost_eq(loaded.samples.speed_kmh[3], 36.0, 1e-4, "без пересчёта")
	var h: HistoryScreen = load(HISTORY_SCENE).instantiate()
	h.setup(rides, profiles, state)
	add_child_autofree(h)
	assert_true(h.show_ride(fresh.id))
	assert_false(h.detail().summary_text().contains("speed:"), "у нового заезда подписи источника скорости нет")
	assert_true(h.detail().summary_text().contains("FTP 200 W"), "строка параметров на месте")
	assert_true(h.show_ride(legacy.id))
	assert_true(h.detail().summary_text().contains("speed: trainer"), "у старого заезда со скоростью станка — подпись")


func _ride(profile: Profile, started_at: int, speed_source: String) -> Ride:
	var r := Ride.new()
	r.id = Ride.generate_id(started_at)
	r.profile_id = profile.id
	r.started_at_unix = started_at
	r.name = "R"
	r.workout = WorkoutSerializer.to_dict(Workout.make("R", [WorkoutStep.watts(10, 200.0)] as Array[WorkoutStep], "zwo"))
	r.metadata = {"workout_name": "R", "workout_source": "zwo", "started_at_unix": started_at, "ftp_w": FTP,
		"weight_kg": 75.0, "max_hr": 0, "intensity": 1.0, "stopped_early": false, "speed_source": speed_source,
		"elapsed_sec": 10, "paused_total_sec": 0.0, "in_progress": false, "recovered": false}
	r.samples.speed_source = speed_source
	for i in 10:
		r.samples.append(i, TrainerSample.full(float(i + 1), 200, 90, 36.0), 150, 200, 0, true, 36.0)
	r.events = [{"type": WorkoutSession.EVENT_START, "at_sec": 0.0, "value": 0}]
	r.compute_summary()
	return r
