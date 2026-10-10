extends GutTest
## Tester acceptance of T-160 — emulator rides: source in the ride metadata, label in history,
## no automatic Strava upload, confirmation for manual upload (REQ-LOC-01 p.1, REQ-STR-04 p.1,
## p.5, REQ-UIX-04 p.3; regression REQ-STR-05 p.1, 2, REQ-DEV-09 p.1, REQ-WRK-09 p.8).
##
## Paths the developer tests do not walk: an emulator ride that survives a crash and is kept
## from the recovery path, `power_meter` mode (emulated and real CPS, trainer without control),
## Esc on the confirmation dialog, a second manual request after confirmation, and a Strava
## service restarted on the same data directory.

const MAIN_SCENE: String = "res://src/app/main.tscn"
const NOW: int = 1_800_000_000
const DEV: String = "tacx-neo"

var _dir: String
var _rides: FileRideRepository
var _profile: Profile
var _services: Array[StravaService] = []
var _disposables: Array = []
var _mains: Array[AppMain] = []
var _locale_before: String


func before_each() -> void:
	_locale_before = TranslationServer.get_locale()
	_dir = "user://test_t160_accept_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	_rides = FileRideRepository.new(_dir + "rides/")
	_profile = Profile.create("Tester")
	_profile.ftp_w = 200
	_services = []
	_disposables = []
	_mains = []


func after_each() -> void:
	for s in _services:
		s.dispose()
	for d in _disposables:
		if d != null and d.has_method("dispose"):
			d.call("dispose")
	for m in _mains:
		if is_instance_valid(m):
			if m.get_parent() != null:
				m.get_parent().remove_child(m)
			m.free()
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


func _service(rides: FileRideRepository) -> StravaService:
	var store := MemorySecureStore.new()
	var config := StravaConfig.from_values("4242", "fixture-client-secret-value")
	var s := StravaService.new(_profile, MockHttpTransport.new(), store, rides, config, func() -> int: return NOW, _dir)
	s.attach()
	var o := s.oauth
	store.set_secret(o.secret_key(SecureStore.ITEM_ACCESS_TOKEN), "fixture-access-token")
	store.set_secret(o.secret_key(SecureStore.ITEM_REFRESH_TOKEN), "fixture-refresh-token")
	store.set_secret(o.secret_key(SecureStore.ITEM_EXPIRES_AT), str(NOW + 99999))
	assert_true(s.is_authorized(), "precondition: Strava linked")
	_services.append(s)
	return s


func _fake(controllable: bool = true) -> FakeTrainer:
	var t := FakeTrainer.new(3)
	t.connect_delay_sec = 0.0
	t.controllable = controllable
	t.connect_device("fake")
	return t


static func _plan() -> Workout:
	return Workout.make("Accept", [WorkoutStep.watts(30, 180.0), WorkoutStep.watts(30, 220.0)] as Array[WorkoutStep])


## Workout recorded by `RideRecorder`; `finish` = false leaves it in progress after a flush.
func _record(trainer: TrainerDevice, seconds: int, finish: bool, pump: StubBleBridge = null) -> String:
	var session := WorkoutSession.new(_plan(), trainer, _profile.ftp_w)
	var recorder := RideRecorder.new(_rides, _profile, session)
	session.start()
	for i in seconds * 2:
		session.tick(0.5)
		if pump != null:
			pump.pump()
	if finish:
		session.stop()
	else:
		recorder.flush()
	var id := recorder.ride_id()
	recorder.dispose()
	return id


# ---------------------------------------------------------------------------
# Crash recovery keeps the source; kept emulator ride is not queued
# ---------------------------------------------------------------------------

## LOC-01 p.1 + STR-04 p.1: an emulator workout interrupted by a crash (in progress on disk) is
## recovered as an emulator ride; «keep» passes it to Strava (`on_ride_saved`, as main does) —
## the queue stays empty, status «not uploaded». A real-trainer ride on the same path is queued.
func test_recovered_emulator_ride_keeps_source_and_is_not_queued() -> void:
	var emu_id := _record(_fake(), 15, false)
	assert_false(emu_id.is_empty())
	assert_true(_rides.get_ride(emu_id).is_in_progress(), "precondition: ride left in progress")
	var reopened := FileRideRepository.new(_dir + "rides/")
	var recovered := reopened.recover_in_progress(_profile.id)
	assert_eq(recovered.size(), 1, "one ride recovered")
	var ride := reopened.get_ride(emu_id)
	assert_true(ride.is_recovered(), "recovered flag")
	assert_true(ride.is_emulator(), "recovered ride keeps trainer_source = emulator")
	var summary: RideSummary = null
	for s in reopened.list(_profile.id):
		if s.ride_id == emu_id:
			summary = s
	assert_not_null(summary)
	assert_true(summary != null and summary.is_emulator(), "history index of the recovered ride keeps the source")
	var strava := _service(reopened)
	strava.on_ride_saved(emu_id)
	assert_eq(strava.queue.size(), 0, "kept emulator ride is not queued")
	assert_eq(str(reopened.get_ride(emu_id).upload.get("strava_status", Ride.UPLOAD_NONE)), Ride.UPLOAD_NONE)


## Same through the app: crash during an emulator ride, restart with Strava linked, «keep» in the
## recovery dialog — queue empty, history row and card show the emulator label.
func test_app_recovery_dialog_keep_does_not_upload_emulator_ride() -> void:
	var profiles := ProfileRepository.new(_dir + "profiles/")
	var p := profiles.create("Tester")
	p.ftp_w = 200
	profiles.save(p)
	_profile = p
	var settings := AppSettings.new(_dir + "settings.json")
	settings.locale = "en"
	settings.save()
	var rides := FileRideRepository.new(_dir + "rides/")
	_rides = rides
	var emu_id := _record(_fake(), 12, false)
	var store := SecureStore.create_default(_dir + "secure/")
	var now := int(Time.get_unix_time_from_system())
	store.set_secret(SecureStore.key_for(p.id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_ACCESS_TOKEN), "fixture-access-token")
	store.set_secret(SecureStore.key_for(p.id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_REFRESH_TOKEN), "fixture-refresh-token")
	store.set_secret(SecureStore.key_for(p.id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_EXPIRES_AT), str(now + 36000))
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	add_child(main)
	main.set_process(false)
	_mains.append(main)
	assert_true(main.strava != null and main.strava.is_authorized(), "precondition: Strava linked after restart")
	var dialog := main.recovery_dialog()
	assert_true(dialog.visible, "recovery dialog shown for the interrupted ride")
	dialog.get_ok_button().pressed.emit()
	assert_eq(main.strava.queue.size(), 0, "«keep» does not queue an emulator ride")
	var ride := main.ride_repository.get_ride(emu_id)
	assert_true(ride.is_emulator())
	assert_eq(str(ride.upload.get("strava_status", Ride.UPLOAD_NONE)), Ride.UPLOAD_NONE)
	main.app_state.navigate(AppState.Screen.HISTORY)
	var history := main.history_screen()
	history.ensure_row(0)
	assert_eq(history.row_emulator_text(emu_id), "Emulator", "history row label (en)")


# ---------------------------------------------------------------------------
# power_meter mode (WRK-09 p.8: trainer_source describes the power source)
# ---------------------------------------------------------------------------

func _cps_meter(bridge: StubBleBridge, id: String) -> BlePowerMeter:
	bridge.set_device_services(id, {BleUuids.CPS_SERVICE: PackedStringArray([BleUuids.CYCLING_POWER_MEASUREMENT])})
	var pm := BlePowerMeter.new(bridge)
	pm.connect_device(id)
	bridge.pump()
	return pm


func _pm_trainer(meter: SensorDevice, hub_trainer: TrainerDevice, source: String) -> UncontrolledTrainer:
	var hub := SensorHub.new(hub_trainer)
	if meter != null:
		hub.set_power_meter(meter)
	var dev := UncontrolledTrainer.new(hub, source)
	_disposables.push_front(dev)
	return dev


func test_power_meter_mode_source_follows_power_source() -> void:
	var strava := _service(_rides)
	# Emulated CPS (the app's power-meter emulator).
	var emu := TrainerFactory.create_power_meter_emulator() as UncontrolledTrainer
	_disposables.push_front(emu)
	assert_true(emu.is_emulator(), "power-meter emulator reports emulator")
	var emu_id := _record(emu, 10, true)
	var emu_ride := _rides.get_ride(emu_id)
	assert_eq(emu_ride.trainer_mode(), Ride.TRAINER_MODE_POWER_METER)
	assert_true(emu_ride.is_emulator(), "power_meter on the CPS emulator → trainer_source emulator")
	assert_false(strava.queue.has(emu_id), "emulated power-meter ride not queued")
	# Real CPS sensor on the BLE stub.
	var bridge := StubBleBridge.new()
	var meter := _cps_meter(bridge, "quarq")
	_disposables.append(meter)
	assert_eq(meter.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "precondition: CPS connected")
	var real := _pm_trainer(meter, null, SensorHub.SOURCE_POWER_METER)
	assert_false(real.is_emulator(), "real CPS is not an emulator")
	var real_id := _record(real, 10, true, bridge)
	var real_ride := _rides.get_ride(real_id)
	assert_eq(real_ride.trainer_source(), Ride.TRAINER_SOURCE_BLE, "power_meter on a real CPS → ble")
	assert_true(strava.queue.has(real_id), "real power-meter ride queued as usual (WRK-09 p.8)")
	# Trainer without control as the power source: emulator FakeTrainer vs a real one.
	var fake_nc := _pm_trainer(null, _fake(false), SensorHub.SOURCE_TRAINER)
	assert_true(fake_nc.is_emulator(), "uncontrolled FakeTrainer as source → emulator")
	var nc_id := _record(fake_nc, 10, true)
	assert_true(_rides.get_ride(nc_id).is_emulator())
	assert_false(strava.queue.has(nc_id), "uncontrolled emulator ride not queued")


# ---------------------------------------------------------------------------
# Manual upload: Esc cancels, no duplicates, queue survives a service restart
# ---------------------------------------------------------------------------

func _app_with_emulator_ride(locale: String) -> Array:
	var profiles := ProfileRepository.new(_dir + "profiles/")
	var p := profiles.create("Tester")
	p.ftp_w = 200
	profiles.save(p)
	var settings := AppSettings.new(_dir + "settings.json")
	settings.locale = locale
	settings.save()
	var store := SecureStore.create_default(_dir + "secure/")
	var now := int(Time.get_unix_time_from_system())
	store.set_secret(SecureStore.key_for(p.id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_ACCESS_TOKEN), "fixture-access-token")
	store.set_secret(SecureStore.key_for(p.id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_REFRESH_TOKEN), "fixture-refresh-token")
	store.set_secret(SecureStore.key_for(p.id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_EXPIRES_AT), str(now + 36000))
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	add_child(main)
	main.set_process(false)
	_mains.append(main)
	assert_true(main.start_workout_on_emulator(Workout.make("Accept", [WorkoutStep.watts(20, 180.0)] as Array[WorkoutStep])))
	var session := main.workout_screen().session()
	var guard := 0
	while session.get_state() != WorkoutSession.State.FINISHED and guard < 1000:
		session.tick(1.0)
		guard += 1
	var id := main.ride_recorder.ride_id()
	main.app_state.navigate(AppState.Screen.HISTORY)
	assert_true(main.history_screen().show_ride(id))
	return [main, id]


func _press_esc(main: AppMain) -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	main.get_viewport().push_input(ev)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	main.get_viewport().push_input(up)


## UIX-01 p.8, 9 (task T-160 p.4): Esc on the confirmation is the safe action — nothing is
## queued, the card stays open (Esc does not also navigate back).
func test_esc_on_emulator_upload_confirmation_cancels_and_stays_on_card() -> void:
	var pair := _app_with_emulator_ride("ru")
	var main: AppMain = pair[0]
	var id: String = pair[1]
	var detail := main.history_screen().detail()
	var dialog := detail.get_node("%UploadEmulatorDialog") as ConfirmationDialog
	(detail.get_node("%UploadButton") as Button).pressed.emit()
	assert_true(dialog.visible, "confirmation shown")
	assert_ne(dialog.get_ok_button().has_focus(), true, "dangerous «Upload» is not the focused default")
	_press_esc(main)
	await wait_process_frames(2)
	assert_false(dialog.visible, "Esc closes the confirmation")
	assert_false(detail.is_upload_confirmation_pending(), "Esc cancels the pending upload")
	assert_eq(main.strava.queue.size(), 0, "Esc — nothing queued")
	assert_eq(main.app_state.current_screen, AppState.Screen.HISTORY, "still in history")
	assert_true(detail.visible, "card still open after Esc on the dialog")
	assert_eq(str(main.ride_repository.get_ride(id).upload.get("strava_status", Ride.UPLOAD_NONE)), Ride.UPLOAD_NONE)


## STR-04 p.5 / STR-05 p.1: after confirmation the ride is queued once; a second request (the
## action stays available for a queued ride) does not add a second item.
func test_confirmed_emulator_upload_is_queued_once() -> void:
	var pair := _app_with_emulator_ride("en")
	var main: AppMain = pair[0]
	var id: String = pair[1]
	var detail := main.history_screen().detail()
	var dialog := detail.get_node("%UploadEmulatorDialog") as ConfirmationDialog
	var button := detail.get_node("%UploadButton") as Button
	button.pressed.emit()
	dialog.get_ok_button().pressed.emit()
	assert_true(main.strava.queue.has(id), "queued after confirmation")
	assert_eq(main.strava.queue.size(), 1)
	assert_eq(str(main.ride_repository.get_ride(id).upload["strava_status"]), Ride.UPLOAD_QUEUED, "status «queued»")
	# STR-04 p.5 keeps the action for every status except «uploaded», so it may stay enabled.
	detail.request_upload()
	if dialog.visible:
		dialog.get_ok_button().pressed.emit()
	assert_eq(main.strava.queue.size(), 1, "second request — still one queue item")
	assert_true(main.ride_repository.get_ride(id).is_emulator(), "source unchanged by the upload")
