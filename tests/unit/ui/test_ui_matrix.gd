extends GutTest
## Матрица адаптивности UI (T-089): REQ-UIX-05 крит. 1–3 (что проверяется автоматически),
## REQ-UIX-01 крит. 2 — на итоговом наборе экранов.
##
## Каждый экран оболочки (выбор профиля, главный, план, выбор трассы, тренировка, свободная
## езда, история и карточка заезда, настройки, устройства) поднимается в `SubViewport` размера
## холста устройства (lp) на разрешениях вводного абзаца UIX и снимков, на ru и en:
## - 1280×720, 1024×768, 1920×1080 — компьютер (`touch_ui` 40);
## - 2732×2048 — iPad (планшет, `touch_ui` 52);
## - 1280×590 с имитацией безопасной зоны и 2556×1179 — телефон (меню ×1.8, HUD ×1.2).
## Холст — растяжение `canvas_items` + `expand` от 1280×720, делённое на множитель `UiScale`.
##
## Проверки (прямоугольники в lp холста):
## 1. Цель нажатия (узел с `focus_mode` ≠ NONE, кнопки, поля, слайдеры) — не меньше порога
##    UIX-05 крит. 1 по обеим сторонам: компьютер — 40 lp; планшет и телефон — 44 pt
##    (`MIN_TARGET_PT`) в lp холста устройства. Измеряется прямоугольник узла (У-11).
## 2. Интерактивные узлы и подписи не выходят за окно, а при безопасной зоне — за её отступы
##    (содержимое прокрутки — только видимая часть, по прямоугольнику прокрутки).
## 3. Области нажатия соседних интерактивных узлов (не предок и потомок) не пересекаются.
## 4. Нет обрезанного текста: подпись с переносом помещается по строкам, подпись без переноса
##    с обрезкой (`clip_text`, `text_overrun_behavior`) — по ширине; сокращение с «…»
##    допустимо только у пользовательских данных: название в строке списка (`ListRow`: тренировка,
##    заезд, устройство) и заголовок AppBar с пользовательскими данными (`title_translate = false`).
## 5. Диалоги (окна) помещаются в окно и безопасную зону.
##
## Состояния: каждый экран меню; на compact — ещё лист предпросмотра плана и лист детали трассы;
## карточки заездов (план и свободная езда); диалоги «Новый профиль», «Отвязать Intervals.icu»,
## «Удалить заезд»; тренировка (езда, панель инструментов, пауза, итог) и свободная езда (езда,
## панель, пауза, итог) — в холсте HUD.

const MAIN_SCENE: String = "res://src/app/main.tscn"
const PLAN_FIXTURE: String = "res://tests/fixtures/workouts_acceptance/acc_full.zwo"
## Базовый холст (`project.godot`).
const BASE: Vector2 = Vector2(1280, 720)
const MIN_TARGET_PT: float = 44.0
const MIN_TARGET_DESKTOP_LP: float = 40.0
## Короткая сторона экрана в pt: iPhone 2556×1179 @3x — 393 pt; iPad 2732×2048 @2x — 1024 pt.
const PHONE_SHORT_PT: float = 393.0
const TABLET_SHORT_PT: float = 1024.0
## Безопасная зона телефона в lp (как у снимков `ui_screenshot.gd --safe-area`).
const SAFE_AREA_LP: Vector4 = Vector4(100.0, 0.0, 100.0, 13.0)
## Ожидание анимаций UI после перехода, с.
const SETTLE_SEC: float = 0.35
## Допуск сравнения, lp.
const EPS: float = 0.5

const CONFIGS: Array[Dictionary] = [
	{"id": "1280x720", "px": Vector2i(1280, 720), "device": UiScale.Device.DESKTOP},
	{"id": "1024x768", "px": Vector2i(1024, 768), "device": UiScale.Device.DESKTOP},
	{"id": "1920x1080", "px": Vector2i(1920, 1080), "device": UiScale.Device.DESKTOP},
	{"id": "2732x2048", "px": Vector2i(2732, 2048), "device": UiScale.Device.TABLET},
	{"id": "1280x590_safe_phone", "px": Vector2i(1280, 590), "device": UiScale.Device.PHONE, "safe": true},
	{"id": "2556x1179", "px": Vector2i(2556, 1179), "device": UiScale.Device.PHONE},
]

var _dir: String = ""
var _prev_locale: String = ""
var _runtime: UiScale = null
var _prev_device: UiScale.Device = UiScale.Device.DESKTOP
## Сколько целей нажатия и подписей проверено (проверка не должна пройти впустую).
var _checked_targets: int = 0
var _checked_labels: int = 0


func before_each() -> void:
	_dir = "user://test_ui_matrix_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_prev_locale = TranslationServer.get_locale()
	_runtime = TouchTarget.default_runtime()
	if _runtime != null:
		_prev_device = _runtime.device


func after_each() -> void:
	if Engine.has_meta(UiScale.DEBUG_SAFE_AREA_META):
		Engine.remove_meta(UiScale.DEBUG_SAFE_AREA_META)
	if _runtime != null:
		_runtime.device = _prev_device
		_runtime.set_mode(UiScale.Mode.MENU)
	TranslationServer.set_locale(_prev_locale)
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
# Холст и порог
# ---------------------------------------------------------------------------

## Холст в lp: окно `px` при растяжении `canvas_items` + `expand` и множителе `scale`.
static func canvas_lp(px: Vector2i, scale: float) -> Vector2:
	var fit: float = minf(px.x / BASE.x, px.y / BASE.y)
	return (Vector2(px) / (fit * scale)).floor()


## Порог цели нажатия в lp холста `canvas` (UIX-05 крит. 1).
static func min_target_lp(device: UiScale.Device, canvas: Vector2) -> float:
	match device:
		UiScale.Device.PHONE:
			return MIN_TARGET_PT * canvas.y / PHONE_SHORT_PT
		UiScale.Device.TABLET:
			return MIN_TARGET_PT * canvas.y / TABLET_SHORT_PT
		_:
			return MIN_TARGET_DESKTOP_LP


func test_canvas_and_thresholds() -> void:
	assert_eq(canvas_lp(Vector2i(2556, 1179), 1.8), Vector2(867, 400))
	assert_eq(canvas_lp(Vector2i(1024, 768), 1.0), Vector2(1280, 960))
	assert_almost_eq(min_target_lp(UiScale.Device.PHONE, Vector2(867, 400)), 44.8, 0.1, "iPhone: 132 px = 44.8 lp меню")
	assert_almost_eq(min_target_lp(UiScale.Device.PHONE, canvas_lp(Vector2i(2556, 1179), 1.2)), 67.2, 0.1, "iPhone: 132 px = 67.2 lp HUD")
	assert_almost_eq(min_target_lp(UiScale.Device.TABLET, canvas_lp(Vector2i(2732, 2048), 1.0)), 41.2, 0.1)


# ---------------------------------------------------------------------------
# Оболочка в окне холста
# ---------------------------------------------------------------------------

func _start(config: Dictionary, locale: String) -> Array:
	var settings := AppSettings.load_from(_dir + "settings.json")
	settings.locale = locale
	settings.save()
	var repo := ProfileRepository.new(_dir + "profiles/")
	var first := repo.create("Даша")
	first.max_hr = 185
	repo.save(first)
	repo.create("Роман")
	var device: UiScale.Device = config["device"]
	if _runtime != null:
		_runtime.device = device
	if bool(config.get("safe", false)):
		Engine.set_meta(UiScale.DEBUG_SAFE_AREA_META, SAFE_AREA_LP)
	elif Engine.has_meta(UiScale.DEBUG_SAFE_AREA_META):
		Engine.remove_meta(UiScale.DEBUG_SAFE_AREA_META)
	var viewport := SubViewport.new()
	# Диалоги встраиваются в окно холста (как в корневом окне приложения).
	viewport.gui_embed_subwindows = true
	viewport.size = Vector2i(canvas_lp(config["px"], UiScale.scale_for(device, UiScale.Mode.MENU)))
	add_child_autofree(viewport)
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	main.env_reader = Callable()
	viewport.add_child(main)
	if _runtime != null:
		_runtime.set_mode(UiScale.Mode.MENU)
	main.app_state.select_profile(main.repo.list()[0].id)
	return [viewport, main]


func _fit(viewport: SubViewport, config: Dictionary, mode: UiScale.Mode) -> void:
	viewport.size = Vector2i(canvas_lp(config["px"], UiScale.scale_for(config["device"], mode)))


# ---------------------------------------------------------------------------
# Проверка экрана
# ---------------------------------------------------------------------------

## Нарушения на видимом экране `screen` в окне `canvas` (lp).
func _inspect(screen: Control, canvas: Vector2, safe: Vector4, threshold: float, where: String) -> Array[String]:
	var issues: Array[String] = []
	var bounds := Rect2(Vector2(safe.x, safe.y), canvas - Vector2(safe.x + safe.z, safe.y + safe.w))
	var targets: Array[Dictionary] = []
	var blockers: Array[Dictionary] = []
	_walk(screen, Rect2(Vector2.ZERO, canvas), false, screen, bounds, threshold, where, issues, targets, blockers)
	# Под модальным слоем (вуаль листа, паузы, итога) нажатия не доходят: такие цели не
	# пересекаются с целями слоя.
	var reachable: Array[Dictionary] = []
	for target in targets:
		var covered := false
		for blocker in blockers:
			if int(target["order"]) < int(blocker["order"]) and (blocker["rect"] as Rect2).encloses(target["rect"]):
				covered = true
				break
		if not covered:
			reachable.append(target)
	targets = reachable
	for i in targets.size():
		for j in range(i + 1, targets.size()):
			var a: Control = targets[i]["node"]
			var b: Control = targets[j]["node"]
			if a.is_ancestor_of(b) or b.is_ancestor_of(a):
				continue
			var ra: Rect2 = targets[i]["rect"]
			var rb: Rect2 = targets[j]["rect"]
			var cross := ra.intersection(rb)
			if cross.size.x > EPS and cross.size.y > EPS:
				issues.append("%s: пересекаются %s и %s" % [where, _path(screen, a), _path(screen, b)])
	return issues


func _walk(node: Node, clip: Rect2, in_scroll: bool, screen: Control, bounds: Rect2, threshold: float,
		where: String, issues: Array[String], targets: Array[Dictionary], blockers: Array[Dictionary]) -> void:
	if node is Window or node is SubViewport:
		return
	var c := node as Control
	if c != null:
		if not c.is_visible_in_tree():
			return
		var rect := c.get_global_rect()
		var shown := rect.intersection(clip) if in_scroll or c != screen else rect
		if in_scroll and (shown.size.x <= 0.0 or shown.size.y <= 0.0):
			return
		if _is_target(c):
			_checked_targets += 1
			if rect.size.x < threshold - EPS or rect.size.y < threshold - EPS:
				issues.append("%s: цель %s %dx%d < %.1f" % [where, _path(screen, c), roundi(rect.size.x), roundi(rect.size.y), threshold])
			_check_bounds(c, rect, in_scroll, clip, bounds, screen, where, issues)
			targets.append({"node": c, "rect": shown, "order": targets.size() + blockers.size()})
		elif c.mouse_filter == Control.MOUSE_FILTER_STOP and c != screen and _is_modal_layer(c, screen):
			blockers.append({"rect": rect, "order": targets.size() + blockers.size()})
		elif c is Label:
			var label := c as Label
			if not _label_text(label).is_empty():
				_checked_labels += 1
				_check_bounds(c, rect, in_scroll, clip, bounds, screen, where, issues)
				_check_label(label, screen, where, issues)
		if c is Button and not (c as Button).text.is_empty():
			_check_button_text(c as Button, screen, where, issues)
		if c is ScrollContainer:
			clip = clip.intersection(rect)
			in_scroll = true
		elif c.clip_contents and c != screen:
			clip = clip.intersection(rect)
		if c is SpinBox:
			return
	for child in node.get_children():
		_walk(child, clip, in_scroll, screen, bounds, threshold, where, issues, targets, blockers)


## Модальный слой: вуаль (`ColorRect`, ловит мышь) во весь экран — листа, паузы, итога.
static func _is_modal_layer(c: Control, screen: Control) -> bool:
	if not (c is ColorRect):
		return false
	var r := c.get_global_rect()
	var full := screen.get_global_rect()
	return r.size.x >= full.size.x * 0.9 and r.size.y >= full.size.y * 0.9


static func _is_target(c: Control) -> bool:
	if c is ScrollContainer or c is ScrollBar or c is SubViewportContainer:
		return false
	if c is SpinBox or c is BaseButton or c is LineEdit or c is TextEdit or c is Slider:
		return c.mouse_filter != Control.MOUSE_FILTER_IGNORE or c.focus_mode != Control.FOCUS_NONE
	return c.focus_mode != Control.FOCUS_NONE


func _check_bounds(c: Control, rect: Rect2, in_scroll: bool, clip: Rect2, bounds: Rect2, screen: Control,
		where: String, issues: Array[String]) -> void:
	var area := clip.intersection(bounds) if in_scroll else bounds
	var r := rect.intersection(clip) if in_scroll else rect
	if r.position.x < area.position.x - EPS or r.position.y < area.position.y - EPS \
			or r.end.x > area.end.x + EPS or r.end.y > area.end.y + EPS:
		issues.append("%s: %s %s вне окна/безопасной зоны %s" % [where, _path(screen, c), _rect_text(r), _rect_text(area)])


func _check_label(label: Label, screen: Control, where: String, issues: Array[String]) -> void:
	var text := _label_text(label)
	if label.autowrap_mode != TextServer.AUTOWRAP_OFF:
		if label.max_lines_visible < 0 and label.get_visible_line_count() < label.get_line_count():
			issues.append("%s: подпись %s «%s» — строк %d из %d" % [where, _path(screen, label), text.left(40),
				label.get_visible_line_count(), label.get_line_count()])
		return
	if not label.clip_text and label.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING:
		return
	var font := label.get_theme_font("font")
	var size := label.get_theme_font_size("font_size")
	if label.label_settings != null:
		font = label.label_settings.font if label.label_settings.font != null else font
		size = label.label_settings.font_size
	var box := label.get_theme_stylebox("normal")
	var avail: float = label.size.x - (box.get_margin(SIDE_LEFT) + box.get_margin(SIDE_RIGHT) if box != null else 0.0)
	var need: float = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if need > avail + 1.0 and not _is_user_data(label):
		issues.append("%s: подпись %s «%s» обрезана: %d > %d" % [where, _path(screen, label), text.left(40), roundi(need), roundi(avail)])


func _check_button_text(b: Button, screen: Control, where: String, issues: Array[String]) -> void:
	if not b.clip_text and b.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING:
		return
	if b.autowrap_mode != TextServer.AUTOWRAP_OFF:
		return
	var text := b.atr(b.text)
	var font := b.get_theme_font("font")
	var need: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x
	var box := b.get_theme_stylebox("normal")
	var avail: float = b.size.x - (box.get_margin(SIDE_LEFT) + box.get_margin(SIDE_RIGHT) if box != null else 0.0)
	if b.icon != null:
		avail -= b.get_theme_constant("icon_max_width") + b.get_theme_constant("h_separation")
	if need > avail + 1.0:
		issues.append("%s: кнопка %s «%s» обрезана: %d > %d" % [where, _path(screen, b), text.left(40), roundi(need), roundi(avail)])


## Подпись с пользовательскими данными (сокращение «…» допустимо, UIX-05 крит. 3): название в
## строке списка и заголовок AppBar без перевода (название заезда).
static func _is_user_data(label: Label) -> bool:
	var parent := label.get_parent()
	if label.name == &"Title" and parent != null and parent.name == &"Texts":
		var p: Node = parent
		while p != null and not (p is ListRow):
			p = p.get_parent()
		if p != null:
			return true
	var bar: Node = label.get_parent()
	while bar != null and not (bar is AppBar):
		bar = bar.get_parent()
	return bar != null and label.name == &"Title" and not (bar as AppBar).title_translate


## Окно диалога в пределах окна приложения и безопасной зоны.
func _inspect_dialog(dialog: Window, canvas: Vector2, safe: Vector4, where: String) -> Array[String]:
	var issues: Array[String] = []
	if dialog == null or not dialog.visible:
		issues.append("%s: диалог не открыт" % where)
		return issues
	var bounds := Rect2(Vector2(safe.x, safe.y), canvas - Vector2(safe.x + safe.z, safe.y + safe.w))
	var rect := Rect2(Vector2(dialog.position), Vector2(dialog.size))
	if not bounds.grow(EPS).encloses(rect):
		issues.append("%s: диалог %s %s вне окна/безопасной зоны %s" % [where, dialog.name, _rect_text(rect), _rect_text(bounds)])
	return issues


static func _label_text(label: Label) -> String:
	var text := label.atr(label.text)
	return text.to_upper() if label.uppercase else text


static func _path(screen: Control, c: Node) -> String:
	return str(screen.get_path_to(c))


static func _rect_text(r: Rect2) -> String:
	return "(%d,%d %dx%d)" % [roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y)]


# ---------------------------------------------------------------------------
# Проход по экранам
# ---------------------------------------------------------------------------

func _run_config(config: Dictionary, locale: String) -> Array[String]:
	var issues: Array[String] = []
	var started := _start(config, locale)
	var viewport: SubViewport = started[0]
	var main: AppMain = started[1]
	var device: UiScale.Device = config["device"]
	var safe: Vector4 = SAFE_AREA_LP if bool(config.get("safe", false)) else Vector4.ZERO
	var tag := "%s %s" % [config["id"], locale]
	# Данные: план из фикстуры, заезды в истории (план и свободная езда).
	main.app_state.navigate(AppState.Screen.PLAN)
	var imported: ParseResult = main.plan_screen().import_path(ProjectSettings.globalize_path(PLAN_FIXTURE))
	var workout: Workout = imported.workout if imported != null and imported.ok() else null
	_save_rides(main)
	var menu: Array[int] = [AppState.Screen.HOME, AppState.Screen.PLAN, AppState.Screen.ROUTE_SELECT,
		AppState.Screen.HISTORY, AppState.Screen.SETTINGS, AppState.Screen.DEVICES]
	var canvas := Vector2(viewport.size)
	var threshold := min_target_lp(device, canvas)
	main.app_state.switch_profile()
	await _settle()
	issues.append_array(_inspect(main.screen_node(AppState.Screen.PROFILE_SELECT), canvas, safe, threshold, tag + " profile_select"))
	main.app_state.select_profile(main.repo.list()[0].id)
	for screen in menu:
		main.app_state.navigate(screen)
		await _settle()
		issues.append_array(_inspect(main.screen_node(screen), canvas, safe, threshold, "%s %s" % [tag, AppState.screen_name(screen)]))
	# Листы compact: предпросмотр плана и деталь трассы.
	if canvas.x < AppBar.COMPACT_MAX_WIDTH:
		main.app_state.navigate(AppState.Screen.PLAN)
		var plan := main.plan_screen()
		if not plan.cards().is_empty():
			plan.cards()[0].pressed.emit()
			await _settle(4, true)
			if plan.is_preview_sheet_open():
				issues.append_array(_inspect(plan, canvas, safe, threshold, tag + " plan_sheet"))
			else:
				issues.append("%s plan_sheet: лист не открыт" % tag)
			plan.close_preview_sheet()
		main.app_state.navigate(AppState.Screen.ROUTE_SELECT)
		var routes := main.route_select_screen()
		routes.cards()[2].pressed.emit()
		await _settle(4, true)
		if routes.is_sheet_open():
			issues.append_array(_inspect(routes, canvas, safe, threshold, tag + " route_sheet"))
		else:
			issues.append("%s route_sheet: лист не открыт" % tag)
		routes.close_sheet()
	# Диалоги.
	main.app_state.switch_profile()
	await _settle()
	var select := main.screen_node(AppState.Screen.PROFILE_SELECT) as ProfileSelectScreen
	select.open_create_form()
	await _settle()
	issues.append_array(_inspect_dialog(select.get_node("%CreateDialog") as Window, canvas, safe, tag + " profile_create"))
	select.close_create_form()
	main.app_state.select_profile(main.repo.list()[0].id)
	main.app_state.navigate(AppState.Screen.SETTINGS)
	var settings := main.settings_screen()
	settings.request_forget_intervals()
	await _settle()
	issues.append_array(_inspect_dialog(settings.get_node("%ForgetIntervalsDialog") as Window, canvas, safe, tag + " forget_intervals"))
	(settings.get_node("%ForgetIntervalsDialog") as Window).hide()
	# Карточки заездов: план и свободная езда.
	main.app_state.navigate(AppState.Screen.HISTORY)
	var history := main.history_screen()
	for i in mini(history.row_count(), 2):
		history.select_index(i)
		await _settle()
		issues.append_array(_inspect(history, canvas, safe, threshold, "%s ride_detail_%d" % [tag, i]))
		if i == 0:
			history.detail().request_delete()
			await _settle()
			issues.append_array(_inspect_dialog(history.detail().get_node("%DeleteDialog") as Window, canvas, safe, tag + " delete_ride"))
			history.detail().cancel_delete()
		history.back_to_list()
	main.app_state.navigate(AppState.Screen.HOME)
	# Экраны заезда — в холсте HUD.
	_fit(viewport, config, UiScale.Mode.HUD)
	canvas = Vector2(viewport.size)
	threshold = min_target_lp(device, canvas)
	if workout != null and main.start_workout_on_emulator(workout):
		await _settle(12, true)
		var ws := main.workout_screen()
		issues.append_array(_inspect(ws, canvas, safe, threshold, tag + " workout"))
		ws.toolbar().poke()
		await _settle(4, true)
		issues.append_array(_inspect(ws, canvas, safe, threshold, tag + " workout_toolbar"))
		ws.toggle_pause()
		await _settle(4, true)
		issues.append_array(_inspect(ws, canvas, safe, threshold, tag + " workout_paused"))
		ws.toggle_pause()
		ws.confirm_stop()
		await _settle(4, true)
		issues.append_array(_inspect(ws, canvas, safe, threshold, tag + " workout_summary"))
	else:
		issues.append("%s: тренировка на эмуляторе не запущена" % tag)
	if main.start_free_ride_on_emulator("hills", 50):
		await _settle(12, true)
		var fr := main.free_ride_screen()
		issues.append_array(_inspect(fr, canvas, safe, threshold, tag + " free_ride"))
		fr.toolbar().poke()
		await _settle(4, true)
		issues.append_array(_inspect(fr, canvas, safe, threshold, tag + " free_ride_toolbar"))
		fr.toggle_pause()
		await _settle(4, true)
		issues.append_array(_inspect(fr, canvas, safe, threshold, tag + " free_ride_paused"))
		fr.toggle_pause()
		fr.confirm_finish()
		await _settle(4, true)
		# Итог заезда — на экране свободной езды, в холсте HUD (масштаб HUD до выхода с экрана).
		issues.append_array(_inspect(fr, canvas, safe, threshold, tag + " free_ride_summary"))
	else:
		issues.append("%s: свободная езда на эмуляторе не запущена" % tag)
	main.queue_free()
	await _settle(2)
	return issues


## Раскладка и анимации UI (появление карточки паузы, вуали, панели инструментов — до 0.3 с).
func _settle(frames: int = 4, animated: bool = false) -> void:
	await wait_process_frames(frames)
	if animated:
		await wait_seconds(SETTLE_SEC)


func _save_rides(main: AppMain) -> void:
	var profile: Profile = main.repo.get_active()
	var now: int = int(Time.get_unix_time_from_system())
	main.ride_repository.save(_plan_ride(profile, now - 86400, 1800))
	main.ride_repository.save(_free_ride(profile, now - 3600, 1200))


static func _plan_ride(profile: Profile, started: int, n: int) -> Ride:
	var r := Ride.new()
	r.id = Ride.generate_id(started)
	r.profile_id = profile.id
	r.started_at_unix = started
	r.name = "Sweet Spot 3×10 с длинным названием тренировки"
	var steps: Array[WorkoutStep] = [WorkoutStep.percent(n / 2, 60.0), WorkoutStep.percent(n - n / 2, 100.0)]
	r.workout = WorkoutSerializer.to_dict(Workout.make(r.name, steps, "zwo"))
	r.metadata = {"workout_name": r.name, "workout_source": "zwo", "started_at_unix": started, "ftp_w": profile.ftp_w,
		"weight_kg": 70.0, "max_hr": 185, "intensity": 1.0, "stopped_early": false,
		"speed_source": SampleStream.SPEED_SOURCE_TRAINER, "elapsed_sec": n, "paused_total_sec": 0.0,
		"in_progress": false, "recovered": false}
	r.samples.speed_source = SampleStream.SPEED_SOURCE_TRAINER
	for i in n:
		var target: int = 150 if i < n / 2 else 250
		r.samples.append(i, TrainerSample.full(float(i), target, 90, 30.0), 140, target, 0 if i < n / 2 else 1, true)
	r.events = [{"type": WorkoutSession.EVENT_START, "at_sec": 0.0, "value": 0}]
	r.compute_summary()
	return r


static func _free_ride(profile: Profile, started: int, n: int) -> Ride:
	var r := Ride.new()
	r.id = Ride.generate_id(started)
	r.profile_id = profile.id
	r.started_at_unix = started
	r.metadata = Ride.free_ride_metadata("hills", 50.0)
	r.metadata["ftp_w"] = profile.ftp_w
	r.metadata["max_hr"] = 185
	r.metadata["weight_kg"] = 70.0
	r.metadata["in_progress"] = false
	r.metadata["recovered"] = false
	r.samples.speed_source = SampleStream.SPEED_SOURCE_MODEL
	var route := RouteCatalog.get_route("hills").profile
	for i in n:
		var d: float = float(i + 1) * 9.0
		var s: float = fposmod(d, route.length_m())
		r.samples.append(i, TrainerSample.full(float(i), 180 + (i % 60) * 2, 88, 0.0), 130, 0, -1, false, 32.4, {},
			{"distance_m": d, "altitude_m": route.height_at(s), "grade_pct": route.grade_at(s)})
	r.events = [{"type": WorkoutSession.EVENT_START, "at_sec": 0.0, "value": 0}]
	r.compute_summary()
	return r


func _run_matrix(locale: String) -> void:
	_checked_targets = 0
	_checked_labels = 0
	var all: Array[String] = []
	for config in CONFIGS:
		var issues := await _run_config(config, locale)
		all.append_array(issues)
		_remove_tree(ProjectSettings.globalize_path(_dir))
		_dir = "user://test_ui_matrix_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	for line in all:
		gut.p(line)
	gut.p("%s: проверено целей %d, подписей %d" % [locale, _checked_targets, _checked_labels])
	assert_gt(_checked_targets, 400, "цели нажатия найдены на всех экранах")
	assert_gt(_checked_labels, 1500, "подписи найдены на всех экранах")
	assert_eq(all.size(), 0, "нарушений матрицы UIX-05 (%s): %d" % [locale, all.size()])


func test_req_uix_05_c1_c2_c3_matrix_ru() -> void:
	await _run_matrix("ru")


func test_req_uix_05_c1_c2_c3_matrix_en() -> void:
	await _run_matrix("en")
