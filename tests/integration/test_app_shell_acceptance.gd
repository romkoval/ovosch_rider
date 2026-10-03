extends GutTest
## Независимые интеграционные приёмочные тесты оболочки приложения (тестировщик, T-012):
## `main.tscn`, экран выбора профиля, главный экран — headless через `add_child_autofree`.
## Покрытие: REQ-PRF-05 крит. 1, 2, 3 (через сцены); REQ-PRF-01 крит. 1, 2, 3, 4, 5 на уровне UI
## (каскад удаления через `main.tscn`: секреты и датчики стираются, станок остаётся);
## REQ-NFR-08 крит. 1, 3 (тексты экранов из переводов, ошибки на выбранном языке).

const MAIN_SCENE: String = "res://src/app/main.tscn"
const SELECT_SCENE: String = "res://src/ui/profile_select/profile_select.tscn"
const HOME_SCENE: String = "res://src/ui/home/home.tscn"

var _dir: String
var _previous_locale: String


func before_each() -> void:
	_dir = "user://test_acc_shell_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_each() -> void:
	TranslationServer.set_locale(_previous_locale)
	_remove_tree(ProjectSettings.globalize_path(_dir))
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_dir)), "временный каталог удалён")


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


func _repo() -> ProfileRepository:
	return ProfileRepository.new(_dir + "profiles/")


func _main() -> AppMain:
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	add_child_autofree(main)
	return main


func _select_screen(main: AppMain) -> ProfileSelectScreen:
	return main.screen_node(AppState.Screen.PROFILE_SELECT) as ProfileSelectScreen


func _home_screen(main: AppMain) -> HomeScreen:
	return main.screen_node(AppState.Screen.HOME) as HomeScreen


func _standalone_select(repo: ProfileRepository, state: AppState) -> ProfileSelectScreen:
	var s: ProfileSelectScreen = load(SELECT_SCENE).instantiate()
	s.setup(repo, state)
	add_child_autofree(s)
	return s


func _k(pid: String, service: String, item: String) -> String:
	return SecureStore.key_for(pid, service, item)


# ===========================================================================
# REQ-PRF-05 через main.tscn
# ===========================================================================

func test_req_prf_05_c3_main_with_no_profiles_shows_select_in_create_mode() -> void:
	var main := _main()
	assert_eq(main.app_state.current_screen, AppState.Screen.PROFILE_SELECT)
	assert_true(main.app_state.create_mode)
	var visible := main.visible_screen_node()
	assert_true(visible is ProfileSelectScreen, "виден экран выбора")
	var s := visible as ProfileSelectScreen
	assert_true(s.is_create_form_open(), "открыта форма создания первого профиля")
	assert_eq(s.profile_count(), 0)
	assert_true((s.get_node("%EmptyHint") as Label).visible)
	assert_false(_home_screen(main).visible)
	assert_false(main.app_state.navigate(AppState.Screen.HOME), "главный экран недоступен")
	assert_true(main.visible_screen_node() is ProfileSelectScreen)


func test_req_prf_05_c3_creating_first_profile_from_form_then_select_opens_home() -> void:
	var main := _main()
	var s := _select_screen(main)
	s.fill_create_form("First", 230, 70.0)
	var p := s.submit_create()
	assert_not_null(p)
	assert_eq(main.repo.count(), 1)
	assert_true(main.visible_screen_node() is ProfileSelectScreen, "после создания выбор ещё не сделан")
	assert_eq(s.selected_profile_id(), p.id, "новый профиль выделен")
	assert_true(s.select_current())
	assert_eq(main.app_state.current_screen, AppState.Screen.HOME)
	assert_true(main.visible_screen_node() is HomeScreen)
	assert_eq(_home_screen(main).active_profile_text(), "Profile: First")


func test_req_prf_05_c1_main_with_one_profile_opens_home_without_select_screen() -> void:
	var p := _repo().create("Solo")
	var main := _main()
	assert_eq(main.app_state.current_screen, AppState.Screen.HOME)
	assert_true(main.visible_screen_node() is HomeScreen)
	assert_false(_select_screen(main).visible)
	assert_eq(main.repo.active_profile_id, p.id)
	assert_eq(_home_screen(main).active_profile_text(), "Profile: Solo")
	var visible_count := 0
	for screen in AppState.Screen.values():
		if main.screen_node(screen).visible:
			visible_count += 1
	assert_eq(visible_count, 1, "виден ровно один экран")


func test_req_prf_05_c2_main_with_two_profiles_shows_select_and_blocks_home_until_choice() -> void:
	var repo := _repo()
	var a := repo.create("Alice")
	var b := repo.create("Bob")
	repo.active_profile_id = b.id # сохранённый активный с прошлого запуска
	var main := _main()
	assert_eq(main.app_state.current_screen, AppState.Screen.PROFILE_SELECT)
	var s := main.visible_screen_node() as ProfileSelectScreen
	assert_not_null(s)
	assert_false(s.is_create_form_open(), "форма создания не открыта")
	assert_eq(s.profile_count(), 2)
	assert_eq(s.selected_profile_id(), b.id, "сохранённый активный лишь предвыделен")
	assert_false(main.app_state.navigate(AppState.Screen.HOME))
	assert_false(main.app_state.navigate(AppState.Screen.WORKOUT))
	assert_true(main.visible_screen_node() is ProfileSelectScreen)
	s.select_index(0)
	assert_true(s.select_current())
	assert_eq(main.repo.active_profile_id, a.id)
	assert_true(main.visible_screen_node() is HomeScreen)
	assert_eq(_home_screen(main).active_profile_text(), "Profile: Alice")
	assert_true(main.app_state.navigate(AppState.Screen.HISTORY), "после выбора профиля остальные экраны доступны")
	assert_true(main.visible_screen_node() is HistoryScreen, "показан реальный экран истории (класс HistoryScreen)")
	assert_eq(_visible_screen_count(main), 1, "виден ровно один экран")


func test_req_prf_05_c2_switch_profile_from_home_returns_to_select_and_locks() -> void:
	var repo := _repo()
	repo.create("Alice")
	repo.create("Bob")
	var main := _main()
	_select_screen(main).select_index(1)
	_select_screen(main).select_current()
	assert_true(main.visible_screen_node() is HomeScreen)
	_home_screen(main).switch_profile()
	assert_true(main.visible_screen_node() is ProfileSelectScreen)
	assert_false(main.app_state.navigate(AppState.Screen.HOME), "после смены профиля главный экран снова заблокирован")
	assert_true(main.visible_screen_node() is ProfileSelectScreen)


# ===========================================================================
# REQ-PRF-01 крит. 3 — переключение профиля меняет данные (через сцены)
# ===========================================================================

func test_req_prf_01_c3_switching_profiles_changes_home_label_ftp_zones_and_devices() -> void:
	var repo := _repo()
	var a := repo.create("Alice")
	var b := repo.create("Bob")
	var eb := b.duplicate_profile()
	eb.ftp_w = 320
	assert_eq(repo.save(eb), [])
	var main := _main()
	main.devices.remember(a.id, RememberedDevices.make_device("hr-a", "Alice HRM", RememberedDevices.KIND_HR))
	main.devices.remember(b.id, RememberedDevices.make_device("cad-b", "Bob Cadence", RememberedDevices.KIND_CADENCE))
	main.devices.set_trainer(RememberedDevices.make_device("neo", "Neo", RememberedDevices.KIND_TRAINER))
	var s := _select_screen(main)
	s.select_index(0)
	s.select_current()
	assert_eq(_home_screen(main).active_profile_text(), "Profile: Alice")
	assert_eq(main.repo.get_active().ftp_w, 200)
	assert_eq(main.repo.get_active().power_zone_of(230), 5)
	var ids_a: Array[String] = []
	for d in main.devices.auto_connect_candidates(main.repo.active_profile_id):
		ids_a.append(d["id"])
	assert_eq(ids_a, ["neo", "hr-a"])
	_home_screen(main).switch_profile()
	s.select_index(1)
	s.select_current()
	assert_eq(_home_screen(main).active_profile_text(), "Profile: Bob")
	assert_eq(main.repo.get_active().ftp_w, 320)
	assert_eq(main.repo.get_active().power_zone_of(230), 2, "230 Вт при FTP 320 = 71.9 % → Z2 (у Alice было Z5)")
	var ids_b: Array[String] = []
	for d in main.devices.auto_connect_candidates(main.repo.active_profile_id):
		ids_b.append(d["id"])
	assert_eq(ids_b, ["neo", "cad-b"], "станок общий, датчики свои")


# ===========================================================================
# REQ-PRF-01 крит. 4 — удаление через UI: подтверждение; каскад через main.tscn
# ===========================================================================

func test_req_prf_01_c4_ui_delete_requires_confirmation_and_cancel_deletes_nothing() -> void:
	var repo := _repo()
	repo.create("Alice")
	var b := repo.create("Bob")
	var main := _main()
	var s := _select_screen(main)
	s.select_index(1)
	assert_true(s.request_delete())
	assert_eq(s.pending_delete_id(), b.id)
	assert_eq(main.repo.count(), 2, "до подтверждения ничего не удалено")
	var dialog := s.get_node("%DeleteDialog") as ConfirmationDialog
	assert_true(dialog.dialog_text.contains("Bob"), "в подтверждении имя профиля: %s" % dialog.dialog_text)
	assert_true(dialog.dialog_text.begins_with("Delete profile"), "текст из перевода (en)")
	dialog.canceled.emit()
	assert_eq(s.pending_delete_id(), "", "отмена сбрасывает ожидание")
	assert_eq(s.confirm_delete(), ProfileRepository.ERR_PROFILE_NOT_FOUND, "подтверждать нечего")
	assert_eq(main.repo.count(), 2)
	assert_not_null(main.repo.get_by_id(b.id))


func test_req_prf_01_c4_confirmed_delete_via_main_cascades_secrets_and_sensors_keeps_trainer() -> void:
	var repo := _repo()
	var a := repo.create("Alice")
	var b := repo.create("Bob")
	var main := _main()
	main.secure_store.set_secret(_k(a.id, "strava", "access_token"), "tok-A")
	main.secure_store.set_secret(_k(b.id, "strava", "access_token"), "tok-B")
	main.secure_store.set_secret(_k(b.id, "intervals", "api_key"), "key-B")
	main.devices.remember(a.id, RememberedDevices.make_device("hr-a", "A HRM", RememberedDevices.KIND_HR))
	main.devices.remember(b.id, RememberedDevices.make_device("hr-b", "B HRM", RememberedDevices.KIND_HR))
	main.devices.set_trainer(RememberedDevices.make_device("neo", "Neo", RememberedDevices.KIND_TRAINER))
	var s := _select_screen(main)
	var deleted: Array[String] = []
	s.profile_deleted.connect(func(id: String) -> void: deleted.append(id))
	s.select_index(1)
	assert_eq(s.selected_profile_id(), b.id)
	s.request_delete()
	assert_eq(s.confirm_delete(), "")
	assert_eq(deleted, [b.id])
	assert_eq(main.repo.count(), 1)
	assert_eq(s.profile_count(), 1)
	assert_eq(main.secure_store.list_keys(b.id + "/"), [], "секреты удалённого стёрты")
	assert_eq(main.secure_store.get_secret(_k(a.id, "strava", "access_token")), "tok-A", "секреты оставшегося целы")
	assert_eq(main.devices.sensors(b.id), [], "датчики удалённого стёрты")
	assert_eq(main.devices.sensors(a.id).size(), 1, "датчики оставшегося целы")
	assert_true(main.devices.has_trainer(), "общий станок остался")
	assert_eq(main.devices.trainer()["id"], "neo")
	# и на диске
	assert_true(RememberedDevices.new(_dir + "devices/").has_trainer())
	assert_eq(RememberedDevices.new(_dir + "devices/").sensors(b.id), [])
	assert_eq(SecureStore.create_default(_dir + "secure/").list_keys(b.id + "/"), [])
	assert_eq(ProfileRepository.new(_dir + "profiles/").count(), 1)


func test_req_prf_01_c4_deleting_active_profile_via_ui_switches_active_and_home_label() -> void:
	var repo := _repo()
	var a := repo.create("Alice")
	var b := repo.create("Bob")
	var main := _main()
	var s := _select_screen(main)
	s.select_index(1)
	s.select_current() # Bob активен, HOME
	assert_eq(main.repo.active_profile_id, b.id)
	main.app_state.switch_profile()
	s.select_index(1)
	s.request_delete()
	assert_eq(s.confirm_delete(), "")
	assert_eq(main.repo.active_profile_id, a.id, "активным стал оставшийся")
	assert_eq(s.selected_profile_id(), a.id, "в списке выделен активный")
	assert_true(s.select_current())
	assert_eq(_home_screen(main).active_profile_text(), "Profile: Alice")


# ===========================================================================
# REQ-PRF-01 крит. 5 — последний профиль нельзя удалить в UI
# ===========================================================================

func test_req_prf_01_c5_delete_button_disabled_for_last_profile_and_error_translated() -> void:
	var repo := _repo()
	var only := repo.create("Solo")
	var state := AppState.new(repo)
	var s := _standalone_select(repo, state)
	s.select_index(0)
	assert_true((s.get_node("%DeleteButton") as Button).disabled, "кнопка удаления недоступна")
	assert_false((s.get_node("%SelectButton") as Button).disabled)
	assert_true(s.request_delete(), "даже если дошли до подтверждения —")
	assert_eq(s.confirm_delete(), ProfileRepository.ERR_LAST_PROFILE)
	assert_eq(s.error_text(), "The last profile cannot be deleted")
	assert_eq(repo.count(), 1)
	assert_not_null(repo.get_by_id(only.id))
	TranslationServer.set_locale("ru")
	s.request_delete()
	s.confirm_delete()
	assert_eq(s.error_text(), "Нельзя удалить последний профиль")


func test_req_prf_01_c5_after_deleting_down_to_one_delete_button_becomes_disabled() -> void:
	var repo := _repo()
	repo.create("Alice")
	repo.create("Bob")
	var s := _standalone_select(repo, AppState.new(repo))
	s.select_index(1)
	assert_false((s.get_node("%DeleteButton") as Button).disabled)
	s.request_delete()
	assert_eq(s.confirm_delete(), "")
	s.select_index(0)
	assert_true((s.get_node("%DeleteButton") as Button).disabled)


# ===========================================================================
# REQ-PRF-01 крит. 1, 2 — форма создания: границы и ошибки на выбранном языке (NFR-08 крит. 3)
# ===========================================================================

func test_req_prf_01_c1_form_ftp_601_shows_error_in_en_and_creates_nothing() -> void:
	var repo := _repo()
	repo.create("Existing")
	var s := _standalone_select(repo, AppState.new(repo))
	s.open_create_form()
	s.fill_create_form("Newbie", 601, 70.0)
	assert_null(s.submit_create())
	assert_eq(s.error_text(), "FTP must be between 50 and 600 W")
	assert_eq(repo.count(), 1, "профиль не создан")
	assert_eq(ProfileRepository.new(_dir + "profiles/").count(), 1, "и на диске")
	assert_true(s.is_create_form_open())
	assert_eq(s.profile_count(), 1)


func test_req_prf_01_c1_form_ftp_601_shows_error_in_ru_when_locale_is_ru() -> void:
	TranslationServer.set_locale("ru")
	var repo := _repo()
	var s := _standalone_select(repo, AppState.new(repo))
	s.fill_create_form("Новичок", 601, 70.0)
	assert_null(s.submit_create())
	assert_eq(s.error_text(), "FTP должен быть от 50 до 600 Вт")
	assert_eq(repo.count(), 0)


func test_req_prf_01_c1_form_boundaries_50_600_accepted_49_rejected_and_whitespace_name() -> void:
	var repo := _repo()
	var s := _standalone_select(repo, AppState.new(repo))
	s.fill_create_form("Low", 50, 20.0)
	assert_not_null(s.submit_create(), "FTP 50 и вес 20.0 — границы включительно")
	s.open_create_form()
	s.fill_create_form("High", 600, 250.0, 220)
	assert_not_null(s.submit_create())
	s.open_create_form()
	s.fill_create_form("   ", 200, 70.0)
	assert_null(s.submit_create())
	assert_eq(s.error_text(), "Enter a profile name")
	# 41 символ: поле ввода ограничено max_length = 40 и обрезает ввод ещё до валидации.
	assert_eq((s.get_node("%NameEdit") as LineEdit).max_length, 40)
	s.fill_create_form("x".repeat(41), 200, 70.0)
	var truncated := s.submit_create()
	assert_not_null(truncated, "UI обрезал имя до 40 — профиль создан")
	if truncated != null:
		assert_eq(truncated.name.length(), 40)
	assert_eq(repo.count(), 3)


func test_req_prf_01_c1_form_spinbox_limits_prevent_49_but_model_still_validates() -> void:
	var repo := _repo()
	var s := _standalone_select(repo, AppState.new(repo))
	s.fill_create_form("Edge", 49, 70.0)
	var ftp := (s.get_node("%FtpSpin") as SpinBox).value
	var p := s.submit_create()
	if p == null:
		assert_eq(s.error_text(), "FTP must be between 50 and 600 W", "49 отклонён моделью")
	else:
		assert_gte(int(ftp), Profile.MIN_FTP_W, "SpinBox сам поднял значение до минимума")
		assert_gte(p.ftp_w, Profile.MIN_FTP_W)


func test_req_prf_01_c2_form_duplicate_name_case_insensitive_error_and_nothing_created() -> void:
	var repo := _repo()
	repo.create("Roman")
	var s := _standalone_select(repo, AppState.new(repo))
	s.open_create_form()
	s.fill_create_form("  roman ", 200, 70.0)
	assert_null(s.submit_create())
	assert_eq(s.error_text(), "A profile with this name already exists")
	assert_eq(repo.count(), 1)
	s.fill_create_form("Roman2", 200, 70.0)
	assert_not_null(s.submit_create())
	assert_eq(s.error_text(), "", "ошибка сброшена после успеха")
	assert_eq(repo.count(), 2)


func test_req_prf_01_c1_form_multiple_errors_listed_each_translated() -> void:
	var repo := _repo()
	var s := _standalone_select(repo, AppState.new(repo))
	s.fill_create_form("", 601, 19.9, 99)
	assert_null(s.submit_create())
	var lines := s.error_text().split("\n")
	assert_eq(lines.size(), 4)
	for line in lines:
		assert_false(line.begins_with("error.profile."), "строка переведена, а не ключ: %s" % line)
	assert_has(lines, "FTP must be between 50 and 600 W")
	assert_has(lines, "Weight must be between 20 and 250 kg")
	assert_has(lines, "Max heart rate must be 100–220 or 0")
	assert_has(lines, "Enter a profile name")


func test_req_prf_01_c1_form_max_hr_0_means_not_set_and_zones_unavailable() -> void:
	var repo := _repo()
	var s := _standalone_select(repo, AppState.new(repo))
	s.fill_create_form("NoHr", 200, 70.0, 0)
	var p := s.submit_create()
	assert_not_null(p)
	assert_eq(repo.get_by_id(p.id).max_hr, 0)
	assert_eq(repo.get_by_id(p.id).hr_zone_of(150), 0)


# ===========================================================================
# REQ-NFR-08 крит. 1, 3 — тексты экранов берутся из переводов и следуют локали
# ===========================================================================

func test_req_nfr_08_c1_screen_texts_resolve_to_translations_not_keys_in_both_locales() -> void:
	var repo := _repo()
	repo.create("Alice")
	var main := _main()
	var s := _select_screen(main)
	var home := _home_screen(main)
	var labelled: Array[Node] = [
		s.get_node("%SelectButton"), s.get_node("%CreateButton"), s.get_node("%DeleteButton"),
		s.get_node("%EmptyHint"), s.get_node("%SaveButton"), s.get_node("%CancelButton"),
		home.get_node("%WorkoutButton"), home.get_node("%HistoryButton"), home.get_node("%SettingsButton"),
		home.get_node("%DevButton"), home.get_node("%SwitchProfileButton"),
	]
	for locale in ["en", "ru"]:
		TranslationServer.set_locale(locale)
		for node in labelled:
			var shown: String = node.tr(node.text)
			assert_false(shown.begins_with("ui."), "%s: «%s» не переведён в %s" % [node.name, shown, locale])
			assert_false(shown.is_empty())
	TranslationServer.set_locale("ru")
	assert_eq((s.get_node("%SelectButton") as Button).tr("ui.profile_select.select"), "Выбрать")
	TranslationServer.set_locale("en")
	assert_eq((s.get_node("%SelectButton") as Button).tr("ui.profile_select.select"), "Select")


func test_req_nfr_08_c3_list_items_and_home_label_follow_locale() -> void:
	var repo := _repo()
	var a := repo.create("Alice")
	var ea := a.duplicate_profile()
	ea.ftp_w = 250
	repo.save(ea)
	var state := AppState.new(repo)
	state.start()
	var s := _standalone_select(repo, state)
	var home: HomeScreen = load(HOME_SCENE).instantiate()
	home.setup(repo, state)
	add_child_autofree(home)
	assert_eq((s.get_node("%ProfileList") as ItemList).get_item_text(0), "Alice — FTP 250 W")
	assert_eq(home.active_profile_text(), "Profile: Alice")
	TranslationServer.set_locale("ru")
	s.refresh()
	home.refresh()
	assert_eq((s.get_node("%ProfileList") as ItemList).get_item_text(0), "Alice — FTP 250 Вт")
	assert_eq(home.active_profile_text(), "Профиль: Alice")


func test_req_nfr_08_c3_main_applies_supported_locale_on_boot() -> void:
	_repo().create("Solo")
	TranslationServer.set_locale("de")
	var main := _main()
	assert_not_null(main)
	assert_has(AppLocale.SUPPORTED_LOCALES, TranslationServer.get_locale().substr(0, 2),
		"после старта локаль — одна из поддерживаемых (система → ru/en, иначе en): %s" % TranslationServer.get_locale())


## Ожидаемый `class_name` сцены экрана по `AppState.Screen` (заглушек `Placeholder_*` больше нет).
static func _expected_screen_class(screen: int) -> String:
	match screen:
		AppState.Screen.PROFILE_SELECT: return "ProfileSelectScreen"
		AppState.Screen.HOME: return "HomeScreen"
		AppState.Screen.WORKOUT: return "WorkoutScreen"
		AppState.Screen.HISTORY: return "HistoryScreen"
		AppState.Screen.SETTINGS: return "SettingsScreen"
		AppState.Screen.DEV: return "DevScreen"
		AppState.Screen.DEVICES: return "DevicesScreen"
		AppState.Screen.PLAN: return "PlanScreen"
	return ""


static func _script_class(node: Node) -> String:
	var script: Script = node.get_script() as Script
	return script.get_global_name() if script != null else ""


static func _visible_screen_count(main: AppMain) -> int:
	var count := 0
	for screen in AppState.Screen.values():
		var node := main.screen_node(screen)
		if node != null and node.visible:
			count += 1
	return count


## Все Button/Label в поддереве экрана (без привязки к именам узлов).
static func _collect_texts(node: Node, out: Array[Node]) -> void:
	if node is Button or node is Label:
		out.append(node)
	for child in node.get_children():
		_collect_texts(child, out)


## Возврат на главный: видимой пользователю кнопкой «назад» `AppBar` (экраны T-076+) или `%HomeButton`/`%BackButton`,
## если экран её показывает (у WorkoutScreen кнопка живёт в сводке и до финиша тренировки скрыта), иначе через
## `AppState.navigate(HOME)` — критерий REQ-PRF-05 о состоянии навигации, не о кнопке.
func _return_home(main: AppMain, screen_node: Control) -> void:
	var back: Button = null
	if screen_node.has_method("app_bar"):
		var bar := screen_node.call("app_bar") as AppBar
		if bar != null and bar.back_button() != null and bar.back_button().is_visible_in_tree():
			back = bar.back_button()
	for unique_name in ["%HomeButton", "%BackButton"]:
		if back != null:
			break
		var candidate := screen_node.get_node_or_null(unique_name) as Button
		if candidate != null and candidate.is_visible_in_tree():
			back = candidate
			break
	if back != null:
		back.pressed.emit()
	else:
		assert_true(main.app_state.navigate(AppState.Screen.HOME), "%s: навигация на HOME" % screen_node.name)
	assert_eq(main.app_state.current_screen, AppState.Screen.HOME, "%s: состояние навигации — HOME" % screen_node.name)
	assert_true(main.visible_screen_node() is HomeScreen, "%s: возврат на главный экран" % screen_node.name)


func test_req_prf_05_real_screens_switch_by_class_use_translation_keys_and_return_home() -> void:
	_repo().create("Solo")
	var main := _main()
	assert_true(main.visible_screen_node() is HomeScreen, "один профиль → сразу HOME")
	var screens_checked := 0
	for screen in [AppState.Screen.WORKOUT, AppState.Screen.HISTORY, AppState.Screen.SETTINGS,
			AppState.Screen.PLAN, AppState.Screen.DEVICES, AppState.Screen.DEV]:
		var screen_label := AppState.screen_name(screen)
		assert_true(main.app_state.navigate(screen), "%s: доступен после выбора профиля" % screen_label)
		assert_eq(main.app_state.current_screen, screen)
		var node := main.visible_screen_node()
		assert_not_null(node, "%s: экран показан" % screen_label)
		if node == null:
			continue
		screens_checked += 1
		assert_eq(_script_class(node), _expected_screen_class(screen), "%s: реальная сцена экрана, не заглушка" % screen_label)
		assert_false(str(node.name).begins_with("Placeholder_"), "%s: заглушки больше нет" % screen_label)
		assert_eq(_visible_screen_count(main), 1, "%s: виден ровно один экран" % screen_label)
		var labelled: Array[Node] = []
		_collect_texts(node, labelled)
		for item in labelled:
			var raw: String = item.text
			if raw.strip_edges().is_empty():
				continue
			var shown: String = item.tr(raw)
			assert_false(shown.begins_with("ui.") or shown.begins_with("error."),
				"%s/%s: текст «%s» — ключ без перевода" % [screen_label, item.name, shown])
		_return_home(main, node)
	assert_eq(screens_checked, 6, "все экраны оболочки проверены")
	main.app_state.switch_profile()
	assert_true(main.visible_screen_node() is ProfileSelectScreen)
	assert_false(main.app_state.navigate(AppState.Screen.HISTORY), "без выбранного профиля экраны недоступны")
	assert_true(main.visible_screen_node() is ProfileSelectScreen)
