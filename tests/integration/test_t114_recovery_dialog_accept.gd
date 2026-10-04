extends GutTest
## Приёмка T-114 (tester): диалог восстановления незавершённого заезда (REQ-UIX-01 п.8, 9 для
## этого диалога, REQ-LOC-07 п.3) — путь пользователя: незавершённые заезды на диске, запуск
## оболочки, диалог при старте — на разрешениях матрицы UIX (компьютер, планшет, телефон с
## безопасной зоной), ru и en:
## - 480 lp, в окне и в безопасной зоне, текст переносится, подписи кнопок не обрезаны, цели
##   нажатия по UIX-05.1; кнопки в одном ряду у правого края; «Удалить» — `DangerButton`;
## - фокус при открытии не на «Удалить»; настоящий Enter (ввод во вьюпорт) — заезд сохранён
##   досрочно и виден в истории; настоящий Esc — следующий заезд тоже сохранён; удаление —
##   только кнопкой «Удалить».

const MAIN_SCENE: String = "res://src/app/main.tscn"
const MATRIX := preload("res://tests/unit/ui/test_ui_matrix.gd")
const SAFE_AREA_LP: Vector4 = Vector4(100.0, 0.0, 100.0, 13.0)
const CONFIGS: Array[Dictionary] = [
	{"id": "1280x720", "px": Vector2i(1280, 720), "device": UiScale.Device.DESKTOP},
	{"id": "1024x768", "px": Vector2i(1024, 768), "device": UiScale.Device.TABLET},
	{"id": "2732x2048", "px": Vector2i(2732, 2048), "device": UiScale.Device.TABLET},
	{"id": "1280x590_safe_phone", "px": Vector2i(1280, 590), "device": UiScale.Device.PHONE, "safe": true},
	{"id": "2556x1179", "px": Vector2i(2556, 1179), "device": UiScale.Device.PHONE},
]

var _dir: String = ""
var _prev_locale: String = ""
var _runtime: UiScale = null
var _prev_device: UiScale.Device = UiScale.Device.DESKTOP
var _m: Node = null


func before_each() -> void:
	_dir = "user://test_t114_accept_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_prev_locale = TranslationServer.get_locale()
	_runtime = TouchTarget.default_runtime()
	if _runtime != null:
		_prev_device = _runtime.device
	_m = MATRIX.new()
	add_child_autofree(_m)


func after_each() -> void:
	DiagLog.uninstall()
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


static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	return e


## Три незавершённых заезда на диске, затем запуск оболочки в холсте устройства.
func _start(config: Dictionary, locale: String) -> Array:
	var dir := _dir + "%s_%s/" % [config["id"], locale]
	var settings := AppSettings.load_from(dir + "settings.json")
	settings.locale = locale
	settings.save()
	var repo := ProfileRepository.new(dir + "profiles/")
	var profile := repo.create("Даша")
	var rides := FileRideRepository.new(dir + "rides/")
	var ids: Array[String] = []
	var now: int = int(Time.get_unix_time_from_system())
	for k in 3:
		var r: Ride = MATRIX._plan_ride(profile, now - 86400 * (3 - k), 600)
		r.name = "Sweet Spot 3×10 с длинным названием тренировки %d" % k
		r.metadata["in_progress"] = true
		r.summary = RideSummary.new()
		rides.save(r)
		ids.append(r.id)
	var device: UiScale.Device = config["device"]
	if _runtime != null:
		_runtime.device = device
	if bool(config.get("safe", false)):
		Engine.set_meta(UiScale.DEBUG_SAFE_AREA_META, SAFE_AREA_LP)
	elif Engine.has_meta(UiScale.DEBUG_SAFE_AREA_META):
		Engine.remove_meta(UiScale.DEBUG_SAFE_AREA_META)
	var viewport := SubViewport.new()
	viewport.gui_embed_subwindows = true
	viewport.size = Vector2i(MATRIX.canvas_lp(config["px"], UiScale.scale_for(device, UiScale.Mode.MENU)))
	add_child_autofree(viewport)
	TranslationServer.set_locale(locale)
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	main.env_reader = Callable()
	viewport.add_child(main)
	if _runtime != null:
		_runtime.set_mode(UiScale.Mode.MENU)
	return [viewport, main, ids]


func _run(config: Dictionary, locale: String) -> Array[String]:
	var issues: Array[String] = []
	var started := _start(config, locale)
	var viewport: SubViewport = started[0]
	var main: AppMain = started[1]
	var ids: Array[String] = started[2]
	var tag := "%s %s" % [config["id"], locale]
	if main.app_state.current_screen == AppState.Screen.PROFILE_SELECT or main.repo.get_active() == null:
		main.app_state.select_profile(main.repo.list()[0].id)
	await wait_process_frames(4)
	var dialog := main.recovery_dialog()
	if not dialog.visible or dialog.current_ride() == null:
		issues.append("%s: диалог восстановления не показан при запуске" % tag)
		main.queue_free()
		return issues
	var canvas := Vector2(viewport.size)
	var safe: Vector4 = SAFE_AREA_LP if bool(config.get("safe", false)) else Vector4.ZERO
	var bounds := Rect2(Vector2(safe.x, safe.y), canvas - Vector2(safe.x + safe.z, safe.y + safe.w))
	var rect := Rect2(Vector2(dialog.position), Vector2(dialog.size))
	var title_h := float(dialog.get_theme_constant("title_height"))
	var full := Rect2(rect.position - Vector2(0, title_h), rect.size + Vector2(0, title_h))
	if absf(rect.size.x - 480.0) > 1.0:
		issues.append("%s: ширина %.1f ≠ 480" % [tag, rect.size.x])
	if not bounds.grow(0.5).encloses(full):
		issues.append("%s: диалог с заголовком %s вне окна/безопасной зоны %s" % [tag, full, bounds])
	var keep := dialog.get_ok_button()
	var del := dialog.delete_button()
	if del.theme_type_variation != &"DangerButton":
		issues.append("%s: «Удалить» не DangerButton (%s)" % [tag, del.theme_type_variation])
	var threshold: float = MATRIX.min_target_lp(config["device"], canvas)
	var visible_buttons: Array[Button] = []
	for b: Button in [keep, del, dialog.get_cancel_button()]:
		if b.is_visible_in_tree():
			visible_buttons.append(b)
			var r := b.get_global_rect()
			if r.size.x < threshold - 0.5 or r.size.y < threshold - 0.5:
				issues.append("%s: кнопка «%s» %s меньше цели %.1f" % [tag, b.atr(b.text), r.size, threshold])
			var bi: Array[String] = []
			_m._check_button_text(b, b.get_parent() as Control, tag, bi)
			issues.append_array(bi)
	# Один ряд у правого края содержимого.
	var right := -INF
	for b in visible_buttons:
		right = maxf(right, b.get_global_rect().end.x)
		if absf(b.get_global_rect().position.y - keep.get_global_rect().position.y) > 0.5:
			issues.append("%s: кнопки не в одном ряду" % tag)
	var label := dialog.get_label()
	var label_rect := label.get_global_rect()
	if right < label_rect.end.x - 1.0:
		issues.append("%s: ряд кнопок не у правого края (%.1f < %.1f)" % [tag, right, label_rect.end.x])
	if label.get_visible_line_count() < label.get_line_count():
		issues.append("%s: текст обрезан (%d из %d строк)" % [tag, label.get_visible_line_count(), label.get_line_count()])
	var focus := viewport.gui_get_focus_owner()
	if focus == del:
		issues.append("%s: фокус при открытии на «Удалить»" % tag)
	# Enter сразу после открытия — сохранить.
	var first: String = dialog.current_ride().id
	viewport.push_input(_key(KEY_ENTER))
	await wait_process_frames(3)
	var r1 := main.ride_repository.get_ride(first)
	if r1 == null or r1.is_in_progress() or not r1.stopped_early():
		issues.append("%s: Enter не сохранил заезд досрочно" % tag)
	# Esc — следующий заезд тоже сохранён.
	if dialog.current_ride() == null or not dialog.visible:
		issues.append("%s: второй заезд не показан после Enter" % tag)
	else:
		var second: String = dialog.current_ride().id
		viewport.push_input(_key(KEY_ESCAPE))
		await wait_process_frames(3)
		var r2 := main.ride_repository.get_ride(second)
		if r2 == null or r2.is_in_progress():
			issues.append("%s: Esc не сохранил заезд" % tag)
	# Третий — кнопкой «Удалить».
	if dialog.current_ride() == null or not dialog.visible:
		issues.append("%s: третий заезд не показан после Esc" % tag)
	else:
		var third: String = dialog.current_ride().id
		dialog.delete_button().pressed.emit()
		await wait_process_frames(2)
		if main.ride_repository.get_ride(third) != null:
			issues.append("%s: «Удалить» не удалил заезд" % tag)
	var kept := 0
	for id in ids:
		if main.ride_repository.get_ride(id) != null:
			kept += 1
	if kept != 2:
		issues.append("%s: осталось заездов %d, ожидалось 2" % [tag, kept])
	main.queue_free()
	await wait_process_frames(2)
	return issues


func _all(locale: String) -> void:
	var all: Array[String] = []
	for config in CONFIGS:
		all.append_array(await _run(config, locale))
	for i in all:
		gut.p(i)
	assert_eq(all.size(), 0, "%s: нарушений %d (первые: %s)" % [locale, all.size(), ", ".join(all.slice(0, 5))])


func test_recovery_dialog_on_startup_matrix_ru() -> void:
	await _all("ru")


func test_recovery_dialog_on_startup_matrix_en() -> void:
	await _all("en")
