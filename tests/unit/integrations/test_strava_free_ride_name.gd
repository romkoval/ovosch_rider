extends GutTest
## Название свободной езды в Strava (T-064): REQ-FRD-07 крит. 7 — «Свободная езда — <трасса>»
## (ru) / «Free ride — <track>» (en) на языке интерфейса вместо названия плана; регрессия
## REQ-STR-03 крит. 1 (название плана и «Тренировка <дата>»), REQ-STR-02 крит. 1 (очередь).
##
## Ключи `ride.free_ride.default_name` и `track.<id>.name` заводит T-060 в CSV переводов. Тест
## не зависит от того, слиты ли они уже: если ключ на языке не переведён, на время теста
## регистрируется перевод с теми же значениями (`tracks.md` п. 3, контракт бэклога).

const NOW: int = 1_800_000_000
const STARTED: int = 1_790_942_400
const ROUTE: String = "mountains"
const TEST_STRINGS: Dictionary = {
	"ru": {"ride.free_ride.default_name": "Свободная езда — %s", "track.mountains.name": "Перевал"},
	"en": {"ride.free_ride.default_name": "Free ride — %s", "track.mountains.name": "Mountain Pass"},
}

var _dir: String
var _mock: MockHttpTransport
var _store: MemorySecureStore
var _rides: FileRideRepository
var _profile: Profile
var _service: StravaService
var _previous_locale: String
var _added: Array[Translation] = []


func before_each() -> void:
	_previous_locale = TranslationServer.get_locale()
	_register_missing_translations()
	_dir = "user://test_strava_free_ride_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_mock = MockHttpTransport.new()
	_store = MemorySecureStore.new()
	_rides = FileRideRepository.new(_dir + "rides/")
	_profile = Profile.create("Даша")
	_service = StravaService.new(_profile, _mock, _store, _rides, StravaConfig.from_values("4242", "fixture-client-secret-value"),
			func() -> int: return NOW, _dir)
	_service.attach()
	_store.set_secret(_service.oauth.secret_key(SecureStore.ITEM_ACCESS_TOKEN), "fixture-access-token-aaaa")
	_store.set_secret(_service.oauth.secret_key(SecureStore.ITEM_REFRESH_TOKEN), "fixture-refresh-token-rrrr")
	_store.set_secret(_service.oauth.secret_key(SecureStore.ITEM_EXPIRES_AT), str(NOW + 99999))


func after_each() -> void:
	_service.dispose()
	TranslationServer.set_locale(_previous_locale)
	for t in _added:
		TranslationServer.remove_translation(t)
	_added.clear()
	_remove_tree(ProjectSettings.globalize_path(_dir))


## Перевод на время теста — только для ключей, которых в проекте ещё нет на этом языке.
func _register_missing_translations() -> void:
	for locale in TEST_STRINGS.keys():
		TranslationServer.set_locale(locale)
		var t := Translation.new()
		t.locale = locale
		var strings: Dictionary = TEST_STRINGS[locale]
		for key in strings.keys():
			if String(TranslationServer.translate(key)) == key:
				t.add_message(key, strings[key])
		if t.get_message_count() > 0:
			TranslationServer.add_translation(t)
			_added.append(t)
	TranslationServer.set_locale(_previous_locale)


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


func _free_ride(route: String = ROUTE) -> Ride:
	var r := Ride.new()
	r.id = Ride.generate_id(STARTED)
	r.profile_id = _profile.id
	r.started_at_unix = STARTED
	r.metadata = Ride.free_ride_metadata(route, 50.0)
	r.metadata["ftp_w"] = 250
	r.metadata["in_progress"] = false
	r.metadata["recovered"] = false
	r.samples.speed_source = SampleStream.SPEED_SOURCE_MODEL
	for i in 6:
		r.samples.append(i, TrainerSample.full(float(i), 220, 88, 0.0), 140, 0, -1, false, 30.0, {},
				{"distance_m": 8.0 * (i + 1), "altitude_m": 300.0 + i, "grade_pct": 3.0})
	r.events = [{"type": WorkoutSession.EVENT_START, "at_sec": 0.0, "value": 0}]
	r.compute_summary()
	return r


func _workout_ride(name: String) -> Ride:
	var r := Ride.new()
	r.id = Ride.generate_id(STARTED)
	r.profile_id = _profile.id
	r.started_at_unix = STARTED
	r.name = name
	r.workout = Workout.make(name, [WorkoutStep.watts(6, 200.0)] as Array[WorkoutStep]).to_dict()
	r.metadata = {"ftp_w": 200, "speed_source": SampleStream.SPEED_SOURCE_TRAINER, "in_progress": false}
	for i in 6:
		r.samples.append(i, TrainerSample.full(float(i), 200, 85, 30.0), 140, 200, 0, true)
	r.compute_summary()
	return r


func test_req_frd_07_c7_queue_name_is_free_ride_with_track_name_ru() -> void:
	TranslationServer.set_locale("ru")
	var ride := _free_ride()
	_rides.save(ride)
	assert_true(_service.queue.has(ride.id), "REQ-STR-02 крит. 1: свободная езда — в очереди, как обычный заезд")
	assert_eq(str(_service.queue.get_item(ride.id)["name"]), "Свободная езда — Перевал",
			"REQ-FRD-07 крит. 7: название по умолчанию на ru")


func test_req_frd_07_c7_queue_name_is_free_ride_with_track_name_en() -> void:
	TranslationServer.set_locale("en")
	var ride := _free_ride()
	_rides.save(ride)
	assert_eq(str(_service.queue.get_item(ride.id)["name"]), "Free ride — Mountain Pass",
			"REQ-FRD-07 крит. 7: название по умолчанию на en")


func test_req_frd_07_c7_default_name_and_card_rule_follow_interface_language() -> void:
	var ride := _free_ride()
	TranslationServer.set_locale("ru")
	assert_eq(_service.default_name(ride), "Свободная езда — Перевал")
	assert_eq(StravaService.compose_default_name(ride, "Тренировка %s"), "Свободная езда — Перевал",
			"карточка заезда строит название тем же правилом, шаблон «Тренировка <дата>» не применяется")
	TranslationServer.set_locale("en")
	assert_eq(_service.default_name(ride), "Free ride — Mountain Pass")


func test_req_frd_07_c7_manual_name_wins_and_unknown_track_falls_back_to_id() -> void:
	TranslationServer.set_locale("en")
	var ride := _free_ride("no_such_track")
	_rides.save(ride)
	assert_eq(str(_service.queue.get_item(ride.id)["name"]), "Free ride — no_such_track", "без перевода трассы — идентификатор")
	_service.queue.remove(ride.id)
	var other := _free_ride()
	_rides.save(other)
	_service.queue.remove(other.id)
	_rides.update_upload_status(other.id, {"strava_status": Ride.UPLOAD_NONE})
	assert_true(_service.upload_now(other.id, "Вечерний перевал"))
	assert_eq(str(_service.queue.get_item(other.id)["name"]), "Вечерний перевал", "REQ-STR-03 крит. 3: название пользователя")


func test_req_str_03_c1_workout_names_not_affected() -> void:
	TranslationServer.set_locale("ru")
	var planned := _workout_ride("Sweet Spot")
	assert_eq(_service.default_name(planned), "Sweet Spot", "название плана")
	var unnamed := _workout_ride("")
	assert_true(_service.default_name(unnamed).begins_with("Тренировка "), "без плана — «Тренировка <дата>»")
