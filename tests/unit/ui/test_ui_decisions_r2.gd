extends GutTest
## Решения game-designer ред. 2 в UI (T-089): деталь трассы (`tracks.md` п. 7.2, `ui.md` п. 8.4),
## миниатюра строки плана (`ui.md` п. 6, 8.3), подтверждение отвязки (`ui.md` п. 8.6), карточка
## заезда — каденс и свободная езда (`ui.md` п. 8.5), «Эмулятор» только в отладке (`ui.md` п. 8.2),
## тема — `TextEdit`, разрывы сеток и рядов, Caption `tnum`, диалог-форма.
## REQ-FRD-03 крит. 6, REQ-UIX-01 крит. 2, 3, REQ-UIX-03 крит. 1, 2, REQ-UIX-04 крит. 3, REQ-LOC-03.

const SETTINGS_SCENE: String = "res://src/ui/settings/settings_screen.tscn"
const SELECT_SCENE: String = "res://src/ui/tracks/route_select_screen.tscn"
const PLAN_SCENE: String = "res://src/ui/plan/plan_screen.tscn"
const DETAIL_SCENE: String = "res://src/ui/history/ride_detail.tscn"
const FIELD := Rect2(0, 0, 600, 200)

var _dir: String = ""
var _repo: ProfileRepository
var _state: AppState
var _profile: Profile
var _previous_locale: String = ""


func before_each() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("ru")
	_dir = "user://test_ui_decisions_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_repo = ProfileRepository.new(_dir + "profiles/")
	_profile = _repo.create("Аня")
	_state = AppState.new(_repo)
	_state.start()


func after_each() -> void:
	TranslationServer.set_locale(_previous_locale)
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


func _host(node: Node, canvas: Vector2i = Vector2i(1280, 720)) -> void:
	var viewport := SubViewport.new()
	viewport.size = canvas
	viewport.gui_embed_subwindows = true
	add_child_autofree(viewport)
	viewport.add_child(node)


func _model(route_id: String) -> RoutePreviewModel:
	return RoutePreviewModel.for_route(RouteCatalog.get_route(route_id))


## Круг из подъёмов 4 % длиной `lengths` (каждый — спуск той же длины и ровный участок 200 м).
static func _climbs_profile(lengths: Array[int]) -> RouteProfile:
	var pts := PackedVector2Array([Vector2(0, 0)])
	var s: float = 0.0
	for length in lengths:
		for part in [[length, 0.04], [length, -0.04], [200, 0.0]]:
			var steps: int = int(part[0]) / 10
			for i in steps:
				s += 10.0
				pts.append(Vector2(s, pts[pts.size() - 1].y + 10.0 * float(part[1])))
	return RouteProfile.from_points(pts)


# --- Деталь трассы: шкала, подписи высот, подъёмы (`tracks.md` п. 7.2) ------------------------

func test_large_profile_span_is_max_of_drop_and_40_m_with_10_percent_margins() -> void:
	for route_id in RouteCatalog.ids():
		var model := _model(route_id)
		var drop: float = model.profile.max_height_m() - model.profile.min_height_m()
		var p := model.plot(RoutePreviewModel.Mode.LARGE, FIELD)
		assert_almost_eq((p.h_top - p.h_bottom) * 0.8, maxf(drop, 40.0), 1e-6, "%s: размах max(перепад, 40 м)" % route_id)
		assert_almost_eq(FIELD.end.y - p.y(model.profile.min_height_m()), FIELD.size.y * 0.1, 1e-6, "%s: поле снизу 10 %%" % route_id)
	# Равнина (перепад 12 м) — волна на 30 % размаха, а не полоска у дна (150 м).
	var flat := _model(RouteCatalog.FLAT)
	assert_almost_eq(flat.fill_fraction(RoutePreviewModel.Mode.LARGE) / 0.8, 0.30, 0.02)
	# Миниатюры по-прежнему в общем масштабе 150 м.
	var thumb := flat.plot(RoutePreviewModel.Mode.THUMB, FIELD)
	assert_almost_eq(thumb.h_top - thumb.h_bottom, 150.0, 1e-6)


func test_height_labels_close_together_leave_only_maximum() -> void:
	var model := _model(RouteCatalog.MOUNTAINS)
	var tall := model.plot(RoutePreviewModel.Mode.LARGE, Rect2(0, 0, 400, 200))
	assert_eq(model.visible_height_labels(tall).size(), 2, "далеко друг от друга — обе")
	var low := model.plot(RoutePreviewModel.Mode.LARGE, Rect2(0, 0, 400, 16))
	var labels := model.visible_height_labels(low)
	assert_eq(labels.size(), 1, "ближе 14 lp — только максимум")
	assert_eq(labels[0]["h_m"], model.profile.max_height_m())


func test_climb_labels_up_to_3_full_4_and_more_four_longest_short() -> void:
	var three := RoutePreviewModel.for_profile(_climbs_profile([400, 600, 800] as Array[int])).climb_labels()
	assert_eq(three.size(), 3, "≤ 3 — подписаны все")
	for label in three:
		assert_false(label["short"])
		assert_string_contains(str(label["text"]), "подъём")
	var five := RoutePreviewModel.for_profile(_climbs_profile([400, 1200, 600, 1000, 800] as Array[int])).climb_labels()
	assert_eq(five.size(), 4, "≥ 4 — четыре самых длинных")
	var lengths: Array[float] = []
	for label in five:
		assert_true(label["short"], "коротко")
		lengths.append(roundf(float(label["length_m"]) / 100.0) * 100.0)
	assert_false(lengths.has(400.0), "самый короткий не подписан")
	for i in range(1, five.size()):
		assert_true(float(five[i]["start_m"]) > float(five[i - 1]["start_m"]), "по порядку s")


func test_overlapping_climb_labels_hide_the_shorter_climb() -> void:
	var labels: Array[Dictionary] = [
		{"text": "a", "length_m": 500.0, "rect": Rect2(0, 0, 100, 16)},
		{"text": "b", "length_m": 900.0, "rect": Rect2(60, 0, 100, 16)},
		{"text": "c", "length_m": 300.0, "rect": Rect2(300, 0, 100, 16)},
	]
	var kept := RoutePreviewModel.without_overlaps(labels)
	var texts: Array[String] = []
	for label in kept:
		texts.append(str(label["text"]))
	assert_eq(texts, ["b", "c"] as Array[String], "из пересекающихся остаётся более длинный подъём, порядок исходный")


func test_route_preview_draws_climb_labels_without_overlaps() -> void:
	var preview := RoutePreview.new()
	preview.size = Vector2(300, 160)
	preview.mode = RoutePreviewModel.Mode.LARGE
	add_child_autofree(preview)
	preview.set_route(RouteCatalog.get_route(RouteCatalog.HILLS))
	var placed := preview.climb_label_layout(preview.current_plot())
	assert_between(placed.size(), 1, 4)
	for i in placed.size():
		for j in range(i + 1, placed.size()):
			assert_false((placed[i]["rect"] as Rect2).intersects(placed[j]["rect"] as Rect2), "подписи не пересекаются")


func test_route_detail_second_line_is_only_kind() -> void:
	var s: RouteSelectScreen = (load(SELECT_SCENE) as PackedScene).instantiate()
	s.setup(_repo, _state)
	_host(s)
	s.refresh()
	s.select_route(RouteCatalog.MOUNTAINS)
	assert_eq(s.detail_subtitle_text(), "горы", "только тип на языке интерфейса")
	TranslationServer.set_locale("en")
	s.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)
	s.refresh()
	assert_eq(s.detail_subtitle_text(), "mountains")


# --- Миниатюра строки плана (`ui.md` п. 6, 8.3) ------------------------------------------------

func test_plan_row_thumbnail_is_128x52_with_6_lp_padding_and_radius_10() -> void:
	var thumb := PlanPreview.new()
	thumb.row_thumb = true
	assert_eq(thumb.custom_minimum_size, Vector2(128, 52))
	assert_eq([thumb.inset_left, thumb.inset_top, thumb.inset_right, thumb.inset_bottom], [6.0, 6.0, 6.0, 6.0])
	assert_eq(thumb.inset_radius, 10.0)
	thumb.size = Vector2(128, 52)
	assert_eq(thumb.field_rect().size, Vector2(116, 40), "видимая часть ≈ 116×40")
	thumb.free()
	var big := PlanPreview.new()
	assert_eq(big.inset_radius, 12.0, "крупное превью — радиус 12")
	big.free()
	assert_eq(PlanScreen.THUMB_SIZE, Vector2(128, 52))


# --- «Эмулятор» в диалоге выбора станка — только отладка (`ui.md` п. 8.2) -----------------------

func test_trainer_dialog_offers_emulator_only_with_dev_tools() -> void:
	var plan: PlanScreen = (load(PLAN_SCENE) as PackedScene).instantiate()
	plan.setup(_state, _repo, MemorySecureStore.new(), MockHttpTransport.new(), PlanCache.new(_dir + "plans/"),
		WorkoutLibrary.new(_dir + "workouts/"))
	_host(plan)
	var dialog := plan.get_node("%TrainerDialog") as ConfirmationDialog
	plan.dev_tools_enabled = false
	plan.show_trainer_choice()
	assert_eq(dialog.dialog_text, tr("ui.plan.trainer_choice.text_release"), "релиз: только «подключить устройства»")
	assert_false(_emulator_button(dialog).visible, "релиз: «Эмулятор» скрыт")
	dialog.custom_action.emit(&"emulator")
	assert_true(plan.is_trainer_choice_pending(), "релиз: действие эмулятора не выполняется")
	dialog.hide()
	plan.dev_tools_enabled = true
	plan.show_trainer_choice()
	assert_eq(dialog.dialog_text, tr("ui.plan.trainer_choice.text"))
	assert_true(_emulator_button(dialog).visible, "отладка: «Эмулятор» есть")
	dialog.hide()


static func _emulator_button(dialog: AcceptDialog) -> Button:
	for child in dialog.find_children("*", "Button", true, false):
		if (child as Button).text == TranslationServer.translate("ui.plan.trainer_choice.emulator"):
			return child
	return null


# --- Подтверждение отвязки (`ui.md` п. 8.6) ---------------------------------------------------

func _settings(store: SecureStore) -> SettingsScreen:
	var s: SettingsScreen = (load(SETTINGS_SCENE) as PackedScene).instantiate()
	s.setup(_repo, _state, store, MockHttpTransport.new(), null)
	_host(s)
	return s


func test_unlink_intervals_asks_for_confirmation_with_danger_button() -> void:
	var store := MemorySecureStore.new()
	var key_id := SecureStore.key_for(_profile.id, SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY)
	store.set_secret(key_id, "k")
	var p := _repo.get_active().duplicate_profile()
	p.intervals_athlete_id = "i1"
	_repo.save(p)
	var s := _settings(store)
	s.refresh()
	(s.get_node("%IntervalsForgetButton") as Button).pressed.emit()
	assert_true(s.is_forget_intervals_pending(), "кнопка открывает подтверждение")
	assert_true(store.has_secret(key_id), "до подтверждения ключ на месте")
	var dialog := s.get_node("%ForgetIntervalsDialog") as ConfirmationDialog
	assert_eq(dialog.title, "Отвязать Intervals.icu?")
	assert_string_contains(dialog.dialog_text, "Ключ API будет удалён")
	assert_eq(dialog.get_ok_button().theme_type_variation, &"DangerButton", "опасная кнопка")
	assert_eq(dialog.get_ok_button().text, "Отвязать")
	dialog.get_cancel_button().pressed.emit()
	await wait_process_frames(2)
	assert_false(s.is_forget_intervals_pending(), "«Отмена» закрывает диалог")
	assert_true(store.has_secret(key_id), "«Отмена» ничего не удаляет")
	s.request_forget_intervals()
	s.confirm_forget_intervals()
	assert_false(store.has_secret(key_id), "подтверждено — ключ удалён")
	assert_false(s.is_forget_intervals_pending())


func test_disconnect_strava_asks_for_confirmation() -> void:
	var s := _settings(MemorySecureStore.new())
	assert_false(s.request_disconnect_strava(), "без сервиса Strava — нечего отвязывать")
	var service := StravaService.new(_profile, MockHttpTransport.new(), MemorySecureStore.new(),
		FileRideRepository.new(_dir + "rides/"), StravaConfig.from_values("", ""), Callable(), _dir + "strava/")
	s.set_strava_service(service)
	s.strava_button().disconnect_requested.emit()
	assert_true(s.is_disconnect_strava_pending(), "«Отвязать Strava» открывает подтверждение")
	var dialog := s.get_node("%DisconnectStravaDialog") as ConfirmationDialog
	assert_eq(dialog.title, "Отвязать Strava?")
	assert_eq(dialog.dialog_text, "Новые заезды перестанут выгружаться в Strava.")
	assert_eq(dialog.get_ok_button().theme_type_variation, &"DangerButton")
	dialog.hide()
	s.set_strava_service(null)
	service.dispose()


# --- Карточка заезда: каденс и свободная езда (`ui.md` п. 8.5) ---------------------------------

func _detail(ride: Ride) -> RideDetail:
	var rides := FileRideRepository.new(_dir + "rides/")
	rides.attach_to_profiles(_repo)
	rides.save(ride)
	var d: RideDetail = (load(DETAIL_SCENE) as PackedScene).instantiate()
	_host(d)
	d.show_ride(ride, rides)
	return d


func _free_ride(cadence: bool) -> Ride:
	var r := Ride.new()
	var started: int = 1_790_000_000
	r.id = Ride.generate_id(started)
	r.profile_id = _profile.id
	r.started_at_unix = started
	r.metadata = Ride.free_ride_metadata(RouteCatalog.FLAT, 50.0)
	r.metadata["ftp_w"] = 250
	r.metadata["in_progress"] = false
	r.metadata["recovered"] = false
	var profile := RouteCatalog.get_route(RouteCatalog.FLAT).profile
	for i in 600:
		var d: float = float(i + 1) * 9.0
		var sample := TrainerSample.full(float(i), 150 + (i % 200), 132, 0.0)
		sample.has_cadence = cadence
		r.samples.append(i, sample, -1, 0, -1, false,
			32.4, {}, {"distance_m": d, "altitude_m": profile.height_at(fposmod(d, profile.length_m())), "grade_pct": 0.0})
	r.compute_summary()
	return r


func test_cadence_chart_scale_grid_height_and_fields_match_power_chart() -> void:
	var d := _detail(_free_ride(true))
	await wait_process_frames(2)
	var chart := d.get_node("%CadenceChart") as RideChart
	assert_true(d.get_node("%CadenceSection").visible, "есть каденс — есть блок")
	assert_eq(chart.custom_minimum_size.y, 96.0, "высота 96")
	assert_eq(chart.scale_range(), Vector2(40, 140), "40…max(120, ⌈132 / 10⌉·10)")
	assert_eq(RideChart.scale_max_for(95.0), 120.0)
	assert_eq(chart.grid_values(), [60.0, 90.0] as Array[float], "подписи и сетка только на 60 и 90")
	var effort := d.effort_chart()
	assert_eq(chart.plot_rect().position.x, effort.field_rect().position.x, "слева — как у графика мощности")
	assert_almost_eq(chart.plot_rect().end.x, effort.field_rect().end.x, 0.5, "справа — как у графика мощности")


func test_cadence_block_hidden_without_cadence_data() -> void:
	var d := _detail(_free_ride(false))
	assert_false(d.get_node("%CadenceSection").visible)


func test_free_ride_card_hides_plan_target_and_paints_power_area_by_ride_zones() -> void:
	var ride := _free_ride(true)
	var d := _detail(ride)
	assert_false(d.meta_text().contains(tr("ui.history.detail.target").format({"target": "—"})), "строка параметров без цели плана")
	assert_string_contains(d.meta_text(), tr("track.flat.name"), "трасса — в строке параметров")
	var effort := d.effort_chart()
	assert_eq(effort.window_zones().boundaries_pct, ride.power_zones().boundaries_pct, "зоны площади — зоны заезда")
	assert_eq(effort.window_zones().ftp_w, ride.ftp_w())
	assert_true(bool(effort.effort_series().style(EffortSeries.SERIES_POWER)["fill"]), "мощность — площадью")


# --- Тема: поля, сетки, Caption `tnum`, диалог-форма -------------------------------------------

func test_theme_text_edit_grid_flow_caption_num_and_form_dialog() -> void:
	var theme := ThemeDB.get_project_theme()
	for state in ["normal", "focus", "read_only"]:
		assert_eq(theme.get_stylebox(state, "TextEdit"), theme.get_stylebox(state, "LineEdit"), "TextEdit.%s — как LineEdit" % state)
	assert_eq(theme.get_font("font", "TextEdit"), theme.get_font("font", "LineEdit"))
	for gap in [8, 12, 16, 24]:
		assert_eq(theme.get_constant("h_separation", "Grid%d" % gap), gap)
		assert_eq(theme.get_constant("v_separation", "Grid%d" % gap), gap)
	assert_eq(theme.get_constant("h_separation", "Flow16"), 16)
	assert_eq(theme.get_constant("v_separation", "Flow16"), 8)
	var caption := theme.get_font("font", "CaptionNumLabel") as FontVariation
	assert_eq(int(caption.opentype_features.get(TextServerManager.get_primary_interface().name_to_tag("tnum"), 0)), 1, "Caption с tnum")
	assert_eq(theme.get_font_size("font_size", "CaptionNumLabel"), 13)
	assert_eq(theme.get_color("font_color", "CaptionNumLabel"), theme.get_color("font_color", "CaptionLabel"))
	assert_eq(theme.get_constant("buttons_separation", "FormDialog"), 0, "форма без ряда кнопок окна — без разрыва")
	assert_eq(theme.get_type_variation_base(&"FormDialog"), &"AcceptDialog")


func test_zone_captions_use_flow_gap_instead_of_spacers() -> void:
	var d := _detail(_free_ride(true))
	var flow := d.get_node("%PowerZoneCaptions") as HFlowContainer
	assert_eq(flow.theme_type_variation, &"Flow16")
	for item in flow.get_children():
		for child in item.get_children():
			assert_false(child.get_class() == "Control", "без пустых узлов-отступов")
