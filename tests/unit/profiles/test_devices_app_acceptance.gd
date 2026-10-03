extends GutTest
## Независимые приёмочные тесты (тестировщик, T-011/T-012), headless без сцен:
## - `RememberedDevices` — REQ-PRF-04 крит. 2, 3, 4; REQ-DEV-06 крит. 1 (хранение id/имя/тип);
##   REQ-PRF-01 крит. 4 (каскад: датчики удаляются, станок остаётся);
## - `AppState` — REQ-PRF-05 крит. 1, 2, 3;
## - локализация — REQ-NFR-08 крит. 1, 2, 3 (`AppLocale.pick`, CSV, ключи в UI).
## Сцены проверяются отдельно в `tests/integration/test_app_shell_acceptance.gd`.

const A: String = "aaaaaaaa-1111-4111-8111-000000000001"
const B: String = "bbbbbbbb-2222-4222-8222-000000000002"
const CSV_PATH: String = "res://assets/i18n/strings.csv"
const UI_SCAN_DIRS: Array[String] = ["res://src/ui", "res://src/app", "res://src/scene3d"]

var _dir: String
var _dev: RememberedDevices
var _changes: int = 0


func before_each() -> void:
	_dir = "user://test_acc_devices_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_changes = 0
	_dev = _open_devices()


func after_each() -> void:
	_remove_tree(ProjectSettings.globalize_path(_dir))
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_dir)), "временный каталог удалён")


func _open_devices() -> RememberedDevices:
	var d := RememberedDevices.new(_dir + "devices/")
	d.changed.connect(func() -> void: _changes += 1)
	return d


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


func _hr(id: String = "hr-1", name: String = "Garmin HRM") -> Dictionary:
	return RememberedDevices.make_device(id, name, RememberedDevices.KIND_HR)


func _cad(id: String = "cad-1", name: String = "Wahoo Cadence") -> Dictionary:
	return RememberedDevices.make_device(id, name, RememberedDevices.KIND_CADENCE)


func _neo(id: String = "neo-1", name: String = "Tacx Neo 2T") -> Dictionary:
	return RememberedDevices.make_device(id, name, RememberedDevices.KIND_TRAINER)


func _ids_of(list: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for d in list:
		out.append(str(d["id"]))
	return out


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


# ===========================================================================
# REQ-DEV-06 крит. 1 — хранение (id, имя, тип): станок на устройстве, датчики в профиле
# ===========================================================================

func test_req_dev_06_c1_sensor_record_persists_id_name_kind_in_profile_file() -> void:
	assert_true(_dev.remember(A, _hr("hr-77", "Polar H10")))
	var path := _dev.profile_file_path(A)
	assert_true(FileAccess.file_exists(path), "файл датчиков профиля создан")
	assert_true(path.begins_with(_dir + "devices/" + RememberedDevices.PROFILE_FILE_PREFIX))
	var data := _read_json(path)
	assert_eq(data.get("profile_id"), A)
	var items: Array = data.get("devices", [])
	assert_eq(items.size(), 1)
	assert_eq(items[0]["id"], "hr-77")
	assert_eq(items[0]["name"], "Polar H10")
	assert_eq(items[0]["kind"], RememberedDevices.KIND_HR)
	assert_true(bool(items[0]["auto_connect"]))
	assert_gt(int(items[0]["last_seen_at"]), 0)
	assert_false(FileAccess.file_exists(_dev.trainer_file_path()), "датчик не пишется в файл станка")


func test_req_dev_06_c1_trainer_record_persists_on_device_level_file() -> void:
	assert_true(_dev.remember(A, _neo("neo-9", "Tacx Neo")))
	assert_true(FileAccess.file_exists(_dev.trainer_file_path()))
	assert_false(FileAccess.file_exists(_dev.profile_file_path(A)), "станок не пишется в файл профиля")
	var data := _read_json(_dev.trainer_file_path())
	var t: Dictionary = data.get("trainer", {})
	assert_eq(t.get("id"), "neo-9")
	assert_eq(t.get("name"), "Tacx Neo")
	assert_eq(t.get("kind"), RememberedDevices.KIND_TRAINER)
	assert_eq(_dev.trainer()["id"], "neo-9")


func test_req_dev_06_c1_records_survive_restart_for_sensor_and_trainer() -> void:
	_dev.remember(A, _hr("hr-1", "HRM"))
	_dev.remember(A, _cad("cad-1", "Cadence"))
	_dev.remember(B, _neo("neo-1", "Neo"))
	var again := RememberedDevices.new(_dir + "devices/")
	assert_eq(_ids_of(again.sensors(A)), ["cad-1", "hr-1"], "датчики по имени")
	assert_eq(again.sensors(A)[1]["name"], "HRM")
	assert_eq(again.sensors(A)[1]["kind"], RememberedDevices.KIND_HR)
	assert_true(again.has_trainer())
	assert_eq(again.trainer()["name"], "Neo")


func test_req_dev_06_c1_all_four_kinds_are_accepted_and_unknown_kind_rejected() -> void:
	for kind in [RememberedDevices.KIND_HR, RememberedDevices.KIND_CADENCE, RememberedDevices.KIND_POWER]:
		assert_true(_dev.remember(A, RememberedDevices.make_device("d-" + kind, kind, kind)), kind)
	assert_eq(_dev.sensors(A).size(), 3)
	assert_false(_dev.remember(A, RememberedDevices.make_device("d-speed", "Speed", "speed")), "неизвестный kind")
	assert_false(_dev.remember(A, RememberedDevices.make_device("d-x", "X", "")), "пустой kind")
	assert_false(_dev.remember(A, RememberedDevices.make_device("d-x", "X", "TRAINER")), "kind чувствителен к регистру")
	assert_eq(_dev.sensors(A).size(), 3)
	assert_false(_dev.has_trainer())


func test_req_dev_06_c1_empty_id_is_rejected_without_creating_files() -> void:
	assert_false(_dev.remember(A, RememberedDevices.make_device("", "NoId", RememberedDevices.KIND_HR)))
	assert_false(_dev.remember(A, RememberedDevices.make_device("", "NoId", RememberedDevices.KIND_TRAINER)))
	assert_false(_dev.set_trainer({"name": "no id"}))
	assert_false(_dev.remember(A, {}))
	assert_false(RememberedDevices.is_valid_device({}))
	assert_false(_dev.remember("", _hr()), "датчик без профиля некуда записать")
	assert_eq(_changes, 0)
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_dir)), "ничего не записано")


func test_req_dev_06_c1_same_id_replaces_record_instead_of_duplicating() -> void:
	_dev.remember(A, _hr("hr-1", "Old name"))
	_dev.remember(A, _hr("hr-1", "New name"))
	assert_eq(_dev.sensors(A).size(), 1)
	assert_eq(_dev.sensors(A)[0]["name"], "New name")
	var items: Array = _read_json(_dev.profile_file_path(A)).get("devices", [])
	assert_eq(items.size(), 1, "на диске тоже одна запись")


func test_req_dev_06_c1_returned_records_are_copies_and_file_unchanged_by_mutation() -> void:
	_dev.remember(A, _hr("hr-1", "HRM"))
	_dev.set_trainer(_neo())
	_dev.sensors(A)[0]["name"] = "hacked"
	_dev.trainer()["name"] = "hacked"
	_dev.list(A)[0]["id"] = "hacked"
	assert_eq(_dev.sensors(A)[0]["name"], "HRM")
	assert_eq(_dev.trainer()["name"], "Tacx Neo 2T")
	assert_eq(RememberedDevices.new(_dir + "devices/").trainer()["name"], "Tacx Neo 2T")


func test_req_dev_06_c4_forget_and_auto_connect_flag_remove_device_from_candidates() -> void:
	_dev.remember(A, _hr("hr-1"))
	_dev.remember(A, _cad("cad-1"))
	_dev.set_trainer(_neo())
	assert_eq(_ids_of(_dev.auto_connect_candidates(A)), ["neo-1", "hr-1", "cad-1"], "станок первым, датчики по имени (Garmin < Wahoo)")
	assert_true(_dev.set_auto_connect(A, "cad-1", false))
	assert_eq(_ids_of(_dev.auto_connect_candidates(A)), ["neo-1", "hr-1"])
	assert_true(_dev.forget(A, "hr-1"))
	assert_eq(_ids_of(_dev.auto_connect_candidates(A)), ["neo-1"])
	assert_eq(_ids_of(RememberedDevices.new(_dir + "devices/").auto_connect_candidates(A)), ["neo-1"], "после перезапуска забытый не возвращается")
	assert_false(_dev.set_auto_connect(A, "ghost", true), "неизвестное устройство")


# ===========================================================================
# REQ-PRF-04 крит. 2 — датчик профиля A не предлагается в профиле B
# ===========================================================================

func test_req_prf_04_c2_hr_sensor_of_a_is_not_visible_in_b_anywhere() -> void:
	assert_true(_dev.remember(A, _hr("hr-A", "A's HRM")))
	assert_eq(_dev.sensors(B), [])
	assert_eq(_dev.list(B), [])
	assert_eq(_dev.auto_connect_candidates(B), [], "REQ-PRF-04 крит. 2")
	assert_eq(_dev.find(B, "hr-A"), {})
	assert_false(_dev.has_profile_devices(B))
	assert_false(FileAccess.file_exists(_dev.profile_file_path(B)))
	assert_eq(_ids_of(_dev.auto_connect_candidates(A)), ["hr-A"])


func test_req_prf_04_c2_isolation_holds_after_restart_and_for_same_device_id_in_both() -> void:
	_dev.remember(A, _hr("hr-same", "In A"))
	_dev.remember(B, _hr("hr-same", "In B"))
	var again := RememberedDevices.new(_dir + "devices/")
	assert_eq(again.sensors(A)[0]["name"], "In A")
	assert_eq(again.sensors(B)[0]["name"], "In B")
	assert_true(again.forget(A, "hr-same"))
	assert_eq(again.sensors(A), [])
	assert_eq(again.sensors(B).size(), 1, "забывание в A не трогает B")


func test_req_prf_04_c2_forget_in_wrong_profile_does_nothing() -> void:
	_dev.remember(A, _hr("hr-A"))
	_changes = 0
	assert_false(_dev.forget(B, "hr-A"), "у B такого датчика нет")
	assert_false(_dev.forget(A, "ghost"))
	assert_false(_dev.forget("", "hr-A"), "без профиля датчик не найти")
	assert_eq(_changes, 0, "сигнал changed не испускается впустую")
	assert_eq(_dev.sensors(A).size(), 1)


# ===========================================================================
# REQ-PRF-04 крит. 3 — станок общий для всех профилей
# ===========================================================================

func test_req_prf_04_c3_trainer_remembered_via_a_is_auto_connect_candidate_in_b_and_c() -> void:
	assert_true(_dev.remember(A, _neo()))
	for pid in [A, B, "cccccccc-3333-4333-8333-000000000003", ""]:
		assert_eq(_ids_of(_dev.auto_connect_candidates(pid)), ["neo-1"], "профиль %s видит станок" % pid)
		assert_eq(_dev.find(pid, "neo-1")["kind"], RememberedDevices.KIND_TRAINER)
	assert_eq(_dev.list(B)[0]["id"], "neo-1", "станок первым в списке")
	assert_eq(_dev.sensors(B), [], "но среди датчиков профиля его нет")


func test_req_prf_04_c3_trainer_is_single_shared_record_replaced_from_any_profile() -> void:
	_dev.remember(A, _neo("neo-1", "Neo from A"))
	_dev.remember(B, _neo("neo-2", "Neo from B"))
	assert_eq(_dev.trainer()["id"], "neo-2", "последний запомненный станок — общий")
	assert_eq(_ids_of(_dev.list(A)), ["neo-2"])
	assert_eq(_dev.list(A).size(), 1, "старый станок не остался «в A»")
	var again := RememberedDevices.new(_dir + "devices/")
	assert_eq(again.trainer()["name"], "Neo from B")
	assert_eq(_ids_of(again.auto_connect_candidates(A)), ["neo-2"])


func test_req_prf_04_c3_forgetting_trainer_from_b_removes_it_for_a_too() -> void:
	_dev.remember(A, _neo())
	_dev.remember(A, _hr())
	assert_true(_dev.forget(B, "neo-1"))
	assert_false(_dev.has_trainer())
	assert_eq(_ids_of(_dev.list(A)), ["hr-1"], "датчики A не пострадали")
	assert_false(FileAccess.file_exists(_dev.trainer_file_path()), "файл станка удалён")
	assert_false(RememberedDevices.new(_dir + "devices/").has_trainer())


func test_req_prf_04_c3_trainer_with_auto_connect_off_is_shared_but_not_a_candidate() -> void:
	var t := _neo()
	t["auto_connect"] = false
	_dev.set_trainer(t)
	assert_true(_dev.has_trainer())
	assert_eq(_dev.list(B).size(), 1)
	assert_eq(_dev.auto_connect_candidates(B), [])
	assert_true(_dev.set_auto_connect(B, "neo-1", true), "флаг станка переключается из любого профиля")
	assert_eq(_ids_of(_dev.auto_connect_candidates(A)), ["neo-1"])


# ===========================================================================
# REQ-PRF-04 крит. 4 / REQ-PRF-01 крит. 4 — удаление профиля не трогает станок
# ===========================================================================

func test_req_prf_04_c4_cascade_delete_removes_a_sensors_keeps_trainer_and_b_sensors() -> void:
	var repo := ProfileRepository.new(_dir + "profiles/")
	var a := repo.create("A")
	var b := repo.create("B")
	_dev.attach_to_profiles(repo)
	_dev.remember(a.id, _hr("hr-A"))
	_dev.remember(a.id, _cad("cad-A"))
	_dev.remember(b.id, _hr("hr-B"))
	_dev.remember(a.id, _neo())
	assert_true(_dev.has_profile_devices(a.id))
	assert_eq(repo.delete(a.id), "")
	assert_true(_dev.has_trainer(), "REQ-PRF-04 крит. 4: станок остался")
	assert_eq(_dev.trainer()["id"], "neo-1")
	assert_true(FileAccess.file_exists(_dev.trainer_file_path()))
	assert_eq(_dev.sensors(a.id), [], "датчики удалённого профиля стёрты")
	assert_false(FileAccess.file_exists(_dev.profile_file_path(a.id)), "файл датчиков удалён")
	assert_eq(_ids_of(_dev.sensors(b.id)), ["hr-B"], "датчики B целы")
	var again := RememberedDevices.new(_dir + "devices/")
	assert_true(again.has_trainer())
	assert_eq(again.sensors(a.id), [])
	assert_eq(again.sensors(b.id).size(), 1)


func test_req_prf_04_c4_deleting_profile_without_devices_file_is_harmless() -> void:
	var repo := ProfileRepository.new(_dir + "profiles/")
	var a := repo.create("A")
	repo.create("B")
	_dev.attach_to_profiles(repo)
	_dev.set_trainer(_neo())
	assert_false(_dev.has_profile_devices(a.id))
	assert_eq(repo.delete(a.id), "")
	assert_true(_dev.has_trainer())
	assert_false(FileAccess.file_exists(_dev.profile_file_path(a.id)))


func test_req_prf_04_c4_refused_deletion_of_last_profile_keeps_devices() -> void:
	var repo := ProfileRepository.new(_dir + "profiles/")
	var only := repo.create("Solo")
	_dev.attach_to_profiles(repo)
	_dev.remember(only.id, _hr())
	_dev.set_trainer(_neo())
	assert_eq(repo.delete(only.id), ProfileRepository.ERR_LAST_PROFILE)
	assert_eq(_dev.sensors(only.id).size(), 1)
	assert_true(_dev.has_trainer())


func test_req_prf_04_c4_delete_profile_devices_direct_call_with_empty_id_is_noop() -> void:
	_dev.set_trainer(_neo())
	_dev.remember(A, _hr())
	_changes = 0
	_dev.delete_profile_devices("")
	assert_eq(_changes, 0)
	assert_eq(_dev.sensors(A).size(), 1)
	assert_true(_dev.has_trainer())


# ===========================================================================
# Негатив: повреждённые файлы, странные идентификаторы
# ===========================================================================

func test_req_prf_04_corrupted_profile_devices_file_is_ignored_with_warning_and_overwritten() -> void:
	_write_text(_dev.profile_file_path(A), "{{ broken json")
	var broken := RememberedDevices.new(_dir + "devices/")
	assert_eq(broken.sensors(A), [])
	assert_push_warning("повреждён")
	assert_true(broken.remember(A, _hr()), "запись после повреждения работает")
	assert_eq(RememberedDevices.new(_dir + "devices/").sensors(A).size(), 1)


func test_req_prf_04_corrupted_trainer_file_is_ignored_and_other_profiles_unaffected() -> void:
	_dev.remember(A, _hr())
	_write_text(_dev.trainer_file_path(), "[1,2,3]")
	var broken := RememberedDevices.new(_dir + "devices/")
	assert_push_warning("повреждён")
	assert_false(broken.has_trainer())
	assert_eq(broken.sensors(A).size(), 1, "датчики A читаются независимо от файла станка")


func test_req_prf_04_profile_file_with_garbage_entries_keeps_only_valid_sensors() -> void:
	var payload := {"schema": 1, "profile_id": A, "devices": [
		1, "x", null, {"id": "", "kind": "hr"}, {"id": "no-kind"}, {"id": "bad-kind", "kind": "speed"},
		{"id": "trainer-in-profile", "kind": "trainer", "name": "Neo"},
		{"id": "ok-hr", "kind": "hr", "name": "Good HRM"},
	]}
	_write_text(_dev.profile_file_path(A), JSON.stringify(payload))
	var d := RememberedDevices.new(_dir + "devices/")
	assert_eq(_ids_of(d.sensors(A)), ["ok-hr"], "мусор и станок в файле профиля игнорируются")
	assert_false(d.has_trainer(), "станок из файла профиля не становится общим")


func test_req_prf_04_trainer_file_without_id_is_ignored() -> void:
	_write_text(_dev.trainer_file_path(), JSON.stringify({"schema": 1, "trainer": {"name": "Nameless", "kind": "trainer"}}))
	assert_false(RememberedDevices.new(_dir + "devices/").has_trainer())
	_write_text(_dev.trainer_file_path(), JSON.stringify({"schema": 1, "trainer": "neo"}))
	assert_false(RememberedDevices.new(_dir + "devices/").has_trainer())


func test_req_prf_04_profile_id_with_path_characters_stays_inside_devices_dir() -> void:
	var weird := "../../evil/..\\id"
	var path := _dev.profile_file_path(weird)
	assert_true(path.begins_with(_dir + "devices/"), "путь не выходит за каталог: %s" % path)
	assert_eq(path.get_base_dir() + "/", _dir + "devices/", "файл лежит прямо в каталоге устройств, разделители из id вычищены")
	assert_true(_dev.remember(weird, _hr()))
	assert_true(FileAccess.file_exists(path))
	var files: Array[String] = []
	var dir := DirAccess.open(_dir + "devices/")
	for f in dir.get_files():
		files.append(f)
	assert_eq(files.size(), 1)


func test_req_prf_04_changed_signal_fires_once_per_mutation() -> void:
	_dev.remember(A, _hr())
	_dev.set_trainer(_neo())
	_dev.forget(A, "hr-1")
	_dev.clear_trainer()
	_dev.clear_trainer()
	assert_eq(_changes, 4)


# ===========================================================================
# REQ-PRF-05 — правило старта (AppState, без сцен)
# ===========================================================================

func _repo() -> ProfileRepository:
	return ProfileRepository.new(_dir + "profiles/")


func test_req_prf_05_c1_single_profile_is_auto_selected_and_home_opens() -> void:
	var repo := _repo()
	var only := repo.create("Solo")
	var state := AppState.new(repo)
	var screens: Array[int] = []
	var selected: Array[String] = []
	state.screen_changed.connect(func(s: int) -> void: screens.append(s))
	state.profile_selected.connect(func(id: String) -> void: selected.append(id))
	assert_eq(AppState.initial_screen(repo), AppState.Screen.HOME)
	state.start()
	assert_eq(state.current_screen, AppState.Screen.HOME, "экран выбора не показывается")
	assert_eq(repo.active_profile_id, only.id, "профиль активен сразу")
	assert_true(state.is_profile_chosen())
	assert_true(state.can_open_main())
	assert_false(state.create_mode)
	assert_eq(selected, [only.id])
	assert_eq(screens, [AppState.Screen.HOME])
	assert_true(state.navigate(AppState.Screen.WORKOUT))


func test_req_prf_05_c2_two_profiles_require_choice_even_with_saved_active() -> void:
	var repo := _repo()
	var a := repo.create("A")
	var b := repo.create("B")
	repo.active_profile_id = b.id
	var state := AppState.new(repo)
	assert_eq(AppState.initial_screen(repo), AppState.Screen.PROFILE_SELECT)
	state.start()
	assert_eq(state.current_screen, AppState.Screen.PROFILE_SELECT)
	assert_false(state.can_open_main(), "главный экран недоступен до выбора")
	assert_false(state.is_profile_chosen())
	assert_false(state.create_mode, "это не режим создания")
	for screen in [AppState.Screen.HOME, AppState.Screen.WORKOUT, AppState.Screen.HISTORY, AppState.Screen.SETTINGS, AppState.Screen.DEV]:
		assert_false(state.navigate(screen), "navigate(%s) заблокирован" % AppState.screen_name(screen))
		assert_eq(state.current_screen, AppState.Screen.PROFILE_SELECT)
	assert_true(state.navigate(AppState.Screen.PROFILE_SELECT))
	assert_false(state.select_profile("ghost"))
	assert_eq(state.current_screen, AppState.Screen.PROFILE_SELECT)
	assert_true(state.select_profile(a.id))
	assert_eq(state.current_screen, AppState.Screen.HOME)
	assert_eq(repo.active_profile_id, a.id)
	assert_eq(ProfileRepository.new(_dir + "profiles/").active_profile_id, a.id, "выбор сохранён на диск")
	assert_true(state.can_open_main())
	assert_ne(a.id, b.id)


func test_req_prf_05_c2_many_profiles_and_switch_profile_locks_main_again() -> void:
	var repo := _repo()
	for i in 12:
		repo.create("P%02d" % i)
	var state := AppState.new(repo)
	state.start()
	assert_eq(state.current_screen, AppState.Screen.PROFILE_SELECT)
	state.select_profile(repo.list()[5].id)
	assert_true(state.navigate(AppState.Screen.SETTINGS))
	state.switch_profile()
	assert_eq(state.current_screen, AppState.Screen.PROFILE_SELECT)
	assert_false(state.can_open_main())
	assert_false(state.navigate(AppState.Screen.HOME))
	assert_eq(repo.active_profile_id, repo.list()[5].id, "активный в репозитории не сброшен, но выбор требуется заново")


func test_req_prf_05_c3_no_profiles_opens_create_mode_and_blocks_main() -> void:
	var repo := _repo()
	var state := AppState.new(repo)
	assert_eq(AppState.initial_screen(repo), AppState.Screen.PROFILE_SELECT)
	state.start()
	assert_eq(state.current_screen, AppState.Screen.PROFILE_SELECT)
	assert_true(state.create_mode, "режим создания первого профиля")
	assert_false(state.can_open_main())
	assert_false(state.navigate(AppState.Screen.HOME))
	assert_false(state.select_profile(""), "выбирать нечего")
	# первый созданный профиль нужно выбрать явно (или перезапустить правило старта)
	var p := repo.create("First")
	assert_true(state.select_profile(p.id))
	assert_false(state.create_mode)
	assert_eq(state.current_screen, AppState.Screen.HOME)


func test_req_prf_05_c3_restart_after_first_profile_goes_straight_home() -> void:
	var repo := _repo()
	var state := AppState.new(repo)
	state.start()
	assert_true(state.create_mode)
	repo.create("First")
	var relaunch := AppState.new(ProfileRepository.new(_dir + "profiles/"))
	relaunch.start()
	assert_eq(relaunch.current_screen, AppState.Screen.HOME, "при перезапуске с одним профилем — сразу HOME")
	assert_false(relaunch.create_mode)


func test_req_prf_05_initial_screen_rule_for_0_1_2_100_profiles() -> void:
	var repo := _repo()
	assert_eq(AppState.initial_screen(repo), AppState.Screen.PROFILE_SELECT)
	repo.create("P0")
	assert_eq(AppState.initial_screen(repo), AppState.Screen.HOME)
	repo.create("P1")
	assert_eq(AppState.initial_screen(repo), AppState.Screen.PROFILE_SELECT)
	for i in range(2, 100):
		repo.create("P%d" % i)
	assert_eq(repo.count(), 100)
	assert_eq(AppState.initial_screen(repo), AppState.Screen.PROFILE_SELECT)


func test_req_prf_05_start_after_deleting_down_to_one_profile_autoselects_remaining() -> void:
	var repo := _repo()
	var a := repo.create("A")
	var b := repo.create("B")
	var state := AppState.new(repo)
	state.start()
	assert_eq(state.current_screen, AppState.Screen.PROFILE_SELECT)
	assert_eq(repo.delete(b.id), "")
	state.start()
	assert_eq(state.current_screen, AppState.Screen.HOME)
	assert_eq(repo.active_profile_id, a.id)


# ===========================================================================
# REQ-PRF-01 крит. 3 (часть: FTP/зоны/датчики при переключении) — без сцен
# ===========================================================================

func test_req_prf_01_c3_switching_profile_changes_ftp_zones_and_sensor_list() -> void:
	var repo := _repo()
	var a := repo.create("A")
	var b := repo.create("B")
	var ea := a.duplicate_profile()
	ea.ftp_w = 200
	var eb := b.duplicate_profile()
	eb.ftp_w = 300
	eb.max_hr = 180
	assert_eq(repo.save(ea), [])
	assert_eq(repo.save(eb), [])
	_dev.remember(a.id, _hr("hr-A", "A HRM"))
	_dev.remember(b.id, _cad("cad-B", "B Cadence"))
	_dev.set_trainer(_neo())
	var state := AppState.new(repo)
	state.start()
	state.select_profile(a.id)
	var active := repo.get_active()
	assert_eq(active.ftp_w, 200)
	assert_eq(active.power_zone_of(230), 5)
	assert_eq(active.hr_zone_of(150), 0, "у A max_hr не задан")
	assert_eq(_ids_of(_dev.auto_connect_candidates(active.id)), ["neo-1", "hr-A"])
	state.switch_profile()
	state.select_profile(b.id)
	active = repo.get_active()
	assert_eq(active.ftp_w, 300)
	assert_eq(active.power_zone_of(230), 3)
	assert_eq(active.hr_zone_of(150), 4)
	assert_eq(_ids_of(_dev.auto_connect_candidates(active.id)), ["neo-1", "cad-B"], "станок общий, датчики свои")


# ===========================================================================
# REQ-NFR-08 крит. 3 — язык по системе с откатом на en
# ===========================================================================

func test_req_nfr_08_c3_pick_locale_rules() -> void:
	var cases := {
		"ru": "ru", "RU": "ru", "ru_RU": "ru", "ru-RU": "ru", "ru_UA": "ru",
		"en": "en", "en_US": "en", "en_GB": "en", "EN": "en",
		"de": "en", "de_DE": "en", "uk": "en", "uk_UA": "en", "be": "en", "kk": "en", "fr": "en", "zh_CN": "en",
		"": "en", "r": "en", "e": "en", "xx": "en",
	}
	for input in cases.keys():
		assert_eq(AppLocale.pick(input), cases[input], "pick(%s)" % JSON.stringify(input))
		assert_eq(AppState.pick_locale(input), cases[input], "AppState.pick_locale(%s)" % JSON.stringify(input))
	assert_eq(AppLocale.FALLBACK_LOCALE, "en")
	assert_eq(AppLocale.SUPPORTED_LOCALES, ["en", "ru"])
	assert_has(AppLocale.SUPPORTED_LOCALES, AppLocale.detect(), "detect() возвращает поддерживаемый язык")


func test_req_nfr_08_c3_project_declares_both_translations_and_en_fallback() -> void:
	var translations: PackedStringArray = ProjectSettings.get_setting("internationalization/locale/translations", PackedStringArray())
	assert_has(translations, "res://assets/i18n/strings.ru.translation")
	assert_has(translations, "res://assets/i18n/strings.en.translation")
	assert_eq(str(ProjectSettings.get_setting("internationalization/locale/fallback", "")), "en")
	assert_eq(str(ProjectSettings.get_setting("application/run/main_scene", "")), "res://src/app/main.tscn")


# ===========================================================================
# REQ-NFR-08 крит. 1, 2 — все ключи UI в CSV; ru и en непустые; без кириллицы в UI
# ===========================================================================

func _load_csv() -> Dictionary:
	# Все файлы переводов: strings.csv и файлы по областям strings_<область>.csv (T-060).
	var table: Dictionary = {}
	var dir := DirAccess.open(CSV_PATH.get_base_dir())
	assert_not_null(dir, "каталог переводов открывается")
	if dir == null:
		return table
	var paths: Array[String] = [CSV_PATH]
	for name in dir.get_files():
		if name.begins_with("strings_") and name.ends_with(".csv"):
			paths.append(CSV_PATH.get_base_dir().path_join(name))
	for path in paths:
		_load_csv_file(path, table)
	return table


func _load_csv_file(path: String, table: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "%s открывается" % path)
	if f == null:
		return
	var header := f.get_csv_line()
	assert_eq(header[0], "keys")
	assert_has(header, "ru")
	assert_has(header, "en")
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() < 2 or line[0].is_empty():
			continue
		var row: Dictionary = {}
		for i in range(1, mini(line.size(), header.size())):
			row[header[i]] = line[i]
		assert_false(table.has(line[0]), "дубликат ключа %s" % line[0])
		table[line[0]] = row
	f.close()


func _files_recursive(dir_path: String, exts: Array[String]) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for f in d.get_files():
		for ext in exts:
			if f.ends_with(ext):
				out.append(dir_path.path_join(f))
	for sub in d.get_directories():
		out.append_array(_files_recursive(dir_path.path_join(sub), exts))
	return out


func _strip_comments(source: String) -> String:
	var kept: Array[String] = []
	for line in source.split("\n"):
		var idx := line.find("#")
		kept.append(line.substr(0, idx) if idx != -1 else line)
	return "\n".join(kept)


func test_req_nfr_08_c2_every_key_has_non_empty_ru_and_en_and_loaded_translations_match_csv() -> void:
	var table := _load_csv()
	assert_gt(table.size(), 30, "таблица не пустая")
	var previous := TranslationServer.get_locale()
	for key in table.keys():
		var row: Dictionary = table[key]
		assert_false(str(row.get("ru", "")).strip_edges().is_empty(), "ru пуст для %s" % key)
		assert_false(str(row.get("en", "")).strip_edges().is_empty(), "en пуст для %s" % key)
		TranslationServer.set_locale("ru")
		assert_eq(TranslationServer.translate(key), row["ru"], "ru-перевод %s загружен" % key)
		TranslationServer.set_locale("en")
		assert_eq(TranslationServer.translate(key), row["en"], "en-перевод %s загружен" % key)
	TranslationServer.set_locale(previous)


func test_req_nfr_08_c2_every_profile_error_code_has_translation_in_both_languages() -> void:
	var table := _load_csv()
	var codes: Array[String] = [
		Profile.ERR_ID_EMPTY, Profile.ERR_NAME_EMPTY, Profile.ERR_NAME_TOO_LONG, Profile.ERR_FTP_OUT_OF_RANGE,
		Profile.ERR_WEIGHT_OUT_OF_RANGE, Profile.ERR_MAX_HR_OUT_OF_RANGE, Profile.ERR_INTENSITY_OUT_OF_RANGE,
		Profile.ERR_RESISTANCE_OUT_OF_RANGE, Profile.ERR_POWER_ZONES_INVALID, Profile.ERR_HR_ZONES_INVALID,
		ProfileRepository.ERR_NAME_NOT_UNIQUE, ProfileRepository.ERR_PROFILE_NOT_FOUND,
		ProfileRepository.ERR_LAST_PROFILE, ProfileRepository.ERR_STORAGE_WRITE_FAILED,
	]
	for code in codes:
		var key := ProfileSelectScreen.ERROR_KEY_PREFIX + code
		assert_true(table.has(key), "нет перевода для кода %s" % code)
	var previous := TranslationServer.get_locale()
	TranslationServer.set_locale("ru")
	assert_eq(ProfileSelectScreen.error_message(Profile.ERR_FTP_OUT_OF_RANGE), "FTP должен быть от 50 до 600 Вт")
	TranslationServer.set_locale("en")
	assert_eq(ProfileSelectScreen.error_message(Profile.ERR_FTP_OUT_OF_RANGE), "FTP must be between 50 and 600 W")
	assert_eq(ProfileSelectScreen.error_message("no_such_code"), "error.profile.no_such_code", "неизвестный код возвращает ключ, не падает")
	TranslationServer.set_locale(previous)


func test_req_nfr_08_c1_every_ui_key_in_sources_and_scenes_exists_in_csv() -> void:
	var table := _load_csv()
	var re := RegEx.create_from_string('"((?:ui|error)\\.[a-z0-9_]+(?:\\.[a-z0-9_]+)+)"')
	var missing: Array[String] = []
	var found: int = 0
	for dir in UI_SCAN_DIRS:
		for path in _files_recursive(dir, [".gd", ".tscn"]):
			var text := FileAccess.get_file_as_string(path)
			if path.ends_with(".gd"):
				text = _strip_comments(text)
			for m in re.search_all(text):
				found += 1
				var key := m.get_string(1)
				if not table.has(key) and not key.ends_with("."):
					missing.append("%s (%s)" % [key, path])
	assert_gt(found, 20, "ключи в исходниках найдены")
	assert_eq(missing, [], "ключи без перевода: %s" % str(missing))


func test_req_nfr_08_c1_scene_text_properties_are_keys_not_literals() -> void:
	var table := _load_csv()
	var re := RegEx.create_from_string('(?m)^(?:text|dialog_text|ok_button_text|cancel_button_text|placeholder_text|tooltip_text) = "([^"]*)"')
	var letters := RegEx.create_from_string("\\p{L}")
	var literals: Array[String] = []
	for path in _files_recursive("res://src/ui", [".tscn"]) + _files_recursive("res://src/app", [".tscn"]):
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			var value := m.get_string(1)
			if value.is_empty():
				continue
			if letters.search(value) == null:
				continue # надписи без букв («+5 %», «−5», «—») не требуют перевода
			if not table.has(value):
				literals.append("%s: %s" % [path, value])
	assert_eq(literals, [], "текстовые свойства сцен без ключа перевода: %s" % str(literals))


func test_req_nfr_08_c1_no_cyrillic_literals_in_ui_and_scene3d_sources() -> void:
	var cyr := RegEx.create_from_string("[\\p{Cyrillic}]")
	var offenders: Array[String] = []
	for dir in ["res://src/ui", "res://src/scene3d", "res://src/app"]:
		for path in _files_recursive(dir, [".gd", ".tscn"]):
			var text := FileAccess.get_file_as_string(path)
			if path.ends_with(".gd"):
				text = _strip_comments(text)
			var n := 0
			for line in text.split("\n"):
				n += 1
				if cyr.search(line) != null:
					offenders.append("%s:%d" % [path, n])
	assert_eq(offenders, [], "кириллица в литералах UI: %s" % str(offenders))
