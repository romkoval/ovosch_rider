extends GutTest
## T-160: источник станка заезда (эмулятор / реальное устройство) и Strava без автовыгрузки
## заездов на эмуляторе. REQ-LOC-01 крит. 1 (поле `trainer_source`, Н-59), REQ-STR-04 крит. 1
## (исключение для эмулятора, Н-52 (а), Н-59), регрессия REQ-STR-05 крит. 1, 2, REQ-DEV-09 крит. 1.

const DEV: String = "tacx-neo"
const FTMS_CHARS: Array[String] = ["2AD2", "2AD9", "2ADA", "2AD6", "2ACC", "2AD5"]
const NOW: int = 1_800_000_000
const STARTED: int = 1_790_942_400

var _dir: String
var _rides: FileRideRepository
var _profile: Profile
var _service: StravaService = null
## Мост станка на заглушке (ответы Control Point приходят по `pump()`).
var _bridge: StubBleBridge = null


func before_each() -> void:
	_dir = "user://test_emulator_ride_source_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_rides = FileRideRepository.new(_dir + "rides/")
	_profile = Profile.create("Даша")
	_profile.ftp_w = 200
	_bridge = null


func after_each() -> void:
	if _service != null:
		_service.dispose()
		_service = null
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


# ---------------------------------------------------------------------------
# Окружение
# ---------------------------------------------------------------------------

static func _fake() -> FakeTrainer:
	var ft := FakeTrainer.new(7)
	ft.connect_delay_sec = 0.0
	ft.connect_device("fake")
	return ft


func _ble() -> BleTrainer:
	var bridge := StubBleBridge.new()
	_bridge = bridge
	bridge.set_device_services(DEV, {"1826": FTMS_CHARS})
	bridge.set_read_value("2ACC", BleBytes.from_hex("83 40 00 00 0C 20 00 00"))
	bridge.set_read_value("2AD5", BleBytes.from_hex("9C FF C8 00 05 00"))
	bridge.set_read_value("2AD6", BleBytes.from_hex("00 00 E8 03 01 00"))
	var ble := BleTrainer.new(bridge)
	ble.connect_device(DEV)
	bridge.pump()
	assert_eq(ble.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "станок на заглушке подключён")
	return ble


static func _workout() -> Workout:
	return Workout.make("Sweet Spot", [WorkoutStep.watts(20, 200.0), WorkoutStep.watts(20, 250.0)] as Array[WorkoutStep])


func _pump() -> void:
	if _bridge != null:
		_bridge.pump()


## Тренировка с записью через `RideRecorder` (как в приложении): id сохранённого заезда.
func _record_workout(trainer: TrainerDevice, sec: int = 12) -> String:
	var session := WorkoutSession.new(_workout(), trainer, _profile.ftp_w)
	var recorder := RideRecorder.new(_rides, _profile, session)
	session.start()
	_pump()
	for i in sec:
		session.tick(0.5)
		_pump()
		session.tick(0.5)
		_pump()
	session.stop()
	assert_eq(session.get_state(), WorkoutSession.State.FINISHED)
	return recorder.ride_id()


## Свободная езда с записью через `RideRecorder`: id сохранённого заезда.
func _record_free_ride(trainer: TrainerDevice, sec: int = 12) -> String:
	var session := FreeRideSession.new(trainer, RouteCatalog.DEFAULT_ID, 50, 75.0, _profile.ftp_w)
	var recorder := RideRecorder.new(_rides, _profile, session)
	session.start()
	_pump()
	for i in sec:
		session.tick(0.5)
		_pump()
		session.tick(0.5)
		_pump()
	session.stop()
	var id := recorder.ride_id()
	session.dispose()
	return id


func _authorized_service() -> StravaService:
	var store := MemorySecureStore.new()
	var config := StravaConfig.from_values("4242", "fixture-client-secret-value")
	_service = StravaService.new(_profile, MockHttpTransport.new(), store, _rides, config, func() -> int: return NOW, _dir)
	_service.attach()
	var o := _service.oauth
	store.set_secret(o.secret_key(SecureStore.ITEM_ACCESS_TOKEN), "fixture-access-token")
	store.set_secret(o.secret_key(SecureStore.ITEM_REFRESH_TOKEN), "fixture-refresh-token")
	store.set_secret(o.secret_key(SecureStore.ITEM_EXPIRES_AT), str(NOW + 99999))
	assert_true(_service.is_authorized(), "предусловие: Strava привязана")
	return _service


## Заезд в формате до T-160: метаданные без `trainer_source`.
func _legacy_ride(n: int = 6) -> Ride:
	var r := Ride.new()
	r.id = Ride.generate_id(STARTED)
	r.profile_id = _profile.id
	r.started_at_unix = STARTED
	r.name = "Legacy"
	r.workout = Workout.make("Legacy", [WorkoutStep.watts(n, 200.0)] as Array[WorkoutStep]).to_dict()
	r.metadata = {"ftp_w": 200, "weight_kg": 75.0, "max_hr": 185, "speed_source": Ride.SPEED_SOURCE_TRAINER_LEGACY,
		"stopped_early": false, "elapsed_sec": n, "paused_total_sec": 0.0, "in_progress": false, "recovered": false}
	r.samples.speed_source = Ride.SPEED_SOURCE_TRAINER_LEGACY
	for i in n:
		r.samples.append(i, TrainerSample.full(float(i + 1), 200, 85, 36.0), 140, 200, 0, true)
	r.events = [{"type": WorkoutSession.EVENT_START, "at_sec": 0.0, "value": 0}]
	r.compute_summary()
	return r


# ---------------------------------------------------------------------------
# Признак через интерфейс TrainerDevice (REQ-DEV-09 крит. 1, REQ-NFR-06 крит. 3)
# ---------------------------------------------------------------------------

func test_trainer_device_reports_source_through_interface() -> void:
	var fake: TrainerDevice = FakeTrainer.new()
	assert_true(fake.is_emulator(), "FakeTrainer — эмулятор")
	assert_eq(fake.trainer_source(), TrainerDevice.SOURCE_EMULATOR)
	var ble: TrainerDevice = BleTrainer.new(StubBleBridge.new())
	assert_false(ble.is_emulator(), "BleTrainer — реальное устройство")
	assert_eq(ble.trainer_source(), TrainerDevice.SOURCE_BLE)
	assert_true(TrainerFactory.create(TrainerFactory.KIND_FAKE).is_emulator(), "эмулятор фабрики")


func test_sensor_hub_reports_source_of_its_trainer() -> void:
	var hub_fake := SensorHub.new(FakeTrainer.new())
	assert_true(hub_fake.is_emulator(), "хаб над эмулятором — эмулятор")
	assert_eq(hub_fake.trainer_source(), TrainerDevice.SOURCE_EMULATOR)
	hub_fake.dispose()
	var hub_ble := SensorHub.new(BleTrainer.new(StubBleBridge.new()))
	assert_false(hub_ble.is_emulator(), "хаб над BLE-станком — реальное устройство")
	hub_ble.dispose()


func test_constants_agree_between_layers() -> void:
	assert_eq(Ride.KEY_TRAINER_SOURCE, "trainer_source", "имя поля по предложению Н-59")
	assert_eq(Ride.KEY_TRAINER_SOURCE, WorkoutSession.META_TRAINER_SOURCE)
	assert_eq(Ride.TRAINER_SOURCE_BLE, "ble")
	assert_eq(Ride.TRAINER_SOURCE_EMULATOR, "emulator")


# ---------------------------------------------------------------------------
# REQ-LOC-01 крит. 1: источник станка в метаданных заезда, переживает save → get_ride
# ---------------------------------------------------------------------------

func test_req_loc_01_c1_workout_on_fake_trainer_saved_as_emulator() -> void:
	var id := _record_workout(_fake())
	assert_false(id.is_empty(), "заезд записан")
	var ride := _rides.get_ride(id)
	assert_not_null(ride)
	assert_eq(str(ride.metadata.get(Ride.KEY_TRAINER_SOURCE)), Ride.TRAINER_SOURCE_EMULATOR, "поле в meta.json")
	assert_true(ride.is_emulator())
	assert_false(ride.is_in_progress(), "заезд завершён")
	var listed := _rides.list(_profile.id)
	assert_eq(listed.size(), 1)
	assert_true(listed[0].is_emulator(), "источник в сводке списка (индекс)")


func test_req_loc_01_c1_free_ride_on_fake_trainer_saved_as_emulator() -> void:
	var id := _record_free_ride(_fake())
	var ride := _rides.get_ride(id)
	assert_not_null(ride)
	assert_true(ride.is_free_ride(), "свободная езда")
	assert_eq(ride.trainer_source(), Ride.TRAINER_SOURCE_EMULATOR)
	assert_true(_rides.list(_profile.id)[0].is_emulator())


func test_req_loc_01_c1_workout_on_ble_stub_saved_as_real_device() -> void:
	var id := _record_workout(_ble())
	var ride := _rides.get_ride(id)
	assert_not_null(ride)
	assert_eq(str(ride.metadata.get(Ride.KEY_TRAINER_SOURCE)), Ride.TRAINER_SOURCE_BLE, "станок — реальное устройство")
	assert_false(ride.is_emulator())
	assert_false(_rides.list(_profile.id)[0].is_emulator())


func test_req_loc_01_c1_free_ride_on_ble_stub_saved_as_real_device() -> void:
	var id := _record_free_ride(_ble())
	var ride := _rides.get_ride(id)
	assert_not_null(ride)
	assert_eq(ride.trainer_source(), Ride.TRAINER_SOURCE_BLE)


func test_session_metadata_has_trainer_source() -> void:
	var ws := WorkoutSession.new(_workout(), _fake(), 200)
	assert_eq(str(ws.metadata()[WorkoutSession.META_TRAINER_SOURCE]), TrainerDevice.SOURCE_EMULATOR)
	var fr := FreeRideSession.new(_ble())
	assert_eq(str(fr.metadata()[WorkoutSession.META_TRAINER_SOURCE]), TrainerDevice.SOURCE_BLE)
	fr.dispose()


func test_legacy_meta_without_field_reads_as_real_device() -> void:
	var raw := _legacy_ride().to_meta_dict()
	(raw["metadata"] as Dictionary).erase(Ride.KEY_TRAINER_SOURCE)
	(raw["summary"] as Dictionary).erase("trainer_source")
	var ride := Ride.from_meta_dict(raw)
	assert_not_null(ride, "meta.json без поля читается")
	assert_eq(ride.trainer_source(), Ride.TRAINER_SOURCE_BLE, "без поля — реальное устройство")
	assert_false(ride.is_emulator())
	assert_false(ride.metadata.has(Ride.KEY_TRAINER_SOURCE), "поле задним числом не дописывается")
	assert_false(RideSummary.from_dict(raw["summary"]).is_emulator(), "старая сводка индекса — не эмулятор")


func test_unknown_source_value_reads_as_real_device() -> void:
	var r := _legacy_ride()
	r.metadata[Ride.KEY_TRAINER_SOURCE] = "something"
	assert_eq(r.trainer_source(), Ride.TRAINER_SOURCE_BLE)
	r.metadata[Ride.KEY_TRAINER_SOURCE] = Ride.TRAINER_SOURCE_EMULATOR
	assert_true(r.is_emulator())


func test_legacy_ride_on_disk_reads_without_error() -> void:
	var r := _legacy_ride()
	assert_ne(_rides.save(r), "")
	var meta_path := ""
	for sub in DirAccess.get_directories_at(ProjectSettings.globalize_path(_dir + "rides/").path_join(_profile.id)):
		meta_path = ProjectSettings.globalize_path(_dir + "rides/").path_join(_profile.id).path_join(sub).path_join("meta.json")
	assert_true(FileAccess.file_exists(meta_path), "meta.json на диске")
	var text := FileAccess.get_file_as_string(meta_path)
	assert_false(text.contains("trainer_source\": \"emulator"), "заезд без поля не помечен эмулятором")
	var fresh := FileRideRepository.new(_dir + "rides/")
	var read := fresh.get_ride(r.id)
	assert_not_null(read)
	assert_false(read.is_emulator())
	assert_false(fresh.rebuild_index(_profile.id)[0].is_emulator(), "перестроенный индекс — не эмулятор")


# ---------------------------------------------------------------------------
# REQ-STR-04 крит. 1: заезд на эмуляторе в очередь сам не ставится (Н-52 (а), Н-59)
# ---------------------------------------------------------------------------

func test_req_str_04_c1_emulator_ride_not_enqueued_status_none() -> void:
	var svc := _authorized_service()
	var id := _record_workout(_fake())
	assert_false(svc.queue.has(id), "заезд на эмуляторе — не в очереди")
	assert_eq(svc.queue.size(), 0, "очередь пуста")
	assert_eq(str(_rides.get_ride(id).upload["strava_status"]), Ride.UPLOAD_NONE, "REQ-STR-05: «не выгружен»")


func test_req_str_04_c1_emulator_free_ride_not_enqueued() -> void:
	var svc := _authorized_service()
	var id := _record_free_ride(_fake())
	assert_eq(svc.queue.size(), 0)
	assert_eq(str(_rides.get_ride(id).upload["strava_status"]), Ride.UPLOAD_NONE)


func test_req_str_04_c1_ble_ride_enqueued_regression() -> void:
	var svc := _authorized_service()
	var id := _record_workout(_ble())
	assert_true(svc.queue.has(id), "заезд на станке — в очереди (регрессия T-049)")
	assert_eq(str(_rides.get_ride(id).upload["strava_status"]), Ride.UPLOAD_QUEUED)


func test_req_str_04_c1_legacy_ride_auto_upload_as_before() -> void:
	var svc := _authorized_service()
	var r := _legacy_ride()
	_rides.save(r)
	assert_true(svc.queue.has(r.id), "заезд без поля — как раньше, в очереди")


func test_req_str_04_c5_manual_upload_of_emulator_ride_enqueues() -> void:
	var svc := _authorized_service()
	var id := _record_workout(_fake())
	assert_eq(svc.queue.size(), 0)
	assert_true(svc.upload_now(id), "ручная выгрузка (после подтверждения в UI) доступна")
	assert_true(svc.queue.has(id))
	assert_eq(str(_rides.get_ride(id).upload["strava_status"]), Ride.UPLOAD_QUEUED)
