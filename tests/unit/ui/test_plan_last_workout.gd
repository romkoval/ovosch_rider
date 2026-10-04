extends GutTest
## T-098: последняя выбранная тренировка в профиле — REQ-UIX-03 крит. 3 (запоминание выбора между
## запусками, решение У-14 по вопросу Н-17): (а) выбор → перезапуск (новый `ProfileRepository` на
## том же каталоге) → выбрана та же карточка; (б) тренировки нет в списке — экран без ошибки,
## предвыбор по REQ-INT-04 крит. 1; (в) профиль без поля `last_workout_id` читается; (г) выбор в
## профиле A не меняет предвыбор в профиле B (PRF-04).

const SCENE: String = "res://src/ui/plan/plan_screen.tscn"
const ACC_FULL: String = "res://tests/fixtures/workouts_acceptance/acc_full.zwo"
const SIMPLE: String = "res://tests/fixtures/workouts/simple.zwo"
const SWEET_SPOT: String = "res://tests/fixtures/workouts/sweet_spot_text.mrc"
const INTERVALS_FIXTURES: String = "res://tests/fixtures/intervals/"
const TODAY: String = "2026-10-02"
const KEY: String = "plan-last-workout-key-0001"

var _dir: String
var _repo: ProfileRepository
var _state: AppState
var _store: MemorySecureStore
var _mock: MockHttpTransport
var _cache: PlanCache
var _library: WorkoutLibrary
var _profile: Profile


func before_each() -> void:
	_dir = "user://test_plan_last_workout_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_repo = ProfileRepository.new(_dir + "profiles/")
	_profile = _repo.create("Rider")
	_profile.intervals_athlete_id = "i4242"
	_repo.save(_profile)
	_store = MemorySecureStore.new()
	_mock = MockHttpTransport.new()
	_library = WorkoutLibrary.new(_dir + "workouts/")
	_restart_state()


func after_each() -> void:
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


## «Перезапуск»: новые репозиторий профилей, состояние, кэш и библиотека на том же каталоге.
func _restart_state() -> void:
	_repo = ProfileRepository.new(_dir + "profiles/")
	_state = AppState.new(_repo)
	_state.start()
	_cache = PlanCache.new(_dir + "plans/")
	_library = WorkoutLibrary.new(_dir + "workouts/")


func _screen() -> PlanScreen:
	var s: PlanScreen = load(SCENE).instantiate()
	s.today = TODAY
	s.setup(_state, _repo, _store, _mock, _cache, _library)
	add_child_autofree(s)
	return s


func _import_all() -> void:
	for f in [ACC_FULL, SIMPLE, SWEET_SPOT]:
		assert_true(_library.import_file(_profile.id, f).ok(), "импорт %s" % f.get_file())


func _index_of(s: PlanScreen, workout_name: String) -> int:
	for i in s.items().size():
		if str(s.items()[i]["name"]) == workout_name:
			return i
	return -1


func _selected_name(s: PlanScreen) -> String:
	return str(s.selected_item().get("name", ""))


func _with_single_today_event() -> void:
	var client := IntervalsIcuClient.for_profile(_mock, _store, _profile)
	_store.set_secret(client.secret_key(), KEY)
	var json := JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string(INTERVALS_FIXTURES + "events_today.json")), OK)
	_mock.enqueue_json("GET", "/events", 200, [(json.data as Array)[0]])


# ---------------------------------------------------------------------------
# Профиль: поле, совместимость, репозиторий
# ---------------------------------------------------------------------------

func test_profile_field_round_trip_and_old_profile_without_field() -> void:
	var p := Profile.create("A")
	assert_eq(p.last_workout_id, "", "новый профиль — тренировка не выбиралась")
	p.last_workout_id = "icu:123"
	var back := Profile.from_dict(p.to_dict())
	assert_eq(back.last_workout_id, "icu:123", "поле сохраняется в словарь и читается")
	var old := p.to_dict()
	old.erase("last_workout_id")
	assert_eq(Profile.from_dict(old).last_workout_id, "", "профиль без поля читается, выбора нет")
	old["last_workout_id"] = 42
	assert_eq(Profile.from_dict(old).last_workout_id, "", "не строка — выбора нет")
	old["last_workout_id"] = "bad\nid"
	assert_eq(Profile.from_dict(old).last_workout_id, "", "управляющие символы — выбора нет")
	assert_true(Profile.from_dict(old).is_valid(), "профиль при этом корректен")


func test_repository_set_last_workout_id_persists_across_instances() -> void:
	assert_eq(_repo.set_last_workout_id(_profile.id, "lib-1"), [] as Array[String])
	var again := ProfileRepository.new(_dir + "profiles/")
	assert_eq(again.get_by_id(_profile.id).last_workout_id, "lib-1", "после перезапуска")
	assert_eq(_repo.set_last_workout_id("no-such", "x"), [ProfileRepository.ERR_PROFILE_NOT_FOUND] as Array[String])
	assert_eq(_repo.set_last_workout_id(_profile.id, "x".repeat(Profile.MAX_WORKOUT_ID_LENGTH + 1)), [] as Array[String])
	assert_eq(_repo.get_by_id(_profile.id).last_workout_id, "", "слишком длинный id — сброс")


func test_old_profiles_file_without_field_is_read() -> void:
	var path := _dir + "profiles/" + ProfileRepository.FILE_NAME
	var json := JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string(path)), OK)
	var data: Dictionary = json.data
	for entry: Dictionary in data["profiles"]:
		entry.erase("last_workout_id")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	_restart_state()
	assert_eq(_repo.count(), 1, "файл без поля читается")
	assert_eq(_repo.get_active().last_workout_id, "")
	_import_all()
	var s := _screen()
	assert_eq(s.selected_index(), -1, "(в) без сохранённого выбора и без плана Intervals.icu — ничего не выбрано")
	assert_eq(s.selected_cards().size(), 0)


# ---------------------------------------------------------------------------
# Экран плана: запись при выборе и предвыбор после перезапуска
# ---------------------------------------------------------------------------

func test_a_selected_card_is_preselected_after_restart() -> void:
	_import_all()
	var s := _screen()
	var b := _index_of(s, "Simple Endurance")
	assert_gte(b, 0, "в списке есть тренировка B")
	s.cards()[b].pressed.emit()
	assert_eq(_repo.get_active().last_workout_id, str(s.items()[b]["id"]), "выбор записан в профиль")
	s.queue_free()
	_restart_state()
	var s2 := _screen()
	assert_eq(_selected_name(s2), "Simple Endurance", "(а) после перезапуска выбрана та же тренировка")
	assert_eq(s2.selected_cards().size(), 1, "ровно одна карточка «выбрано»")
	assert_eq(s2.selected_cards()[0], s2.cards()[s2.selected_index()])
	assert_false((s2.get_node("%StartButton") as Button).disabled, "запуск доступен")


func test_remembered_selection_wins_over_single_today_rule() -> void:
	_import_all()
	_repo.set_last_workout_id(_profile.id, str(_library.list(_profile.id)[0]["id"]))
	_restart_state()
	_profile = _repo.get_active()
	_with_single_today_event()
	var s := _screen()
	await s.load_today()
	assert_eq(str(s.selected_item().get("source", "")), PlanScreen.SOURCE_LIBRARY,
			"последний выбор (библиотека) важнее единственной тренировки на сегодня")
	assert_eq(str(s.selected_item()["id"]), _repo.get_active().last_workout_id)


func test_b_missing_workout_falls_back_to_int_04_rule_without_errors() -> void:
	_repo.set_last_workout_id(_profile.id, "deleted-entry")
	_restart_state()
	_profile = _repo.get_active()
	_with_single_today_event()
	var s := _screen()
	await s.load_today()
	assert_eq(s.remembered_index(), -1, "сохранённой тренировки в списке нет")
	assert_eq(s.selected_cards().size(), 1, "(б) предвыбор по REQ-INT-04 крит. 1")
	assert_eq(str(s.selected_item()["source"]), PlanScreen.SOURCE_INTERVALS)
	assert_eq(_repo.get_active().last_workout_id, "deleted-entry", "автопредвыбор профиль не переписывает")


func test_b_deleted_library_entry_no_selection_and_screen_works() -> void:
	_import_all()
	var s := _screen()
	var i := _index_of(s, "Simple Endurance")
	s.select_index(i)
	var entry_id := str(s.items()[i]["id"])
	assert_eq(_repo.get_active().last_workout_id, entry_id)
	s.queue_free()
	assert_true(_library.delete(_profile.id, entry_id), "запись библиотеки удалена")
	_restart_state()
	var s2 := _screen()
	assert_eq(s2.selected_index(), -1, "удалённая тренировка не выбрана, ошибки нет")
	assert_eq(s2.items().size(), 2, "остальные тренировки на месте")


func test_d_selection_is_per_profile() -> void:
	_import_all()
	var other := _repo.create("Other")
	for f in [SIMPLE, SWEET_SPOT]:
		assert_true(_library.import_file(other.id, f).ok())
	var s := _screen()
	s.select_index(_index_of(s, "Simple Endurance"))
	_state.switch_profile()
	assert_true(_state.select_profile(other.id))
	s.refresh()
	assert_eq(s.selected_index(), -1, "(г) в профиле B выбор A не действует")
	s.select_index(1 - _index_of(s, "Simple Endurance"))
	_state.switch_profile()
	assert_true(_state.select_profile(_profile.id))
	s.refresh()
	assert_eq(_selected_name(s), "Simple Endurance", "в профиле A — его выбор")
	assert_ne(_repo.get_by_id(other.id).last_workout_id, _repo.get_by_id(_profile.id).last_workout_id)
