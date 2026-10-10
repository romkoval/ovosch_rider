extends GutTest
## Приёмка T-169 (tester): скорость только по модели во всех режимах.
## REQ-D3D-02 п.6, REQ-D3D-08 п.13, REQ-WRK-08 п.5, REQ-LOC-05 п.2 (У-30).
##
## Путь — приложение (`main.tscn`, `StubBleBridge`): станок FTMS с полем скорости Indoor Bike Data
## 50.00 км/ч (фикстура (а)), датчик CSC с оборотами колеса (фикстура (в)), измеритель мощности CPS
## (`power_meter`), эмулятор. Мощность 200 Вт постоянно, вес 75 кг. Сверка: скорость сэмпла =
## независимый пересчёт модели с уклоном g(s) трассы, скорость сцены и HUD = скорости сэмпла,
## прогон с полем скорости совпадает с прогоном без поля (сэмплы, дистанция, FIT).
## Фикстура FE-C (б) — после T-167 (в задаче так и оговорено).

const MAIN_SCENE: String = "res://src/app/main.tscn"
const FitAcc = preload("res://tests/unit/integrations/fit/test_fit_acceptance.gd")
const WEIGHT: float = 75.0
const POWER: int = 200
const TRAINER_ID: String = "neo"
const CSC_ID: String = "csc"
const PM_ID: String = "quarq"
const PLAN_SEC: int = 120

var _dir: String
var _profiles: ProfileRepository
var _profile: Profile
var _mains: Array[AppMain] = []
var _locale_before: String


func before_each() -> void:
	_locale_before = TranslationServer.get_locale()
	_dir = "user://test_speed_model_acc_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	var s := AppSettings.new(_dir + "settings.json")
	s.locale = "en"
	s.save()
	_profiles = ProfileRepository.new(_dir + "profiles/")
	_profile = _profiles.create("Rider")
	_profile.ftp_w = 200
	_profile.weight_kg = WEIGHT
	_profiles.save(_profile)
	_mains = []


func after_each() -> void:
	for m in _mains:
		if is_instance_valid(m):
			if m.get_parent() != null:
				m.get_parent().remove_child(m)
			m.free()
	_mains = []
	TranslationServer.set_locale(_locale_before)
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


func _main(kind: String = TrainerFactory.KIND_BLE) -> AppMain:
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.trainer_kind = kind
	main.transport = MockHttpTransport.new()
	add_child(main)
	main.set_process(false)
	_mains.append(main)
	assert_true(main.app_state.select_profile(_profile.id), "профиль выбран")
	return main


func _stub(main: AppMain) -> StubBleBridge:
	return main.bridge as StubBleBridge


## Управляемый FTMS-станок (`2AD2` + `2AD9`) через менеджер подключений приложения.
func _connect_ftms(main: AppMain, with_cp: bool = true) -> void:
	var chars := PackedStringArray([BleUuids.INDOOR_BIKE_DATA, BleUuids.FTMS_STATUS])
	if with_cp:
		chars.append(BleUuids.FTMS_CONTROL_POINT)
	_stub(main).set_device_services(TRAINER_ID, {BleUuids.FTMS_SERVICE: chars})
	main.connections.connect_trainer(TRAINER_ID)
	_stub(main).pump()


func _connect_csc(main: AppMain) -> void:
	_stub(main).set_device_services(CSC_ID, {"1816": ["2A5B"]})
	main.connections.connect_sensor(CSC_ID, RememberedDevices.KIND_CADENCE)
	_stub(main).pump()


func _connect_cps(main: AppMain) -> void:
	_stub(main).set_device_services(PM_ID, {BleUuids.CPS_SERVICE: PackedStringArray([BleUuids.CYCLING_POWER_MEASUREMENT])})
	main.connections.connect_sensor(PM_ID, RememberedDevices.KIND_POWER)
	_stub(main).pump()


## Indoor Bike Data: 200 Вт, 90 об/мин; `speed_kmh < 0` — поля скорости нет (флаг More Data).
func _ibd(main: AppMain, speed_kmh: float) -> void:
	_stub(main).emit_notification(TRAINER_ID, BleUuids.INDOOR_BIKE_DATA,
		FtmsCodec.encode_indoor_bike_data(speed_kmh, 90.0, POWER))


## CSC Measurement с данными колеса и шатуна: колесо 2.1 м крутится как 50 км/ч.
func _csc_wheel(main: AppMain, sec: int) -> void:
	var out := PackedByteArray([CscCodec.FLAG_WHEEL_REV | CscCodec.FLAG_CRANK_REV])
	var wheel_revs: int = roundi(50.0 / 3.6 / 2.1 * float(sec))
	var t: int = (sec * 1024) & 0xFFFF
	out.append_array(PackedByteArray([wheel_revs & 0xFF, (wheel_revs >> 8) & 0xFF, (wheel_revs >> 16) & 0xFF, (wheel_revs >> 24) & 0xFF]))
	out.append_array(PackedByteArray([t & 0xFF, (t >> 8) & 0xFF]))
	var crank: int = (sec * 3 / 2) & 0xFFFF
	out.append_array(PackedByteArray([crank & 0xFF, (crank >> 8) & 0xFF, t & 0xFF, (t >> 8) & 0xFF]))
	_stub(main).emit_notification(CSC_ID, "2A5B", out)


func _cps(main: AppMain) -> void:
	_stub(main).emit_notification(PM_ID, BleUuids.CYCLING_POWER_MEASUREMENT, CpsCodec.encode_cycling_power_measurement(POWER))


static func _plan() -> Workout:
	return Workout.make("Speed", [WorkoutStep.watts(PLAN_SEC, float(POWER))] as Array[WorkoutStep], "zwo")


## Независимый пересчёт: скорость модели с уклоном g(s) трассы по мощности сэмплов
## (позиция — интеграл этой же скорости от старта трассы, как у сессии).
static func _reference(stream: SampleStream, route_id: String, start_s: float = 0.0) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var pos := RoutePosition.new(RouteCatalog.get_route(route_id).profile)
	pos.reset(start_s)
	var m := SpeedModel.new()
	for i in stream.size():
		var g: float = pos.grade_pct()
		var v: float = m.step(float(stream.power_w[i]), WEIGHT, 1.0, g) if stream.has_power[i] \
			else m.step_without_power(WEIGHT, 1.0, g)
		pos.advance(v, 1.0)
		out.append(v)
	return out


## Тренировка по плану в приложении; на каждой секунде — пакеты устройств, затем сверка
## сцена = HUD = сэмпл. Возвращает сохранённый заезд.
func _plan_ride(main: AppMain, feed: Callable) -> Ride:
	assert_true(main.start_workout(_plan()), "план стартует")
	var screen := main.workout_screen()
	var session := screen.session()
	assert_not_null(session)
	if session == null:
		return null
	assert_eq(screen.ride_scene().route_id, RouteCatalog.FLAT, "план идёт на трассе flat (D3D-08 п.13)")
	var sec := 0
	while session.get_state() != WorkoutSession.State.FINISHED and sec < PLAN_SEC + 5:
		sec += 1
		feed.call(sec)
		session.tick(1.0)
		if session.get_state() == WorkoutSession.State.FINISHED:
			break
		var row := session.samples.last_row()
		assert_almost_eq(screen.ride_scene().speed_kmh, float(row["speed_kmh"]), 1e-4, "сек %d: скорость сцены = сэмпла" % sec)
		screen.refresh()
		assert_eq(screen.speed_text(), HudModel.format_speed(float(row["speed_kmh"])), "сек %d: HUD = сэмпла" % sec)
	assert_eq(session.get_state(), WorkoutSession.State.FINISHED)
	return main.ride_repository.get_ride(main.ride_recorder.ride_id())


func _assert_model_stream(ride: Ride, route_id: String, what: String) -> void:
	assert_not_null(ride, what)
	if ride == null:
		return
	assert_eq(ride.speed_source(), SampleStream.SPEED_SOURCE_MODEL, "%s: WRK-08 п.5 — speed_source «модель»" % what)
	var ref := _reference(ride.samples, route_id)
	for i in ride.samples.size():
		assert_true(ride.samples.has_power[i] and ride.samples.power_w[i] == POWER, "%s, сэмпл %d: 200 Вт" % [what, i])
		assert_almost_eq(ride.samples.speed_kmh[i], ref[i], 0.01, "%s, сэмпл %d: скорость = модель с уклоном" % [what, i])
		assert_lt(ride.samples.speed_kmh[i], 45.0, "%s, сэмпл %d: не 50 км/ч станка" % [what, i])
	assert_almost_eq(ride.samples.speed_kmh[ride.samples.size() - 1], 34.0, 3.0, "%s: 200 Вт / 75 кг → 34 ± 3 км/ч" % what)


## Сэмплы скорости, дистанция и FIT прогона «с полем» совпадают с прогоном «без поля».
func _assert_same(a: Ride, b: Ride, what: String) -> void:
	if a == null or b == null:
		fail_test("%s: заезд не сохранён" % what)
		return
	assert_eq(a.samples.size(), b.samples.size(), what)
	for i in mini(a.samples.size(), b.samples.size()):
		assert_almost_eq(a.samples.speed_kmh[i], b.samples.speed_kmh[i], 0.01, "%s, сэмпл %d: скорость" % [what, i])
		assert_almost_eq(a.samples.distance_m[i], b.samples.distance_m[i], 0.01, "%s, сэмпл %d: дистанция" % [what, i])
	var fa = FitAcc.decode(FitEncoder.encode(a))
	var fb = FitAcc.decode(FitEncoder.encode(b))
	assert_true(fa.ok and fb.ok, "%s: FIT декодируется" % what)
	var ra: Array = fa.of(FitAcc.G_RECORD)
	var rb: Array = fb.of(FitAcc.G_RECORD)
	assert_eq(ra.size(), a.samples.size(), "%s: record на каждый сэмпл" % what)
	assert_eq(ra.size(), rb.size())
	for i in mini(ra.size(), rb.size()):
		assert_eq(FitAcc.MiniFit.field(ra[i], FitAcc.REC_SPEED), FitAcc.MiniFit.field(rb[i], FitAcc.REC_SPEED), "%s, FIT record %d: speed" % [what, i])
		assert_eq(FitAcc.MiniFit.field(ra[i], FitAcc.REC_DISTANCE), FitAcc.MiniFit.field(rb[i], FitAcc.REC_DISTANCE), "%s, FIT record %d: distance" % [what, i])
		assert_eq(FitAcc.MiniFit.field(ra[i], FitAcc.REC_SPEED), roundi(a.samples.speed_kmh[i] / 3.6 * 1000.0), "%s, FIT record %d: speed = модель" % [what, i])


# ===========================================================================
# REQ-D3D-02 п.6 (а), REQ-D3D-08 п.13, REQ-WRK-08 п.5, REQ-LOC-05 п.2 — план, smart (ERG), FTMS
# ===========================================================================

func test_req_d3d_02_c6a_d3d_08_c13_plan_ftms_speed_field_50_ignored_app_path() -> void:
	var with_main := _main()
	_connect_ftms(with_main)
	var with_field := _plan_ride(with_main, func(_s: int) -> void: _ibd(with_main, 50.0))
	var cmds_with := _stub(with_main).calls_of("write")
	var without_main := _main()
	_connect_ftms(without_main)
	var without := _plan_ride(without_main, func(_s: int) -> void: _ibd(without_main, -1.0))
	_assert_model_stream(with_field, RouteCatalog.FLAT, "план FTMS с полем 50")
	_assert_model_stream(without, RouteCatalog.FLAT, "план FTMS без поля")
	_assert_same(with_field, without, "план FTMS: с полем / без поля")
	# D3D-08 п.13: станку уклон не уходит — в плане ERG, ни одной Indoor Bike Simulation (опкод 0x11).
	var sims := 0
	for c: Dictionary in cmds_with:
		var bytes: PackedByteArray = c.get("bytes", c.get("data", PackedByteArray()))
		if str(c.get("char", c.get("characteristic", ""))).to_upper().contains("2AD9") and not bytes.is_empty() and bytes[0] == 0x11:
			sims += 1
	assert_eq(sims, 0, "план: ни одной команды SIM (уклон станку не передаётся)")
	assert_gt(cmds_with.size(), 0, "предусловие: станок управляется (ERG)")


# ===========================================================================
# REQ-D3D-02 п.6 (в) — датчик CSC с оборотами колеса
# ===========================================================================

func test_req_d3d_02_c6c_plan_csc_wheel_data_ignored_app_path() -> void:
	var with_main := _main()
	_connect_ftms(with_main)
	_connect_csc(with_main)
	var with_wheel := _plan_ride(with_main, func(s: int) -> void:
		_ibd(with_main, -1.0)
		_csc_wheel(with_main, s))
	var without_main := _main()
	_connect_ftms(without_main)
	var without := _plan_ride(without_main, func(_s: int) -> void: _ibd(without_main, -1.0))
	_assert_model_stream(with_wheel, RouteCatalog.FLAT, "план + CSC колесо")
	_assert_same(with_wheel, without, "план: CSC с колесом / без CSC")


# ===========================================================================
# REQ-D3D-02 п.6 — свободная езда (SIM), FTMS с полем 50
# ===========================================================================

func _free_ride(main: AppMain, feed: Callable, n: int = 120) -> Ride:
	assert_true(main.start_free_ride(RouteCatalog.FLAT, 50), "свободная езда стартует")
	var screen := main.free_ride_screen()
	var session := screen.session()
	assert_not_null(session)
	if session == null:
		return null
	for sec in range(1, n + 1):
		feed.call(sec)
		session.tick(1.0)
		screen._process(1.0 / 60.0)
		var row := session.samples.last_row()
		assert_almost_eq(session.speed_kmh(), float(row["speed_kmh"]), 1e-4, "сек %d: скорость сессии = сэмпла" % sec)
		assert_almost_eq(screen.ride_scene().speed_kmh, float(row["speed_kmh"]), 1e-4, "сек %d: скорость сцены = сэмпла" % sec)
		screen.refresh()
		assert_eq(screen.metric_panel().speed_text(), HudModel.format_speed(float(row["speed_kmh"])), "сек %d: HUD = сэмпла" % sec)
	assert_true(screen.request_finish())
	screen.confirm_finish()
	return main.ride_repository.get_ride(main.ride_recorder.ride_id())


func test_req_d3d_02_c6a_free_ride_ftms_speed_field_50_ignored_app_path() -> void:
	var with_main := _main()
	_connect_ftms(with_main)
	var with_field := _free_ride(with_main, func(_s: int) -> void: _ibd(with_main, 50.0))
	var without_main := _main()
	_connect_ftms(without_main)
	var without := _free_ride(without_main, func(_s: int) -> void: _ibd(without_main, -1.0))
	assert_not_null(with_field)
	if with_field != null:
		assert_eq(with_field.speed_source(), SampleStream.SPEED_SOURCE_MODEL)
		for i in with_field.samples.size():
			assert_lt(with_field.samples.speed_kmh[i], 45.0, "сэмпл %d: не 50 км/ч станка" % i)
	_assert_same(with_field, without, "свободная езда FTMS: с полем / без поля")


# ===========================================================================
# REQ-D3D-02 п.6 — режим power_meter: CPS + станок без управления с полем 50
# ===========================================================================

func test_req_d3d_02_c6_power_meter_mode_data_only_trainer_speed_field_ignored_app_path() -> void:
	var with_main := _main()
	_connect_ftms(with_main, false)
	_connect_cps(with_main)
	assert_eq(with_main.session_start_check()["mode"], TrainerDevice.MODE_POWER_METER, "предусловие: power_meter")
	var with_field := _plan_ride(with_main, func(_s: int) -> void:
		_cps(with_main)
		_ibd(with_main, 50.0))
	var without_main := _main()
	_connect_cps(without_main)
	var without := _plan_ride(without_main, func(_s: int) -> void: _cps(without_main))
	_assert_model_stream(with_field, RouteCatalog.FLAT, "power_meter, станок с полем 50")
	_assert_same(with_field, without, "power_meter: станок с полем / только CPS")


# ===========================================================================
# REQ-D3D-02 п.6 — эмулятор
# ===========================================================================

func test_req_d3d_02_c6_emulator_plan_speed_is_model_with_grade_app_path() -> void:
	var main := _main(TrainerFactory.KIND_FAKE)
	assert_true(main.start_workout_on_emulator(_plan()))
	var screen := main.workout_screen()
	var session := screen.session()
	assert_not_null(session)
	if session == null:
		return
	var fake := main.emulator_trainer() as FakeTrainer
	assert_not_null(fake)
	var speed_fields: Array[float] = []
	fake.telemetry.connect(func(s: TrainerSample) -> void:
		if s.has_speed:
			speed_fields.append(s.speed_kmh))
	var guard := 0
	while session.get_state() != WorkoutSession.State.FINISHED and guard < PLAN_SEC + 5:
		guard += 1
		session.tick(1.0)
		if session.get_state() != WorkoutSession.State.FINISHED:
			assert_almost_eq(screen.ride_scene().speed_kmh, float(session.samples.last_row()["speed_kmh"]), 1e-4)
	var ride := main.ride_repository.get_ride(main.ride_recorder.ride_id())
	assert_not_null(ride)
	if ride == null:
		return
	assert_eq(ride.speed_source(), SampleStream.SPEED_SOURCE_MODEL)
	var ref := _reference(ride.samples, RouteCatalog.FLAT)
	for i in ride.samples.size():
		assert_almost_eq(ride.samples.speed_kmh[i], ref[i], 0.01, "эмулятор, сэмпл %d: модель с уклоном" % i)
	assert_gt(speed_fields.size(), 0, "предусловие: эмулятор шлёт поле скорости — и оно не используется")


# ===========================================================================
# REQ-D3D-08 п.13 — на участке с наибольшим уклоном установившаяся скорость ниже
# ===========================================================================

func test_req_d3d_08_c13_plan_on_flat_steepest_slower_than_flattest_each_equals_model() -> void:
	var profile: RouteProfile = RouteCatalog.get_route(RouteCatalog.FLAT).profile
	var length: float = profile.length_m()
	var s_max := 0.0
	var s_min := 0.0
	var g_max := -INF
	var g_min := INF
	var x := 0.0
	while x < length:
		var g := profile.grade_at(x)
		if g > g_max:
			g_max = g
			s_max = x
		if g < g_min:
			g_min = g
			s_min = x
		x += 5.0
	gut.p("flat: макс. уклон %.2f %% на %.0f м, мин. %.2f %% на %.0f м" % [g_max, s_max, g_min, s_min])
	assert_gt(g_max - g_min, 0.5, "предусловие: у flat есть рельеф")
	var at_max := _steady_on_flat(s_max)
	var at_min := _steady_on_flat(s_min)
	assert_almost_eq(at_max, SpeedModel.steady_speed_kmh(float(POWER), WEIGHT, g_max), 0.1, "на макс. уклоне — модель для его g(s)")
	assert_almost_eq(at_min, SpeedModel.steady_speed_kmh(float(POWER), WEIGHT, g_min), 0.1, "на мин. уклоне — модель для его g(s)")
	assert_lt(at_max, at_min, "на макс. уклоне скорость ниже")


## Установившаяся скорость сессии плана на `flat` в точке `s_m` (разгон до неё издалека).
func _steady_on_flat(s_m: float) -> float:
	var fake := FakeTrainer.new(3)
	fake.connect_delay_sec = 0.0
	fake.power_noise_w = 0.0
	fake.power_tau_sec = 0.001
	fake.set_rider_power(POWER)
	fake.connect_device("fake")
	var session := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(600, float(POWER))] as Array[WorkoutStep]),
		fake, 200, 1.0, WEIGHT, RouteCatalog.FLAT)
	session.start()
	# Скорость устанавливается, пока гонщик въезжает в участок: старт так, чтобы к точке прийти
	# установившимся — подбор по пройденному пути.
	var start: float = maxf(s_m - 300.0, 0.0)
	session.position.reset(start)
	var guard := 0
	while session.position.distance_m() < s_m - start and guard < 600:
		guard += 1
		session.tick(1.0)
	var v: float = float(session.samples.last_row()["speed_kmh"])
	session.stop()
	return v


# ===========================================================================
# REQ-WRK-09 п.14 (г) (T-170), REQ-WRK-08 п.5 (T-169): в настройках нет выбора источника
# мощности и источника скорости; старый профиль с полем «power_source» загружается
# ===========================================================================

static func _visible_texts(node: Node) -> Array[String]:
	var out: Array[String] = []
	for child in node.find_children("*", "Control", true, false):
		var c := child as Control
		if not c.is_visible_in_tree():
			continue
		if c is Label:
			out.append((c as Label).text)
		elif c is Button:
			out.append((c as Button).text)
		elif c is OptionButton:
			for i in (c as OptionButton).item_count:
				out.append((c as OptionButton).get_item_text(i))
	return out


func test_req_wrk_09_c14g_wrk_08_c5_settings_without_source_choice_legacy_profile_loads() -> void:
	# Старый профиль с полем источника мощности на диске (как записывала версия до T-170).
	var path := ProjectSettings.globalize_path(_dir + "profiles/" + ProfileRepository.FILE_NAME)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var legacy := {"id": "legacy01", "name": "Old", "ftp_w": 250, "weight_kg": 70.0, "power_source": "power_meter"}
	(data["profiles"] as Array).append(legacy)
	for item: Dictionary in data["profiles"]:
		item["power_source"] = "power_meter"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	var main := _main()
	var listed := false
	for p: Profile in main.repo.list():
		assert_eq(p.validate(), [] as Array[String], "профиль %s с полем power_source валиден" % p.id)
		if p.id == "legacy01":
			listed = true
			assert_eq(p.ftp_w, 250, "старый профиль прочитан без ошибок")
	assert_true(listed, "старый профиль загружен")
	assert_eq(main.repo.get_active().id, _profile.id, "активный профиль прочитан")
	assert_true(main.app_state.navigate(AppState.Screen.SETTINGS))
	await wait_process_frames(2)
	for loc in ["ru", "en"]:
		TranslationServer.set_locale(loc)
		var s := main.settings_screen()
		s.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)
		await wait_process_frames(1)
		var texts := _visible_texts(s)
		assert_gt(texts.size(), 5, "%s: экран настроек отрисован" % loc)
		for t in texts:
			for banned in ["Источник мощности", "Power source", "Измеритель мощности", "Power meter",
					"Источник скорости", "Speed source", "скорость: ", "speed: "]:
				assert_false(t.containsn(banned), "%s: в настройках нет «%s» (текст «%s»)" % [loc, banned, t])
