extends GutTest
## Приёмка T-073 (tester, независимо от `tests/unit/ui/test_hud_layout.gd` и `test_hud_metric_panel.gd`):
## каркас экрана тренировки на живом `WorkoutScreen` с сессией на `FakeTrainer`.
## REQ-HUD-01 (ред. 2026-10-03) крит. 1–4; REQ-HUD-13 крит. 1, 5, 6, 10; REQ-HUD-14 крит. 2–4;
## регрессия REQ-HUD-02..06, REQ-HUD-09.
##
## Геометрия проверяется на реальных узлах экрана при настоящем размере окна (`root.size`) с растяжением
## `canvas_items` + `expand` из `project.godot`: 1280×720, 1024×768 (4:3), 1280×590 (≈ 19.5:9, телефон,
## `Engine.set_meta("ui_debug_device", "phone")`, имитация безопасной зоны 100/100/0/13 lp базового
## холста), плюс 1920×1080, 2732×2048 (iPad) и 2556×1179 (iPhone) из вводного абзаца HUD.
## Доли окна — в lp видимого холста (`get_viewport_rect()`), пиксели — `Window.size`.

const SCENE: String = "res://src/ui/workout/workout_screen.tscn"
const SAFE_BASE_LP: Vector4 = Vector4(100, 0, 100, 13)
## Самый светлый фон кадра (облако), REQ-HUD-14 крит. 4.
const LIGHTEST_BG: Color = Color(0.95, 0.96, 0.98)
const CASES: Array[Dictionary] = [
	{"name": "1280x720", "px": Vector2i(1280, 720), "phone": false},
	{"name": "1024x768", "px": Vector2i(1024, 768), "phone": false},
	{"name": "1280x590", "px": Vector2i(1280, 590), "phone": true},
	{"name": "1920x1080", "px": Vector2i(1920, 1080), "phone": false},
	{"name": "2732x2048", "px": Vector2i(2732, 2048), "phone": false},
	{"name": "2556x1179", "px": Vector2i(2556, 1179), "phone": true},
]
## Узлы-значения панели с цифрами (ключи `HudMetricPanel.value_nodes()`).
const PANEL_NUMERIC: Array[String] = ["elapsed", "distance", "speed", "target", "target_cadence", "countdown",
	"power", "hr", "cadence", "power_zone", "hr_zone", "target_zone"]

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
	_dir = "user://test_t073_acc_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_repo = ProfileRepository.new(_dir + "profiles/")
	_state = AppState.new(_repo)
	_trainer = FakeTrainer.new(11)
	_trainer.connect_delay_sec = 0.0
	_trainer.power_noise_w = 0.0
	_trainer.power_tau_sec = 0.01
	_trainer.cadence_noise_rpm = 0.0
	_trainer.connect_device("t073")
	_profile = Profile.create("Rider")
	_profile.ftp_w = 200
	_profile.max_hr = 180
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
	return Workout.make("t073-plan", typed)


## План 60 с 50 % (каденс 90), 30 с 100 %, 90 с 60 %.
static func _default_plan() -> Workout:
	var warm := WorkoutStep.percent(60, 50.0, WorkoutStep.StepKind.WARMUP)
	warm.cadence_rpm = 90
	return _plan([warm, WorkoutStep.percent(30, 100.0, WorkoutStep.StepKind.INTERVAL_ON),
		WorkoutStep.percent(90, 60.0, WorkoutStep.StepKind.COOLDOWN)])


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
	s.setup(workout if workout != null else _default_plan(), _profile, _trainer, _state)
	assert_true(s.start(), "предусловие: экран запущен")
	s.on_screen_entered()
	return s


## Окно нужного размера, тип устройства и безопасная зона (на телефоне — 100/100/0/13 lp базового холста).
func _apply_case(s: WorkoutScreen, c: Dictionary) -> void:
	var phone: bool = c["phone"]
	_set_device(phone)
	if phone:
		var scale := UiScale.HUD_SCALE_PHONE
		Engine.set_meta(UiScale.DEBUG_SAFE_AREA_META, SAFE_BASE_LP / scale)
	elif Engine.has_meta(UiScale.DEBUG_SAFE_AREA_META):
		Engine.remove_meta(UiScale.DEBUG_SAFE_AREA_META)
	get_tree().root.size = c["px"]
	# Тип устройства в приложении не меняется на ходу: применяем масштаб HUD заново, как при входе на экран.
	if _ui != null:
		_ui.set_mode(UiScale.Mode.HUD)
	s.on_screen_entered()
	await wait_process_frames(3)
	s.refresh()


func _advance(s: WorkoutScreen, sec: float) -> void:
	_now_usec += int(round(sec * 1_000_000.0))
	if s.ticker() != null:
		s.ticker().poll()


func _manual_second(s: WorkoutScreen, power: int, hr: int = -1, cadence: int = 85) -> void:
	if power >= 0:
		_trainer.telemetry.emit(TrainerSample.full(_trainer.get_time_sec(), power, cadence, 30.0))
	if hr >= 0:
		_trainer.heart_rate.emit(hr)
	_advance(s, 1.0)


func _label(s: Node, unique_name: String) -> Label:
	return s.get_node("%" + unique_name) as Label


## Прямоугольник узла в lp холста экрана.
static func _rect(c: Control) -> Rect2:
	return c.get_global_rect()


## Итоговая непрозрачность узла (произведение modulate/self_modulate по цепочке).
static func _opacity(c: CanvasItem) -> float:
	var a := c.self_modulate.a
	var n: Node = c
	while n is CanvasItem:
		a *= (n as CanvasItem).modulate.a
		n = n.get_parent()
	return a


## Узел что-то рисует сам: текст, кнопка, картинка, подложка или свой `draw`.
static func _draws(c: Control) -> bool:
	if c is Label or c is Button or c is TextureRect or c is PanelContainer or c is Panel:
		return true
	return not c.get_signal_connection_list(&"draw").is_empty() or (c.get_script() != null and c.has_method("_draw"))


func _drawing_nodes(root: Node) -> Array[Control]:
	var out: Array[Control] = []
	for n in root.find_children("*", "Control", true, false):
		var c := n as Control
		if c.is_visible_in_tree() and c.size.x > 0.0 and c.size.y > 0.0 and _draws(c):
			out.append(c)
	return out


## Элементы HUD верхнего уровня (то, что не должно пересекаться): панель, кнопка паузы, фишки статусов,
## содержимое левого слота, график, панель инструментов, плашка подсказки.
func _hud_elements(s: WorkoutScreen) -> Dictionary:
	var out := {"panel": s.metric_panel(), "pause": s.get_node("%PauseButton"), "list": s.get_node("%StepPlate"),
		"chart": s.chart_slot(), "toolbar": s.get_node("%Toolbar")}
	for chip_name in ["TrainerChip", "HrChip", "ModeChip", "IntensityChip"]:
		var chip := s.get_node("%" + chip_name) as Control
		if chip.is_visible_in_tree():
			out[chip_name] = chip
	var cue := s.get_node("%CuePlate") as Control
	if cue.is_visible_in_tree():
		out["cue"] = cue
	return out


# --- WCAG 2.x (своя реализация, независимо от `UiTokens.contrast_ratio`) ---------------------------

static func _lin(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


static func _luminance(c: Color) -> float:
	return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)


static func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _over(top: Color, bottom: Color) -> Color:
	return Color(lerpf(bottom.r, top.r, top.a), lerpf(bottom.g, top.g, top.a), lerpf(bottom.b, top.b, top.a), 1.0)


# ===========================================================================
# REQ-HUD-13 крит. 10 — 3D в физическом разрешении окна; HUD масштабируется от 1280×720
# ===========================================================================

func test_req_hud_13_c10_scene_image_equals_window_pixels_on_all_resolutions() -> void:
	var s := _screen()
	for c in CASES:
		await _apply_case(s, c)
		var window := s.get_window()
		var vp := s.ride_viewport_size()
		gut.p("%s: окно %s, холст %s, 3D %s, s=%.2f" % [c["name"], window.size, s.get_viewport_rect().size, vp, window.content_scale_factor])
		assert_eq(window.size, c["px"] as Vector2i, "%s: предусловие — окно нужного размера" % c["name"])
		assert_true(absi(vp.x - window.size.x) <= 1 and absi(vp.y - window.size.y) <= 1,
			"%s: изображение 3D %s = окно %s ±1 px" % [c["name"], vp, window.size])
		# Растр 3D показан 1:1 на весь экран (контейнер уменьшен scale до lp экрана).
		var container := s.get_node("%ViewportContainer") as SubViewportContainer
		var shown := container.get_global_rect().size
		var px_per_lp := Vector2(window.size) / s.get_viewport_rect().size
		assert_true((shown * px_per_lp).distance_to(Vector2(window.size)) <= 1.5,
			"%s: 3D на весь кадр %s px" % [c["name"], shown * px_per_lp])
		# HUD пропорционален базовому холсту: панель 640·s lp базы → в пикселях × (пикселей на lp базы).
		var base_px_per_lp := minf(window.size.x / 1280.0, window.size.y / 720.0)
		var s_hud := UiScale.HUD_SCALE_PHONE if c["phone"] else 1.0
		var panel_px := _rect(s.metric_panel()).size.x * px_per_lp.x
		assert_almost_eq(panel_px, 640.0 * s_hud * base_px_per_lp, 1.5, "%s: ширина панели в пикселях" % c["name"])


func test_req_hud_13_c10_viewport_follows_window_resize() -> void:
	var s := _screen()
	await _apply_case(s, CASES[0])
	assert_eq(s.ride_viewport_size(), Vector2i(1280, 720))
	get_tree().root.size = Vector2i(2732, 2048)
	await wait_process_frames(3)
	var vp := s.ride_viewport_size()
	assert_true(absi(vp.x - 2732) <= 1 and absi(vp.y - 2048) <= 1, "после смены размера окна 3D %s = 2732×2048" % vp)
	get_tree().root.size = Vector2i(1024, 768)
	await wait_process_frames(3)
	vp = s.ride_viewport_size()
	assert_true(absi(vp.x - 1024) <= 1 and absi(vp.y - 768) <= 1, "и обратно: %s = 1024×768" % vp)


# ===========================================================================
# REQ-HUD-13 крит. 1, 5, 6 — раскладка в долях окна на живом экране
# ===========================================================================

func test_req_hud_13_c1_panel_in_top_30_percent_and_centered_on_resolutions() -> void:
	var s := _screen()
	_advance(s, 2.0)
	for c in CASES:
		await _apply_case(s, c)
		var canvas := s.get_viewport_rect().size
		var r := _rect(s.metric_panel())
		gut.p("%s: холст %s, панель %s (низ %.1f %% H)" % [c["name"], canvas, r, 100.0 * r.end.y / canvas.y])
		assert_true(r.position.y >= 0.0 and r.end.y <= 0.30 * canvas.y + 0.01, "%s: панель в верхних 30 %% (низ %.1f)" % [c["name"], r.end.y])
		assert_true(absf(r.get_center().x - canvas.x * 0.5) <= 0.05 * canvas.x, "%s: центр панели ±5 %% ширины" % c["name"])
		# Всё содержимое панели внутри её прямоугольника.
		for key: String in s.metric_panel().value_nodes():
			var n := s.metric_panel().value_nodes()[key] as Control
			if n.is_visible_in_tree():
				assert_true(r.grow(0.5).encloses(_rect(n)), "%s: %s %s внутри панели %s" % [c["name"], key, _rect(n), r])


func test_req_hud_13_c5_center_zone_free_of_opaque_hud_on_resolutions() -> void:
	var s := _screen()
	_trainer.set_heart_rate(140)
	_advance(s, 3.0)
	for c in CASES:
		await _apply_case(s, c)
		var canvas := s.get_viewport_rect().size
		var center := Rect2(canvas * Vector2(0.30, 0.35), canvas * Vector2(0.40, 0.40))
		var checked := 0
		for node in _drawing_nodes(s.get_node("%HudRoot")):
			if _opacity(node) < 0.5:
				continue
			checked += 1
			assert_false(_rect(node).intersects(center), "%s: %s %s заходит в центр %s" % [c["name"], node.get_path(), _rect(node), center])
		assert_gt(checked, 20, "%s: проверено элементов HUD: %d" % [c["name"], checked])


func test_req_hud_13_c6_elements_do_not_overlap_gap_and_safe_area_on_resolutions() -> void:
	var s := _screen()
	_trainer.set_heart_rate(140)
	_advance(s, 3.0)
	s.adjust_intensity(0.05) # фишка «105 %» — все четыре фишки статуса видны
	for c in CASES:
		await _apply_case(s, c)
		var canvas := s.get_viewport_rect().size
		var elements := _hud_elements(s)
		var names: Array = elements.keys()
		var rects := {}
		for n: String in names:
			rects[n] = _rect(elements[n] as Control)
		gut.p("%s: %s" % [c["name"], rects])
		for i in names.size():
			for j in range(i + 1, names.size()):
				var a: Rect2 = rects[names[i]]
				var b: Rect2 = rects[names[j]]
				assert_false(a.grow(-0.5).intersects(b.grow(-0.5)), "%s: %s %s и %s %s пересекаются" % [c["name"], names[i], a, names[j], b])
		var s_hud := UiScale.HUD_SCALE_PHONE if c["phone"] else 1.0
		# Зазор между левым слотом (список) и панелью цифр ≥ 16·s (в lp базового холста).
		var list_end := _rect(s.list_slot()).end.x
		var gap_base := (_rect(s.metric_panel()).position.x - list_end) * s.get_window().content_scale_factor
		assert_true(gap_base >= 16.0 * s_hud - 0.01, "%s: зазор список — панель %.1f ≥ 16·s" % [c["name"], gap_base])
		# Безопасная зона (на телефоне — имитация 100/100/0/13 lp базы).
		var safe := Rect2(Vector2.ZERO, canvas)
		if c["phone"]:
			var m := SAFE_BASE_LP / s.get_window().content_scale_factor
			safe = Rect2(m.x, m.y, canvas.x - m.x - m.z, canvas.y - m.y - m.w)
		for n: String in names:
			assert_true(safe.grow(0.5).encloses(rects[n]), "%s: %s %s в безопасной зоне %s" % [c["name"], n, rects[n], safe])


# ===========================================================================
# REQ-HUD-01 крит. 1–4 и REQ-HUD-13 крит. 1 — состав панели цифр на живом экране
# ===========================================================================

func test_req_hud_01_c4_target_and_countdown_in_one_card_inside_panel_without_hero() -> void:
	var s := _screen()
	var panel := s.metric_panel()
	var card := panel.target_card()
	assert_not_null(card, "карточка цели есть")
	if card == null:
		return
	assert_true(card.is_ancestor_of(_label(s, "TargetLabel")), "цель — потомок карточки")
	assert_true(card.is_ancestor_of(_label(s, "CountdownLabel")), "отсчёт интервала — потомок той же карточки")
	assert_false(card.is_ancestor_of(_label(s, "PowerLabel")), "факт мощности в карточку не входит")
	assert_true(panel.is_ancestor_of(card), "карточка лежит внутри панели цифр")
	# Геометрически: цель и отсчёт внутри прямоугольника карточки, факт — вне его.
	var cr := _rect(card)
	assert_true(cr.grow(0.5).encloses(_rect(_label(s, "TargetLabel"))), "цель в прямоугольнике карточки")
	assert_true(cr.grow(0.5).encloses(_rect(_label(s, "CountdownLabel"))), "отсчёт в прямоугольнике карточки")
	assert_false(cr.intersects(_rect(_label(s, "PowerLabel"))), "факт вне карточки")


func test_req_hud_01_c1_c2_target_text_unit_ru_en_and_dash_on_free_ride() -> void:
	var s := _screen(_plan([WorkoutStep.percent(30, 150.0), WorkoutStep.free_ride(30)]))
	assert_eq(s.target_text(), "300 W", "150 %% от FTP 200, единица из перевода")
	TranslationServer.set_locale("ru")
	s.refresh()
	assert_eq(s.target_text(), "300 Вт")
	_advance(s, 30.0)
	assert_eq(s.target_text(), "—", "шаг без цели — «—»")
	assert_eq(_label(s, "TargetLabel").text, "—", "на экране «—»")
	assert_eq(s.metric_panel().deviation_text(), "", "без цели отклонение скрыто (HUD-02 крит. 3)")


func test_req_hud_13_c1_panel_composition_on_live_screen_ru() -> void:
	TranslationServer.set_locale("ru")
	var s := _screen()
	_trainer.inject_silence(1_000_000.0)
	for i in 3:
		_manual_second(s, 181, 150, 88)
	var p := s.metric_panel()
	var v := p.value_nodes()
	# Ряд «где я»: время, дистанция, скорость — слева направо, на одной линии.
	assert_eq(p.elapsed_text(), "00:03")
	assert_true(RegEx.create_from_string("^[0-9]+\\.[0-9]$").search(p.distance_text()) != null, "дистанция км с 1 знаком: %s" % p.distance_text())
	assert_true(RegEx.create_from_string("^[0-9]+\\.[0-9]$").search(p.speed_text()) != null, "скорость с 1 знаком: %s" % p.speed_text())
	var e := _rect(v["elapsed"])
	var d := _rect(v["distance"])
	var sp := _rect(v["speed"])
	assert_true(e.end.x <= d.position.x and d.end.x <= sp.position.x, "время → дистанция → скорость слева направо")
	assert_almost_eq(e.get_center().y, d.get_center().y, 1.0, "одна строка")
	assert_almost_eq(d.get_center().y, sp.get_center().y, 1.0, "одна строка")
	assert_eq((v["distance_unit"] as Label).text, "км")
	assert_eq((v["speed_unit"] as Label).text, "км/ч")
	# Полоса прогресса шага цветом зоны шага (50 % FTP → Z1) ниже ряда «где я», выше карточки.
	assert_eq(p.step_bar_color(), ZonePalette.color("z1"), "полоса шага — цвет зоны текущего шага")
	assert_almost_eq(p.step_fraction(), 3.0 / 60.0, 0.02, "пройденная доля шага")
	var bar := p.get_node("%StepBar") as Control
	assert_true(_rect(bar).position.y >= e.end.y - 1.0 and _rect(bar).end.y <= _rect(p.target_card()).position.y + 1.0, "полоса шага между рядом A и карточкой")
	# Карточка цели: «ЦЕЛЬ», зона цели, цель, «ещё» + отсчёт, целевой каденс плана.
	var title := p.get_node("%TargetTitle") as Label
	assert_eq(title.text.to_upper() if title.uppercase else title.text, "ЦЕЛЬ", "надпись «ЦЕЛЬ»")
	assert_eq(p.target_zone_text(), "Z1", "фишка зоны цели")
	assert_eq(p.target_zone_color(), ZonePalette.color("z1"))
	assert_eq(s.target_text(), "100 Вт")
	assert_eq(s.countdown_text(), "00:57")
	assert_string_contains((v["target_cadence"] as Label).text, "90", "целевой каденс плана")
	# Герой: факт, фишка зоны факта и отклонение; пульс и каденс справа.
	assert_eq(s.power_text(), "181 Вт")
	assert_eq(p.power_zone_text(), "Z4")
	assert_eq(p.deviation_text(), "▲", "181 при цели 100 — выше")
	assert_eq(p.deviation_delta_text(), "+81")
	assert_eq(s.hr_text(), "150")
	assert_eq(p.hr_zone_text(), "Z4")
	assert_eq(s.cadence_text(), "88")
	var card := _rect(p.target_card())
	var hero := _rect(v["hero"])
	var vitals := _rect(v["vitals"])
	assert_true(card.end.x <= hero.position.x and hero.end.x <= vitals.position.x, "карточка цели → герой → пульс и каденс")


func test_req_hud_13_c1_target_cadence_absent_when_plan_has_none() -> void:
	var s := _screen(_plan([WorkoutStep.percent(60, 50.0)]))
	var cad := s.metric_panel().value_nodes()["target_cadence"] as Label
	assert_true(cad.text.is_empty() or not cad.is_visible_in_tree(), "без каденса в плане — ничего: «%s»" % cad.text)


# ===========================================================================
# REQ-HUD-09 (регрессия) — сглаживание 3 с на экране
# ===========================================================================

func test_req_hud_09_smoothing_on_screen() -> void:
	var s := _screen(_plan([WorkoutStep.watts(120, 200.0)]))
	_trainer.inject_silence(1_000_000.0)
	_manual_second(s, 100)
	assert_eq(s.power_text(), "100 W", "один сэмпл — среднее доступных")
	_manual_second(s, 200)
	assert_eq(s.power_text(), "150 W")
	_manual_second(s, 300)
	assert_eq(s.power_text(), "200 W", "100, 200, 300 → 200")
	_manual_second(s, 300)
	assert_eq(s.power_text(), "267 W", "затем 300 → 267")
	for i in 3:
		_manual_second(s, -1)
	assert_eq(s.power_text(), "—", "три сэмпла «нет данных» → «—»")


# ===========================================================================
# REQ-HUD-14 крит. 2 — моноширинные цифры на узлах живой панели
# ===========================================================================

func _digit_widths(label: Label, size: int = -1) -> Array[float]:
	var font := label.get_theme_font("font")
	var fs := size if size > 0 else label.get_theme_font_size("font_size")
	var out: Array[float] = []
	for probe in ["0000", "1111", "8888"]:
		out.append(font.get_string_size(probe, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	return out


func test_req_hud_14_c2_panel_value_digits_are_monospaced() -> void:
	var s := _screen()
	_advance(s, 2.0)
	var v := s.metric_panel().value_nodes()
	for key in ["elapsed", "distance", "speed", "target", "target_cadence", "countdown", "power", "hr", "cadence"]:
		var label := v[key] as Label
		var w := _digit_widths(label)
		gut.p("%s (%d): 0000=%.2f 1111=%.2f 8888=%.2f" % [key, label.get_theme_font_size("font_size"), w[0], w[1], w[2]])
		assert_almost_eq(w[0], w[2], 0.5, "%s: «0000» = «8888»" % key)
		assert_almost_eq(w[1], w[2], 0.5, "%s: «1111» = «8888»" % key)
	# Разница отклонения рисуется шрифтом отсчёта кеглем 15 (HudMetricPanel.DELTA_FONT_SIZE).
	var dw := _digit_widths(v["countdown"] as Label, HudMetricPanel.DELTA_FONT_SIZE)
	assert_almost_eq(dw[1], dw[2], 0.5, "разница отклонения: «1111» = «8888»")
	assert_almost_eq(dw[0], dw[2], 0.5, "разница отклонения: «0000» = «8888»")


## REQ-HUD-14 крит. 1: все подписи HUD — из одного файла Inter (тот же, что у темы меню).
func test_req_hud_14_c1_all_hud_labels_use_inter_file() -> void:
	var s := _screen()
	_trainer.set_heart_rate(140)
	_advance(s, 3.0)
	var checked := 0
	for node in (s.get_node("%HudRoot") as Node).find_children("*", "Label", true, false):
		var label := node as Label
		var font := label.get_theme_font("font")
		var base: Font = font
		while base is FontVariation and (base as FontVariation).base_font != null:
			base = (base as FontVariation).base_font
		checked += 1
		assert_true(base != null and base.resource_path.begins_with("res://assets/fonts/inter/Inter-Variable"),
			"%s: шрифт из файла Inter, а не %s" % [label.name, base.resource_path if base != null else "null"])
	assert_gt(checked, 20)


## Все остальные подписи HUD с цифрами (фишки зон «Z4», номер шага, фишка интенсивности, значения
## сопротивления и интенсивности): цифры тоже моноширинные — крит. 2 «для шрифта и каждого размера».
func test_req_hud_14_c2_other_hud_labels_with_digits_are_monospaced() -> void:
	var s := _screen()
	_trainer.set_heart_rate(140)
	_advance(s, 3.0)
	s.adjust_intensity(0.05)
	s.toggle_erg() # строка сопротивления видна
	var failures: Array[String] = []
	var checked := 0
	for node in (s.get_node("%HudRoot") as Node).find_children("*", "Label", true, false):
		var label := node as Label
		if not label.is_visible_in_tree() or RegEx.create_from_string("[0-9]").search(label.text) == null:
			continue
		checked += 1
		var w := _digit_widths(label)
		if absf(w[0] - w[2]) > 0.5 or absf(w[1] - w[2]) > 0.5:
			failures.append("%s «%s» (%s, %d): 0000=%.1f 1111=%.1f 8888=%.1f" % [label.name, label.text,
				label.theme_type_variation, label.get_theme_font_size("font_size"), w[0], w[1], w[2]])
	gut.p("проверено подписей с цифрами: %d" % checked)
	for f in failures:
		gut.p("без tnum: " + f)
	assert_gt(checked, 10)
	assert_eq(failures, [] as Array[String], "подписи HUD с цифрами без tnum")


# ===========================================================================
# REQ-HUD-14 крит. 3 — значения не «прыгают» (живой экран и панель)
# ===========================================================================

## Прямоугольники всех узлов панели, кнопки паузы и фишек статусов.
func _layout_rects(s: WorkoutScreen) -> Dictionary:
	var out := {}
	var p := s.metric_panel()
	for n in p.find_children("*", "Control", true, false):
		var c := n as Control
		if c.is_visible_in_tree():
			out[str(p.get_path_to(c))] = _rect(c)
	out["PauseButton"] = _rect(s.get_node("%PauseButton"))
	for chip in ["TrainerChip", "HrChip", "ModeChip"]:
		out[chip] = _rect(s.get_node("%" + chip))
	return out


func _assert_still(base: Dictionary, now: Dictionary, msg: String) -> void:
	for key: String in base:
		if not now.has(key):
			continue
		var a: Rect2 = base[key]
		var b: Rect2 = now[key]
		assert_true(a.position.distance_to(b.position) <= 1.0 and a.size.distance_to(b.size) <= 1.0,
			"%s: %s сдвинулся %s → %s" % [msg, key, a, b])


## Текст значения целиком помещается в резерв подписи (иначе подпись растёт и толкает соседей).
func _assert_fits(s: WorkoutScreen, msg: String) -> void:
	var v := s.metric_panel().value_nodes()
	for key in ["elapsed", "distance", "speed", "target", "countdown", "power", "hr", "cadence"]:
		var label := v[key] as Label
		var font := label.get_theme_font("font")
		var text_w := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
		assert_true(text_w <= label.size.x + 0.5, "%s: %s «%s» (%.1f) в резерве %.1f" % [msg, key, label.text, text_w, label.size.x])


func test_req_hud_14_c3_live_power_hr_cadence_9_to_9999_do_not_move_neighbours() -> void:
	var s := _screen(_plan([WorkoutStep.watts(600, 200.0)]))
	_trainer.inject_silence(1_000_000.0)
	for i in 3:
		_manual_second(s, 9, 9, 9)
	assert_eq([s.power_text(), s.hr_text(), s.cadence_text()], ["9 W", "9", "9"], "предусловие: однозначные значения")
	var base := _layout_rects(s)
	for value in [99, 100, 999, 9999]:
		var hr: int = mini(value, 999)
		var cad: int = mini(value, 999)
		for i in 3:
			_manual_second(s, value, hr, cad)
		gut.p("мощность %s, пульс %s, каденс %s" % [s.power_text(), s.hr_text(), s.cadence_text()])
		assert_eq(s.power_text(), "%d W" % value)
		_assert_still(base, _layout_rects(s), "мощность %d" % value)
		_assert_fits(s, "мощность %d" % value)


func test_req_hud_14_c3_speed_time_countdown_distance_templates_do_not_move_neighbours() -> void:
	var s := _screen()
	_advance(s, 2.0)
	var p := s.metric_panel()
	var live := s.hud().state()
	var sequences := [
		["speed_text", ["9.9", "99.9"]],
		["elapsed_text", ["9:59", "10:00", "59:59", "1:00:00", "9:59:59"]],
		["countdown_text", ["00:09", "09:59", "59:59"]],
	]
	for seq in sequences:
		var field: String = seq[0]
		var first := live.duplicate()
		first[field] = (seq[1] as Array)[0]
		p.set_state(first)
		var base := _layout_rects(s)
		for value: String in seq[1]:
			var st := live.duplicate()
			st[field] = value
			p.set_state(st)
			_assert_still(base, _layout_rects(s), "%s = %s" % [field, value])
			_assert_fits(s, "%s = %s" % [field, value])
	var dist_base := {}
	for m in [9_000.0, 99_000.0, 100_000.0, 888_800.0]:
		var st := live.duplicate()
		st["distance_m"] = m
		p.set_state(st)
		if dist_base.is_empty():
			dist_base = _layout_rects(s)
		_assert_still(dist_base, _layout_rects(s), "дистанция %.1f км" % (m / 1000.0))
		_assert_fits(s, "дистанция %.1f км" % (m / 1000.0))


# ===========================================================================
# REQ-HUD-14 крит. 4 — подложки и контраст
# ===========================================================================

## Подложка под подписью: ближайший предок-`PanelContainer` с плоским стилем или фишка статуса,
## рисующая подложку `hud.plate` сама (`_draw_status_chip`). Прозрачный — подложки нет.
func _plate_under(s: WorkoutScreen, label: Label) -> Color:
	var status_slot := s.get_node("%StatusSlot")
	var n: Node = label.get_parent()
	while n != null and n != s:
		if n is PanelContainer:
			var box := (n as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
			if box != null and box.bg_color.a > 0.0:
				return box.bg_color
		if n.get_parent() == status_slot:
			return UiTokens.HUD_PLATE
		n = n.get_parent()
	return Color.TRANSPARENT


func test_req_hud_14_c4_every_hud_label_has_plate_078_and_text_contrast() -> void:
	var s := _screen()
	_trainer.set_heart_rate(140)
	_advance(s, 3.0)
	s.adjust_intensity(0.05)
	var ink := Color("#0B0E13")
	var chips: Array = [_label(s, "PowerZoneLabel"), _label(s, "HrZoneLabel"), s.metric_panel().value_nodes()["target_zone"]]
	var checked := 0
	for node in (s.get_node("%HudRoot") as Node).find_children("*", "Label", true, false):
		var label := node as Label
		if not label.is_visible_in_tree() or label.text.is_empty():
			continue
		var plate := _plate_under(s, label)
		checked += 1
		assert_true(plate.a >= 0.78 - 1e-4, "%s «%s»: подложка с альфой %.2f ≥ 0.78" % [label.name, label.text, plate.a])
		if plate.a <= 0.0:
			continue
		assert_eq(Color(plate, 1.0), ink, "%s: подложка цвета hud.plate #0B0E13" % label.name)
		if chips.has(label) and s.metric_panel().chip_fill_color(label).a > 0.0:
			continue # текст на заливке зоны — проверка ниже
		var under := _over(plate, LIGHTEST_BG)
		var fc := label.get_theme_color("font_color") * label.modulate
		var ratio := _contrast(Color(fc, 1.0), under)
		assert_true(ratio >= 4.5, "%s «%s»: контраст %.2f ≥ 4.5 над подложкой на светлом фоне" % [label.name, label.text, ratio])
	assert_gt(checked, 15, "проверено подписей: %d" % checked)
	# hud.text и hud.text2 к подложке на самом светлом фоне.
	var under_plate := _over(Color(ink, 0.78), LIGHTEST_BG)
	assert_true(_contrast(Color("#F5F7FA"), under_plate) >= 4.5, "hud.text")
	assert_true(_contrast(Color("#B9C1CD"), under_plate) >= 4.5, "hud.text2")
	assert_eq(UiTokens.HUD_TEXT, Color("#F5F7FA"))
	assert_eq(UiTokens.HUD_TEXT2, Color("#B9C1CD"))
	# Текст на заливке зоны — hud.ink, контраст к каждой из 7 зон ≥ 4.5.
	assert_eq(_label(s, "PowerZoneLabel").get_theme_color("font_color"), ink, "текст фишки зоны — hud.ink")
	for token: String in ZonePalette.POWER_TOKENS:
		var zone := ZonePalette.color(token)
		var ratio := _contrast(ink, zone)
		assert_true(ratio >= 4.5, "hud.ink на %s (%s): %.2f ≥ 4.5" % [token, ZonePalette.color_name(token), ratio])
