extends GutTest
## Приёмка T-089 (tester, независимо от тестов исполнителя): REQ-UIX-05 крит. 1–3 и
## REQ-UIX-01 крит. 2 на том, чего нет в матрице `test_ui_matrix.gd`.
##
## 1. Набор разрешений вводного абзаца UIX (`requirements.md`, раздел UIX): 1024×768 —
##    **планшет** (в матрице — компьютер: другой `touch_ui` и порог 40 lp); 2556×1179 —
##    iPhone **с имитацией безопасной зоны** 100/100/0/13 lp (в матрице безопасная зона —
##    только у 1280×590). Проход экранов — тот же, что в матрице (`_run_config`), чтобы
##    расхождение было только в конфигурации.
## 2. UIX-01 крит. 2: цвет текста задаётся темой и вариациями; подкраска подписи в постоянный
##    цвет палитры через `self_modulate` — тоже локальное переопределение цвета (не данные:
##    не зона, не уклон, не статус). Статическая проверка исполнителя её не видит.

const MATRIX := preload("res://tests/unit/ui/test_ui_matrix.gd")
const UI_DIR: String = "res://src/ui/"

## Конфигурации из требований, которых нет в матрице исполнителя.
const MISSING_CONFIGS: Array[Dictionary] = [
	{"id": "1024x768_tablet", "px": Vector2i(1024, 768), "device": UiScale.Device.TABLET},
	{"id": "2556x1179_safe_phone", "px": Vector2i(2556, 1179), "device": UiScale.Device.PHONE, "safe": true},
]

var _m: Node = null


func before_each() -> void:
	_m = MATRIX.new()
	_m.gut = gut
	_m.set_logger(gut.get_logger())
	add_child_autofree(_m)
	_m.before_each()


func after_each() -> void:
	if _m != null:
		_m.after_each()
	_m = null


func _run(config: Dictionary, locale: String) -> void:
	_m._checked_targets = 0
	_m._checked_labels = 0
	var issues: Array[String] = await _m._run_config(config, locale)
	await wait_process_frames(1)  # ожидание помощника завершилось до его освобождения
	for line in issues:
		gut.p(line)
	gut.p("%s %s: проверено целей %d, подписей %d" % [config["id"], locale, _m._checked_targets, _m._checked_labels])
	assert_gt(_m._checked_targets, 60, "предусловие: цели нажатия найдены")
	assert_gt(_m._checked_labels, 200, "предусловие: подписи найдены")
	assert_eq(issues.size(), 0, "нарушений UIX-05 крит. 1–3 на %s %s: %d" % [config["id"], locale, issues.size()])


func test_req_uix_05_c1_c2_c3_tablet_1024x768_ru() -> void:
	await _run(MISSING_CONFIGS[0], "ru")


func test_req_uix_05_c1_c2_c3_tablet_1024x768_en() -> void:
	await _run(MISSING_CONFIGS[0], "en")


func test_req_uix_05_c2_iphone_2556x1179_with_safe_area_ru() -> void:
	await _run(MISSING_CONFIGS[1], "ru")


func test_req_uix_05_c2_iphone_2556x1179_with_safe_area_en() -> void:
	await _run(MISSING_CONFIGS[1], "en")


# --- UIX-01 крит. 2: подкраска подписей постоянным цветом -------------------------------------

static func _files(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		if f.get_extension() == "gd":
			out.append(dir_path.path_join(f))
	for sub in d.get_directories():
		_files(dir_path.path_join(sub), out)


func test_req_uix_01_c2_no_constant_text_tint_in_src_ui() -> void:
	# Подпись (`get_theme_color("font_color")` → `tint_for`) подкрашивается в постоянный цвет
	# палитры `UiTokens.*` — это цвет текста мимо темы. Для таких случаев в теме есть вариации
	# (`LogoAccentLabel`, `SecondaryLabel`, `OverlineAccent`/`OverlineSim`).
	var re := RegEx.create_from_string("self_modulate\\s*=.*tint_for\\(.*font_color.*,\\s*UiTokens\\.[A-Z_0-9]+\\s*\\)")
	var files: Array[String] = []
	_files(UI_DIR, files)
	assert_gt(files.size(), 50, "предусловие: файлы src/ui найдены")
	var found: Array[String] = []
	for path in files:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			if lines[i].strip_edges().begins_with("#"):
				continue
			if re.search(lines[i]) != null:
				found.append("%s:%d: %s" % [path.trim_prefix(UI_DIR), i + 1, lines[i].strip_edges()])
	assert_eq(found, [] as Array[String], "цвет текста подписи — темой/вариацией, а не self_modulate постоянным цветом")


# --- UIX-05 крит. 5: обход фокуса и стиль фокуса; крит. 4: ширина контента ----------------------

const MENU_SCREENS: Array[int] = [AppState.Screen.HOME, AppState.Screen.PLAN, AppState.Screen.ROUTE_SELECT,
	AppState.Screen.HISTORY, AppState.Screen.SETTINGS, AppState.Screen.DEVICES]


## Интерактивные узлы экрана (как в матрице: `focus_mode` ≠ NONE, кнопки, поля, слайдеры), видимые.
func _targets(node: Node, out: Array[Control]) -> void:
	if node is Window or node is SubViewport:
		return
	var c := node as Control
	if c != null:
		if not c.is_visible_in_tree():
			return
		if c is SpinBox:
			# Фокус у SpinBox принимает его поле ввода.
			out.append((c as SpinBox).get_line_edit())
			return
		if _m._is_target(c):
			out.append(c)
	for child in node.get_children():
		_targets(child, out)


## Обход Tab: от первой цели по `find_next_valid_focus` до возврата; достигнутые узлы.
static func _tab_walk(first: Control, limit: int) -> Array[Control]:
	var seen: Array[Control] = []
	var cur: Control = first
	for i in limit:
		if cur == null or seen.has(cur):
			break
		seen.append(cur)
		cur = cur.find_next_valid_focus()
	return seen


func _focus_issues(screen: Control, tag: String) -> Array[String]:
	var issues: Array[String] = []
	var targets: Array[Control] = []
	_targets(screen, targets)
	if targets.is_empty():
		issues.append("%s: интерактивных элементов нет" % tag)
		return issues
	var first: Control = null
	for t in targets:
		if t.focus_mode == Control.FOCUS_ALL:
			first = t
			break
	var reached: Array[Control] = _tab_walk(first, 2000) if first != null else []
	for t in targets:
		var p := str(screen.get_path_to(t))
		if t.focus_mode != Control.FOCUS_ALL:
			issues.append("%s: %s (%s) — focus_mode %d, Tab до него не доходит" % [tag, p, t.get_class(), t.focus_mode])
		elif not reached.has(t):
			issues.append("%s: %s — не достигается обходом Tab" % [tag, p])
		var box := t.get_theme_stylebox("focus")
		if t.focus_mode != Control.FOCUS_NONE and (box == null or box is StyleBoxEmpty):
			issues.append("%s: %s (%s) — нет стиля фокуса темы" % [tag, p, t.get_class()])
	return issues


func _menu_walk(locale: String, check: Callable) -> Array[String]:
	var config: Dictionary = {"id": "1280x720", "px": Vector2i(1280, 720), "device": UiScale.Device.DESKTOP}
	var started: Array = _m._start(config, locale)
	var main: AppMain = started[1]
	main.app_state.navigate(AppState.Screen.PLAN)
	main.plan_screen().import_path(ProjectSettings.globalize_path(MATRIX.PLAN_FIXTURE))
	_m._save_rides(main)
	var issues: Array[String] = []
	main.app_state.switch_profile()
	await _m._settle()
	issues.append_array(check.call(main.screen_node(AppState.Screen.PROFILE_SELECT), "profile_select"))
	main.app_state.select_profile(main.repo.list()[0].id)
	for screen in MENU_SCREENS:
		main.app_state.navigate(screen)
		await _m._settle()
		issues.append_array(check.call(main.screen_node(screen), AppState.screen_name(screen)))
	main.app_state.navigate(AppState.Screen.HISTORY)
	main.history_screen().select_index(0)
	await _m._settle()
	issues.append_array(check.call(main.history_screen(), "ride_detail"))
	main.queue_free()
	await _m._settle(2)
	return issues


func test_req_uix_05_c5_every_target_reachable_by_tab_with_focus_style() -> void:
	var issues: Array[String] = await _menu_walk("ru", _focus_issues)
	await wait_process_frames(1)
	for line in issues:
		gut.p(line)
	assert_eq(issues.size(), 0, "UIX-05 крит. 5: элементы вне обхода фокуса или без стиля фокуса: %d" % issues.size())


## UIX-05 крит. 4: ни один `ScrollContainer` не прокручивается по горизонтали; на широком
## холсте (wide ≥ 1600 lp) содержимое экрана (без AppBar) не шире 1216 lp.
func _width_issues(screen: Control, tag: String) -> Array[String]:
	var issues: Array[String] = []
	for n in screen.find_children("*", "ScrollContainer", true, false):
		var sc := n as ScrollContainer
		if not sc.is_visible_in_tree():
			continue
		var bar := sc.get_h_scroll_bar()
		if bar.visible and bar.max_value - bar.page > 1.0:
			issues.append("%s: %s прокручивается по горизонтали (%d > %d)" % [tag, screen.get_path_to(sc), roundi(bar.max_value), roundi(bar.page)])
	var left: float = INF
	var right: float = -INF
	for n in screen.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree() or c is AppBar or _inside_app_bar(c, screen):
			continue
		if not (c is Label or c is BaseButton or c is LineEdit or c is Range):
			continue
		var r := c.get_global_rect()
		left = minf(left, r.position.x)
		right = maxf(right, r.end.x)
	gut.p("%s: контент %d…%d (%d lp)" % [tag, roundi(left), roundi(right), roundi(right - left)])
	if right - left > 1216.0 + 0.5:
		issues.append("%s: контент шириной %d lp > 1216" % [tag, roundi(right - left)])
	return issues


static func _inside_app_bar(c: Node, screen: Node) -> bool:
	var p := c.get_parent()
	while p != null and p != screen:
		if p is AppBar:
			return true
		p = p.get_parent()
	return false


func test_req_uix_05_c4_content_max_1216_and_no_horizontal_scroll_on_wide() -> void:
	# 2560×1080 (21:9): холст 1706×720 lp — wide (≥ 1600 lp).
	var wide: Dictionary = {"id": "2560x1080", "px": Vector2i(2560, 1080), "device": UiScale.Device.DESKTOP}
	var started: Array = _m._start(wide, "en")
	var main: AppMain = started[1]
	assert_gte((started[0] as SubViewport).size.x, 1600, "предусловие: холст wide")
	main.app_state.navigate(AppState.Screen.PLAN)
	main.plan_screen().import_path(ProjectSettings.globalize_path(MATRIX.PLAN_FIXTURE))
	_m._save_rides(main)
	var issues: Array[String] = []
	for screen in MENU_SCREENS:
		main.app_state.navigate(screen)
		await _m._settle()
		issues.append_array(_width_issues(main.screen_node(screen), AppState.screen_name(screen)))
	main.queue_free()
	await _m._settle(2)
	await wait_process_frames(1)
	for line in issues:
		gut.p(line)
	assert_eq(issues.size(), 0, "UIX-05 крит. 4: %d нарушений" % issues.size())
