extends GutTest
## История и карточка заезда ред. 2 (T-085): REQ-UIX-04 крит. 1 (AppBar и «назад»), 3 (строки
## истории — вариация строки списка, колонки фиксированной ширины, статус Strava, метка режима),
## 4 (пустая история); REQ-FRD-07 крит. 6 (свободная езда в истории наравне с тренировками:
## дистанция и набор в строке, карточка без ошибок, поля цели «—», график без серии цели,
## профиль высоты по дистанции); регрессия REQ-LOC-02 крит. 1, 2, REQ-LOC-03, REQ-LOC-06.
## Раскладка — `docs/game/ui.md` п. 8.5, профиль высоты — `tracks.md` п. 7.3.

const SCENE: String = "res://src/ui/history/history_screen.tscn"
const FILES: Array[String] = [
	"res://src/ui/history/history_screen.tscn", "res://src/ui/history/history_screen.gd",
	"res://src/ui/history/ride_detail.tscn", "res://src/ui/history/ride_detail.gd",
	"res://src/ui/history/history_format.gd", "res://src/ui/history/ride_chart.gd",
	"res://src/ui/history/ride_effort_chart.gd", "res://src/ui/history/ride_altitude_chart.gd",
	"res://src/ui/history/zone_bar.gd", "res://src/ui/history/recovery_dialog.gd",
]
const FTP: int = 250
const ROUTE: String = "flat"
## Скорость синтетической свободной езды, м/с: за 1200 с — 48 км, больше двух кругов «равнины».
const FREE_SPEED_MS: float = 40.0

var _dir: String
var _profiles: ProfileRepository
var _rides: FileRideRepository
var _state: AppState
var _profile: Profile
var _previous_locale: String


func before_each() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("ru")
	_dir = "user://test_history_r2_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_profiles = ProfileRepository.new(_dir + "profiles/")
	_rides = FileRideRepository.new(_dir + "rides/")
	_rides.attach_to_profiles(_profiles)
	_profile = _profiles.create("Аня")
	_profile.ftp_w = FTP
	_profile.max_hr = 185
	_profiles.save(_profile)
	_state = AppState.new(_profiles)
	_state.select_profile(_profile.id)


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


# ---------------------------------------------------------------------------
# Данные
# ---------------------------------------------------------------------------

## Тренировка по плану: два шага, постоянная мощность, пульс 140.
func _plan_ride(started: int, n: int, ride_name: String, status: String = Ride.UPLOAD_NONE) -> Ride:
	var r := Ride.new()
	r.id = Ride.generate_id(started)
	r.profile_id = _profile.id
	r.started_at_unix = started
	r.name = ride_name
	var steps: Array[WorkoutStep] = [WorkoutStep.percent(n / 2, 60.0), WorkoutStep.percent(n - n / 2, 100.0)]
	r.workout = WorkoutSerializer.to_dict(Workout.make(ride_name, steps, "zwo"))
	r.metadata = {"workout_name": ride_name, "workout_source": "zwo", "started_at_unix": started, "ftp_w": FTP,
		"weight_kg": 70.0, "max_hr": 185, "intensity": 1.0, "stopped_early": false,
		"speed_source": SampleStream.SPEED_SOURCE_TRAINER, "elapsed_sec": n, "paused_total_sec": 0.0,
		"in_progress": false, "recovered": false}
	r.samples.speed_source = SampleStream.SPEED_SOURCE_TRAINER
	for i in n:
		var target: int = 150 if i < n / 2 else 250
		r.samples.append(i, TrainerSample.full(float(i), target, 90, 30.0), 140, target, 0 if i < n / 2 else 1, true)
	r.events = [{"type": WorkoutSession.EVENT_START, "at_sec": 0.0, "value": 0}]
	r.upload["strava_status"] = status
	r.compute_summary()
	return r


## Свободная езда по «равнине»: позиция и высота — из профиля трассы каталога.
func _free_ride(started: int, n: int, route_id: String = ROUTE) -> Ride:
	var r := Ride.new()
	r.id = Ride.generate_id(started)
	r.profile_id = _profile.id
	r.started_at_unix = started
	r.metadata = Ride.free_ride_metadata(route_id, 50.0)
	r.metadata["ftp_w"] = FTP
	r.metadata["max_hr"] = 185
	r.metadata["weight_kg"] = 70.0
	r.metadata["in_progress"] = false
	r.metadata["recovered"] = false
	r.samples.speed_source = SampleStream.SPEED_SOURCE_MODEL
	var profile := RouteCatalog.get_route(route_id).profile
	for i in n:
		var d: float = float(i + 1) * FREE_SPEED_MS
		var s: float = fposmod(d, profile.length_m())
		r.samples.append(i, TrainerSample.full(float(i), 220, 88, 0.0), 130, 0, -1, false, FREE_SPEED_MS * 3.6, {},
			{"distance_m": d, "altitude_m": profile.height_at(s), "grade_pct": profile.grade_at(s)})
	r.events = [{"type": WorkoutSession.EVENT_START, "at_sec": 0.0, "value": 0}]
	r.compute_summary()
	return r


func _save(r: Ride) -> Ride:
	assert_ne(_rides.save(r), "", "заезд сохранён")
	return r


## Экран в окне размера `canvas` (lp): `SubViewport` задаёт ширину холста для брейкпоинтов.
func _screen(canvas: Vector2i = Vector2i(1280, 720)) -> HistoryScreen:
	var viewport := SubViewport.new()
	viewport.size = canvas
	add_child_autofree(viewport)
	var screen: HistoryScreen = (load(SCENE) as PackedScene).instantiate()
	screen.setup(_rides, _profiles, _state)
	viewport.add_child(screen)
	return screen


# ---------------------------------------------------------------------------
# REQ-UIX-04 крит. 3, REQ-FRD-07 крит. 6: строки истории
# ---------------------------------------------------------------------------

func test_req_frd_07_c6_free_ride_listed_with_workouts_with_distance_and_ascent() -> void:
	var plan := _save(_plan_ride(1_790_000_000, 600, "Sweet Spot"))
	var free := _save(_free_ride(1_790_100_000, 1200))
	var s := _screen()
	assert_eq(s.row_count(), 2, "свободная езда и тренировка в одном списке")
	var rows := s.row_nodes()
	assert_eq(rows.size(), 2)
	assert_eq(rows[0].row_id, free.id, "новые сверху")
	var track := tr("track.flat.name")
	assert_eq(rows[0].title, "Свободная езда — " + track, "название — по трассе (FRD-07 крит. 7)")
	var cols := rows[0].column_texts()
	assert_eq(cols.size(), 5, "время, км, ср. Вт, NP, набор")
	assert_eq(cols[0], "20:00")
	assert_eq(cols[1], "%.1f" % (free.summary.distance_m / 1000.0), "дистанция свободной езды")
	assert_almost_eq(free.summary.distance_m, 48000.0, 1.0)
	assert_eq(cols[2], "220")
	assert_eq(cols[4], str(roundi(free.summary.ascent_m)), "набор у свободной езды")
	assert_gt(free.summary.ascent_m, 0.0)
	var plan_cols := rows[1].column_texts()
	assert_eq(rows[1].row_id, plan.id)
	assert_eq(rows[1].title, "Sweet Spot")
	assert_eq(plan_cols[4], "—", "у тренировки по плану набора нет")
	assert_string_contains(s.rows()[0], "Свободная езда — " + track, "строка текстом — тоже с названием трассы")
	assert_string_contains(s.rows()[0], "48.0 км", "и с дистанцией")


func test_req_uix_04_c3_rows_are_list_row_variation_with_fixed_columns() -> void:
	_save(_plan_ride(1_790_000_000, 120, "A"))
	_save(_free_ride(1_790_100_000, 120))
	var s := _screen()
	for row in s.row_nodes():
		assert_eq(row.theme_type_variation, &"ListRowButton", "вариация строки списка темы")
		var labels: Array[Label] = []
		for child in row.get_node("%Columns").get_children():
			labels.append(child as Label)
		assert_eq(labels.size(), HistoryFormat.COLUMN_WIDTHS.size())
		for i in labels.size():
			assert_eq(labels[i].custom_minimum_size.x, HistoryFormat.COLUMN_WIDTHS[i], "колонка %d фиксированной ширины" % i)
			assert_eq(labels[i].theme_type_variation, &"NumLabel", "цифры — tnum")
	assert_eq(s.column_titles(), ["время", "км", "ср. Вт", "NP", "набор, м"] as Array[String], "единицы — в заголовке колонок")


func test_req_uix_04_c3_mode_label_and_strava_icon() -> void:
	_save(_plan_ride(1_790_000_000, 60, "Done", Ride.UPLOAD_DONE))
	_save(_plan_ride(1_790_001_000, 60, "Failed", Ride.UPLOAD_FAILED))
	_save(_free_ride(1_790_002_000, 60))
	var s := _screen()
	var rows := s.row_nodes()
	var expect := [
		["SIM", Ride.UPLOAD_NONE, "cloud-upload", UiTokens.SIM],
		["План", Ride.UPLOAD_FAILED, "triangle-alert", UiTokens.ACCENT],
		["План", Ride.UPLOAD_DONE, "check", UiTokens.ACCENT],
	]
	for i in rows.size():
		var mode := rows[i].leading_slot().get_child(0) as Label
		assert_eq(mode.text, expect[i][0], "метка режима строки %d" % i)
		assert_true(mode.uppercase, "Overline заглавными")
		var tinted: Color = mode.get_theme_color("font_color") * mode.self_modulate
		assert_almost_eq(tinted.r, (expect[i][3] as Color).r, 0.01, "цвет метки режима")
		var icon := rows[i].trailing_slot().get_child(0) as TextureRect
		assert_eq(icon.texture.resource_path, UiIcons.path(expect[i][2]), "значок Strava строки %d" % i)
		assert_eq(icon.tooltip_text, tr(HistoryScreen.strava_status_key(expect[i][1])))
	assert_eq((rows[2].trailing_slot().get_child(0) as TextureRect).self_modulate, UiTokens.ACCENT, "выгружено — accent")


func test_rows_grouped_by_month_newest_first() -> void:
	_save(_plan_ride(1_790_000_000, 60, "Sep"))   # 2026-09-21
	_save(_plan_ride(1_791_800_000, 60, "Oct"))   # 2026-10-12
	var s := _screen()
	var groups := s.get_node("%Groups")
	assert_eq(groups.get_child_count(), 2, "две группы месяцев")
	var first := groups.get_child(0).get_child(0) as Label
	assert_eq(first.theme_type_variation, &"OverlineLabel")
	assert_eq(first.text, HistoryFormat.month_header(1_791_800_000))
	assert_string_contains(first.text, "Октябрь")


func test_row_overline_date_and_flags() -> void:
	var r := _plan_ride(1_790_000_000, 60, "Early")
	r.metadata["stopped_early"] = true
	r.compute_summary()
	_save(r)
	var s := _screen()
	var overline: String = s.row_nodes()[0].overline
	assert_eq(overline, HistoryFormat.short_date(1_790_000_000) + " · завершён досрочно")
	var d := HistoryFormat.local_datetime(1_790_000_000)
	assert_string_contains(overline, "%d %s" % [d["day"], tr("ui.history.mon.%d" % d["month"])])


func test_req_uix_05_compact_has_three_columns() -> void:
	_save(_free_ride(1_790_000_000, 120))
	var s := _screen(Vector2i(867, 400))
	assert_true(s.is_compact(), "холст уже 1100 lp — compact")
	assert_eq(s.row_nodes()[0].column_texts().size(), 3, "время, км, ср. Вт")
	assert_eq(s.column_titles().size(), 3)


func test_row_touch_target_and_zone_strip() -> void:
	_save(_plan_ride(1_790_000_000, 300, "Zones"))
	var s := _screen()
	var row := s.row_nodes()[0]
	assert_gte(row.custom_minimum_size.y, ListRow.HEIGHT_TWO_LINES, "строка 76 lp и выше")
	assert_not_null(TouchTarget.of(row), "цель нажатия — хелпер TouchTarget")
	var bar := row.bottom_slot().get_child(0) as ZoneBar
	assert_not_null(bar, "полоса времени в зонах внизу строки")
	assert_eq(bar.custom_minimum_size.y, HistoryScreen.ROW_ZONE_BAR_HEIGHT)
	assert_eq(bar.total_sec(), 300)


func test_req_loc_02_c2_rows_created_by_pages() -> void:
	for i in 100:
		_rides.save(_plan_ride(1_780_000_000 + i * 3600, 30, "Ride %03d" % i))
	var s := _screen()
	assert_eq(s.row_count(), 100, "данные — все заезды")
	assert_eq(s.rows().size(), 100)
	assert_eq(s.row_nodes().size(), HistoryScreen.PAGE_SIZE, "на экране — первая страница")
	var last := s.ensure_row(99)
	assert_not_null(last)
	assert_eq(s.row_nodes().size(), 100)
	assert_eq(last.title, "Ride 000", "самый старый — последним")
	last.pressed.emit()
	assert_true(s.is_detail_visible(), "нажатие строки открывает карточку")
	assert_eq(s.detail().ride().name, "Ride 000")


# ---------------------------------------------------------------------------
# Фильтр
# ---------------------------------------------------------------------------

func test_filter_chips_plan_and_free() -> void:
	_save(_plan_ride(1_790_000_000, 60, "Plan"))
	_save(_free_ride(1_790_100_000, 60))
	var s := _screen()
	assert_eq(s.filter_chip(HistoryFormat.Filter.ALL).text, "Все")
	assert_true(s.filter_chip(HistoryFormat.Filter.ALL).button_pressed)
	s.filter_chip(HistoryFormat.Filter.FREE).button_pressed = true
	assert_eq(s.filter(), HistoryFormat.Filter.FREE)
	assert_eq(s.row_count(), 1)
	assert_true(s.summaries()[0].is_free_ride())
	s.filter_chip(HistoryFormat.Filter.PLAN).button_pressed = true
	assert_eq(s.row_count(), 1)
	assert_false(s.summaries()[0].is_free_ride())


func test_filter_without_matches_shows_reset_action() -> void:
	_save(_plan_ride(1_790_000_000, 60, "Plan"))
	var s := _screen()
	s.set_filter(HistoryFormat.Filter.FREE)
	assert_eq(s.row_count(), 0)
	assert_true(s.is_empty_label_visible())
	assert_eq(s.empty_state().title_label().text, "Нет заездов этого типа")
	s.empty_state().action_button().pressed.emit()
	assert_eq(s.filter(), HistoryFormat.Filter.ALL, "«Показать все» сбрасывает фильтр")
	assert_eq(s.row_count(), 1)
	assert_true(s.filter_chip(HistoryFormat.Filter.ALL).button_pressed)


# ---------------------------------------------------------------------------
# REQ-UIX-04 крит. 4: пустая история
# ---------------------------------------------------------------------------

func test_req_uix_04_c4_empty_history_icon_text_and_action() -> void:
	_state.navigate(AppState.Screen.HISTORY)
	var s := _screen()
	assert_eq(s.row_count(), 0)
	assert_true(s.is_empty_label_visible())
	var empty := s.empty_state()
	assert_true(empty.icon_rect().visible)
	assert_eq(empty.icon_rect().texture.resource_path, UiIcons.path("history"))
	assert_eq(empty.title_label().text, "Заездов пока нет")
	assert_eq(empty.text_label().text, "Первая тренировка появится здесь")
	assert_eq(empty.action_button().text, "На главный")
	assert_false((s.get_node("%Scroll") as Control).visible, "списка нет")
	empty.action_button().pressed.emit()
	assert_eq(_state.current_screen, AppState.Screen.HOME, "«На главный»")


# ---------------------------------------------------------------------------
# REQ-UIX-04 крит. 1: AppBar и «назад»
# ---------------------------------------------------------------------------

func test_req_uix_04_c1_list_app_bar_back_goes_back() -> void:
	_state.navigate(AppState.Screen.HISTORY)
	var s := _screen()
	assert_eq(s.app_bar().title_text(), "История")
	assert_eq(s.app_bar().get_node("%Title").theme_type_variation, &"H1Label")
	var back := s.get_node("%BackButton") as Button
	assert_true(back.visible)
	back.pressed.emit()
	assert_eq(_state.current_screen, AppState.Screen.HOME, "«назад» — на экран, с которого пришли")


func test_req_uix_04_c1_detail_back_returns_to_list_without_navigation() -> void:
	var r := _save(_plan_ride(1_790_000_000, 60, "Card"))
	_state.navigate(AppState.Screen.HISTORY)
	var s := _screen()
	assert_true(s.show_ride(r.id))
	var d := s.detail()
	assert_eq(d.title_text(), "Card", "название заезда в AppBar")
	(d.get_node("%BackButton") as Button).pressed.emit()
	assert_false(s.is_detail_visible(), "к списку")
	assert_eq(_state.current_screen, AppState.Screen.HISTORY, "экран не сменился")
	assert_true(s.show_ride(r.id))
	assert_true(s.handle_back(), "Esc закрывает карточку")
	assert_false(s.handle_back(), "дальше решает стек AppState")


# ---------------------------------------------------------------------------
# REQ-FRD-07 крит. 6: карточка свободной езды
# ---------------------------------------------------------------------------

func test_req_frd_07_c6_free_ride_card_without_target_with_altitude_profile() -> void:
	var r := _save(_free_ride(1_790_000_000, 1200))
	var s := _screen()
	assert_true(s.show_ride(r.id))
	var d := s.detail()
	assert_eq(d.mode_text(), "SIM")
	assert_eq(d.title_text(), "Свободная езда — " + tr("track.flat.name"))
	assert_string_contains(d.summary_text(), "Средняя цель плана: — Вт", "поля цели — «—»")
	assert_string_contains(d.meta_text(), "Средняя цель плана: — Вт")
	assert_string_contains(d.meta_text(), tr("track.flat.name"), "трасса в параметрах заезда")
	assert_false(d.series().has_data(RideSeries.TARGET), "серии цели нет")
	assert_false((d.get_node("%PowerChart") as RideChart).has_target(), "график без серии цели")
	assert_false(d.effort_chart().has_plan(), "общий график — без плана")
	assert_eq(d.effort_chart().mode, HudChart.Mode.WINDOW)
	assert_gt(EffortSeries.point_count(d.effort_chart().effort_series().power_runs(0.0, 1200.0, 800, 1000.0)), 0, "линия мощности есть")
	assert_true(d.is_altitude_visible(), "профиль высоты по дистанции")
	var alt := d.altitude_chart()
	assert_gt(alt.point_count(), 100)
	assert_almost_eq(alt.total_distance_m(), 48000.0, 1.0)
	var lap := RouteCatalog.get_route(ROUTE).profile.length_m()
	assert_eq(alt.lap_marks().size(), int(ceil(48000.0 / lap)) - 1, "граница каждого круга")
	assert_almost_eq(alt.lap_marks()[0], lap, 0.01)
	var ascent := d.stat("ascent")
	assert_true(ascent.visible, "плитка набора у свободной езды")
	assert_eq(ascent.value, str(roundi(r.summary.ascent_m)))
	assert_eq(d.visible_stats().size(), 9)


func test_plan_card_has_ghost_plan_and_no_altitude() -> void:
	var r := _save(_plan_ride(1_790_000_000, 600, "Ghost"))
	var s := _screen()
	assert_true(s.show_ride(r.id))
	var d := s.detail()
	assert_eq(d.mode_text(), "План")
	assert_true(d.effort_chart().has_plan(), "план под фактом")
	assert_eq(d.effort_chart().mode, HudChart.Mode.PLAN)
	var model := d.effort_chart().plan_model()
	assert_eq(model.total_sec(), 600)
	for piece in model.pieces():
		assert_eq(str(piece["status"]), PlanChartModel.STATUS_DONE, "весь план — «призрак» пройденного")
	assert_false(d.is_altitude_visible())
	assert_false(d.stat("ascent").visible, "набора у плана нет")
	assert_eq(d.visible_stats().size(), 8)
	assert_eq(d.stat("avg_power").value, "200")
	assert_eq(d.stat("np").unit_label().text, "Вт")
	assert_string_contains(d.meta_text(), "Средняя цель плана: 200 Вт")
	assert_eq(d.stats_columns(), RideDetail.STAT_COLUMNS)


func test_card_compact_three_stats_per_row() -> void:
	var r := _save(_plan_ride(1_790_000_000, 60, "Phone"))
	var s := _screen(Vector2i(867, 400))
	s.show_ride(r.id)
	assert_true(s.detail().is_compact())
	assert_eq(s.detail().stats_columns(), RideDetail.STAT_COLUMNS_COMPACT)


func test_card_zone_bars_with_captions() -> void:
	var r := _save(_plan_ride(1_790_000_000, 600, "Zones"))
	var s := _screen()
	s.show_ride(r.id)
	var captions := s.detail().get_node("%PowerZoneCaptions") as HFlowContainer
	assert_gt(captions.get_child_count(), 0, "подписи долей зон")
	var total := 0
	for share in (s.detail().get_node("%PowerZoneBar") as ZoneBar).shares():
		total += int(share["sec"])
	assert_eq(total, 600)
	assert_eq((s.detail().get_node("%PowerZoneBar") as Control).custom_minimum_size.y, 12.0, "полоса 12 lp")


# ---------------------------------------------------------------------------
# Меню «⋯»: экспорт и удаление остаются (REQ-LOC-05, REQ-LOC-06)
# ---------------------------------------------------------------------------

func test_more_menu_holds_export_and_delete() -> void:
	var r := _save(_plan_ride(1_790_000_000, 60, "Menu"))
	var s := _screen()
	s.show_ride(r.id)
	var d := s.detail()
	assert_not_null(d.more_button())
	assert_eq(d.more_button().icon.resource_path, UiIcons.path("ellipsis"))
	assert_false(d.is_menu_open())
	d.more_button().pressed.emit()
	assert_true(d.is_menu_open())
	var delete := d.get_node("%DeleteButton") as Button
	assert_true(delete.is_visible_in_tree(), "«Удалить заезд» в меню")
	assert_true((d.get_node("%ExportButton") as Button).is_visible_in_tree(), "«Экспорт FIT» в меню")
	delete.pressed.emit()
	assert_false(d.is_menu_open(), "меню закрывается")
	assert_true(d.is_delete_pending(), "удаление — с подтверждением")
	assert_true((d.get_node("%DeleteDialog") as ConfirmationDialog).visible)
	d.cancel_delete()
	assert_not_null(_rides.get_ride(r.id))
	d.open_menu()
	s.back_to_list()
	assert_false(d.is_menu_open(), "закрытие карточки закрывает меню")


# ---------------------------------------------------------------------------
# Чистые функции
# ---------------------------------------------------------------------------

func test_altitude_lap_boundaries_and_grade_pieces() -> void:
	assert_eq(RideAltitudeChart.lap_boundaries(4500.0, 2000.0), PackedFloat32Array([2000.0, 4000.0]))
	assert_eq(RideAltitudeChart.lap_boundaries(4000.0, 2000.0), PackedFloat32Array([2000.0]), "конец ровно на круге — без линии у края")
	assert_eq(RideAltitudeChart.lap_boundaries(1000.0, 0.0).size(), 0)
	var pts := PackedVector2Array([Vector2(0, 100), Vector2(50, 101), Vector2(100, 102), Vector2(150, 102), Vector2(250, 97)])
	var pieces := RideAltitudeChart.grade_pieces(pts, 100.0)
	assert_eq(pieces.size(), 2)
	assert_eq(int(pieces[0]["to"]), 2)
	assert_almost_eq(float(pieces[0]["grade"]), 2.0, 1e-4)
	assert_almost_eq(float(pieces[1]["grade"]), -3.33333, 1e-3)
	assert_eq(RideAltitudeChart.km_labels(48000.0).size(), 10, "≤ 10 подписей км")


func test_format_dates_ru_en() -> void:
	var unix := 1_790_000_000
	var d := HistoryFormat.local_datetime(unix)
	var time := "%02d:%02d" % [d["hour"], d["minute"]]
	assert_eq(HistoryFormat.short_date(unix), "%d %s, %s" % [d["day"], tr("ui.history.mon.%d" % d["month"]), time])
	TranslationServer.set_locale("en")
	assert_eq(HistoryFormat.short_date(unix), "%s %d, %s" % [tr("ui.history.mon.%d" % d["month"]), d["day"], time])
	assert_eq(HistoryFormat.full_date(unix), "%s %d, %d, %s" % [tr("ui.history.mon.%d" % d["month"]), d["day"], d["year"], time])
	assert_eq(HistoryFormat.ride_title("", true, "mountains"), "Free ride — Mountain Pass")
	assert_eq(HistoryFormat.ride_title("", false, ""), "Workout")


func test_new_keys_translated_ru_and_en() -> void:
	var keys: Array[String] = ["ui.history.bar.title", "ui.history.empty.title", "ui.history.col.ascent",
		"ui.history.mode.plan", "ui.history.section.effort", "ui.history.stat.ascent", "ui.history.detail.target",
		"ui.history.menu.more", "ui.history.flag.stopped_early", "ui.history.filter.free"]
	for i in 12:
		keys.append("ui.history.month.%d" % (i + 1))
		keys.append("ui.history.mon.%d" % (i + 1))
	for locale in ["ru", "en"]:
		TranslationServer.set_locale(locale)
		for key in keys:
			assert_ne(tr(key), key, "%s: перевод %s" % [locale, key])


func test_history_files_have_no_theme_overrides() -> void:
	for path in FILES:
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.is_empty(), path)
		assert_false(text.contains("theme_override_"), "%s: без theme_override_*" % path)
		assert_false(text.contains("add_theme_"), "%s: без add_theme_*_override" % path)
