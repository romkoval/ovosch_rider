extends GutTest
## Заезд — ble-станок (T-160: эмулятор не выгружается автоматически).
## Приёмка T-049 «Связка Strava с приложением» — независимые тесты тестировщика.
## REQ-STR-04 крит. 1, 5; REQ-STR-03 крит. 1–3; REQ-STR-05 крит. 2; REQ-STR-02 крит. 1;
## REQ-STR-01 крит. 6 (кнопка выключена без client_id/secret) и механика крит. 9
## (сам брендбук — вне контейнера).
## Источник истины — `docs/requirements.md`. Сценарии — сквозные через `main.tscn`:
## данные во временном `user://`, HTTP — `MockHttpTransport`, тренировка — на двойнике реального
## станка (`BleSourceTrainer`, источник `ble`) до завершения, привязка — токены в защищённом хранилище профиля.
## Ядро очереди/выгрузчика принято отдельно (`test_strava_acceptance.gd`) и здесь не дублируется.

const MAIN_SCENE: String = "res://src/app/main.tscn"
## Двойник реального станка: `FakeTrainer` с `is_emulator() == false` (T-160).
const BleSourceTrainer := preload("res://tests/fixtures/devices/ble_source_trainer.gd")
const CLIENT_ID: String = "4242"
const CLIENT_SECRET: String = "fixture-client-secret-value"
## 2026-10-02 12:00 UTC.
const STARTED: int = 1_790_942_400

var _dir: String
var _profiles: ProfileRepository
var _profile: Profile
var _mains: Array[AppMain] = []
var _locale_before: String


func before_each() -> void:
	_locale_before = TranslationServer.get_locale()
	_dir = "user://test_strava_svc_acc_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	_write_locale("ru")
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


# ---------------------------------------------------------------------------
# Окружение
# ---------------------------------------------------------------------------

func _write_locale(locale: String) -> void:
	var s := AppSettings.new(_dir + "settings.json")
	s.locale = locale
	s.save()


## `secrets.cfg` в каталоге данных (REQ-STR-01 крит. 6, dev-сборка).
func _write_secrets() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(StravaConfig.CFG_SECTION, "client_id", CLIENT_ID)
	cfg.set_value(StravaConfig.CFG_SECTION, "client_secret", CLIENT_SECRET)
	assert_eq(cfg.save(_dir + "secrets.cfg"), OK)


## Привязка Strava до запуска: токены в том же защищённом хранилище, что откроет `main`.
func _prelink(profile_id: String) -> void:
	var store := SecureStore.create_default(_dir + "secure/")
	var now := int(Time.get_unix_time_from_system())
	store.set_secret(SecureStore.key_for(profile_id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_ACCESS_TOKEN), "fixture-access-token")
	store.set_secret(SecureStore.key_for(profile_id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_REFRESH_TOKEN), "fixture-refresh-token")
	store.set_secret(SecureStore.key_for(profile_id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_EXPIRES_AT), str(now + 36000))


## Привязка в уже запущенном `main` (токены в его хранилище + сигнал сервиса).
func _link(main: AppMain) -> void:
	var o := main.strava.oauth
	main.secure_store.set_secret(o.secret_key(SecureStore.ITEM_ACCESS_TOKEN), "fixture-access-token")
	main.secure_store.set_secret(o.secret_key(SecureStore.ITEM_REFRESH_TOKEN), "fixture-refresh-token")
	main.secure_store.set_secret(o.secret_key(SecureStore.ITEM_EXPIRES_AT), str(int(Time.get_unix_time_from_system()) + 36000))
	main.strava.authorized_changed.emit(true)


## `main` с эмулятором и мок-транспортом. `_process` выключен: шаги очереди — только
## явным `step_queue()`, без гонки с кадрами.
func _main() -> AppMain:
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	add_child(main)
	main.set_process(false)
	_mains.append(main)
	return main


func _restart(main: AppMain) -> AppMain:
	_mains.erase(main)
	remove_child(main)
	main.free()
	return _main()


func _mock(main: AppMain) -> MockHttpTransport:
	return main.transport as MockHttpTransport


func _short_workout(name: String, description: String = "") -> Workout:
	var w := Workout.make(name, [
		WorkoutStep.percent(20, 55.0, WorkoutStep.StepKind.WARMUP),
		WorkoutStep.percent(15, 100.0, WorkoutStep.StepKind.INTERVAL_ON),
		WorkoutStep.percent(10, 50.0, WorkoutStep.StepKind.COOLDOWN),
	] as Array[WorkoutStep])
	w.description = description
	return w


## Тренировка на станке (двойник `BleSourceTrainer`, источник `ble`) до естественного завершения
## — тот же запуск, что у `AppMain` для подключённого станка: экран тренировки → навигация → старт.
## `mid_check` — вызывается на середине (заезд пишется, но не завершён). Возвращает id заезда.
func _ride_on_ble(main: AppMain, workout: Workout, mid_check: Callable = Callable()) -> String:
	var trainer: FakeTrainer = BleSourceTrainer.new()
	trainer.connect_delay_sec = 0.0
	trainer.connect_device("ble-double")
	assert_false(trainer.is_emulator(), "предусловие: заезд на реальном станке")
	var screen := main.workout_screen()
	var profile: Profile = main.repo.get_active()
	screen.setup(workout, profile, trainer, main.app_state, null)
	var started := main.app_state.navigate(AppState.Screen.WORKOUT) and screen.start()
	assert_true(started, "тренировка на эмуляторе запущена")
	var session := main.workout_screen().session()
	var total := workout.total_duration_sec() if workout.has_method("total_duration_sec") else 45
	var guard := 0
	while session.get_state() != WorkoutSession.State.FINISHED and guard < 5000:
		session.tick(1.0)
		guard += 1
		if guard == 12 and mid_check.is_valid():
			mid_check.call(main.ride_recorder.ride_id())
	assert_eq(session.get_state(), WorkoutSession.State.FINISHED, "сессия завершилась сама (план %d с)" % total)
	return main.ride_recorder.ride_id()


func _ok_upload(main: AppMain, upload_id: int, activity_id: int) -> void:
	_mock(main).enqueue_json("POST", "/uploads", 201, {"id": upload_id, "activity_id": activity_id, "error": null})


## Завершённый заезд с синтетическим потоком (для сценариев «чужой профиль» и восстановления).
func _ride(profile_id: String, name: String, started: int = STARTED, n: int = 20, in_progress: bool = false) -> Ride:
	var r := Ride.new()
	r.id = Ride.generate_id(started)
	r.profile_id = profile_id
	r.started_at_unix = started
	r.name = name
	r.description = ""
	r.workout = Workout.make(name, [WorkoutStep.watts(n, 200.0)] as Array[WorkoutStep]).to_dict()
	r.metadata = {"ftp_w": 200, "weight_kg": 75.0, "max_hr": 185, "speed_source": SampleStream.SPEED_SOURCE_TRAINER,
		"stopped_early": false, "elapsed_sec": n, "paused_total_sec": 0.0, "in_progress": in_progress, "recovered": false}
	r.samples.speed_source = SampleStream.SPEED_SOURCE_TRAINER
	for i in n:
		r.samples.append(i, TrainerSample.full(float(i + 1), 200 + i, 85, 36.0), 140, 200, 0, true)
	r.events = [{"type": WorkoutSession.EVENT_START, "at_sec": 0.0, "value": 0}]
	r.compute_summary()
	return r


# --- разбор multipart-запроса выгрузки ---------------------------------------

static func _find_bytes(hay: PackedByteArray, needle: PackedByteArray, from: int = 0) -> int:
	for i in range(from, hay.size() - needle.size() + 1):
		var ok := true
		for j in needle.size():
			if hay[i + j] != needle[j]:
				ok = false
				break
		if ok:
			return i
	return -1


## Текстовая часть тела (до файла).
static func _text_part(body: PackedByteArray) -> String:
	var idx := _find_bytes(body, "name=\"file\"".to_utf8_buffer())
	return body.slice(0, idx if idx > 0 else body.size()).get_string_from_utf8()


static func _field(body: PackedByteArray, name: String) -> String:
	var re := RegEx.new()
	re.compile("(?s)name=\"" + name + "\"\\r\\n\\r\\n(.*?)\\r\\n--")
	var m := re.search(_text_part(body))
	return m.get_string(1) if m != null else "<нет поля %s>" % name


## Байты поля `file` и имя файла.
static func _file_part(body: PackedByteArray) -> Dictionary:
	var text := _text_part(body)
	var boundary := text.substr(2, text.find("\r\n") - 2)
	var head := _find_bytes(body, "name=\"file\"; filename=\"".to_utf8_buffer())
	if head < 0:
		return {"bytes": PackedByteArray(), "filename": ""}
	var name_start := head + "name=\"file\"; filename=\"".length()
	var name_end := _find_bytes(body, "\"".to_utf8_buffer(), name_start)
	var filename := body.slice(name_start, name_end).get_string_from_utf8()
	var marker := "\r\n\r\n".to_utf8_buffer()
	var start := _find_bytes(body, marker, name_end) + marker.size()
	var tail := ("\r\n--%s--\r\n" % boundary).to_utf8_buffer()
	return {"bytes": body.slice(start, body.size() - tail.size()), "filename": filename}


func _upload_requests(main: AppMain) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in _mock(main).requests:
		if str(r["method"]) == "POST" and str(r["url"]).ends_with("/uploads"):
			out.append(r)
	return out


## Узлы класса `cls` в карточке, не считая содержимого вложенных окон (FileDialog и т.п.).
static func _card_controls(root: Node, cls: String) -> Array[Node]:
	var out: Array[Node] = []
	for c in root.get_children(true):
		if c is Window:
			continue
		if c.is_class(cls):
			out.append(c)
		out.append_array(_card_controls(c, cls))
	return out


func _local_date(unix: int) -> String:
	return HistoryScreen.format_date_time(unix).substr(0, 10)


# ---------------------------------------------------------------------------
# REQ-STR-04 крит. 1: по завершении заезда в профиле с привязкой — элемент очереди;
# очередь на диске переживает перезапуск
# ---------------------------------------------------------------------------

func test_req_str_04_c1_finished_emulator_ride_enqueued_and_survives_restart() -> void:
	_prelink(_profile.id)
	var main := _main()
	assert_not_null(main.strava, "сервис Strava создан для выбранного профиля")
	assert_true(main.strava.is_authorized(), "привязка из защищённого хранилища видна после запуска")
	var mid_state := {}
	var ride_id := _ride_on_ble(main, _short_workout("Sweet Spot"), func(id: String) -> void:
		mid_state["id"] = id
		mid_state["queued"] = main.strava.queue.has(id)
		mid_state["status"] = str(main.ride_repository.get_ride(id).upload.get("strava_status", Ride.UPLOAD_NONE)))
	assert_false(ride_id.is_empty())
	assert_eq(str(mid_state.get("id", "")), ride_id, "заезд уже пишется на диск во время тренировки")
	assert_false(bool(mid_state.get("queued", true)), "незавершённый заезд не ставится в очередь")
	assert_eq(str(mid_state.get("status", "")), Ride.UPLOAD_NONE)
	assert_true(main.strava.queue.has(ride_id), "по завершении заезд в очереди")
	assert_eq(main.strava.queue.size(), 1, "ровно один элемент")
	assert_eq(str(main.ride_repository.get_ride(ride_id).upload["strava_status"]), Ride.UPLOAD_QUEUED)
	assert_eq(_mock(main).request_count("POST"), 0, "выгрузки во время/сразу после тренировки без шага очереди нет")
	var main2 := _restart(main)
	assert_true(main2.strava.queue.has(ride_id), "очередь пережила перезапуск приложения")
	_ok_upload(main2, 11, 9001)
	await main2.strava.step_queue()
	assert_eq(_upload_requests(main2).size(), 1, "после перезапуска заезд выгружен")
	assert_eq(str(main2.ride_repository.get_ride(ride_id).upload["strava_status"]), Ride.UPLOAD_DONE)


func test_req_str_04_c1_edge_not_linked_finished_ride_not_enqueued_no_requests() -> void:
	var main := _main()
	assert_false(main.strava.is_authorized())
	var ride_id := _ride_on_ble(main, _short_workout("Sweet Spot"))
	assert_false(main.strava.queue.has(ride_id), "Strava не привязана — очереди нет")
	assert_eq(str(main.ride_repository.get_ride(ride_id).upload.get("strava_status", Ride.UPLOAD_NONE)), Ride.UPLOAD_NONE)
	await main.strava.step_queue()
	assert_eq(_mock(main).request_count(), 0, "ни одного HTTP-запроса")


func test_req_str_04_c1_edge_auto_upload_off_not_enqueued_manual_still_works() -> void:
	_profile.strava_auto_upload = false
	_profiles.save(_profile)
	_prelink(_profile.id)
	var main := _main()
	var ride_id := _ride_on_ble(main, _short_workout("Sweet Spot"))
	assert_false(main.strava.queue.has(ride_id), "автовыгрузка выключена — не ставится")
	assert_eq(str(main.ride_repository.get_ride(ride_id).upload.get("strava_status", Ride.UPLOAD_NONE)), Ride.UPLOAD_NONE)
	main.history_screen().upload_requested.emit(ride_id)
	assert_true(main.strava.queue.has(ride_id), "ручная выгрузка доступна и при выключенной автовыгрузке")


func test_req_str_04_c1_edge_resaving_same_ride_no_duplicate_queue_or_upload() -> void:
	_prelink(_profile.id)
	var main := _main()
	var ride_id := _ride_on_ble(main, _short_workout("Sweet Spot"))
	assert_eq(main.strava.queue.size(), 1)
	# Повторное сохранение того же заезда, пока он в очереди.
	main.ride_repository.save(main.ride_repository.get_ride(ride_id))
	assert_eq(main.strava.queue.size(), 1, "повторное сохранение не дублирует элемент")
	_ok_upload(main, 21, 777)
	await main.strava.step_queue()
	assert_eq(str(main.ride_repository.get_ride(ride_id).upload["strava_status"]), Ride.UPLOAD_DONE)
	# Повторное сохранение уже выгруженного заезда.
	main.ride_repository.save(main.ride_repository.get_ride(ride_id))
	assert_false(main.strava.queue.has(ride_id), "выгруженный заезд не ставится снова")
	_ok_upload(main, 22, 778)
	await main.strava.step_queue()
	assert_eq(_upload_requests(main).size(), 1, "повторной выгрузки той же тренировки нет")
	assert_eq(str(main.ride_repository.get_ride(ride_id).upload["strava_activity_id"]), "777", "activity_id не перезаписан")


func test_req_str_04_c1_edge_other_profile_ride_not_enqueued() -> void:
	var other := _profiles.create("Борис")
	_profiles.active_profile_id = _profile.id
	_prelink(_profile.id)
	_prelink(other.id)
	var main := _main()
	main.app_state.select_profile(_profile.id)
	assert_eq(main.strava.profile_id(), _profile.id)
	var foreign := _ride(other.id, "Чужой")
	main.ride_repository.save(foreign)
	assert_false(main.strava.queue.has(foreign.id), "заезд чужого профиля не ставится в очередь активного")
	assert_eq(str(main.ride_repository.get_ride(foreign.id).upload.get("strava_status", Ride.UPLOAD_NONE)), Ride.UPLOAD_NONE)


func test_req_str_04_c1_edge_recovered_ride_not_uploaded_before_user_choice() -> void:
	_prelink(_profile.id)
	var rides := FileRideRepository.new(_dir + "rides/")
	var crashed := _ride(_profile.id, "Сбой", STARTED, 30, true)
	crashed.summary = RideSummary.new()
	rides.save(crashed)
	var main := _main()
	var dialog := main.recovery_dialog()
	assert_eq(dialog.current_ride().id if dialog.current_ride() != null else "", crashed.id, "диалог восстановления показан")
	# Пользователь ещё не выбрал «сохранить досрочно» / «удалить» (REQ-LOC-07 крит. 3).
	assert_false(main.strava.queue.has(crashed.id), "незавершённый заезд не в очереди до решения пользователя")
	_ok_upload(main, 31, 555)
	await main.strava.step_queue()
	assert_eq(_upload_requests(main).size(), 0, "до решения пользователя в Strava ничего не уходит")
	dialog.delete_current()
	assert_null(main.ride_repository.get_ride(crashed.id))
	assert_false(main.strava.queue.has(crashed.id))


# ---------------------------------------------------------------------------
# REQ-STR-04 крит. 5: «выгрузить в Strava» из карточки — в очередь немедленно
# ---------------------------------------------------------------------------

func test_req_str_04_c5_card_upload_button_enqueues_immediately() -> void:
	_profile.strava_auto_upload = false
	_profiles.save(_profile)
	var main := _main()
	var ride_id := _ride_on_ble(main, _short_workout("Sweet Spot"))
	main.app_state.navigate(AppState.Screen.HISTORY)
	var history := main.history_screen()
	assert_true(history.show_ride(ride_id))
	var detail := history.detail()
	var button := detail.get_node("%UploadButton") as Button
	assert_true(button.disabled, "без привязки кнопка недоступна")
	_link(main)
	assert_false(button.disabled, "после привязки кнопка доступна для невыгруженного заезда")
	button.pressed.emit()
	assert_true(main.strava.queue.has(ride_id), "заезд в очереди сразу после нажатия")
	assert_eq(str(main.ride_repository.get_ride(ride_id).upload["strava_status"]), Ride.UPLOAD_QUEUED)
	assert_string_contains(detail.get_node("%StatusLabel").text, tr("ui.history.strava.queued"), "карточка показывает «в очереди» без перехода")
	assert_eq(_mock(main).request_count("POST"), 0, "сама выгрузка — шагом очереди")
	_ok_upload(main, 41, 4242)
	await main.strava.step_queue()
	assert_eq(_upload_requests(main).size(), 1)
	assert_true(button.disabled, "для выгруженного заезда действие недоступно")


# ---------------------------------------------------------------------------
# REQ-STR-03 крит. 1–3: название и описание
# ---------------------------------------------------------------------------

func test_req_str_03_c1_untitled_ride_name_is_workout_date_in_ui_language() -> void:
	_prelink(_profile.id)
	var main := _main()
	assert_eq(TranslationServer.get_locale().substr(0, 2), "ru", "язык интерфейса — русский (settings.json)")
	var ride_id := _ride_on_ble(main, _short_workout(""))
	var ride := main.ride_repository.get_ride(ride_id)
	var expected := "Тренировка " + _local_date(ride.started_at_unix)
	assert_eq(str(main.strava.queue.get_item(ride_id).get("name", "")), expected, "название по дате заезда")
	_ok_upload(main, 51, 5151)
	await main.strava.step_queue()
	assert_eq(_field(_upload_requests(main)[0]["body"], "name"), expected, "поле name запроса")


func test_req_str_03_c1_named_plan_name_goes_to_request() -> void:
	_prelink(_profile.id)
	var main := _main()
	var ride_id := _ride_on_ble(main, _short_workout("Пороговая 3×5"))
	_ok_upload(main, 52, 5252)
	await main.strava.step_queue()
	var reqs := _upload_requests(main)
	assert_eq(reqs.size(), 1)
	assert_eq(_field(reqs[0]["body"], "name"), "Пороговая 3×5", "название плана (кириллица, UTF-8)")
	assert_eq(_field(reqs[0]["body"], "external_id"), ride_id)


func test_req_str_03_c1_language_switched_at_runtime_name_and_app_line_follow_ui() -> void:
	_prelink(_profile.id)
	var main := _main()
	assert_true(main.app_state.set_locale("en"), "язык переключён в настройках на английский")
	var ride := _ride(_profile.id, "")
	main.ride_repository.save(ride)
	assert_true(main.strava.queue.has(ride.id))
	var item := main.strava.queue.get_item(ride.id)
	assert_eq(str(item.get("name", "")), "Workout " + _local_date(STARTED), "название на текущем языке интерфейса")
	assert_eq(str(item.get("description", "")), "Recorded in ovosch-rider", "строка приложения на текущем языке")


func test_req_str_03_c2_description_is_plan_text_plus_app_line() -> void:
	_prelink(_profile.id)
	var main := _main()
	_ride_on_ble(main, _short_workout("Sweet Spot", "3×10 мин на 90 % FTP"))
	_ok_upload(main, 53, 5353)
	await main.strava.step_queue()
	var desc := _field(_upload_requests(main)[0]["body"], "description")
	assert_string_contains(desc, "3×10 мин на 90 % FTP", "описание плана")
	assert_string_contains(desc, "ovosch-rider", "строка с названием приложения")
	assert_true(desc.find("3×10") < desc.find("ovosch-rider"), "сначала описание, затем строка приложения")


func test_req_str_03_c2_no_plan_description_only_app_line() -> void:
	_prelink(_profile.id)
	var main := _main()
	_ride_on_ble(main, _short_workout("Sweet Spot", ""))
	_ok_upload(main, 54, 5454)
	await main.strava.step_queue()
	assert_eq(_field(_upload_requests(main)[0]["body"], "description"), tr("ui.strava.default_description"))


## Пользователь меняет название и описание в карточке заезда до выгрузки.
func test_req_str_03_c3_user_edits_name_and_description_in_card_reach_request() -> void:
	_profile.strava_auto_upload = false
	_profiles.save(_profile)
	_prelink(_profile.id)
	var main := _main()
	var ride_id := _ride_on_ble(main, _short_workout("Sweet Spot", "план"))
	main.app_state.navigate(AppState.Screen.HISTORY)
	var history := main.history_screen()
	assert_true(history.show_ride(ride_id))
	var detail := history.detail()
	# Поля самой карточки (внутренние поля диалогов экспорта/удаления не в счёт).
	var name_edits := _card_controls(detail, "LineEdit")
	var desc_edits := _card_controls(detail, "TextEdit")
	assert_gt(name_edits.size(), 0, "в карточке есть поле для изменения названия перед выгрузкой")
	assert_gt(desc_edits.size(), 0, "в карточке есть поле для изменения описания перед выгрузкой")
	if name_edits.is_empty() or desc_edits.is_empty():
		return
	var name_edit := name_edits[0] as LineEdit
	name_edit.text = "Утро на Neo"
	name_edit.text_changed.emit(name_edit.text)
	name_edit.text_submitted.emit(name_edit.text)
	var desc_edit := desc_edits[0] as TextEdit
	desc_edit.text = "ноги после вчерашнего"
	desc_edit.text_changed.emit()
	(detail.get_node("%UploadButton") as Button).pressed.emit()
	_ok_upload(main, 61, 6161)
	await main.strava.step_queue()
	var reqs := _upload_requests(main)
	assert_eq(reqs.size(), 1)
	if reqs.size() == 1:
		assert_eq(_field(reqs[0]["body"], "name"), "Утро на Neo")
		assert_string_contains(_field(reqs[0]["body"], "description"), "ноги после вчерашнего")


# ---------------------------------------------------------------------------
# REQ-STR-05 крит. 2: статус в метаданных заезда, виден в списке и карточке
# ---------------------------------------------------------------------------

func test_req_str_05_c2_status_persisted_in_meta_and_shown_in_list_and_card() -> void:
	_prelink(_profile.id)
	var main := _main()
	var ride_id := _ride_on_ble(main, _short_workout("Sweet Spot"))
	main.app_state.navigate(AppState.Screen.HISTORY)
	var history := main.history_screen()
	assert_eq(history.row_count(), 1)
	assert_string_contains(history.rows()[0], tr("ui.history.strava.queued"), "список: «в очереди»")
	assert_true(history.show_ride(ride_id))
	var status_label := history.detail().get_node("%StatusLabel") as Label
	assert_string_contains(status_label.text, tr("ui.history.strava.queued"), "карточка: «в очереди»")
	_ok_upload(main, 71, 31337)
	await main.strava.step_queue()
	# Без ручного обновления экрана: статус меняется на открытой карточке и в списке.
	assert_string_contains(status_label.text, tr("ui.history.strava.done"), "карточка: «выгружено»")
	assert_string_contains(status_label.text, "https://www.strava.com/activities/31337")
	assert_string_contains(history.rows()[0], tr("ui.history.strava.done"), "список: «выгружено»")
	# Метаданные заезда на диске (новый экземпляр хранилища).
	var fresh := FileRideRepository.new(_dir + "rides/")
	var stored := fresh.get_ride(ride_id)
	assert_eq(str(stored.upload.get("strava_status", "")), Ride.UPLOAD_DONE)
	assert_eq(str(stored.upload.get("strava_activity_id", "")), "31337")
	assert_eq(fresh.list(_profile.id)[0].strava_status, Ride.UPLOAD_DONE, "индекс списка тоже обновлён")


func test_req_str_05_c2_failed_status_with_text_visible_in_card() -> void:
	_prelink(_profile.id)
	var main := _main()
	var ride_id := _ride_on_ble(main, _short_workout("Sweet Spot"))
	_mock(main).enqueue_json("POST", "/uploads", 201, {"id": 72, "activity_id": null, "error": "Improperly formatted data."})
	await main.strava.step_queue()
	assert_eq(str(main.ride_repository.get_ride(ride_id).upload["strava_status"]), Ride.UPLOAD_FAILED)
	main.app_state.navigate(AppState.Screen.HISTORY)
	var history := main.history_screen()
	assert_string_contains(history.rows()[0], tr("ui.history.strava.failed"))
	assert_true(history.show_ride(ride_id))
	var text := (history.detail().get_node("%StatusLabel") as Label).text
	assert_string_contains(text, tr("ui.history.strava.failed"))
	assert_string_contains(text, "Improperly formatted data.", "текст ошибки в карточке")


# ---------------------------------------------------------------------------
# REQ-STR-02 крит. 1: в запрос уходит FIT от FitEncoder для этого заезда
# ---------------------------------------------------------------------------

func test_req_str_02_c1_each_request_carries_fit_encoder_bytes_of_its_ride() -> void:
	_prelink(_profile.id)
	var main := _main()
	var first := _ride_on_ble(main, _short_workout("Первый"))
	var second := _ride_on_ble(main, _short_workout("Второй"))
	assert_ne(first, second)
	assert_eq(main.strava.queue.size(), 2)
	_ok_upload(main, 81, 8101)
	_ok_upload(main, 82, 8102)
	await main.strava.step_queue()
	await main.strava.step_queue()
	var reqs := _upload_requests(main)
	assert_eq(reqs.size(), 2, "оба заезда выгружены")
	var seen: Array[String] = []
	for r in reqs:
		var body: PackedByteArray = r["body"]
		var ext := _field(body, "external_id")
		seen.append(ext)
		var ride := main.ride_repository.get_ride(ext)
		assert_not_null(ride, "external_id = id заезда")
		if ride == null:
			continue
		var part := _file_part(body)
		var expected := FitEncoder.encode(ride)
		assert_gt(expected.size(), 14)
		assert_eq((part["bytes"] as PackedByteArray).size(), expected.size(), "размер файла = FitEncoder.encode(заезд)")
		assert_eq(part["bytes"], expected, "байты файла = FitEncoder.encode(заезд %s)" % ext)
		assert_eq(_field(body, "data_type"), "fit")
		assert_eq(str(part["filename"]), ext + ".fit")
		assert_true(str(r["headers"].get("Content-Type", "")).begins_with("multipart/form-data"), "multipart")
	seen.sort()
	var ids: Array[String] = [first, second]
	ids.sort()
	assert_eq(seen, ids, "каждый заезд со своим файлом")


# ---------------------------------------------------------------------------
# REQ-STR-01 крит. 6: без client_id/secret привязка недоступна, кнопка выключена;
# механика брендбука (крит. 9 — вне контейнера)
# ---------------------------------------------------------------------------

func test_req_str_01_c6_connect_button_disabled_without_client_credentials() -> void:
	var main := _main()
	assert_false(main.strava.is_configured(), "нет secrets.cfg и переменных окружения")
	main.app_state.navigate(AppState.Screen.SETTINGS)
	var settings := main.settings_screen()
	var button := settings.strava_button()
	assert_true(button.is_button_disabled(), "кнопка «Connect with Strava» выключена")
	assert_eq(settings.strava_status_text(), tr("ui.settings.strava_unavailable"), "понятное сообщение")
	assert_true(main.strava.connect_flow_start().is_empty(), "вход не начинается")


func test_req_str_01_c6_edge_button_stays_disabled_after_connect_attempt_and_relocale() -> void:
	var main := _main()
	main.app_state.navigate(AppState.Screen.SETTINGS)
	var settings := main.settings_screen()
	var button := settings.strava_button()
	assert_true(button.is_button_disabled())
	settings.start_strava_connect()
	assert_true(button.is_button_disabled(), "после неудачной попытки входа кнопка остаётся выключенной")
	main.app_state.set_locale("en")
	assert_true(button.is_button_disabled(), "после смены языка кнопка остаётся выключенной")


func test_req_str_01_c9_mechanics_connect_button_and_powered_by_with_credentials() -> void:
	_write_secrets()
	var main := _main()
	assert_true(main.strava.is_configured(), "secrets.cfg из каталога данных прочитан")
	main.app_state.navigate(AppState.Screen.SETTINGS)
	var button := main.settings_screen().strava_button()
	assert_false(button.is_button_disabled(), "с client_id/secret кнопка доступна")
	assert_eq(button.button_text(), "Connect with Strava", "текст по брендбуку и на русском интерфейсе")
	assert_eq(button.brand_color().to_html(false).to_upper(), "FC5200")
	var powered := button.get_node("%PoweredBy") as Label
	assert_true(powered.is_visible_in_tree(), "«Powered by Strava» виден на экране настроек")
	assert_eq(powered.text, "Powered by Strava")
	_link(main)
	assert_true(button.is_authorized())
	assert_ne(button.button_text(), "Connect with Strava", "после привязки — действие отвязки")
