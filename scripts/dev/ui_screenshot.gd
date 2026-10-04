extends SceneTree
## Снимки экранов UI и HUD тренировки в PNG — инструмент приёмки HUD и меню (`docs/game/hud.md`
## п. 14, T-059). Запуск: ./scripts/ui_screenshot.sh [каталог] [разрешение] [язык] [--safe-area]
## [--phone] (оболочка перебирает разрешения и языки; этот скрипт снимает одно разрешение и
## один язык).
##
## Аргументы после `--`: каталог, разрешение `WxH` (имя файла и обязательный размер кадра; окно
## открывает `--resolution`), язык `ru|en`, флаги `--safe-area` и `--phone` (тип устройства
## «телефон» через `Engine.set_meta("ui_debug_device", "phone")`: масштаб HUD 1.2, кнопки 72 lp,
## фишки статусов столбиком, слот подсказки у низа кадра, компактная панель инструментов).
##
## Размер кадра проверяется: кадр должен быть ровно запрошенного разрешения в пикселях. Если окно
## оказалось другого размера (Retina/HiDPI, оконный менеджер растянул окно — на macOS был кадр
## 2704×1522 под именем 1280×720), скрипт возвращает окно к запрошенному размеру
## (`window_set_size` в пикселях) и снимает заново; не вышло — снимок не сохраняется, ошибка,
## код выхода 1. Кадр не масштабируется: вёрстка при другом размере окна другая.
##
## Что делает: поднимает `main.tscn` с временным `data_dir`, `trainer_kind = "fake"`,
## `env_reader = Callable()`, заводит два профиля, импортирует `acc_full.zwo` и проходит
## таблицу `SCENARIOS`. Экран снимается не раньше чем через `SETTLE_SEC` (0.5 с) реального
## времени и `SETTLE_FRAMES` кадров, после `frame_post_draw`: анимации UI (появление карточки
## паузы, вуали, листов, панели инструментов) идут 200–300 мс по реальному времени, а
## виртуальные часы сессий за это время стоят — снимок остаётся детерминированным. HUD тренировки
## идёт на эмуляторе (`start_workout_on_emulator`) с подменёнными часами
## `WorkoutScreen.clock_usec`: каждый кадр часы уходят вперёд на `TIME_SCALE × FRAME_DT`
## (×30), поэтому снимок детерминирован и не зависит от скорости машины.
##
## Свободная езда (T-084): на эмуляторе (`start_free_ride_on_emulator`) по трассе «горы» с
## подменёнными часами `FreeRideScreen.clock_usec`; гонщик доезжает до дистанции `s_m` первого
## круга (ровно, подъём, спуск) с ускорением `FREE_TIME_SCALE`, мощность эмулятора — по участку
## (`power_w`). Отдельно — станок без SIM (`set_simulation_supported(false)`): сообщение
## «станок не поддерживает SIM» и «СОПР.» в карточке уклона.
##
## Имя файла: `<id>_<WxH>_<язык>[_safe][_phone].png`. Код выхода 0 — все снимки сохранены.

const MAIN_SCENE: String = "res://src/app/main.tscn"
const PLAN_FIXTURE: String = "res://tests/fixtures/workouts_acceptance/acc_full.zwo"
## Профили: первый — активный (с максимальным пульсом, чтобы были зоны пульса).
const PROFILE_NAMES: Array[String] = ["Даша", "Роман"]
const ACTIVE_MAX_HR: int = 185
## Кадров после перехода до снимка.
const SETTLE_FRAMES: int = 6
## Реального времени после перехода до снимка, с: дольше анимаций UI (200–300 мс).
const SETTLE_SEC: float = 0.5
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
## Отладочный тип устройства (`--phone`): читает `UiScale` (T-060).
const DEVICE_META: StringName = &"ui_debug_device"
## Экраны `AppState`, которые не снимаются общим проходом: у них свои сценарии в таблице.
## Свободная езда в общем проходе снимается пустой (до заезда — «Заезд не запущен»), заезд —
## своими сценариями `free_ride_*` в конце таблицы.
const SCREENS_WITH_SCENARIOS: Array[String] = ["workout"]
## Свободная езда: ускорение часов на переездах (сессионных секунд на секунду кадров) и предел
## кадров на один переезд.
const FREE_TIME_SCALE: float = 120.0
const FREE_MAX_ADVANCE_FRAMES: int = 6000
const FREE_ROUTE: String = "mountains"
const FREE_NO_SIM_ROUTE: String = "hills"
const FREE_STEEPNESS_PCT: int = 50

## Виды сценариев (обработчики — `_run_scenario`).
const KIND_APP_SCREENS: String = "app_screens"
const KIND_WORKOUT_AT: String = "workout_at"
const KIND_WORKOUT_BEFORE_CHANGE: String = "workout_before_change"
const KIND_WORKOUT_PAUSED: String = "workout_paused"
const KIND_WORKOUT_LAST_STEP: String = "workout_last_step"
const KIND_WORKOUT_SUMMARY: String = "workout_summary"
## Итог с паузой (REQ-HUD-14 крит. 8): короткая тренировка `DevScreen.test_workout()` заново, пауза
## `pause_sec` секунд сессии в начале, затем до финиша.
const KIND_WORKOUT_SUMMARY_PAUSED: String = "workout_summary_paused"
const KIND_RIDE_DETAIL: String = "ride_detail"
const KIND_FREE_RIDE_AT: String = "free_ride_at"
const KIND_FREE_RIDE_PAUSED: String = "free_ride_paused"
const KIND_FREE_RIDE_FINISH: String = "free_ride_finish"
const KIND_FREE_RIDE_NO_SIM: String = "free_ride_no_sim"
const KIND_HISTORY_ROWS: String = "history_rows"
const KIND_DIALOG: String = "dialog"

## Таблица сценариев, выполняется по порядку (тренировка продолжается от сценария к сценарию).
## Новые сценарии (свободная езда — T-084) добавляются строками и веткой в `_run_scenario`.
## Поля: `id` — префикс имени файла; `kind`; `at_sec` — сессионное время тренировки
## (для `workout_*` сначала доехать до него); `lead_sec` — за сколько секунд до смены шага;
## `offset_sec` — сдвиг от начала последнего шага. Свободная езда: `s_m` — дистанция от старта
## по трассе `FREE_ROUTE` (на первом круге — позиция на круге), `at_sec` — время сессии,
## `power_w` — мощность эмулятора на переезде, `toolbar` — показать панель инструментов,
## `confirm_id` — снять ещё и подтверждение завершения. Карточка заезда: `scroll_end` — снять
## низ карточки (каденс, зоны, Strava). История (`history_rows`): `rides` — 0 (второй профиль,
## без заездов) или сколько заездов показать (недостающие — синтетические, план и свободная
## езда вперемешку). Диалоги (`dialog`): `profile_create` — «Новый профиль», `forget_intervals` —
## подтверждение «Отвязать Intervals.icu».
const SCENARIOS: Array[Dictionary] = [
	{"id": "hud_0030", "kind": KIND_WORKOUT_AT, "at_sec": 30},
	{"id": "hud_toolbar_plan", "kind": KIND_WORKOUT_AT, "at_sec": 60, "toolbar": true},
	{"id": "hud_1700", "kind": KIND_WORKOUT_AT, "at_sec": 1020},
	{"id": "hud_next", "kind": KIND_WORKOUT_BEFORE_CHANGE, "lead_sec": 5},
	{"id": "hud_paused", "kind": KIND_WORKOUT_PAUSED, "at_sec": 1230},
	{"id": "hud_last_step", "kind": KIND_WORKOUT_LAST_STEP, "offset_sec": 30},
	{"id": "hud_summary", "kind": KIND_WORKOUT_SUMMARY},
	{"id": "screen", "kind": KIND_APP_SCREENS},
	{"id": "dialog_profile_create", "kind": KIND_DIALOG, "dialog": "profile_create"},
	{"id": "dialog_forget_intervals", "kind": KIND_DIALOG, "dialog": "forget_intervals"},
	{"id": "history_ride_detail", "kind": KIND_RIDE_DETAIL},
	{"id": "history_ride_detail_end", "kind": KIND_RIDE_DETAIL, "scroll_end": true},
	{"id": "free_start", "kind": KIND_FREE_RIDE_AT, "at_sec": 20, "power_w": 190},
	{"id": "free_flat", "kind": KIND_FREE_RIDE_AT, "s_m": 1600.0, "power_w": 200},
	{"id": "hud_toolbar_free", "kind": KIND_FREE_RIDE_AT, "s_m": 1700.0, "power_w": 200, "toolbar": true},
	{"id": "free_climb", "kind": KIND_FREE_RIDE_AT, "s_m": 6300.0, "power_w": 265, "toolbar": true},
	{"id": "free_paused", "kind": KIND_FREE_RIDE_PAUSED},
	{"id": "free_descent", "kind": KIND_FREE_RIDE_AT, "s_m": 13600.0, "power_w": 140},
	{"id": "free_summary", "kind": KIND_FREE_RIDE_FINISH, "confirm_id": "free_finish_confirm"},
	{"id": "history_free_ride_detail", "kind": KIND_RIDE_DETAIL},
	{"id": "history_free_ride_detail_end", "kind": KIND_RIDE_DETAIL, "scroll_end": true},
	{"id": "free_no_sim", "kind": KIND_FREE_RIDE_NO_SIM, "at_sec": 4},
	{"id": "history_empty", "kind": KIND_HISTORY_ROWS, "rides": 0},
	{"id": "history_20", "kind": KIND_HISTORY_ROWS, "rides": 20},
	# Последним: новая тренировка добавляет заезд в историю — кадры истории выше её не видят.
	{"id": "hud_summary_paused", "kind": KIND_WORKOUT_SUMMARY_PAUSED, "pause_sec": 75},
]

var _out_dir: String = "screenshots/ui"
var _resolution: String = ""
## Запрошенный размер кадра в пикселях (из аргумента `WxH`); (0, 0) — не задан, берётся окно.
var _requested_size := Vector2i.ZERO
var _lang: String = "ru"
var _safe_area: bool = false
var _phone: bool = false
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
	if _phone:
		Engine.set_meta(DEVICE_META, "phone")
	# Автозагрузка `UiScaleRuntime` определила устройство до разбора аргументов — переопределяем.
	var ui := root.get_node_or_null(^"UiScaleRuntime") as UiScale
	if ui != null:
		ui.device = UiScale.detect_device()
		ui.set_mode(ui.mode)
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
		elif arg == "--phone":
			_phone = true
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
	if kind.begins_with("free_ride_"):
		await _run_free_ride_scenario(id, kind, scenario)
		return
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
			if bool(scenario.get("toolbar", false)):
				_main.workout_screen().toolbar().poke()
				# Панель проявляется за 200 мс — снимаем после проявления.
				await create_timer(HudToolbar.FADE_SEC + 0.1).timeout
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
		KIND_WORKOUT_SUMMARY_PAUSED:
			if not _main.start_workout_on_emulator(DevScreen.test_workout()) or _session() == null:
				_fail("%s: короткая тренировка не запущена" % id)
				return
			await _advance_to(5)
			var screen: WorkoutScreen = _main.workout_screen()
			screen.toggle_pause()
			_clock_usec += int(scenario.get("pause_sec", 75)) * 1_000_000
			await process_frame
			screen.toggle_pause()
			await _advance_to(_session().executor.workout.total_duration_sec() + 1)
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
			if bool(scenario.get("scroll_end", false)):
				await process_frame
				var scroll := history.detail().find_child("Scroll", true, false) as ScrollContainer
				if scroll != null:
					scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
			await _shoot(id)
			history.back_to_list()
		KIND_HISTORY_ROWS:
			await _shoot_history_rows(id, int(scenario.get("rides", 0)))
		KIND_DIALOG:
			await _shoot_dialog(id, str(scenario.get("dialog", "")))
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


## История на `count` заездах: 0 — второй профиль (пустое состояние), иначе у активного
## профиля добавляются синтетические заезды до `count`.
func _shoot_history_rows(id: String, count: int) -> void:
	var profiles: Array[Profile] = _main.repo.list()
	if count == 0:
		_main.app_state.select_profile(profiles[profiles.size() - 1].id)
	else:
		var active: Profile = _main.repo.get_active()
		var have: int = _main.ride_repository.list(active.id).size()
		var now: int = int(Time.get_unix_time_from_system())
		for i in range(have, count):
			var started: int = now - (i + 1) * 86400 - (i % 5) * 3600
			_main.ride_repository.save(_synthetic_ride(active, started, i))
	_main.app_state.navigate(AppState.Screen.HISTORY)
	_main.history_screen().refresh()
	await _shoot(id)
	if count == 0:
		_main.app_state.select_profile(profiles[0].id)


## Синтетический заезд для списка истории: план (чётные) или свободная езда (нечётные).
static func _synthetic_ride(profile: Profile, started: int, index: int) -> Ride:
	var r := Ride.new()
	r.id = Ride.generate_id(started)
	r.profile_id = profile.id
	r.started_at_unix = started
	var n: int = 1200 + (index % 4) * 600
	var free: bool = index % 2 == 1
	if free:
		var route_id: String = RouteCatalog.ids()[index % RouteCatalog.ids().size()]
		r.metadata = Ride.free_ride_metadata(route_id, 50.0)
		r.metadata["ftp_w"] = profile.ftp_w
		r.metadata["max_hr"] = ACTIVE_MAX_HR
		r.metadata["weight_kg"] = profile.weight_kg
		r.samples.speed_source = SampleStream.SPEED_SOURCE_MODEL
		var route := RouteCatalog.get_route(route_id).profile
		for i in n:
			var d: float = float(i + 1) * 9.0
			var s: float = fposmod(d, route.length_m())
			r.samples.append(i, TrainerSample.full(float(i), 170 + (i % 90), 88, 0.0), 135, 0, -1, false, 32.4, {},
				{"distance_m": d, "altitude_m": route.height_at(s), "grade_pct": route.grade_at(s)})
	else:
		r.name = ["Sweet Spot 3×10", "Endurance 60", "VO2max 5×3", "Recovery 30"][index / 2 % 4]
		var steps: Array[WorkoutStep] = [WorkoutStep.percent(n / 2, 60.0), WorkoutStep.percent(n - n / 2, 95.0)]
		r.workout = WorkoutSerializer.to_dict(Workout.make(r.name, steps, "zwo"))
		r.metadata = {"workout_name": r.name, "workout_source": "zwo", "started_at_unix": started,
			"ftp_w": profile.ftp_w, "weight_kg": profile.weight_kg, "max_hr": ACTIVE_MAX_HR, "intensity": 1.0,
			"stopped_early": false, "speed_source": SampleStream.SPEED_SOURCE_TRAINER, "elapsed_sec": n,
			"paused_total_sec": 0.0}
		r.samples.speed_source = SampleStream.SPEED_SOURCE_TRAINER
		for i in n:
			var target: int = roundi(profile.ftp_w * (0.6 if i < n / 2 else 0.95))
			r.samples.append(i, TrainerSample.full(float(i), target, 90, 30.0), 140, target, 0 if i < n / 2 else 1, true)
	r.metadata["in_progress"] = false
	r.metadata["recovered"] = false
	r.events = [{"type": WorkoutSession.EVENT_START, "at_sec": 0.0, "value": 0}]
	r.upload["strava_status"] = [Ride.UPLOAD_NONE, Ride.UPLOAD_DONE, Ride.UPLOAD_DUPLICATE, Ride.UPLOAD_QUEUED, Ride.UPLOAD_FAILED][index % 5]
	r.compute_summary()
	return r


## Диалог поверх экрана: «Новый профиль» или подтверждение «Отвязать Intervals.icu».
func _shoot_dialog(id: String, dialog: String) -> void:
	match dialog:
		"profile_create":
			_main.app_state.switch_profile()
			var select := _main.screen_node(AppState.Screen.PROFILE_SELECT) as ProfileSelectScreen
			select.open_create_form()
			await _shoot(id)
			select.close_create_form()
			_main.app_state.select_profile(_main.repo.list()[0].id)
		"forget_intervals":
			_main.app_state.navigate(AppState.Screen.SETTINGS)
			var settings := _main.settings_screen()
			settings.request_forget_intervals()
			await _shoot(id)
			(settings.get_node("%ForgetIntervalsDialog") as Window).hide()
		_:
			_fail("%s: неизвестный диалог '%s'" % [id, dialog])


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
# Свободная езда
# ---------------------------------------------------------------------------

func _run_free_ride_scenario(id: String, kind: String, scenario: Dictionary) -> void:
	var screen: FreeRideScreen = _main.free_ride_screen()
	match kind:
		KIND_FREE_RIDE_AT:
			if not _ensure_free_ride():
				_fail("%s: свободная езда на эмуляторе не запущена" % id)
				return
			_set_free_power(int(scenario.get("power_w", 0)))
			if scenario.has("at_sec"):
				await _advance_free_ride(_reached_time.bind(int(scenario["at_sec"])))
			if scenario.has("s_m"):
				await _advance_free_ride(_reached_distance.bind(float(scenario["s_m"])))
			if bool(scenario.get("toolbar", false)):
				screen.toolbar().poke()
				# Панель проявляется за 200 мс — снимаем после проявления.
				await create_timer(HudToolbar.FADE_SEC + 0.1).timeout
			await _shoot(id)
		KIND_FREE_RIDE_PAUSED:
			if not screen.is_session_active():
				_fail("%s: свободная езда не запущена" % id)
				return
			screen.pause()
			await _shoot(id)
			screen.resume()
		KIND_FREE_RIDE_FINISH:
			if not screen.is_session_active():
				_fail("%s: свободная езда не запущена" % id)
				return
			screen.request_finish()
			if scenario.has("confirm_id"):
				await _shoot(str(scenario["confirm_id"]))
			screen.confirm_finish()
			if not screen.is_summary_visible():
				_fail("%s: итог заезда не показан" % id)
			await _shoot(id)
		KIND_FREE_RIDE_NO_SIM:
			var trainer := TrainerFactory.create(TrainerFactory.KIND_FAKE) as FakeTrainer
			trainer.connect_delay_sec = 0.0
			trainer.set_simulation_supported(false)
			trainer.set_rider_power(180)
			trainer.connect_device("emulator_no_sim")
			screen.clock_usec = _virtual_clock
			screen.keep_awake_setter = _ignore_keep_awake
			if not _main.launch_free_ride(trainer, FREE_NO_SIM_ROUTE, FREE_STEEPNESS_PCT):
				_fail("%s: свободная езда без SIM не запущена" % id)
				return
			await _advance_free_ride(_reached_time.bind(int(scenario.get("at_sec", 3))))
			if not screen.is_notice_visible():
				_fail("%s: сообщение «станок не поддерживает SIM» не показано" % id)
			await _shoot(id)
			screen.request_finish()
			screen.confirm_finish()


## Свободная езда на эмуляторе один раз; часы экрана — виртуальные.
func _ensure_free_ride() -> bool:
	var screen: FreeRideScreen = _main.free_ride_screen()
	if screen.is_session_active():
		return true
	screen.clock_usec = _virtual_clock
	screen.keep_awake_setter = _ignore_keep_awake
	return _main.start_free_ride_on_emulator(FREE_ROUTE, FREE_STEEPNESS_PCT) and screen.session() != null


## Мощность эмулятора на переезде (0 — не менять).
func _set_free_power(watts: int) -> void:
	var trainer := _main.emulator_trainer() as FakeTrainer
	if trainer != null and watts > 0:
		trainer.set_rider_power(watts)


static func _reached_time(session: FreeRideSession, at_sec: int) -> bool:
	return session.elapsed_sec() >= at_sec


static func _reached_distance(session: FreeRideSession, distance_m: float) -> bool:
	return session.distance_m() >= distance_m


## Двигать виртуальные часы (×`FREE_TIME_SCALE`) по кадру, пока `done(session)` не станет true.
func _advance_free_ride(done: Callable) -> void:
	var session: FreeRideSession = _main.free_ride_screen().session()
	var step_usec: int = int(round(FREE_TIME_SCALE * FRAME_DT * 1_000_000.0))
	var frames: int = 0
	while not bool(done.call(session)):
		if session.get_state() != WorkoutSession.State.RUNNING:
			_fail("свободная езда не идёт (состояние %d)" % session.get_state())
			return
		if frames >= FREE_MAX_ADVANCE_FRAMES:
			_fail("свободная езда: условие не выполнено за %d кадров" % frames)
			return
		_clock_usec += step_usec
		frames += 1
		await process_frame


# ---------------------------------------------------------------------------
# Снимок и служебное
# ---------------------------------------------------------------------------

func _shoot(id: String) -> void:
	var name: String = "%s_%s_%s%s%s.png" % [id, _resolution, _lang, "_safe" if _safe_area else "",
			"_phone" if _phone else ""]
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


## Кадр окна не раньше чем через `SETTLE_SEC` и `SETTLE_FRAMES` кадров, после `frame_post_draw`.
func _capture() -> Image:
	await create_timer(SETTLE_SEC).timeout
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
	if Engine.has_meta(DEVICE_META):
		Engine.remove_meta(DEVICE_META)
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
