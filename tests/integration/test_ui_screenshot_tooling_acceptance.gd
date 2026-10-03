extends GutTest
## Независимые приёмочные тесты инструмента снимков UI и синтетического пульса (тестировщик, T-059).
## Покрытие: REQ-DEV-09 крит. 5 (расширение: эмулятор приложения отдаёт пульс 1 Гц по кривой
## 95 → 165 уд/мин — вводный абзац HUD), пульс на HUD тренировки на эмуляторе — число;
## состав снимков `scripts/ui_screenshot.sh` против вводного абзаца HUD и `hud.md` п. 14
## (состояния 0:30, середина, за 5 с до смены, пауза, последний шаг, сводка; все экраны;
## разрешения 1280×720, 1024×768, 1280×590; безопасная зона 100/100/0/13 lp).
## Сами снимки и их разбор — в отчёте приёмки (скилл ride-visual-review).

const MAIN_SCENE: String = "res://src/app/main.tscn"
const SHOT_SCRIPT: String = "res://scripts/dev/ui_screenshot.gd"
const SHOT_SHELL: String = "res://scripts/ui_screenshot.sh"
const ACC_FULL: String = "res://tests/fixtures/workouts_acceptance/acc_full.zwo"

var _dir: String
var _prev_locale: String
var _now_usec: int = 0
var _hr: Array[int] = []


func before_each() -> void:
	_dir = "user://test_ui_shot_acc_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_prev_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("ru")
	_now_usec = 0
	_hr.clear()


func after_each() -> void:
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


func _on_hr(bpm: int) -> void:
	_hr.append(bpm)


func _clock() -> int:
	return _now_usec


# ===========================================================================
# REQ-DEV-09 крит. 5 — синтетический пульс эмулятора приложения
# ===========================================================================

func _emulator_hr(seconds: int) -> Array[int]:
	var trainer: TrainerDevice = TrainerFactory.create(TrainerFactory.KIND_FAKE)
	trainer.set("connect_delay_sec", 0.0)
	trainer.heart_rate.connect(_on_hr)
	trainer.connect_device("acc")
	for i in seconds:
		trainer.tick(1.0)
	trainer.heart_rate.disconnect(_on_hr)
	var out: Array[int] = _hr.duplicate()
	_hr.clear()
	return out


func test_req_dev_09_c5_emulator_hr_1hz_curve_95_to_165_then_plateau() -> void:
	var hr := _emulator_hr(1800)
	assert_eq(hr.size(), 1800, "одно значение пульса в секунду")
	assert_between(hr[0], 93, 97, "старт около 95")
	assert_between(hr[1199], 163, 167, "к 20 мин около 165")
	var plateau_bad: Array[int] = []
	for i in range(1260, 1800):
		if hr[i] < 163 or hr[i] > 167:
			plateau_bad.append(hr[i])
	assert_eq(plateau_bad, [] as Array[int], "после 20 мин — плато 165 ± 2")
	# Тренд растёт: средние по минутам не убывают больше чем на шум.
	var prev: float = -INF
	for m in 20:
		var sum: float = 0.0
		for i in range(m * 60, m * 60 + 60):
			sum += hr[i]
		var avg: float = sum / 60.0
		assert_gt(avg, prev - 1.0, "минута %d: средний пульс не падает" % m)
		prev = avg
	for v in hr:
		if v <= 0:
			fail_test("пульс 0 — «нет данных» не должно быть у эмулятора")
			return


func test_req_dev_09_c5_emulator_hr_is_deterministic() -> void:
	var a := _emulator_hr(300)
	var b := _emulator_hr(300)
	assert_eq(a, b, "одинаковая последовательность при каждом запуске — снимки воспроизводимы")


func test_req_dev_09_c5_dev_mode_connection_manager_fake_has_hr() -> void:
	var cm := ConnectionManager.new(StubBleBridge.new(), RememberedDevices.new(_dir + "devices/"), TrainerFactory.KIND_FAKE)
	var trainer: TrainerDevice = cm.trainer
	assert_true(trainer is FakeTrainer, "режим разработки — эмулятор")
	trainer.set("connect_delay_sec", 0.0)
	trainer.heart_rate.connect(_on_hr)
	trainer.connect_device("dev")
	for i in 30:
		trainer.tick(1.0)
	assert_eq(_hr.size(), 30, "эмулятор режима разработки тоже отдаёт пульс 1 Гц")
	trainer.heart_rate.disconnect(_on_hr)
	cm.dispose()


func test_req_dev_09_c5_hr_on_workout_hud_is_a_number() -> void:
	ProfileRepository.new(_dir + "profiles/").create("Пульс")
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	main.env_reader = Callable()
	add_child_autofree(main)
	var result: ParseResult = ZwoParser.parse(FileAccess.get_file_as_string(ACC_FULL))
	var screen := main.workout_screen()
	screen.clock_usec = _clock
	screen.keep_awake_setter = func(_on: bool) -> void: pass
	assert_true(main.start_workout_on_emulator(result.workout))
	for target in [30, 1020]:
		while screen.session().executor.elapsed_sec() < target:
			_now_usec += 1_000_000
			screen.ticker().poll()
		var text := screen.hr_text()
		assert_true(text.is_valid_int(), "%d с: пульс на HUD — число, а не «—» (факт «%s»)" % [target, text])
		var expected: float = 95.0 + 70.0 * minf(float(target) / 1200.0, 1.0)
		assert_almost_eq(float(text.to_int()), expected, 4.0, "%d с: значение по кривой" % target)


# ===========================================================================
# Состав снимков (T-059): все заявленные экраны и моменты HUD
# ===========================================================================

func test_shot_script_covers_hud_states_of_hud_intro() -> void:
	var script: GDScript = load(SHOT_SCRIPT)
	var consts := script.get_script_constant_map()
	assert_eq(consts["PLAN_FIXTURE"], ACC_FULL, "план снимков — acc_full.zwo")
	var by_kind := {}
	var ids: Array[String] = []
	for s: Dictionary in consts["SCENARIOS"]:
		by_kind[str(s["kind"])] = s
		ids.append(str(s["id"]))
	var at_secs: Array[int] = []
	for s: Dictionary in consts["SCENARIOS"]:
		if s.has("at_sec"):
			at_secs.append(int(s["at_sec"]))
	assert_true(at_secs.has(30), "кадр 0:30")
	assert_true(at_secs.has(1020), "кадр середины 17:00 (hud.md п. 14)")
	assert_true(by_kind.has("workout_before_change") and int(by_kind["workout_before_change"]["lead_sec"]) == 5, "за 5 с до смены")
	assert_true(by_kind.has("workout_paused"), "пауза")
	assert_true(by_kind.has("workout_last_step"), "последний шаг")
	assert_true(by_kind.has("workout_summary"), "сводка")
	assert_true(by_kind.has("app_screens"), "проход по всем экранам")
	assert_true(by_kind.has("ride_detail"), "карточка заезда в истории")
	assert_eq(consts["SCREENS_WITH_SCENARIOS"], ["workout"], "общим проходом снимаются все экраны AppState, кроме тренировки")
	var safe: Dictionary = consts["SAFE_AREA_LP"]
	assert_eq([safe["left"], safe["right"], safe["top"], safe["bottom"]], [100.0, 100.0, 0.0, 13.0], "безопасная зона 100/100/0/13 lp")
	assert_eq(consts["PROFILE_NAMES"].size(), 2, "два профиля (экран выбора профиля не пуст)")


func test_shot_shell_default_resolutions_and_langs() -> void:
	var sh := FileAccess.get_file_as_string(SHOT_SHELL)
	assert_string_contains(sh, "ALL_RESOLUTIONS=\"1280x720,1024x768,1280x590\"", "три разрешения снимков")
	assert_string_contains(sh, "ALL_LANGS=\"ru,en\"", "ru и en")
	assert_string_contains(sh, "--safe-area", "флаг имитации безопасной зоны")
	assert_string_contains(sh, "gl_compatibility", "рендер gl_compatibility")
