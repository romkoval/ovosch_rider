extends GutTest
## Приёмка T-078 (tester, независимо от разработчика): сборка HUD тренировки на живом
## `WorkoutScreen` с сессией на `FakeTrainer` — `HudChart`, `IntervalList`, `NextChip`,
## `PauseOverlay`, `HudToolbar` в слотах `HudLayout`.
## REQ-HUD-13 крит. 2–5, 9; REQ-HUD-10 крит. 5 (курсор на паузе); REQ-HUD-06 крит. 2 (фишка «ДАЛЕЕ»);
## T-078: в тренировке по плану станку не уходит уклон (`CMD_SIM`).
##
## Геометрия — на реальных узлах при настоящем размере окна (`root.size`), растяжение `canvas_items`
## + `expand` из `project.godot`: разрешения вводного абзаца HUD (1280×720, 1024×768, 1280×590 с
## имитацией телефона и безопасной зоны 100/100/0/13 lp базового холста, 1920×1080, 2732×2048,
## 2556×1179). Доли окна — в lp видимого холста (`get_viewport_rect()`).

const SCENE: String = "res://src/ui/workout/workout_screen.tscn"
const ACC_FULL: String = "res://tests/fixtures/workouts_acceptance/acc_full.zwo"
const SAFE_BASE_LP: Vector4 = Vector4(100, 0, 100, 13)
const CASES: Array[Dictionary] = [
	{"name": "1280x720", "px": Vector2i(1280, 720), "phone": false},
	{"name": "1024x768", "px": Vector2i(1024, 768), "phone": false},
	{"name": "1280x590", "px": Vector2i(1280, 590), "phone": true},
	{"name": "1920x1080", "px": Vector2i(1920, 1080), "phone": false},
	{"name": "2732x2048", "px": Vector2i(2732, 2048), "phone": false},
	{"name": "2556x1179", "px": Vector2i(2556, 1179), "phone": true},
]

var _now_usec: int = 0
var _trainer: FakeTrainer
var _profile: Profile
var _state: AppState
var _repo: ProfileRepository
var _dir: String
var _previous_locale: String
var _root_size: Vector2i
var _ui: UiScale


func before_each() -> void:
	_now_usec = 3_000_000
	_dir = "user://test_t078_acc_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_repo = ProfileRepository.new(_dir + "profiles/")
	_state = AppState.new(_repo)
	_trainer = FakeTrainer.new(78)
	_trainer.connect_delay_sec = 0.0
	_trainer.power_noise_w = 0.0
	_trainer.power_tau_sec = 0.01
	_trainer.cadence_noise_rpm = 0.0
	_trainer.connect_device("t078")
	_profile = Profile.create("Rider")
	_profile.ftp_w = 250
	_profile.max_hr = 185
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_root_size = get_tree().root.size
	_ui = get_tree().root.get_node_or_null(^"UiScaleRuntime") as UiScale


func after_each() -> void:
	TranslationServer.set_locale(_previous_locale)
	_set_device(false)
	if Engine.has_meta(UiScale.DEBUG_SAFE_AREA_META):
		Engine.remove_meta(UiScale.DEBUG_SAFE_AREA_META)
	if _ui != null:
		_ui.set_mode(UiScale.Mode.MENU)
	get_tree().root.size = _root_size
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
# Помощники
# ---------------------------------------------------------------------------

func _clock() -> int:
	return _now_usec


static func _plan(steps: Array) -> Workout:
	var typed: Array[WorkoutStep] = []
	for s in steps:
		typed.append(s)
	return Workout.make("t078-plan", typed)


func _acc_full() -> Workout:
	var result: ParseResult = ZwoParser.parse(FileAccess.get_file_as_string(ACC_FULL))
	assert_true(result.ok(), "предусловие: acc_full.zwo разбирается")
	return result.workout


## 30 шагов по 20 с: 100 / 200 / 300 Вт по кругу.
static func _long_plan() -> Workout:
	var steps: Array = []
	for i in 30:
		steps.append(WorkoutStep.watts(20, [100.0, 200.0, 300.0][i % 3]))
	return _plan(steps)


func _set_device(phone: bool) -> void:
	if phone:
		Engine.set_meta(UiScale.DEBUG_DEVICE_META, "phone")
	elif Engine.has_meta(UiScale.DEBUG_DEVICE_META):
		Engine.remove_meta(UiScale.DEBUG_DEVICE_META)
	if _ui != null:
		_ui.device = UiScale.detect_device()


func _screen(workout: Workout = null) -> WorkoutScreen:
	var s: WorkoutScreen = load(SCENE).instantiate()
	s.clock_usec = _clock
	s.keep_awake_setter = func(_on: bool) -> void: pass
	add_child_autofree(s)
	s.setup(workout if workout != null else _acc_full(), _profile, _trainer, _state)
	assert_true(s.start(), "предусловие: экран запущен")
	s.on_screen_entered()
	return s


func _apply_case(s: WorkoutScreen, c: Dictionary) -> void:
	var phone: bool = c["phone"]
	_set_device(phone)
	if phone:
		Engine.set_meta(UiScale.DEBUG_SAFE_AREA_META, SAFE_BASE_LP / UiScale.HUD_SCALE_PHONE)
	elif Engine.has_meta(UiScale.DEBUG_SAFE_AREA_META):
		Engine.remove_meta(UiScale.DEBUG_SAFE_AREA_META)
	get_tree().root.size = c["px"]
	if _ui != null:
		_ui.set_mode(UiScale.Mode.HUD)
	s.on_screen_entered()
	await wait_process_frames(3)
	s.refresh()


func _advance(s: WorkoutScreen, sec: float) -> void:
	_now_usec += int(round(sec * 1_000_000.0))
	if s.ticker() != null:
		s.ticker().poll()


## По секунде: тикер обрабатывает каждую секунду отдельно (как в приложении).
func _ride(s: WorkoutScreen, seconds: int) -> void:
	for i in seconds:
		_advance(s, 1.0)


## Безопасная (рабочая) область холста в lp: на телефоне — без имитированных отступов.
func _safe_rect(s: WorkoutScreen, c: Dictionary) -> Rect2:
	var canvas := s.get_viewport_rect().size
	if not c["phone"]:
		return Rect2(Vector2.ZERO, canvas)
	var m := SAFE_BASE_LP / s.get_window().content_scale_factor
	return Rect2(m.x, m.y, canvas.x - m.x - m.z, canvas.y - m.y - m.w)


static func _center(canvas: Vector2) -> Rect2:
	return Rect2(canvas * Vector2(0.30, 0.35), canvas * Vector2(0.40, 0.40))


static func _opacity(c: CanvasItem) -> float:
	var a := c.self_modulate.a
	var n: Node = c
	while n is CanvasItem:
		a *= (n as CanvasItem).modulate.a
		n = n.get_parent()
	return a


static func _draws(c: Control) -> bool:
	if c is Label or c is Button or c is TextureRect or c is PanelContainer or c is Panel:
		return true
	return not c.get_signal_connection_list(&"draw").is_empty() or (c.get_script() != null and c.has_method("_draw"))


func _opaque_nodes(root: Node) -> Array[Control]:
	var out: Array[Control] = []
	for n in root.find_children("*", "Control", true, false):
		var c := n as Control
		if c.is_visible_in_tree() and c.size.x > 0.0 and c.size.y > 0.0 and _draws(c) and _opacity(c) >= 0.5:
			out.append(c)
	return out


# ===========================================================================
# REQ-HUD-13 крит. 4 — график прижат к низу, во всю ширину, 12–22 % высоты
# ===========================================================================

func test_req_hud_13_c4_chart_at_bottom_full_safe_width_12_to_22_percent_on_resolutions() -> void:
	var s := _screen()
	_trainer.set_heart_rate(140)
	_ride(s, 30)
	for c in CASES:
		await _apply_case(s, c)
		var canvas := s.get_viewport_rect().size
		var safe := _safe_rect(s, c)
		var chart := s.chart()
		assert_true(chart.is_visible_in_tree(), "%s: график на экране" % c["name"])
		assert_not_null(chart.plan_model(), "%s: график плана построен" % c["name"])
		var r := chart.get_global_rect()
		# Подложка графика — без градиента над ней (градиент полупрозрачный, `hud.md` п. 4.1).
		var plate := Rect2(r.position.x, r.position.y + chart.plate_top(), r.size.x, r.size.y - chart.plate_top())
		var share := plate.size.y / canvas.y
		gut.p("%s: холст %s, безопасная %s, график %s (подложка %.1f %% H)" % [c["name"], canvas, safe, r, 100.0 * share])
		assert_almost_eq(plate.end.y, safe.end.y, 1.0, "%s: низ графика у нижнего края безопасной зоны" % c["name"])
		assert_almost_eq(plate.position.x, safe.position.x, 1.0, "%s: левый край графика у безопасного отступа" % c["name"])
		assert_almost_eq(plate.end.x, safe.end.x, 1.0, "%s: правый край графика у безопасного отступа" % c["name"])
		assert_true(share >= 0.12 - 0.001 and share <= 0.22 + 0.001, "%s: высота графика %.1f %% окна в 12–22 %%" % [c["name"], 100.0 * share])
		assert_gte(_opacity(chart), 0.99, "%s: график непрозрачен" % c["name"])


# ===========================================================================
# REQ-HUD-13 крит. 2, 3 на экране — список в левых 25 %, текущая строка видна
# ===========================================================================

func test_req_hud_13_c2_interval_list_in_left_25_percent_on_resolutions() -> void:
	var s := _screen()
	_ride(s, 30)
	for c in CASES:
		await _apply_case(s, c)
		var canvas := s.get_viewport_rect().size
		var safe := _safe_rect(s, c)
		var list := s.interval_list()
		assert_true(list.is_visible_in_tree(), "%s: список на экране" % c["name"])
		var r := list.get_global_rect()
		gut.p("%s: список %s, 25 %% ширины = %.1f" % [c["name"], r, 0.25 * canvas.x])
		assert_true(r.has_area(), "%s: список не пустой" % c["name"])
		assert_true(r.position.x >= safe.position.x - 0.5, "%s: список не заходит в безопасный отступ" % c["name"])
		assert_true(r.end.x <= 0.25 * canvas.x + 0.5, "%s: список %.1f в левых 25 %% (%.1f)" % [c["name"], r.end.x, 0.25 * canvas.x])
		var chart_top := s.chart().get_global_rect().position.y + s.chart().plate_top()
		assert_true(r.end.y <= chart_top + 0.5, "%s: список не заходит на график" % c["name"])
		assert_true(list.current_row_rect().has_area(), "%s: текущая строка видна" % c["name"])


func test_req_hud_13_c3_selection_follows_session_on_long_plan_and_stays_visible() -> void:
	var s := _screen(_long_plan())
	await _apply_case(s, CASES[0])
	var list := s.interval_list()
	for k in 29:
		var expected := k
		assert_eq(list.model.current_row(), expected, "шаг %d: выделена строка %d" % [k, expected])
		var rows := list.model.rows()
		var current := 0
		for row in rows:
			if row["status"] == IntervalListModel.STATUS_CURRENT:
				current += 1
		assert_eq(current, 1, "шаг %d: ровно одна строка «текущий»" % k)
		assert_lte(list.visible_rows().size(), 8, "шаг %d: в окне не больше 8 строк" % k)
		list.skip_animation()
		assert_true(list.current_row_rect().has_area(), "шаг %d: текущая строка в видимой области" % k)
		_ride(s, 20) # смена шага — на следующем сэмпле выделение уже на новой строке
	assert_eq(list.model.current_row(), 29)


func test_req_hud_13_c3_skip_marks_row_skipped_and_moves_selection_same_sample() -> void:
	var s := _screen(_long_plan())
	_ride(s, 5)
	s.toolbar().button(&"skip").pressed.emit()
	var list := s.interval_list()
	assert_eq(list.model.current_row(), 1, "выделение на новой строке сразу после пропуска")
	assert_eq(list.model.rows()[0]["status"], IntervalListModel.STATUS_SKIPPED, "пропущенный шаг — «пропущен»")
	_ride(s, 20)
	assert_eq(list.model.rows()[1]["status"], IntervalListModel.STATUS_DONE, "пройденный — «пройден»")


# ===========================================================================
# REQ-HUD-13 крит. 5 — центр свободен, в том числе при показанной панели инструментов
# ===========================================================================

func test_req_hud_13_c5_center_free_with_toolbar_shown_erg_on_and_off_on_resolutions() -> void:
	var s := _screen()
	_trainer.set_heart_rate(140)
	_ride(s, 20)
	for erg_on in [true, false]:
		if s.session().erg_enabled != erg_on:
			s.toolbar().button(&"erg").pressed.emit()
		for c in CASES:
			await _apply_case(s, c)
			s.toolbar().poke()
			await wait_seconds(0.3) # появление 200 мс
			var canvas := s.get_viewport_rect().size
			var center := _center(canvas)
			var tag := "%s, ERG %s" % [c["name"], "вкл" if erg_on else "выкл"]
			assert_true(s.toolbar().is_shown(), "%s: панель инструментов показана" % tag)
			var tr_rect := s.toolbar().get_global_rect()
			gut.p("%s: панель %s (%d кнопок, рядов %d), центр %s" % [tag, tr_rect, s.toolbar().visible_buttons().size(), s.toolbar().button_row_count(), center])
			assert_false(tr_rect.intersects(center), "%s: панель %s заходит в центр %s" % [tag, tr_rect, center])
			for b in s.toolbar().visible_buttons():
				assert_false(b.get_global_rect().intersects(center), "%s: кнопка %s в центре" % [tag, b.name])
			assert_true(_safe_rect(s, c).grow(0.5).encloses(tr_rect), "%s: панель в безопасной зоне" % tag)
			var chart_top := s.chart().get_global_rect().position.y + s.chart().plate_top()
			assert_true(tr_rect.end.y <= chart_top + 0.5, "%s: панель не заходит на график" % tag)
			var checked := 0
			for node in _opaque_nodes(s.get_node("%HudRoot")):
				checked += 1
				assert_false(node.get_global_rect().intersects(center), "%s: %s %s в центре" % [tag, node.get_path(), node.get_global_rect()])
			assert_gt(checked, 20, "%s: проверено %d элементов" % [tag, checked])


## Крит. 9: фишка «ДАЛЕЕ» (за 5 с до смены) и подсказка не пересекают центр; на телефоне — над графиком.
func test_req_hud_13_c9_next_chip_outside_center_on_resolutions() -> void:
	var first := WorkoutStep.watts(60, 150.0)
	first.text_cues.append(TextCue.make(54, "Get ready"))
	var s := _screen(_plan([first, WorkoutStep.watts(60, 300.0)]))
	_ride(s, 55)
	for c in CASES:
		await _apply_case(s, c)
		await wait_seconds(0.3)
		var canvas := s.get_viewport_rect().size
		var chip := s.next_chip()
		assert_true(chip.is_shown(), "%s: фишка «ДАЛЕЕ» показана за 5 с" % c["name"])
		var r := chip.get_global_rect()
		assert_false(r.intersects(_center(canvas)), "%s: фишка %s не в центре" % [c["name"], r])
		var chart_top := s.chart().get_global_rect().position.y + s.chart().plate_top()
		assert_true(r.end.y <= chart_top + 0.5, "%s: фишка не на графике" % c["name"])
		if c["phone"]:
			assert_gt(r.position.y, canvas.y * 0.5, "%s: на телефоне фишка у низа кадра" % c["name"])
		else:
			assert_gte(r.position.y, s.metric_panel().get_global_rect().end.y, "%s: под панелью цифр" % c["name"])


# ===========================================================================
# REQ-HUD-06 крит. 2 — «скоро смена» на экране: фишка «ДАЛЕЕ», вытесняет подсказку
# ===========================================================================

func test_req_hud_06_c2_next_chip_5_to_1_seconds_then_hidden_and_cue_suppressed() -> void:
	var first := WorkoutStep.watts(60, 150.0)
	first.text_cues.append(TextCue.make(52, "Get ready"))
	var s := _screen(_plan([first, WorkoutStep.watts(90, 300.0), WorkoutStep.free_ride(30)]))
	_ride(s, 54)
	assert_false(s.next_chip().is_shown(), "6 с до смены — фишки нет")
	assert_eq(s.cue_text(), "Get ready")
	assert_true((s.get_node("%CueLabel") as Label).visible, "подсказка видна, пока нет фишки")
	_ride(s, 1)
	assert_true(s.next_chip().is_shown(), "за 5 с — фишка")
	assert_eq(s.next_chip().seconds_text(), "5")
	assert_string_contains(s.next_chip().line_text(), "1:30")
	assert_string_contains(s.next_chip().line_text(), "300 W")
	assert_eq(s.next_chip().zone_color(), ZonePalette.color("z5"), "полоса цвета зоны следующего шага (300 / 250 = 120 %% → Z5)")
	assert_false((s.get_node("%CueLabel") as Label).visible, "фишка вытесняет подсказку")
	for left in [4, 3, 2, 1]:
		_ride(s, 1)
		assert_eq(s.next_chip().seconds_text(), str(left), "секунды %d" % left)
	_ride(s, 1)
	assert_false(s.next_chip().is_shown(), "на смене шага фишка уходит")
	_ride(s, 85)
	assert_true(s.next_chip().is_shown(), "перед свободным шагом — фишка")
	assert_string_contains(s.next_chip().line_text(), "free ride", "следующий — «свободно»")
	_ride(s, 5)
	_ride(s, 25)
	assert_false(s.next_chip().is_shown(), "за 5 с до конца последнего шага следующего нет — фишки нет")


# ===========================================================================
# REQ-HUD-10 крит. 5 — на паузе курсор графика и линии факта стоят
# ===========================================================================

func test_req_hud_10_c5_cursor_and_fact_lines_stand_on_pause() -> void:
	var s := _screen()
	await _apply_case(s, CASES[0])
	_trainer.set_heart_rate(140)
	_ride(s, 30)
	var chart := s.chart()
	var model := chart.plan_model()
	var x0 := chart.cursor_x()
	var sec0 := model.cursor_sec()
	var points0 := chart.effort_series().size()
	assert_almost_eq(sec0, 30.0, 1e-6, "предусловие: курсор на 30 с плана")
	s.get_node("%PauseButton").pressed.emit()
	assert_eq(s.session().get_state(), WorkoutSession.State.PAUSED)
	assert_eq(s.pause_overlay().view(), PauseOverlay.View.PAUSE, "карточка паузы")
	_ride(s, 20)
	await wait_process_frames(2)
	assert_eq(model.cursor_sec(), sec0, "на паузе позиция курсора стоит")
	assert_almost_eq(chart.cursor_x(), x0, 0.01, "на паузе курсор на графике стоит")
	assert_eq(chart.effort_series().size(), points0, "на паузе точек факта не прибавилось")
	s.pause_overlay().resume_button().pressed.emit()
	assert_eq(s.session().get_state(), WorkoutSession.State.RUNNING)
	_ride(s, 1)
	assert_almost_eq(model.cursor_sec(), sec0 + 1.0, 1e-6, "после возобновления курсор продолжает с того же места")
	assert_eq(chart.effort_series().last_time_sec(), 31, "линия продолжается с того же x")


# ===========================================================================
# T-078 — в тренировке по плану уклон станку не уходит
# ===========================================================================

func test_t078_plan_workout_never_sends_sim_to_trainer() -> void:
	var s := _screen()
	await _apply_case(s, CASES[0])
	assert_eq(s.ride_scene().route_id, RouteCatalog.DEFAULT_ID, "тренировка по плану — трасса по умолчанию")
	_ride(s, 30)
	s.toolbar().button(&"erg").pressed.emit() # ERG выкл
	_ride(s, 30)
	s.toolbar().button(&"resistance_up").pressed.emit()
	s.toolbar().button(&"erg").pressed.emit() # ERG вкл
	s.toolbar().button(&"intensity_up").pressed.emit()
	s.toolbar().button(&"skip").pressed.emit()
	s.get_node("%PauseButton").pressed.emit()
	_ride(s, 5)
	s.pause_overlay().resume_button().pressed.emit()
	_ride(s, 120)
	await wait_process_frames(2)
	var types := {}
	for cmd in _trainer.commands:
		types[cmd["type"]] = int(types.get(cmd["type"], 0)) + 1
	gut.p("журнал FakeTrainer: %s" % types)
	assert_gt(_trainer.commands.size(), 5, "предусловие: команды станку шли")
	assert_false(types.has(FakeTrainer.CMD_SIM), "в журнале нет CMD_SIM")
