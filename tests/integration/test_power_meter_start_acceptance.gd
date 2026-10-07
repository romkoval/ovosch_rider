extends GutTest
## Приёмка T-152 (tester): правило старта в приложении (`main.tscn`) без управляемого станка —
## REQ-WRK-09 п.2 (логика исходов, без UI), REQ-FRD-01 п.4, REQ-DEV-05 п.5, REQ-WRK-09 п.8
## (автовыгрузка). Исходы: «старт power_meter сразу» (станок не запомнен), «старта нет»,
## «переподключение» — неподключённый. Исход «нужно подтверждение» (п.2 (в)) — вне объёма T-152
## (решение владельца 2026-10-07, T-171); его проверки — в docs/tasks/T-152.md, «отложенные проверки».
## Одинаково для плана («Начать») и свободной езды («Поехать»).

const MAIN_SCENE: String = "res://src/app/main.tscn"

var _dir: String
var _profiles: ProfileRepository
var _profile: Profile
var _mains: Array[AppMain] = []
var _locale_before: String


func before_each() -> void:
	_locale_before = TranslationServer.get_locale()
	_dir = "user://acc_t152_start_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	var s := AppSettings.new(_dir + "settings.json")
	s.locale = "ru"
	s.save()
	_profiles = ProfileRepository.new(_dir + "profiles/")
	_profile = _profiles.create("Тестер")
	_profile.ftp_w = 200
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


func _prelink_strava(profile_id: String) -> void:
	var store := SecureStore.create_default(_dir + "secure/")
	var now := int(Time.get_unix_time_from_system())
	store.set_secret(SecureStore.key_for(profile_id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_ACCESS_TOKEN), "fixture-access")
	store.set_secret(SecureStore.key_for(profile_id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_REFRESH_TOKEN), "fixture-refresh")
	store.set_secret(SecureStore.key_for(profile_id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_EXPIRES_AT), str(now + 36000))


func _main() -> AppMain:
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	add_child(main)
	main.set_process(false)
	_mains.append(main)
	return main


func _stub(main: AppMain) -> StubBleBridge:
	return main.bridge as StubBleBridge


func _connect_cps(main: AppMain) -> void:
	_stub(main).set_device_services("quarq", {BleUuids.CPS_SERVICE: PackedStringArray([BleUuids.CYCLING_POWER_MEASUREMENT])})
	main.connections.connect_sensor("quarq", RememberedDevices.KIND_POWER)
	_stub(main).pump()


## Для отложенной проверки п.2 (в) (T-171).
func _remember_trainer(main: AppMain) -> void:
	main.connections.remembered.set_trainer(RememberedDevices.make_device("neo", "Tacx Neo", RememberedDevices.KIND_TRAINER))


static func _workout() -> Workout:
	return Workout.make("Quarq", [WorkoutStep.percent(15, 55.0), WorkoutStep.percent(15, 75.0)] as Array[WorkoutStep])


func _fake(main: AppMain) -> FakeTrainer:
	return main.connections.trainer as FakeTrainer


# ---------------------------------------------------------------------------
# (б) без запомненного станка — power_meter сразу; ни одной команды
# ---------------------------------------------------------------------------

func test_req_wrk_09_c2b_frd_01_c4_plan_and_ride_start_power_meter_immediately_without_remembered_trainer() -> void:
	var main := _main()
	assert_false(main.connections.remembered.has_trainer(), "предусловие: станок не запомнен")
	_connect_cps(main)
	assert_true(main.start_workout(_workout()), "«Начать» — сразу, без диалога")
	var s := main.workout_screen().session()
	assert_not_null(s, "сессия создана")
	assert_eq(s.trainer_mode, TrainerDevice.MODE_POWER_METER)
	while s.get_state() != WorkoutSession.State.FINISHED:
		_stub(main).emit_notification("quarq", BleUuids.CYCLING_POWER_MEASUREMENT, CpsCodec.encode_cycling_power_measurement(150))
		s.toggle_erg()
		s.set_resistance_level(55)
		s.tick(1.0)
	assert_eq(_stub(main).calls_of("write"), [] as Array[Dictionary], "ни одного write в мост")
	assert_eq(_fake(main).commands.size(), 0, "ни одной команды на станок приложения")
	assert_true(_fake(main).has_control(), "после сессии станку возвращено разрешение на управление")
	# Свободная езда.
	assert_true(main.start_free_ride(RouteCatalog.HILLS, 50), "«Поехать» — сразу, без диалога")
	assert_false(main.free_ride_trainer_dialog().visible)
	var fr := main.free_ride_screen().session()
	assert_not_null(fr)
	assert_eq(fr.trainer_mode, TrainerDevice.MODE_POWER_METER)
	for i in 20:
		_stub(main).emit_notification("quarq", BleUuids.CYCLING_POWER_MEASUREMENT, CpsCodec.encode_cycling_power_measurement(220))
		fr.tick(1.0)
	fr.stop()
	assert_eq(_stub(main).calls_of("write"), [] as Array[Dictionary], "ни одной SIM-команды")
	assert_eq(_fake(main).commands.size(), 0)


# ---------------------------------------------------------------------------
# (г) ни станка, ни источника мощности; (д) «переподключение» — неподключённый
# ---------------------------------------------------------------------------

func test_req_wrk_09_c2g_no_power_source_no_plan_session() -> void:
	var main := _main()
	main.connections.connect_sensor("hrs", RememberedDevices.KIND_HR)
	main.connections.connect_sensor("csc", RememberedDevices.KIND_CADENCE)
	_stub(main).pump()
	assert_false(main.can_start_session())
	assert_eq(main.session_start_check()["reason"], ConnectionManager.START_NO_POWER_SOURCE)
	assert_false(main.start_workout(_workout()))
	assert_null(main.workout_screen().session(), "план: сессия не создана")


func test_req_wrk_09_c2g_frd_01_c4_no_power_source_no_free_ride_session() -> void:
	var main2 := _main()
	main2.connections.connect_sensor("hrs", RememberedDevices.KIND_HR)
	main2.connections.connect_sensor("csc", RememberedDevices.KIND_CADENCE)
	_stub(main2).pump()
	assert_false(main2.start_free_ride(RouteCatalog.FLAT, 50))
	assert_null(main2.free_ride_screen().session(), "езда: сессия не создана")
	assert_true(main2.free_ride_trainer_dialog().visible, "диалог «Станок не подключён»")


func test_req_wrk_09_c2d_reconnecting_power_meter_counts_as_not_connected() -> void:
	var main := _main()
	_connect_cps(main)
	assert_true(main.can_start_session(), "предусловие: CPS подключён")
	_stub(main).auto_connect = false
	_stub(main).emit_disconnected("quarq", BleBridge.DisconnectReason.LINK_LOSS)
	_stub(main).pump()
	var pm := main.connections.sensor(RememberedDevices.KIND_POWER)
	assert_eq(pm.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING, "предусловие: переподключение")
	assert_false(main.can_start_session(), "«переподключение» — не «подключено»")
	assert_false(main.start_free_ride(RouteCatalog.FLAT, 50))
	assert_null(main.free_ride_screen().session())


# ---------------------------------------------------------------------------
# REQ-WRK-09 п.8 — автовыгрузка как у обычного заезда
# ---------------------------------------------------------------------------

func test_req_wrk_09_c8_power_meter_ride_ble_source_is_queued_for_strava() -> void:
	_prelink_strava(_profile.id)
	var main := _main()
	_connect_cps(main)
	assert_true(main.start_workout(_workout()))
	var s := main.workout_screen().session()
	while s.get_state() != WorkoutSession.State.FINISHED:
		_stub(main).emit_notification("quarq", BleUuids.CYCLING_POWER_MEASUREMENT, CpsCodec.encode_cycling_power_measurement(170))
		s.tick(1.0)
	var ride := main.ride_repository.get_ride(main.ride_recorder.ride_id())
	assert_not_null(ride)
	assert_eq(ride.trainer_mode(), Ride.TRAINER_MODE_POWER_METER, "get_ride → power_meter")
	assert_eq(ride.trainer_source(), Ride.TRAINER_SOURCE_BLE, "реальный датчик → ble")
	assert_true(main.strava.queue.has(ride.id), "задача выгрузки поставлена автоматически (STR-04)")
	var summaries := main.ride_repository.list(_profile.id)
	var found := false
	for x in summaries:
		if x.ride_id == ride.id:
			found = true
			assert_eq(x.trainer_mode, Ride.TRAINER_MODE_POWER_METER, "режим — в сводке истории")
	assert_true(found)
