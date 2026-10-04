extends GutTest
## Повторная приёмка T-103 (tester, независимо от `test_ride_summary_card.gd` исполнителя):
## REQ-HUD-14 крит. 7 — итог заезда карточкой в приложении целиком (`main.tscn`), на всех
## разрешениях вводного абзаца HUD (и 1280×590 телефона из набора снимков), ru и en, для обоих
## режимов:
## - вуаль `scrim` на весь кадр, фон карточки `surface1` с альфой ≥ 0.96, каждая подпись и
##   кнопка итога — внутри прямоугольника карточки, карточка — в безопасной зоне;
## - заголовок на языке интерфейса: «Тренировка завершена» / «Workout finished» (план),
##   «Заезд завершён» / «Ride complete» (свободная езда);
## - значения плиток равны сводке LOC-04 **сохранённого** заезда (`RideRepository.get_ride`),
##   а не пересчёту экрана (у исполнителя — сравнение с `RideSummary.compute` по сессии);
## - ни одной видимой подписи экрана с числом сэмплов;
## - паузы: строка только при `paused_total_sec` > 0; пауза 75 с — «01:15» (оба режима);
## - кнопки: область нажатия по UIX-05 крит. 1 на компьютере и планшете, `touch_hud·s` на
##   телефоне (≥ 86 lp базового холста, на iPhone 2556×1179 — ≥ 132 px), без перекрытий;
##   текст подписей и кнопок не обрезан (UIX-05 крит. 3, измерение — как в матрице UI).

const MAIN_SCENE: String = "res://src/app/main.tscn"
const MATRIX := preload("res://tests/unit/ui/test_ui_matrix.gd")
const SAFE_AREA_LP: Vector4 = Vector4(100.0, 0.0, 100.0, 13.0)
## Разрешения вводного абзаца HUD (+ 1280×590 из набора снимков).
const CONFIGS: Array[Dictionary] = [
	{"id": "1280x720", "px": Vector2i(1280, 720), "device": UiScale.Device.DESKTOP},
	{"id": "1920x1080", "px": Vector2i(1920, 1080), "device": UiScale.Device.DESKTOP},
	{"id": "2732x2048", "px": Vector2i(2732, 2048), "device": UiScale.Device.TABLET},
	{"id": "2556x1179_safe", "px": Vector2i(2556, 1179), "device": UiScale.Device.PHONE, "safe": true},
	{"id": "1280x590_safe", "px": Vector2i(1280, 590), "device": UiScale.Device.PHONE, "safe": true},
]
const TITLES: Dictionary = {
	"plan_ru": "Тренировка завершена", "plan_en": "Workout finished",
	"free_ru": "Заезд завершён", "free_en": "Ride complete",
}
## Порог `touch_hud·s` на телефоне, lp базового холста 1280×720 (REQ-HUD-14 крит. 7).
const PHONE_TOUCH_BASE_LP: float = 86.0
const IPHONE_TOUCH_PX: float = 132.0

var _dir: String = ""
var _prev_locale: String = ""
var _runtime: UiScale = null
var _prev_device: UiScale.Device = UiScale.Device.DESKTOP
var _now_usec: int = 0
var _m: Node = null


func before_each() -> void:
	_dir = "user://test_ride_summary_reaccept_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_prev_locale = TranslationServer.get_locale()
	_runtime = TouchTarget.default_runtime()
	if _runtime != null:
		_prev_device = _runtime.device
	_now_usec = 5_000_000
	_m = MATRIX.new()
	add_child_autofree(_m)


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


func _clock() -> int:
	return _now_usec


func _keep(_on: bool) -> void:
	pass


func _start(config: Dictionary, locale: String, sub: String) -> Array:
	var dir := _dir + sub + "/"
	var settings := AppSettings.load_from(dir + "settings.json")
	settings.locale = locale
	settings.save()
	var repo := ProfileRepository.new(dir + "profiles/")
	var p := repo.create("Даша")
	p.ftp_w = 220
	p.max_hr = 185
	repo.save(p)
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
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	main.env_reader = Callable()
	viewport.add_child(main)
	if _runtime != null:
		_runtime.set_mode(UiScale.Mode.MENU)
	main.app_state.select_profile(main.repo.list()[0].id)
	TranslationServer.set_locale(locale)
	# Экраны заезда — в холсте HUD (как в матрице UI).
	viewport.size = Vector2i(MATRIX.canvas_lp(config["px"], UiScale.scale_for(device, UiScale.Mode.HUD)))
	return [viewport, main]


## Порог области нажатия кнопки итога в lp холста HUD.
static func _touch_threshold(config: Dictionary, canvas: Vector2) -> float:
	var device: UiScale.Device = config["device"]
	if device == UiScale.Device.PHONE:
		var s := UiScale.scale_for(device, UiScale.Mode.HUD)
		var lp := PHONE_TOUCH_BASE_LP / s
		var px_per_lp := float(Vector2i(config["px"]).x) / canvas.x
		return maxf(lp, IPHONE_TOUCH_PX / px_per_lp if config["id"].begins_with("2556") else 0.0)
	return MATRIX.min_target_lp(device, canvas)


## Плановая тренировка на эмуляторе до конца плана; `pause_sec` > 0 — пауза на 10-й секунде.
func _ride_plan(main: AppMain, pause_sec: int) -> WorkoutScreen:
	var ws := main.workout_screen()
	ws.clock_usec = _clock
	ws.keep_awake_setter = _keep
	assert_true(main.start_workout_on_emulator(DevScreen.test_workout()), "тренировка запущена")
	for i in 10:
		_now_usec += 1_000_000
		ws.ticker().poll()
	if pause_sec > 0:
		ws.toggle_pause()
		for i in pause_sec:
			_now_usec += 1_000_000
			ws.ticker().poll()
		ws.toggle_pause()
	for i in 400:
		if ws.is_summary_visible():
			break
		_now_usec += 1_000_000
		ws.ticker().poll()
	await wait_process_frames(6)
	return ws


## Свободная езда на эмуляторе 120 с (и пауза), завершение через подтверждение.
func _ride_free(main: AppMain, pause_sec: int) -> FreeRideScreen:
	var fr := main.free_ride_screen()
	fr.clock_usec = _clock
	fr.keep_awake_setter = _keep
	assert_true(main.start_free_ride_on_emulator("hills", 50), "свободная езда запущена")
	await wait_process_frames(2)
	for i in 60:
		_now_usec += 1_000_000
		fr.ticker().poll()
	if pause_sec > 0:
		fr.toggle_pause()
		for i in pause_sec:
			_now_usec += 1_000_000
			fr.ticker().poll()
		fr.toggle_pause()
	for i in 60:
		_now_usec += 1_000_000
		fr.ticker().poll()
	assert_true(fr.request_finish(), "подтверждение завершения открыто")
	fr.confirm_finish()
	await wait_process_frames(6)
	return fr


func _visible_labels(root: Node, out: Array[Label]) -> void:
	for n in root.find_children("*", "Label", true, false):
		if (n as Label).is_visible_in_tree():
			out.append(n)


static func _num(text: String) -> String:
	return text.split(" ")[0]


## Ожидаемое число плитки: «—», если данных нет (LOC-04.6).
static func _int_text(value: int) -> String:
	return str(value) if value >= 0 else HudModel.NO_DATA_TEXT


## Общие проверки итога на экране `screen` с карточкой `card` и сохранённым заездом `ride`.
func _check(card: RideSummaryCard, screen: Control, ride: Ride, viewport: SubViewport, config: Dictionary,
		locale: String, mode: String, pause_sec: int) -> void:
	var where := "%s %s %s pause=%d" % [config["id"], locale, mode, pause_sec]
	assert_true(card.is_visible_in_tree(), "%s: итог показан" % where)
	if not card.is_visible_in_tree():
		return
	var canvas := Vector2(viewport.size)
	# Вуаль на весь кадр.
	assert_true(card.scrim().is_visible_in_tree(), "%s: вуаль видна" % where)
	assert_true(card.scrim().get_global_rect().grow(0.5).encloses(Rect2(Vector2.ZERO, canvas)), "%s: вуаль на весь кадр" % where)
	assert_eq(card.scrim().color, UiTokens.SCRIM, "%s: цвет вуали scrim" % where)
	var box := card.card().get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(box, "%s: фон карточки" % where)
	if box != null:
		assert_gte(box.bg_color.a, 0.96, "%s: альфа фона ≥ 0.96" % where)
		assert_eq(Color(box.bg_color, 1.0), Color(UiTokens.SURFACE1, 1.0), "%s: фон surface1" % where)
	var rect := card.card().get_global_rect()
	var safe: Vector4 = SAFE_AREA_LP if bool(config.get("safe", false)) else Vector4.ZERO
	var bounds := Rect2(Vector2(safe.x, safe.y), canvas - Vector2(safe.x + safe.z, safe.y + safe.w))
	assert_true(bounds.grow(0.5).encloses(rect), "%s: карточка %s в окне и безопасной зоне %s" % [where, rect, bounds])
	# Подписи и кнопки — внутри карточки; текст не обрезан.
	var issues: Array[String] = []
	var labels: Array[Label] = []
	_visible_labels(card, labels)
	assert_gte(labels.size(), 14, "%s: предусловие — заголовок, подзаголовок, 6 значений и 6 подписей" % where)
	for l in labels:
		assert_true(rect.grow(0.5).encloses(l.get_global_rect()), "%s: подпись «%s» внутри карточки" % [where, l.text])
		_m._check_label(l, card, where, issues)
	var buttons: Array[Button] = [card.history_button(), card.home_button()]
	var threshold := _touch_threshold(config, canvas)
	for b in buttons:
		assert_true(b.is_visible_in_tree(), "%s: кнопка «%s» видна" % [where, b.text])
		assert_true(rect.grow(0.5).encloses(b.get_global_rect()), "%s: кнопка «%s» внутри карточки" % [where, b.text])
		assert_gte(b.size.x + 0.01, threshold, "%s: ширина «%s» %.1f ≥ %.1f" % [where, b.text, b.size.x, threshold])
		assert_gte(b.size.y + 0.01, threshold, "%s: высота «%s» %.1f ≥ %.1f" % [where, b.text, b.size.y, threshold])
		_m._check_button_text(b, card, where, issues)
	assert_false(buttons[0].get_global_rect().intersects(buttons[1].get_global_rect()), "%s: кнопки не перекрываются" % where)
	assert_eq(issues, [] as Array[String], "%s: текст не обрезан" % where)
	# Заголовок на языке интерфейса.
	var title := card.card().find_child("SummaryTitle", true, false) as Label
	assert_eq(title.atr(title.text), TITLES["%s_%s" % [mode, locale]], "%s: заголовок" % where)
	# Нет числа сэмплов ни в одной видимой подписи экрана.
	var all: Array[Label] = []
	_visible_labels(screen, all)
	for l in all:
		var t := l.atr(l.text).to_lower()
		assert_false(t.contains("сэмпл") or t.contains("sample"), "%s: служебное поле «%s»" % [where, l.text])
	# Значения = сводка LOC-04 сохранённого заезда.
	assert_not_null(ride, "%s: заезд сохранён" % where)
	if ride == null:
		return
	var sm := ride.summary
	var shown: Array[String] = []
	for key in card.stat_keys():
		shown.append("%s=%s" % [key, card.value_text(key)])
	gut.p("%s: %s; паузы «%s»" % [where, ", ".join(shown), card.paused_text()])
	assert_gt(sm.avg_power_w, 0, "%s: предусловие — в заезде есть мощность" % where)
	assert_eq(card.value_text("time"), HudModel.format_elapsed(sm.duration_sec), "%s: время = LOC-04" % where)
	assert_eq(_num(card.value_text("distance")), "%.1f" % (sm.distance_m / 1000.0), "%s: дистанция = LOC-04" % where)
	assert_eq(_num(card.value_text("avg_power")), _int_text(sm.avg_power_w), "%s: ср. мощность = LOC-04" % where)
	assert_eq(_num(card.value_text("np")), _int_text(sm.normalized_power_w), "%s: NP = LOC-04" % where)
	assert_eq(_num(card.value_text("avg_hr")), _int_text(sm.avg_hr), "%s: ср. пульс = LOC-04" % where)
	if mode == "plan":
		assert_eq(_num(card.value_text("work")), _int_text(roundi(sm.work_kj) if sm.has_power() else -1), "%s: работа = LOC-04" % where)
	else:
		assert_eq(_num(card.value_text("ascent")), str(roundi(sm.ascent_m)), "%s: набор = LOC-04" % where)
	# Паузы.
	if pause_sec > 0:
		assert_string_contains(card.paused_text(), HudModel.format_elapsed(pause_sec), "%s: строка пауз" % where)
	else:
		assert_eq(card.paused_text(), "", "%s: пауз не было — строки нет" % where)


func _run_plan(config: Dictionary, locale: String, pause_sec: int) -> void:
	var started := _start(config, locale, "%s_%s_plan_%d" % [config["id"], locale, pause_sec])
	var viewport: SubViewport = started[0]
	var main: AppMain = started[1]
	var ws := await _ride_plan(main, pause_sec)
	var ride := main.ride_repository.get_ride(ws.saved_ride_id()) if not ws.saved_ride_id().is_empty() else null
	_check(ws.summary_card(), ws, ride, viewport, config, locale, "plan", pause_sec)
	main.queue_free()
	await wait_process_frames(2)


func _run_free(config: Dictionary, locale: String, pause_sec: int) -> void:
	var started := _start(config, locale, "%s_%s_free_%d" % [config["id"], locale, pause_sec])
	var viewport: SubViewport = started[0]
	var main: AppMain = started[1]
	var fr := await _ride_free(main, pause_sec)
	var ride := main.ride_repository.get_ride(fr.saved_ride_id()) if not fr.saved_ride_id().is_empty() else null
	_check(fr.summary_card(), fr, ride, viewport, config, locale, "free", pause_sec)
	main.queue_free()
	await wait_process_frames(2)


func test_req_hud_14_c7_plan_summary_all_hud_resolutions_ru() -> void:
	for config in CONFIGS:
		await _run_plan(config, "ru", 0)


func test_req_hud_14_c7_plan_summary_all_hud_resolutions_en() -> void:
	for config in CONFIGS:
		await _run_plan(config, "en", 0)


func test_req_hud_14_c7_free_ride_summary_all_hud_resolutions_ru() -> void:
	for config in CONFIGS:
		await _run_free(config, "ru", 0)


func test_req_hud_14_c7_free_ride_summary_all_hud_resolutions_en() -> void:
	for config in CONFIGS:
		await _run_free(config, "en", 0)


func test_req_hud_14_c7_plan_summary_with_pause_75s() -> void:
	await _run_plan(CONFIGS[0], "ru", 75)
	await _run_plan(CONFIGS[4], "en", 75)


func test_req_hud_14_c7_free_ride_summary_with_pause_75s() -> void:
	await _run_free(CONFIGS[0], "ru", 75)
	await _run_free(CONFIGS[4], "en", 75)
