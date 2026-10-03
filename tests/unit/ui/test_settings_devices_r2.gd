extends GutTest
## Настройки, устройства и выбор профиля в системе UIX (T-086): REQ-UIX-04 крит. 1, 3–5;
## REQ-UIX-05 крит. 1, 4; REQ-UIX-01 крит. 2 (без `theme_override_*`); регрессия REQ-PRF-05,
## REQ-DEV-01 крит. 7, REQ-NFR-08 крит. 3. Раскладка — `docs/game/ui.md` п. 8.1, 8.6, 8.7.
## Прежние функции экранов проверяют приёмки T-002/T-019/T-020/T-057 (не меняются).

const SETTINGS_SCENE: String = "res://src/ui/settings/settings_screen.tscn"
const DEVICES_SCENE: String = "res://src/ui/devices/devices_screen.tscn"
const SELECT_SCENE: String = "res://src/ui/profile_select/profile_select.tscn"
const OWNED_DIRS: Array[String] = ["res://src/ui/settings", "res://src/ui/devices", "res://src/ui/profile_select"]
const SECTION_TITLES_RU: Array[String] = ["Профиль", "Тренировка", "Зоны", "Интеграции", "Интерфейс", "О программе"]
const SECTION_TITLES_EN: Array[String] = ["Profile", "Training", "Zones", "Integrations", "Interface", "About"]

var _dir: String
var _repo: ProfileRepository
var _state: AppState
var _profile: Profile
var _previous_locale: String
var _bridge: StubBleBridge
var _cm: ConnectionManager


func before_each() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_dir = "user://test_t086_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_repo = ProfileRepository.new(_dir + "profiles/")
	_profile = _repo.create("Rider")
	_state = AppState.new(_repo)
	_state.start()
	_bridge = StubBleBridge.new()
	_cm = ConnectionManager.new(_bridge, RememberedDevices.new(_dir + "devices/"))
	_cm.set_profile(_profile.id)


func after_each() -> void:
	if _cm != null:
		_cm.dispose()
		_cm = null
	TranslationServer.set_locale(_previous_locale)
	_remove_tree(ProjectSettings.globalize_path(_dir))


static func _remove_tree(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	var d := DirAccess.open(abs_path)
	for f in d.get_files():
		DirAccess.remove_absolute(abs_path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(abs_path.path_join(sub))
	DirAccess.remove_absolute(abs_path)


## Экран в окне размера `canvas` (lp): `SubViewport` задаёт ширину холста для брейкпоинтов.
func _host(canvas: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = canvas
	viewport.gui_embed_subwindows = true
	add_child_autofree(viewport)
	return viewport


func _settings(canvas: Vector2i = Vector2i(1280, 720)) -> SettingsScreen:
	var s: SettingsScreen = (load(SETTINGS_SCENE) as PackedScene).instantiate()
	s.setup(_repo, _state, MemorySecureStore.new(), MockHttpTransport.new(), _cm)
	_host(canvas).add_child(s)
	return s


func _devices(canvas: Vector2i = Vector2i(1280, 720)) -> DevicesScreen:
	var s: DevicesScreen = (load(DEVICES_SCENE) as PackedScene).instantiate()
	s.setup(_cm, _repo, _state)
	_host(canvas).add_child(s)
	return s


func _select(canvas: Vector2i = Vector2i(1280, 720)) -> ProfileSelectScreen:
	var s: ProfileSelectScreen = (load(SELECT_SCENE) as PackedScene).instantiate()
	s.setup(_repo, _state)
	_host(canvas).add_child(s)
	return s


func _collect_focusable(node: Node, out: Array[Control]) -> void:
	var c := node as Control
	if c != null and c.focus_mode != Control.FOCUS_NONE and c.is_visible_in_tree():
		out.append(c)
	for child in node.get_children():
		_collect_focusable(child, out)


# --- UIX-04 крит. 1: AppBar с H1 и «назад» → go_back ------------------------------------------

func test_req_uix_04_c1_settings_and_devices_have_app_bar_back_to_previous_screen() -> void:
	var s := _settings()
	var d := _devices()
	for bar: AppBar in [s.app_bar(), d.app_bar()]:
		assert_eq((bar.get_node("%Title") as Label).theme_type_variation, &"H1Label", "заголовок — H1")
		assert_true(bar.back_button().visible, "есть «назад»")
	assert_eq(s.app_bar().title_text(), "Settings")
	assert_eq(d.app_bar().title_text(), "Devices")
	assert_eq(s.get_node("%BackButton"), s.app_bar().back_button(), "%BackButton — кнопка AppBar")
	assert_true(_state.navigate(AppState.Screen.SETTINGS))
	assert_true(_state.navigate(AppState.Screen.DEVICES))
	(d.get_node("%BackButton") as Button).pressed.emit()
	assert_eq(_state.current_screen, AppState.Screen.SETTINGS, "«назад» — на экран, с которого пришли")
	(s.get_node("%BackButton") as Button).pressed.emit()
	assert_eq(_state.current_screen, AppState.Screen.HOME)


# --- UIX-04 крит. 3: разделы настроек в порядке, заголовки, начало прокрутки ---------------------

func test_req_uix_04_c3_settings_sections_in_required_order_with_h2_titles() -> void:
	var s := _settings()
	await wait_process_frames(2)
	assert_eq(s.section_ids(), SettingsSections.ids(), "порядок узлов на экране = порядок UIX-04 крит. 3")
	assert_eq(SettingsSections.ids(), ["profile", "training", "zones", "integrations", "interface", "about"] as Array[String])
	var titles: Array[String] = []
	var last_y := -1.0
	for id in s.section_ids():
		var title := s.section_title(id)
		assert_not_null(title, "у раздела %s есть заголовок" % id)
		assert_eq(title.theme_type_variation, &"H2Label", "%s: заголовок — H2" % id)
		titles.append(title.text)
		var y := s.section_node(id).position.y
		assert_gt(y, last_y, "%s ниже предыдущего" % id)
		last_y = y
	assert_eq(titles, SECTION_TITLES_EN)
	assert_true(s.set_locale("ru"))
	titles.clear()
	for id in s.section_ids():
		titles.append(s.section_title(id).text)
	assert_eq(titles, SECTION_TITLES_RU, "заголовки разделов следуют языку без перезапуска")


func test_req_uix_04_c3_training_section_has_resistance_intensity_and_sim_steepness() -> void:
	var s := _settings()
	var rows := s.section_node(SettingsSections.TRAINING)
	assert_true(rows.is_ancestor_of(s.get_node("%ResistanceSpin")))
	assert_true(rows.is_ancestor_of(s.get_node("%IntensitySpin")))
	assert_true(rows.is_ancestor_of(s.get_node("%SteepnessSlider")))
	var integrations := s.section_node(SettingsSections.INTEGRATIONS)
	assert_true(integrations.is_ancestor_of(s.get_node("%IntervalsKeyButton")), "Intervals.icu — в «Интеграциях»")
	assert_true(integrations.is_ancestor_of(s.strava_button()), "Strava — в «Интеграциях»")
	assert_true(s.section_node(SettingsSections.INTERFACE).is_ancestor_of(s.get_node("%LocaleOption")), "язык — в «Интерфейсе»")
	assert_true(s.section_node(SettingsSections.ZONES).is_ancestor_of(s.get_node("%OverrideCheck")))
	var about := s.section_node(SettingsSections.ABOUT)
	assert_true(about.is_ancestor_of(s.get_node("%VersionLabel")))
	assert_true(about.is_ancestor_of(s.get_node("%LicensesButton")))


func test_req_uix_04_c3_settings_open_scrolled_to_top_and_nav_scrolls_to_section() -> void:
	var s := _settings(Vector2i(1280, 720))
	await wait_process_frames(3)
	assert_false(s.is_compact())
	assert_eq(s.scroll_container().scroll_vertical, 0, "экран открывается сверху")
	assert_eq(s.selected_section(), SettingsSections.PROFILE)
	for id in SettingsSections.ids():
		assert_not_null(s.nav_button(id), "в навигации есть раздел %s" % id)
		assert_true(s.nav_button(id).is_visible_in_tree())
	s.nav_button(SettingsSections.ABOUT).pressed.emit()
	await wait_process_frames(2)
	assert_gt(s.scroll_container().scroll_vertical, 0, "нажатие в навигации прокручивает к разделу")
	assert_eq(s.selected_section(), SettingsSections.ABOUT)
	var selected := 0
	for id in SettingsSections.ids():
		if s.nav_button(id).button_pressed:
			selected += 1
	assert_eq(selected, 1, "выбран ровно один раздел")
	s.hide()
	s.show()
	await wait_process_frames(2)
	assert_eq(s.scroll_container().scroll_vertical, 0, "повторный вход — снова сверху")


func test_req_uix_05_c4_settings_compact_one_column_without_nav() -> void:
	var s := _settings(Vector2i(867, 400))
	await wait_process_frames(3)
	assert_true(s.is_compact())
	assert_false(s.nav_button(SettingsSections.PROFILE).is_visible_in_tree(), "compact — без навигации слева")
	var body := s.get_node("%Body") as Control
	assert_lte(body.get_global_rect().end.x, 867.5, "без горизонтальной прокрутки")
	assert_eq(s.section_ids().size(), 6, "все разделы в одном столбце")


# --- Тренировка: крутизна SIM по умолчанию, интенсивность (T-061 sim_steepness_pct) -------------

func test_training_fields_save_immediately_to_profile() -> void:
	var s := _settings()
	var slider := s.get_node("%SteepnessSlider") as HSlider
	assert_eq(int(slider.value), Profile.DEFAULT_SIM_STEEPNESS_PCT, "по умолчанию 50 %")
	assert_eq(slider.step, float(Profile.SIM_STEEPNESS_STEP_PCT), "шаг 5 %")
	slider.value = 73
	assert_eq(_repo.get_active().sim_steepness_pct, 75, "крутизна приведена к шагу 5 и сохранена")
	assert_eq((s.get_node("%SteepnessValue") as Label).text, "75 %")
	(s.get_node("%IntensitySpin") as SpinBox).value = 110
	assert_eq(_repo.get_active().intensity_default, 110, "интенсивность по умолчанию сохранена")
	(s.get_node("%ResistanceSpin") as SpinBox).value = 30
	assert_eq(_repo.get_active().resistance_level_default, 30)
	assert_eq(ProfileRepository.new(_dir + "profiles/").get_active().sim_steepness_pct, 75, "на диске")


func test_save_profile_button_enabled_only_with_changes() -> void:
	var s := _settings()
	var save := s.get_node("%SaveProfileButton") as Button
	assert_eq(save.theme_type_variation, &"PrimaryButton")
	assert_true(save.disabled, "без изменений — недоступна")
	var name_edit := s.get_node("%NameEdit") as LineEdit
	name_edit.text = "Rider 2"
	name_edit.text_changed.emit("Rider 2")
	assert_false(save.disabled, "имя изменено — доступна")
	save.pressed.emit()
	assert_eq(_repo.get_active().name, "Rider 2")
	assert_true(save.disabled, "после сохранения — снова недоступна")


# --- «О программе»: лицензии Inter OFL 1.1, Lucide ISC, политика конфиденциальности ------------

func test_about_lists_inter_ofl_and_lucide_isc_and_privacy_policy() -> void:
	var s := _settings()
	var text := s.licenses_text()
	for expected in ["Godot Engine — MIT", "GUT (Godot Unit Test) — MIT", "godot-cpp — MIT",
			"Inter 4.1", "SIL Open Font License 1.1", "Lucide 1.51", "ISC"]:
		assert_string_contains(text, expected)
	assert_true(FileAccess.file_exists("res://assets/fonts/inter/OFL.txt"), "текст OFL лежит рядом со шрифтом")
	assert_true(FileAccess.file_exists("res://assets/icons/lucide/LICENSE"), "текст ISC лежит рядом с иконками")
	assert_string_contains(s.privacy_text(), SettingsScreen.PRIVACY_POLICY_DOC)
	assert_true(FileAccess.file_exists("res://" + SettingsScreen.PRIVACY_POLICY_DOC))
	assert_true(s.set_locale("ru"))
	assert_string_contains(s.licenses_text(), "Шрифт Inter 4.1")
	assert_string_contains(s.privacy_text(), "Документ: ")


# --- UIX-04 крит. 3, 4, 5: устройства — строки списка, пустое состояние, слоты, баннер -----------

func test_req_uix_04_c4_no_devices_shows_empty_state_with_search_action() -> void:
	var d := _devices()
	var empty := d.found_empty_state()
	assert_true(empty.is_visible_in_tree(), "0 устройств — пустое состояние, а не пустой экран")
	assert_true(empty.icon_rect().visible, "иконка")
	assert_eq(empty.title_label().text, "No devices found")
	assert_eq(empty.text_label().text, "Spin the pedals to wake the trainer up")
	assert_true(empty.action_button().visible)
	assert_eq(empty.action_button().text, "Search")
	empty.action_button().pressed.emit()
	assert_true(_cm.scanner.is_scanning(), "«Искать» запускает поиск")
	assert_false(empty.action_button().visible, "во время поиска кнопки нет")
	_bridge.emit_device_found("neo", "Tacx Neo", -55, PackedStringArray(["1826"]))
	assert_false(empty.visible, "устройство найдено — пустого состояния нет")


func test_req_uix_04_c3_device_rows_use_list_row_variation_with_columns() -> void:
	var d := _devices()
	_cm.start_scan()
	_bridge.emit_device_found("neo", "Tacx Neo", -55, PackedStringArray(["1826"]))
	_bridge.emit_device_found("hrm", "Polar", -70, PackedStringArray(["180D"]))
	for id in ["neo", "hrm"]:
		var list_row: ListRow = d.row(id)["list_row"]
		assert_eq(list_row.theme_type_variation, &"ListRowButton", "%s: вариация строки списка темы" % id)
		assert_eq(list_row.column_texts().size(), 3, "%s: колонки сигнала, состояния и заряда" % id)
		assert_true(list_row.is_ancestor_of(d.row(id)["connect_button"]), "кнопка «Подключить» в строке")
	assert_eq((d.row("neo")["list_row"] as ListRow).title, "Tacx Neo", "имя — заголовок строки, а не текст через «·»")
	assert_eq((d.row("neo")["list_row"] as ListRow).column_texts()[0], "-55 dBm")


func test_req_uix_04_c5_three_slots_with_status() -> void:
	var d := _devices()
	var titles: Array[String] = []
	for kind in DevicesScreen.SLOT_KINDS:
		titles.append(d.slot(kind).title_text())
		assert_false(d.slot(kind).is_connected_view())
		assert_eq(d.slot(kind).chip_text(), "not connected")
	assert_eq(titles, ["Trainer", "Heart-rate monitor", "Cadence"] as Array[String])
	_bridge.set_device_services("neo", {"1826": ["2AD2", "2AD9", "2ADA"], "180F": ["2A19"]})
	_bridge.set_read_value("2A19", BatteryCodec.encode_level(77))
	_cm.start_scan()
	_bridge.emit_device_found("neo", "Tacx Neo", -55, PackedStringArray(["1826"]))
	(d.row("neo")["connect_button"] as Button).pressed.emit()
	_bridge.pump()
	var trainer := d.slot(RememberedDevices.KIND_TRAINER)
	assert_true(trainer.is_connected_view(), "станок подключён — имя, сигнал, заряд")
	assert_eq(trainer.chip_text(), "connected")
	assert_eq(trainer.name_text(), "Tacx Neo")
	assert_eq(trainer.battery_text(), "77 %")
	trainer.disconnect_button().pressed.emit()
	_bridge.pump()
	assert_eq(_cm.state_of("neo"), TrainerDevice.ConnectionState.DISCONNECTED, "«Отключить» в слоте")
	assert_false(trainer.is_connected_view())
	assert_eq(trainer.name_text(), "Tacx Neo", "запомненный станок назван в пустом слоте")


func test_req_uix_04_c5_bluetooth_unavailable_banner_with_action() -> void:
	var d := _devices()
	assert_false(d.is_ble_banner_visible())
	_bridge.set_available(false)
	assert_true(d.is_ble_banner_visible(), "REQ-DEV-01 крит. 7: баннер вместо строки статуса")
	assert_eq(d.ble_banner().kind, Banner.Kind.WARN)
	assert_eq(d.ble_banner().theme_type_variation, &"BannerWarn")
	assert_true(d.ble_banner().action_button().visible, "действие «Как включить»")
	assert_eq(d.ble_banner().action_button().text, "How to turn on")
	assert_true((d.get_node("%ScanButton") as Button).disabled)
	_bridge.set_available(true)
	assert_false(d.is_ble_banner_visible())


func test_req_uix_05_c4_device_slots_stack_on_compact() -> void:
	var regular := _devices(Vector2i(1280, 720))
	await wait_process_frames(2)
	assert_false(regular.is_compact())
	var a := regular.slot(RememberedDevices.KIND_TRAINER).get_global_rect()
	var b := regular.slot(RememberedDevices.KIND_HR).get_global_rect()
	assert_almost_eq(a.position.y, b.position.y, 0.5, "regular — в ряд")
	var compact := _devices(Vector2i(867, 400))
	await wait_process_frames(2)
	assert_true(compact.is_compact())
	a = compact.slot(RememberedDevices.KIND_TRAINER).get_global_rect()
	b = compact.slot(RememberedDevices.KIND_HR).get_global_rect()
	assert_gt(b.position.y, a.end.y - 0.5, "compact — столбиком")


# --- 8.1: выбор профиля — карточки, «Новый профиль», удаление через «⋯» с подтверждением --------

func test_profile_select_cards_choose_and_new_profile_card() -> void:
	_repo.create("Second")
	var s := _select()
	await wait_process_frames(2)
	assert_eq(s.cards().size(), 2, "карточка на каждый профиль")
	for card in s.cards():
		assert_eq(card.theme_type_variation, &"CardButton")
		assert_true(card.menu_button().visible, "«⋯» при двух профилях")
	assert_eq(s.card_for(_profile.id).stats_text(), "FTP 200 W · 75 kg")
	assert_true(s.create_card().is_visible_in_tree(), "последняя карточка — «Новый профиль»")
	var second := s.cards()[1]
	second.pressed.emit()
	assert_eq(_repo.active_profile_id, second.profile_id, "нажатие на карточку = выбор")
	assert_eq(_state.current_screen, AppState.Screen.HOME)
	s.create_card().pressed.emit()
	assert_true(s.is_create_form_open(), "создание — диалог")
	s.close_create_form()


func test_profile_select_delete_via_card_menu_requires_danger_confirmation() -> void:
	var second := _repo.create("Second")
	var s := _select()
	await wait_process_frames(2)
	s.open_card_menu(second.id)
	assert_eq(s.card_menu().item_count, 1)
	assert_eq(s.card_menu().get_item_text(0), "Delete profile")
	s.activate_card_menu_item(ProfileSelectScreen.MENU_DELETE_ID)
	assert_eq(s.pending_delete_id(), second.id, "запрошено подтверждение")
	var dialog := s.get_node("%DeleteDialog") as ConfirmationDialog
	assert_eq(dialog.get_ok_button().theme_type_variation, &"DangerButton", "опасная кнопка")
	assert_eq(_repo.count(), 2, "до подтверждения ничего не удалено")
	dialog.confirmed.emit()
	assert_eq(_repo.count(), 1)
	assert_eq(s.cards().size(), 1)
	assert_false(s.cards()[0].menu_button().visible, "последний профиль удалить нельзя — «⋯» нет")


func test_profile_select_grid_four_per_row_regular_three_compact() -> void:
	for n in ["B", "C", "D", "E"]:
		_repo.create(n)
	var regular := _select(Vector2i(1280, 720))
	await wait_process_frames(3)
	assert_eq(regular.columns(), 4)
	var first_row_y := regular.cards()[0].get_global_rect().position.y
	assert_almost_eq(regular.cards()[3].get_global_rect().position.y, first_row_y, 0.5, "4 в ряд")
	assert_gt(regular.cards()[4].get_global_rect().position.y, first_row_y + 1.0, "пятая — во втором ряду")
	var compact := _select(Vector2i(867, 400))
	await wait_process_frames(3)
	assert_true(compact.is_compact())
	assert_eq(compact.columns(), 3)
	assert_eq(compact.cards()[0].size, ProfileCard.SIZE_COMPACT)
	assert_gt(compact.cards()[3].get_global_rect().position.y, compact.cards()[0].get_global_rect().position.y + 1.0)


# --- UIX-05 крит. 1: цели нажатия ≥ 40 lp на компьютере ------------------------------------------

func test_req_uix_05_c1_touch_targets_on_desktop() -> void:
	_repo.create("Second")
	var screens: Array[Control] = [_settings(), _devices(), _select()]
	_cm.start_scan()
	_bridge.emit_device_found("neo", "Tacx Neo", -55, PackedStringArray(["1826"]))
	await wait_process_frames(3)
	for screen in screens:
		var focusable: Array[Control] = []
		_collect_focusable(screen, focusable)
		assert_gt(focusable.size(), 3, "%s: интерактивные элементы найдены" % screen.name)
		for c in focusable:
			# Кнопка Strava — по брендбуку Strava (исключение UIX-01, решение оркестратора).
			if c.get_parent() is StravaConnectButton:
				continue
			assert_gte(c.size.x, UiScale.TOUCH_UI_DESKTOP - 0.01, "%s/%s ширина" % [screen.name, c.name])
			assert_gte(c.size.y, UiScale.TOUCH_UI_DESKTOP - 0.01, "%s/%s высота" % [screen.name, c.name])


# --- UIX-01 крит. 2: в сценах и коде экранов нет локальных переопределений темы ----------------

func test_req_uix_01_c2_no_theme_overrides_in_owned_screens() -> void:
	var re := RegEx.create_from_string("theme_override_|add_theme_[a-z_]+_override")
	var checked := 0
	for dir in OWNED_DIRS:
		for f in DirAccess.get_files_at(dir):
			if not (f.ends_with(".gd") or f.ends_with(".tscn")):
				continue
			checked += 1
			var text := FileAccess.get_file_as_string(dir.path_join(f))
			assert_null(re.search(text), "%s: локальное переопределение темы" % f)
	assert_gt(checked, 6)
