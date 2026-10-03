extends SceneTree
## Снимки экранов UI и HUD тренировки в PNG — инструмент приёмки HUD и меню (`docs/game/hud.md`
## п. 14, T-059). Запуск: ./scripts/ui_screenshot.sh [каталог] [разрешение] [язык] [--safe-area]
## (оболочка перебирает разрешения и языки; этот скрипт снимает одно разрешение и один язык).
##
## Аргументы после `--`: каталог, разрешение `WxH` (имя файла и обязательный размер кадра; окно
## открывает `--resolution`), язык `ru|en`, флаг `--safe-area`.
##
## Размер кадра проверяется: кадр должен быть ровно запрошенного разрешения в пикселях. Если окно
## оказалось другого размера (Retina/HiDPI, оконный менеджер растянул окно — на macOS был кадр
## 2704×1522 под именем 1280×720), скрипт возвращает окно к запрошенному размеру
## (`window_set_size` в пикселях) и снимает заново; не вышло — снимок не сохраняется, ошибка,
## код выхода 1. Кадр не масштабируется: вёрстка при другом размере окна другая.
##
## Что делает: поднимает `main.tscn` с временным `data_dir`, `trainer_kind = "fake"`,
## `env_reader = Callable()`, заводит два профиля, импортирует `acc_full.zwo` и проходит
## таблицу `SCENARIOS`. Экран снимается после 6 кадров и `frame_post_draw`. HUD тренировки
## идёт на эмуляторе (`start_workout_on_emulator`) с подменёнными часами
## `WorkoutScreen.clock_usec`: каждый кадр часы уходят вперёд на `TIME_SCALE × FRAME_DT`
## (×30), поэтому снимок детерминирован и не зависит от скорости машины.
##
## Имя файла: `<id>_<WxH>_<язык>[_safe].png`. Код выхода 0 — все снимки сохранены.

const MAIN_SCENE: String = "res://src/app/main.tscn"
const PLAN_FIXTURE: String = "res://tests/fixtures/workouts_acceptance/acc_full.zwo"
## Профили: первый — активный (с максимальным пульсом, чтобы были зоны пульса).
const PROFILE_NAMES: Array[String] = ["Даша", "Роман"]
const ACTIVE_MAX_HR: int = 185
## Кадров после перехода до снимка.
const SETTLE_FRAMES: int = 6
const FRAME_DT: float = 1.0 / 60.0
## Ускорение часов тренировки: сессионных секунд на секунду кадров.
const TIME_SCALE: float = 30.0
## Предохранитель от зависания: столько кадров максимум на один переход по времени.
const MAX_ADVANCE_FRAMES: int = 20000
## Попыток вернуть окно к запрошенному размеру перед снимком.
const RESIZE_ATTEMPTS: int = 3
## Отладочная безопасная зона (lp): читает `UiScale` (T-060).
const SAFE_AREA_META: StringName = &"ui_debug_safe_area"
const SAFE_AREA_LP: Dictionary = {"left": 100.0, "right": 100.0, "top": 0.0, "bottom": 13.0}
## Экраны `AppState`, которые не снимаются общим проходом: у них свои сценарии в таблице.
const SCREENS_WITH_SCENARIOS: Array[String] = ["workout"]

## Виды сценариев (обработчики — `_run_scenario`).
const KIND_APP_SCREENS: String = "app_screens"
const KIND_WORKOUT_AT: String = "workout_at"
const KIND_WORKOUT_BEFORE_CHANGE: String = "workout_before_change"
const KIND_WORKOUT_PAUSED: String = "workout_paused"
const KIND_WORKOUT_LAST_STEP: String = "workout_last_step"
const KIND_WORKOUT_SUMMARY: String = "workout_summary"
const KIND_RIDE_DETAIL: String = "ride_detail"

## Таблица сценариев, выполняется по порядку (тренировка продолжается от сценария к сценарию).
## Новые сценарии (свободная езда — T-084) добавляются строками и веткой в `_run_scenario`.
## Поля: `id` — префикс имени файла; `kind`; `at_sec` — сессионное время тренировки
## (для `workout_*` сначала доехать до него); `lead_sec` — за сколько секунд до смены шага;
## `offset_sec` — сдвиг от начала последнего шага.
const SCENARIOS: Array[Dictionary] = [
	{"id": "hud_0030", "kind": KIND_WORKOUT_AT, "at_sec": 30},
	{"id": "hud_1700", "kind": KIND_WORKOUT_AT, "at_sec": 1020},
	{"id": "hud_next", "kind": KIND_WORKOUT_BEFORE_CHANGE, "lead_sec": 5},
	{"id": "hud_paused", "kind": KIND_WORKOUT_PAUSED, "at_sec": 1230},
	{"id": "hud_last_step", "kind": KIND_WORKOUT_LAST_STEP, "offset_sec": 30},
	{"id": "hud_summary", "kind": KIND_WORKOUT_SUMMARY},
	{"id": "screen", "kind": KIND_APP_SCREENS},
	{"id": "history_ride_detail", "kind": KIND_RIDE_DETAIL},
]

var _out_dir: String = "screenshots/ui"
var _resolution: String = ""
## Запрошенный размер кадра в пикселях (из аргумента `WxH`); (0, 0) — не задан, берётся окно.
var _requested_size := Vector2i.ZERO
var _lang: String = "ru"
var _safe_area: bool = false
var _data_dir: String = ""
var _main: AppMain = null
var _workout: Workout = null
var _clock_usec: int = 0
var _failures: int = 0
var _saved: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_parse_args()
	if _safe_area:
		Engine.set_meta(SAFE_AREA_META, SAFE_AREA_LP)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# Окно фиксированного размера: оконный менеджер не растягивает его во время прохода.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, true)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_data_dir = "user://ui_screenshot_%d/" % OS.get_process_id()
	_remove_tree(ProjectSettings.globalize_path(_data_dir))
	var ok: bool = _prepare_data()
	if ok:
		ok = _start_app()
	if ok:
		for scenario in SCENARIOS:
			await _run_scenario(scenario)
	else:
		_failures += 1
	_cleanup()
	print("ui_screenshot: сохранено %d, ошибок %d" % [_saved, _failures])
	quit(0 if _failures == 0 else 1)


func _parse_args() -> void:
	var positional: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		if arg == "--safe-area":
			_safe_area = true
		else:
			positional.append(arg)
	if positional.size() > 0 and not positional[0].is_empty():
		_out_dir = positional[0]
	if positional.size() > 1:
		_resolution = positional[1]
	if positional.size() > 2 and not positional[2].is_empty():
		_lang = positional[2]
	if _resolution.is_empty():
		_resolution = "%dx%d" % [root.size.x, root.size.y]
	_requested_size = parse_resolution(_resolution)
	if _requested_size == Vector2i.ZERO:
		_fail("разрешение '%s' не в формате WxH" % _resolution)
		_requested_size = root.size


## `WxH` → размер в пикселях; не тот формат — (0, 0).
static func parse_resolution(text: String) -> Vector2i:
	var parts: PackedStringArray = text.split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	var size := Vector2i(parts[0].to_int(), parts[1].to_int())
	return size if size.x > 0 and size.y > 0 else Vector2i.ZERO


# ---------------------------------------------------------------------------
# Подготовка: данные, приложение, план
# ---------------------------------------------------------------------------

## Язык и два профиля пишутся в `data_dir` до запуска приложения (как у пользователя).
func _prepare_data() -> bool:
	var settings := AppSettings.load_from(_data_dir + "settings.json")
	settings.locale = _lang
	if not settings.save():
		push_error("ui_screenshot: не записаны настройки в %s" % _data_dir)
		return false
	var repo := ProfileRepository.new(_data_dir + "profiles/")
	for profile_name in PROFILE_NAMES:
		if repo.create(profile_name) == null:
			push_error("ui_screenshot: не создан профиль %s" % profile_name)
			return false
	var first: Profile = repo.list()[0]
	first.max_hr = ACTIVE_MAX_HR
	return repo.save(first).is_empty()


func _start_app() -> bool:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate() as AppMain
	_main.data_dir = _data_dir
	_main.trainer_kind = "fake"
	_main.env_reader = Callable()
	root.add_child(_main)
	var first: Profile = _main.repo.list()[0]
	if not _main.app_state.select_profile(first.id):
		push_error("ui_screenshot: профиль не выбран (%s)" % _main.app_state.last_select_error())
		return false
	_main.app_state.navigate(AppState.Screen.PLAN)
	var result: ParseResult = _main.plan_screen().import_path(ProjectSettings.globalize_path(PLAN_FIXTURE))
	if result == null or not result.ok():
		push_error("ui_screenshot: не импортирован %s" % PLAN_FIXTURE)
		return false
	_workout = result.workout
	return true


# ---------------------------------------------------------------------------
# Сценарии
# ---------------------------------------------------------------------------

func _run_scenario(scenario: Dictionary) -> void:
	var id: String = str(scenario["id"])
	var kind: String = str(scenario["kind"])
	if kind.begins_with("workout_"):
		if not _ensure_workout():
			_fail("%s: тренировка на эмуляторе не запущена" % id)
			return
		if scenario.has("at_sec"):
			await _advance_to(int(scenario["at_sec"]))
	match kind:
		KIND_APP_SCREENS:
			await _shoot_app_screens(id)
		KIND_WORKOUT_AT:
			await _shoot(id)
		KIND_WORKOUT_BEFORE_CHANGE:
			var executor: IntervalExecutor = _session().executor
			var next_start: int = _workout.step_start_sec(executor.current_step_index() + 1)
			await _advance_to(next_start - int(scenario.get("lead_sec", 5)))
			await _shoot(id)
		KIND_WORKOUT_PAUSED:
			_main.workout_screen().toggle_pause()
			await _shoot(id)
			_main.workout_screen().toggle_pause()
		KIND_WORKOUT_LAST_STEP:
			var last_start: int = _workout.step_start_sec(_workout.steps.size() - 1)
			await _advance_to(last_start + int(scenario.get("offset_sec", 0)))
			await _shoot(id)
		KIND_WORKOUT_SUMMARY:
			await _advance_to(_workout.total_duration_sec() + 1)
			if _session().get_state() != WorkoutSession.State.FINISHED:
				_fail("%s: тренировка не завершилась" % id)
			await _shoot(id)
		KIND_RIDE_DETAIL:
			_main.app_state.navigate(AppState.Screen.HISTORY)
			var history: HistoryScreen = _main.history_screen()
			if history.row_count() == 0:
				_fail("%s: в истории нет заезда" % id)
				return
			history.select_index(0)
			await _shoot(id)
			history.back_to_list()
		_:
			_fail("неизвестный вид сценария '%s'" % kind)


## Общий проход: каждый экран, зарегистрированный в `AppState`, кроме экранов со своими сценариями.
func _shoot_app_screens(prefix: String) -> void:
	for screen: int in AppState.Screen.values():
		var screen_id: String = AppState.screen_name(screen)
		if SCREENS_WITH_SCENARIOS.has(screen_id):
			continue
		if screen == AppState.Screen.PROFILE_SELECT:
			_main.app_state.switch_profile()
		elif not _main.app_state.navigate(screen):
			_fail("%s_%s: переход не выполнен" % [prefix, screen_id])
			continue
		await _shoot("%s_%s" % [prefix, screen_id])
		if screen == AppState.Screen.PROFILE_SELECT:
			_main.app_state.select_profile(_main.repo.list()[0].id)


## Запустить план на эмуляторе один раз; часы экрана тренировки — виртуальные.
func _ensure_workout() -> bool:
	if _session() != null:
		return true
	var screen: WorkoutScreen = _main.workout_screen()
	screen.clock_usec = _virtual_clock
	screen.keep_awake_setter = _ignore_keep_awake
	return _main.start_workout_on_emulator(_workout) and _session() != null


func _session() -> WorkoutSession:
	return _main.workout_screen().session()


## Двигать виртуальные часы по кадру до сессионного времени `target_sec` (или до финиша).
func _advance_to(target_sec: int) -> void:
	var session: WorkoutSession = _session()
	var step_usec: int = int(round(TIME_SCALE * FRAME_DT * 1_000_000.0))
	var frames: int = 0
	while session.get_state() != WorkoutSession.State.FINISHED \
			and session.executor.elapsed_sec() < target_sec:
		if session.get_state() == WorkoutSession.State.PAUSED:
			_fail("часы стоят: сессия на паузе")
			return
		if frames >= MAX_ADVANCE_FRAMES:
			_fail("не дошли до %d с за %d кадров" % [target_sec, frames])
			return
		_clock_usec += step_usec
		frames += 1
		await process_frame


func _virtual_clock() -> int:
	return _clock_usec


func _ignore_keep_awake(_on: bool) -> void:
	pass


# ---------------------------------------------------------------------------
# Снимок и служебное
# ---------------------------------------------------------------------------

func _shoot(id: String) -> void:
	var name: String = "%s_%s_%s%s.png" % [id, _resolution, _lang, "_safe" if _safe_area else ""]
	var path: String = _out_dir.path_join(name)
	var image: Image = await _capture()
	var attempt: int = 0
	while image.get_size() != _requested_size and attempt < RESIZE_ATTEMPTS:
		attempt += 1
		push_warning("ui_screenshot: %s: кадр %s вместо %s — окно возвращается к запрошенному размеру"
				% [name, _size_text(image.get_size()), _resolution])
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(_requested_size)
		image = await _capture()
	if image.get_size() != _requested_size:
		_fail("%s: кадр %s, а запрошено %s — снимок не сохранён" % [path, _size_text(image.get_size()), _resolution])
		return
	var err: Error = image.save_png(path)
	if err != OK:
		_fail("%s: %s" % [path, error_string(err)])
		return
	# Проверка сохранённого файла, а не только кадра в памяти.
	var saved: Image = Image.load_from_file(path)
	if saved == null or saved.get_size() != _requested_size:
		_fail("%s: сохранённый файл %s, а запрошено %s" % [path,
				_size_text(saved.get_size()) if saved != null else "не читается", _resolution])
		return
	_saved += 1
	print("ui_screenshot: %s (%s)" % [path, _size_text(saved.get_size())])


## Кадр окна после `SETTLE_FRAMES` кадров и `frame_post_draw`.
func _capture() -> Image:
	for i in SETTLE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


static func _size_text(size: Vector2i) -> String:
	return "%dx%d" % [size.x, size.y]


func _fail(message: String) -> void:
	_failures += 1
	push_error("ui_screenshot: " + message)


func _cleanup() -> void:
	if _main != null:
		_main.queue_free()
		_main = null
	if Engine.has_meta(SAFE_AREA_META):
		Engine.remove_meta(SAFE_AREA_META)
	_remove_tree(ProjectSettings.globalize_path(_data_dir))


static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for file in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
