extends GutTest
## T-152: правило старта в приложении (`main.tscn`) без управляемого станка (REQ-WRK-09 п.2, 8;
## REQ-DEV-05 п.5; REQ-FRD-01 п.4). С измерителем мощности «Начать» и «Поехать» создают сессию
## `power_meter` без диалога «Станок не подключён»; заезд сохраняется с `trainer_mode`, уходит в
## очередь Strava (источник — реальный датчик); после сессии хабу возвращено управление.
## Без станка и измерителя — как прежде: сессии нет, диалог.

const MAIN_SCENE: String = "res://src/app/main.tscn"

var _dir: String
var _profiles: ProfileRepository
var _profile: Profile
var _mains: Array[AppMain] = []
var _locale_before: String


func before_each() -> void:
	_locale_before = TranslationServer.get_locale()
	_dir = "user://test_power_meter_start_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	var s := AppSettings.new(_dir + "settings.json")
	s.locale = "ru"
	s.save()
	_profiles = ProfileRepository.new(_dir + "profiles/")
	_profile = _profiles.create("Даша")
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


func _prelink(profile_id: String) -> void:
	var store := SecureStore.create_default(_dir + "secure/")
	var now := int(Time.get_unix_time_from_system())
	store.set_secret(SecureStore.key_for(profile_id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_ACCESS_TOKEN), "fixture-access-token")
	store.set_secret(SecureStore.key_for(profile_id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_REFRESH_TOKEN), "fixture-refresh-token")
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


## Измеритель мощности подключён через менеджер подключений приложения.
func _connect_power_meter(main: AppMain) -> void:
	# Пустой список сервисов — «нет сервиса» (T-154): у измерителя объявлен CPS.
	_stub(main).set_device_services("quarq", {BleUuids.CPS_SERVICE: PackedStringArray([BleUuids.CYCLING_POWER_MEASUREMENT])})
	main.connections.connect_sensor("quarq", RememberedDevices.KIND_POWER)
	_stub(main).pump()


func _packet(main: AppMain, watts: int) -> void:
	_stub(main).emit_notification("quarq", BleUuids.CYCLING_POWER_MEASUREMENT, CpsCodec.encode_cycling_power_measurement(watts))


static func _short_workout() -> Workout:
	return Workout.make("Quarq", [
		WorkoutStep.percent(20, 55.0, WorkoutStep.StepKind.WARMUP),
		WorkoutStep.percent(20, 75.0, WorkoutStep.StepKind.INTERVAL_ON),
	] as Array[WorkoutStep])


func test_req_wrk_09_c2_dev_05_c5_plan_starts_in_power_meter_mode_without_dialog() -> void:
	_prelink(_profile.id)
	var main := _main()
	assert_false(main.is_trainer_ready(), "предусловие: станка нет")
	assert_false(main.can_start_session(), "без измерителя старт запрещён")
	assert_eq(main.session_start_check()["reason"], ConnectionManager.START_NO_POWER_SOURCE)
	_connect_power_meter(main)
	var check := main.session_start_check()
	assert_true(check["allowed"], "с измерителем мощности старт разрешён")
	assert_eq(check["mode"], TrainerDevice.MODE_POWER_METER)
	assert_true(main.start_workout(_short_workout()), "«Начать» стартует сразу (WRK-09 п.2 (б))")
	assert_eq(main.app_state.current_screen, AppState.Screen.WORKOUT)
	assert_null(main.pending_workout(), "план не ждёт станка")
	var session := main.workout_screen().session()
	assert_not_null(session)
	assert_eq(session.trainer_mode, TrainerDevice.MODE_POWER_METER)
	assert_false(main.connections.ticks_devices, "устройства тикает сессия")
	var guard := 0
	while session.get_state() != WorkoutSession.State.FINISHED and guard < 200:
		guard += 1
		_packet(main, 160)
		session.tick(1.0)
	assert_eq(session.get_state(), WorkoutSession.State.FINISHED, "план прошёл по таймеру")
	assert_eq(_stub(main).calls_of("write"), [] as Array[Dictionary], "ни одной команды управления")
	var ride := main.ride_repository.get_ride(main.ride_recorder.ride_id())
	assert_not_null(ride)
	assert_eq(ride.trainer_mode(), Ride.TRAINER_MODE_POWER_METER, "WRK-09 п.8: режим в метаданных")
	assert_eq(ride.trainer_source(), Ride.TRAINER_SOURCE_BLE, "источник мощности — реальный датчик")
	assert_eq(ride.samples.power_w[ride.samples.size() - 1], 160)
	assert_true(main.strava.queue.has(ride.id), "автовыгрузка: задача Strava поставлена как обычно")
	assert_eq(main.connections.hub.power_source, SensorHub.SOURCE_TRAINER, "после сессии хабу возвращён выбор профиля")


func test_req_wrk_09_c7_frd_01_c4_free_ride_starts_with_power_meter_only() -> void:
	var main := _main()
	_connect_power_meter(main)
	assert_true(main.start_free_ride(RouteCatalog.MOUNTAINS, 50), "«Поехать» без станка с измерителем")
	assert_false(main.free_ride_trainer_dialog().visible, "диалог «Станок не подключён» не блокирует старт")
	var session := main.free_ride_screen().session()
	assert_not_null(session)
	assert_eq(session.trainer_mode, TrainerDevice.MODE_POWER_METER)
	for i in 30:
		_packet(main, 200)
		session.tick(1.0)
	assert_gt(session.distance_m(), 50.0, "едет по модели от мощности датчика")
	session.stop()
	assert_eq(_stub(main).calls_of("write"), [] as Array[Dictionary], "ни одной SIM-команды")
	var ride := main.ride_repository.get_ride(main.ride_recorder.ride_id())
	assert_eq(ride.trainer_mode(), Ride.TRAINER_MODE_POWER_METER)
	assert_true(ride.is_free_ride())


func test_req_wrk_09_c2_v_hr_and_cadence_only_still_blocked_with_dialog() -> void:
	var main := _main()
	main.connections.connect_sensor("hrs", RememberedDevices.KIND_HR)
	main.connections.connect_sensor("csc", RememberedDevices.KIND_CADENCE)
	_stub(main).pump()
	assert_false(main.can_start_session(), "только пульс и каденс — старт запрещён")
	assert_false(main.start_free_ride(RouteCatalog.FLAT, 50))
	assert_null(main.free_ride_screen().session())
	assert_true(main.free_ride_trainer_dialog().visible, "пояснение со ссылкой на устройства")
